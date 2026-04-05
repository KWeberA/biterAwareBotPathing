local constants = require("runtime.constants")
local util = require("runtime.util")
local threat_index = require("runtime.threat_index")
local network_cache = require("runtime.network_cache")
local tasks = require("runtime.tasks")
local debug_tools = require("runtime.debug")
local smoke_lab = require("runtime.smoke_lab")

local manager = {}

local runtime = {
  mutation_depth = 0,
  contexts = {},
  needs_transient_rebuild = false
}

local function with_mutation(work)
  runtime.mutation_depth = runtime.mutation_depth + 1
  local ok, result_a, result_b = pcall(work)
  runtime.mutation_depth = math.max(0, runtime.mutation_depth - 1)

  if not ok then
    error(result_a)
  end

  return result_a, result_b
end

local function relevant_force(force)
  return force.name ~= "enemy" and force.name ~= "neutral"
end

local function resolve_order_force(entity, player_index)
  if entity ~= nil and entity.valid and entity.force ~= nil and relevant_force(entity.force) then
    return entity.force
  end

  if player_index ~= nil then
    local player = game.get_player(player_index)
    if player ~= nil and player.valid and relevant_force(player.force) then
      return player.force
    end
  end

  return nil
end

local function relevant_surface_force_pairs(root, surface_name, force_name)
  local result = {}
  local selected_surfaces = {}
  local selected_forces = {}

  if surface_name ~= nil then
    local surface = util.resolve_surface(surface_name)
    if surface ~= nil then
      selected_surfaces[#selected_surfaces + 1] = surface
    end
  else
    for _, surface in pairs(game.surfaces) do
      selected_surfaces[#selected_surfaces + 1] = surface
    end
  end

  if force_name ~= nil then
    local force = util.resolve_force(force_name)
    if force ~= nil and relevant_force(force) then
      selected_forces[#selected_forces + 1] = force
    end
  else
    for _, force in pairs(game.forces) do
      if relevant_force(force) then
        selected_forces[#selected_forces + 1] = force
      end
    end
  end

  for _, surface in ipairs(selected_surfaces) do
    for _, force in ipairs(selected_forces) do
      local key = util.force_surface_key(surface.index, force.name)
      local has_activity = (root.task_counts_by_force_surface[key] or 0) > 0
        or (root.watch_counts_by_force_surface[key] or 0) > 0
        or surface.count_entities_filtered {
          force = force.name,
          type = "roboport",
          limit = 1
        } > 0

      if has_activity then
        result[#result + 1] = {
          surface = surface,
          force = force
        }
      end
    end
  end

  return result
end

local function invalidate_context(force_surface_key)
  runtime.contexts[force_surface_key] = nil
end

local function mark_force_surface_dirty(root, surface_index, force_name)
  local key = util.force_surface_key(surface_index, force_name)
  if root.active_force_surfaces[key] == nil then
    root.full_rescan_force_surfaces[key] = true
  end

  root.dirty_force_surfaces[key] = true
  root.active_force_surfaces[key] = true
  invalidate_context(key)
end

local function mark_surface_dirty(root, surface_index)
  root.dirty_surfaces[surface_index] = true

  for key in pairs(root.active_force_surfaces) do
    if string.match(key, "^" .. surface_index .. ":") then
      root.dirty_force_surfaces[key] = true
      invalidate_context(key)
    end
  end
end

local function get_context(root, force, surface, force_refresh)
  local key = util.force_surface_key(surface.index, force.name)
  local cached = runtime.contexts[key]
  local needs_refresh = force_refresh or cached == nil or cached.tick ~= game.tick or root.dirty_force_surfaces[key]

  if not needs_refresh then
    return cached.context, cached.threat
  end

  local threat = threat_index.ensure(root, surface, force_refresh or root.dirty_surfaces[surface.index])
  local context = network_cache.build_context(root, force, surface, threat)

  runtime.contexts[key] = {
    tick = game.tick,
    context = context,
    threat = threat
  }

  root.dirty_force_surfaces[key] = nil

  return context, threat
end

local function refresh_activity(root, force_surface_key)
  local has_activity = (root.task_counts_by_force_surface[force_surface_key] or 0) > 0
    or (root.watch_counts_by_force_surface[force_surface_key] or 0) > 0

  if has_activity then
    root.active_force_surfaces[force_surface_key] = true
  else
    root.active_force_surfaces[force_surface_key] = nil
  end
end

local function prepare_root(root)
  if not runtime.needs_transient_rebuild then
    return root
  end

  root.threat_indexes = {}
  root.networks = {}
  root.object_registrations = {}
  runtime.contexts = {}
  tasks.rebuild_indexes(root)

  for _, surface in pairs(game.surfaces) do
    root.dirty_surfaces[surface.index] = true
  end

  for key in pairs(root.active_force_surfaces) do
    root.dirty_force_surfaces[key] = true
    root.full_rescan_force_surfaces[key] = true
  end

  runtime.needs_transient_rebuild = false
  return root
end

local function recheck_force_surface(root, force, surface, force_refresh)
  local context = nil
  local threat = nil
  local summary = nil

  with_mutation(function()
    context, threat = get_context(root, force, surface, force_refresh)
    summary = tasks.recheck_force_surface(root, force, surface, context, threat)
  end)

  local force_surface_key = util.force_surface_key(surface.index, force.name)
  root.full_rescan_force_surfaces[force_surface_key] = nil
  refresh_activity(root, force_surface_key)
  root.stats.last_recheck_tick = game.tick
  return summary, context, threat
end

local function record_entity_change(root, entity)
  if entity == nil then
    return
  end

  if entity.force ~= nil and relevant_force(entity.force) and entity.name == "roboport" then
    mark_force_surface_dirty(root, entity.surface.index, entity.force.name)
    return
  end

  if entity.type == "unit-spawner" then
    mark_surface_dirty(root, entity.surface.index)
    return
  end

  if util.array_contains(constants.THREAT_ENTITY_TYPES, entity.type) and (entity.force == nil or not relevant_force(entity.force)) then
    mark_surface_dirty(root, entity.surface.index)
  end
end

local function dump_payload(root, scope_pairs, area)
  local payload = {
    tick = game.tick,
    scopes = {},
    threat_indexes = {},
    networks = {},
    deferred_tasks = {},
    watch_ghosts = {},
    smoke_labs = root.smoke_labs
  }

  for _, pair in ipairs(scope_pairs) do
    local summary, context, threat = recheck_force_surface(root, pair.force, pair.surface, true)
    payload.scopes[#payload.scopes + 1] = {
      surface_name = pair.surface.name,
      force_name = pair.force.name,
      summary = summary
    }

    payload.threat_indexes[pair.surface.name] = threat
    payload.networks[util.force_surface_key(pair.surface.index, pair.force.name)] = context.network_list
  end

  for _, task in pairs(root.deferred_tasks) do
    if area == nil or util.bbox_contains(area, task.position) then
      payload.deferred_tasks[#payload.deferred_tasks + 1] = task
    end
  end

  for _, watch in pairs(root.watch_ghosts) do
    if area == nil or util.bbox_contains(area, watch.position) then
      payload.watch_ghosts[#payload.watch_ghosts + 1] = watch
    end
  end

  return payload
end

function manager.on_init()
  local root = util.ensure_root()
  root.threat_indexes = {}
  root.networks = {}
  root.object_registrations = {}
  tasks.rebuild_indexes(root)
  runtime.needs_transient_rebuild = false

  for _, surface in pairs(game.surfaces) do
    root.dirty_surfaces[surface.index] = true

    for _, force in pairs(game.forces) do
      if relevant_force(force) then
        local count = surface.count_entities_filtered {
          force = force.name,
          type = "roboport",
          limit = 1
        }

        if count > 0 then
          local key = util.force_surface_key(surface.index, force.name)
          root.active_force_surfaces[key] = true
          root.dirty_force_surfaces[key] = true
          root.full_rescan_force_surfaces[key] = true
        end
      end
    end
  end
end

function manager.on_load()
  runtime.mutation_depth = 0
  runtime.contexts = {}
  runtime.needs_transient_rebuild = true
end

function manager.on_configuration_changed()
  local root = util.ensure_root()
  root.threat_indexes = {}
  root.networks = {}
  root.object_registrations = {}
  tasks.rebuild_indexes(root)
  runtime.contexts = {}
  runtime.needs_transient_rebuild = false

  for _, surface in pairs(game.surfaces) do
    root.dirty_surfaces[surface.index] = true
  end

  for _, pair in ipairs(relevant_surface_force_pairs(root)) do
    local key = util.force_surface_key(pair.surface.index, pair.force.name)
    root.dirty_force_surfaces[key] = true
    root.active_force_surfaces[key] = true
    root.full_rescan_force_surfaces[key] = true
  end
end

function manager.on_nth_tick()
  local root = prepare_root(util.ensure_root())
  local processed = 0
  local dirty_keys = {}
  local processed_keys = {}

  for key in pairs(root.dirty_force_surfaces) do
    dirty_keys[#dirty_keys + 1] = key
  end

  for _, key in ipairs(dirty_keys) do
    local separator = string.find(key, ":")
    local surface_index = tonumber(string.sub(key, 1, separator - 1))
    local force_name = string.sub(key, separator + 1)
    local surface = game.surfaces[surface_index]
    local force = game.forces[force_name]

    if surface ~= nil and force ~= nil then
      recheck_force_surface(root, force, surface, false)
      processed = processed + 1
      processed_keys[key] = true
    else
      root.dirty_force_surfaces[key] = nil
      root.active_force_surfaces[key] = nil
    end

    if processed >= constants.MAX_FORCE_SURFACES_PER_CYCLE then
      return
    end
  end

  local active_keys = {}
  for key in pairs(root.active_force_surfaces) do
    active_keys[#active_keys + 1] = key
  end

  for _, key in ipairs(active_keys) do
    if not processed_keys[key] then
      local separator = string.find(key, ":")
      local surface_index = tonumber(string.sub(key, 1, separator - 1))
      local force_name = string.sub(key, separator + 1)
      local surface = game.surfaces[surface_index]
      local force = game.forces[force_name]

      if surface ~= nil and force ~= nil then
        recheck_force_surface(root, force, surface, false)
        processed = processed + 1
      else
        root.active_force_surfaces[key] = nil
      end

      if processed >= constants.MAX_FORCE_SURFACES_PER_CYCLE then
        break
      end
    end
  end
end

function manager.on_built_entity(event)
  if runtime.mutation_depth > 0 then
    return
  end

  local entity = event.entity
  if entity == nil or not entity.valid then
    return
  end

  local root = prepare_root(util.ensure_root())

  if entity.type == "entity-ghost" or entity.type == "tile-ghost" then
    with_mutation(function()
      local context, threat = get_context(root, entity.force, entity.surface, false)
      tasks.evaluate_live_ghost(root, entity.force, context, threat, entity)
    end)

    mark_force_surface_dirty(root, entity.surface.index, entity.force.name)
    return
  end

  record_entity_change(root, entity)
end

function manager.on_marked_for_deconstruction(event)
  if runtime.mutation_depth > 0 then
    return
  end

  local entity = event.entity
  if entity == nil or not entity.valid then
    return
  end

  local root = prepare_root(util.ensure_root())
  local force = resolve_order_force(entity, event.player_index)
  if force == nil then
    return
  end

  with_mutation(function()
    local context, threat = get_context(root, force, entity.surface, false)
    tasks.evaluate_live_mark(root, force, context, threat, entity, "deconstruction", event.player_index)
  end)

  mark_force_surface_dirty(root, entity.surface.index, force.name)
end

function manager.on_marked_for_upgrade(event)
  if runtime.mutation_depth > 0 then
    return
  end

  local entity = event.entity
  if entity == nil or not entity.valid then
    return
  end

  local root = prepare_root(util.ensure_root())
  local force = resolve_order_force(entity, event.player_index)
  if force == nil then
    return
  end

  with_mutation(function()
    local context, threat = get_context(root, force, entity.surface, false)
    tasks.evaluate_live_mark(root, force, context, threat, entity, "upgrade", event.player_index, event.target, event.quality)
  end)

  mark_force_surface_dirty(root, entity.surface.index, force.name)
end

function manager.on_cancelled_deconstruction(event)
  if runtime.mutation_depth > 0 then
    return
  end

  local entity = event.entity
  if entity == nil or not entity.valid then
    return
  end

  local force = resolve_order_force(entity, event.player_index)
  if force == nil then
    return
  end

  local root = prepare_root(util.ensure_root())
  tasks.cancel_deferred_mark(root, force, entity, "deconstruction")
  mark_force_surface_dirty(root, entity.surface.index, force.name)
end

function manager.on_cancelled_upgrade(event)
  if runtime.mutation_depth > 0 then
    return
  end

  local entity = event.entity
  if entity == nil or not entity.valid then
    return
  end

  local force = resolve_order_force(entity, event.player_index)
  if force == nil then
    return
  end

  local root = prepare_root(util.ensure_root())
  tasks.cancel_deferred_mark(root, force, entity, "upgrade", event.target, event.quality)
  mark_force_surface_dirty(root, entity.surface.index, force.name)
end

function manager.on_object_destroyed(event)
  local root = prepare_root(util.ensure_root())
  tasks.handle_object_destroyed(root, event.registration_number)
end

function manager.on_entity_removed(event)
  if runtime.mutation_depth > 0 then
    return
  end

  local entity = event.entity
  if entity == nil then
    return
  end

  local root = prepare_root(util.ensure_root())
  record_entity_change(root, entity)
end

function manager.on_biter_base_built(event)
  local root = prepare_root(util.ensure_root())
  mark_surface_dirty(root, event.entity.surface.index)
end

function manager.recheck(surface_name, force_name)
  local root = prepare_root(util.ensure_root())
  local scope_pairs = relevant_surface_force_pairs(root, surface_name, force_name)
  local processed_scopes = 0

  for _, pair in ipairs(scope_pairs) do
    recheck_force_surface(root, pair.force, pair.surface, true)
    processed_scopes = processed_scopes + 1
  end

  return {
    processed_scopes = processed_scopes
  }
end

function manager.clear_deferred(surface_name, force_name, area)
  local root = prepare_root(util.ensure_root())
  local surface = surface_name ~= nil and util.resolve_surface(surface_name) or nil
  local force = force_name ~= nil and util.resolve_force(force_name) or nil
  local cleared = tasks.clear_deferred(root, surface and surface.index or nil, force and force.name or nil, area)

  if surface ~= nil and force ~= nil then
    mark_force_surface_dirty(root, surface.index, force.name)
  else
    for key in pairs(root.active_force_surfaces) do
      root.dirty_force_surfaces[key] = true
      invalidate_context(key)
    end
  end

  return {
    cleared = cleared
  }
end

function manager.dump_state(surface_name, force_name, area, player_index)
  local root = prepare_root(util.ensure_root())
  local scope_pairs = relevant_surface_force_pairs(root, surface_name, force_name)
  local payload = dump_payload(root, scope_pairs, area)

  local suffix_parts = { "state" }
  if surface_name ~= nil then
    suffix_parts[#suffix_parts + 1] = surface_name
  end
  if force_name ~= nil then
    suffix_parts[#suffix_parts + 1] = force_name
  end

  return debug_tools.write_state_dump(payload, table.concat(suffix_parts, "-"), player_index)
end

function manager.smoke_setup(player_index)
  local root = prepare_root(util.ensure_root())
  local setup = with_mutation(function()
    return smoke_lab.setup(root, player_index)
  end)

  local surface = game.surfaces[setup.surface_name]
  local force = game.forces[setup.force_name]
  mark_force_surface_dirty(root, surface.index, force.name)
  recheck_force_surface(root, force, surface, true)

  return setup
end

function manager.test_map_setup(player_index)
  local root = prepare_root(util.ensure_root())
  local setup = with_mutation(function()
    return smoke_lab.setup_test_map(root, player_index)
  end)

  local surface = game.surfaces[setup.surface_name]
  local force = game.forces[setup.force_name]
  mark_surface_dirty(root, surface.index)
  mark_force_surface_dirty(root, surface.index, force.name)
  recheck_force_surface(root, force, surface, true)

  setup.summary_file = debug_tools.write_state_dump({
    test_map = setup
  }, "test-map", player_index)

  return setup
end

function manager.register_commands()
  commands.add_command("babp-recheck", { "babp-command-help.recheck" }, function(command)
    local surface_name, force_name = util.parse_scope_args(command.parameter)
    local result = manager.recheck(surface_name, force_name)
    util.print_to_player(command.player_index, { "babp-message.recheck-finished", result.processed_scopes })
  end)

  commands.add_command("babp-dump-state", { "babp-command-help.dump-state" }, function(command)
    local surface_name, force_name = util.parse_scope_args(command.parameter)
    local filename = manager.dump_state(surface_name, force_name, nil, command.player_index)
    util.print_to_player(command.player_index, { "babp-message.dump-written", filename })
  end)

  commands.add_command("babp-clear-deferred", { "babp-command-help.clear-deferred" }, function(command)
    local surface_name, force_name = util.parse_scope_args(command.parameter)
    local result = manager.clear_deferred(surface_name, force_name)
    util.print_to_player(command.player_index, { "babp-message.clear-deferred-finished", result.cleared })
  end)

  commands.add_command("babp-smoke-setup", { "babp-command-help.smoke-setup" }, function(command)
    local setup = manager.smoke_setup(command.player_index)
    util.print_to_player(command.player_index, {
      "babp-message.smoke-ready",
      setup.surface_name,
      util.position_key(setup.origin)
    })
  end)

  commands.add_command("babp-testmap-setup", { "babp-command-help.testmap-setup" }, function(command)
    local setup = manager.test_map_setup(command.player_index)
    if command.player_index ~= nil then
      util.print_to_player(command.player_index, {
        "babp-message.testmap-ready-player",
        setup.surface_name,
        util.position_key(setup.origin),
        setup.summary_file
      })
    else
      util.print_to_player(command.player_index, {
        "babp-message.testmap-ready-console",
        setup.surface_name,
        util.position_key(setup.origin),
        setup.summary_file
      })
    end
  end)
end

function manager.remote_interface()
  return {
    recheck = function(surface_name, force_name)
      return manager.recheck(surface_name, force_name)
    end,
    dump_state = function(surface_name, force_name, area)
      return manager.dump_state(surface_name, force_name, area)
    end,
    clear_deferred = function(surface_name, force_name, area)
      return manager.clear_deferred(surface_name, force_name, area)
    end,
    smoke_setup = function(player_index)
      return manager.smoke_setup(player_index)
    end,
    test_map_setup = function(player_index)
      return manager.test_map_setup(player_index)
    end
  }
end

return manager
