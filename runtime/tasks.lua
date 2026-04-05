local constants = require("runtime.constants")
local util = require("runtime.util")
local network_cache = require("runtime.network_cache")

local tasks = {}

local function adjust_count(map, key, delta)
  local next_value = (map[key] or 0) + delta
  if next_value > 0 then
    map[key] = next_value
  else
    map[key] = nil
  end
end

local function task_force_surface_key(task)
  return util.force_surface_key(task.surface_index, task.force_name)
end

local function make_ghost_key(kind, surface_index, force_name, position, inner_name, direction, quality_name)
  return table.concat({
    kind,
    surface_index,
    force_name,
    kind == "tile-ghost" and util.tile_position_key(position) or util.position_key(position),
    inner_name,
    direction or "none",
    quality_name or "normal"
  }, ":")
end

local function make_mark_key(kind, surface_index, force_name, entity, target_name, target_quality_name)
  local identity = entity.unit_number ~= nil and ("u:" .. entity.unit_number)
    or ("p:" .. util.position_key(entity.position) .. ":" .. entity.name)

  return table.concat({
    kind,
    surface_index,
    force_name,
    identity,
    target_name or "none",
    target_quality_name or "normal"
  }, ":")
end

local function register_object(root, entity, payload)
  if entity == nil or not entity.valid then
    return nil
  end

  local registration_number = script.register_on_object_destroyed(entity)
  root.object_registrations[registration_number] = payload
  return registration_number
end

local function clear_registration(root, registration_number)
  if registration_number ~= nil then
    root.object_registrations[registration_number] = nil
  end
end

local function remove_watch(root, key)
  local watch = root.watch_ghosts[key]
  if watch == nil then
    return
  end

  clear_registration(root, watch.registration_number)
  root.watch_ghosts[key] = nil
  adjust_count(root.watch_counts_by_force_surface, util.force_surface_key(watch.surface_index, watch.force_name), -1)
end

local function upsert_watch(root, entity)
  local key = make_ghost_key(
    entity.type,
    entity.surface.index,
    entity.force.name,
    entity.position,
    entity.ghost_name,
    entity.direction,
    util.quality_name(entity.quality)
  )

  local watch = root.watch_ghosts[key]
  if watch == nil then
    watch = {
      key = key,
      kind = entity.type,
      surface_index = entity.surface.index,
      force_name = entity.force.name
    }

    root.watch_ghosts[key] = watch
    adjust_count(root.watch_counts_by_force_surface, util.force_surface_key(entity.surface.index, entity.force.name), 1)
  else
    clear_registration(root, watch.registration_number)
  end

  watch.position = util.copy_position(entity.position)
  watch.inner_name = entity.ghost_name
  watch.direction = entity.direction
  watch.quality_name = util.quality_name(entity.quality)
  watch.live_entity_unit_number = entity.unit_number
  watch.registration_number = register_object(root, entity, {
    kind = "watch",
    key = key
  })

  return watch
end

local function remove_deferred_task(root, task_id)
  local task = root.deferred_tasks[task_id]
  if task == nil then
    return
  end

  clear_registration(root, task.registration_number)
  root.deferred_tasks[task_id] = nil
  root.deferred_task_keys[task.key] = nil
  adjust_count(root.task_counts_by_force_surface, task_force_surface_key(task), -1)
end

local function upsert_deferred_task(root, key, snapshot, reason, network_key, target_entity)
  local existing_id = root.deferred_task_keys[key]
  local task = existing_id ~= nil and root.deferred_tasks[existing_id] or nil

  if task == nil then
    local next_id = root.next_task_id
    root.next_task_id = next_id + 1

    task = {
      id = next_id,
      key = key,
      kind = snapshot.kind,
      surface_index = snapshot.surface_index,
      force_name = snapshot.force_name,
      position = util.copy_position(snapshot.position),
      created_tick = game.tick
    }

    root.deferred_tasks[next_id] = task
    root.deferred_task_keys[key] = next_id
    adjust_count(root.task_counts_by_force_surface, task_force_surface_key(task), 1)
  else
    clear_registration(root, task.registration_number)
  end

  task.snapshot = util.copy_value(snapshot)
  task.block_reason = reason
  task.network_key = network_key
  task.updated_tick = game.tick
  task.last_status = reason
  task.registration_number = register_object(root, target_entity, {
    kind = "task",
    task_id = task.id
  })

  return task
end

local function module_request_plans(item_requests)
  local plans = {}

  for _, request in ipairs(item_requests or {}) do
    local prototype = game.item_prototypes[request.name]
    if prototype ~= nil and prototype.type == "module" and request.count > 0 then
      plans[#plans + 1] = {
        id = request.quality ~= nil and { name = request.name, quality = request.quality } or request.name,
        items = { grid_count = request.count }
      }
    end
  end

  return plans
end

local function has_unsupported_item_requests(snapshot)
  for _, request in ipairs(snapshot.item_requests or {}) do
    local prototype = game.item_prototypes[request.name]
    if prototype ~= nil and prototype.type ~= "module" and request.count > 0 then
      return true
    end
  end

  return false
end

local function restore_item_requests(entity, snapshot)
  local plans = module_request_plans(snapshot.item_requests)
  if #plans == 0 then
    return
  end

  entity.surface.create_entity {
    name = "item-request-proxy",
    target = entity,
    modules = plans,
    force = entity.force,
    raise_built = true
  }
end

local function serialize_live_ghost(entity)
  return {
    kind = entity.type,
    surface_index = entity.surface.index,
    force_name = entity.force.name,
    position = util.copy_position(entity.position),
    inner_name = entity.ghost_name,
    direction = entity.type == "entity-ghost" and entity.direction or nil,
    quality_name = util.quality_name(entity.quality),
    tags = entity.type == "entity-ghost" and util.copy_value(entity.tags) or nil,
    item_requests = entity.type == "entity-ghost" and util.copy_item_requests(entity.item_requests) or {},
    source_unit_number = entity.unit_number
  }
end

local function serialize_marked_entity(entity, kind, player_index, target, quality)
  local snapshot = {
    kind = kind,
    surface_index = entity.surface.index,
    force_name = entity.force.name,
    position = util.copy_position(entity.position),
    entity_name = entity.name,
    entity_quality_name = util.quality_name(entity.quality),
    entity_unit_number = entity.unit_number,
    player_index = player_index
  }

  if kind == "upgrade" then
    local resolved_target = target
    local resolved_quality = quality

    if resolved_target == nil then
      resolved_target, resolved_quality = util.safe_get_upgrade_target(entity)
    end

    snapshot.target_name = resolved_target and resolved_target.name or nil
    snapshot.target_quality_name = util.quality_name(resolved_quality)
  end

  return snapshot
end

local function build_live_ghost_candidate(root, entity)
  local key = make_ghost_key(
    entity.type,
    entity.surface.index,
    entity.force.name,
    entity.position,
    entity.ghost_name,
    entity.direction,
    util.quality_name(entity.quality)
  )

  local deferred_task_id = root.deferred_task_keys[key]

  return {
    key = key,
    kind = entity.type,
    position = util.copy_position(entity.position),
    live_entity = entity,
    task = deferred_task_id and root.deferred_tasks[deferred_task_id] or nil
  }
end

local function build_live_mark_candidate(root, entity, kind, player_index, target, quality)
  local target_name = target and target.name or nil
  local target_quality_name = util.quality_name(quality)
  local key = make_mark_key(kind, entity.surface.index, entity.force.name, entity, target_name, target_quality_name)
  local deferred_task_id = root.deferred_task_keys[key]

  return {
    key = key,
    kind = kind,
    position = util.copy_position(entity.position),
    live_entity = entity,
    player_index = player_index,
    target = target,
    quality = quality,
    task = deferred_task_id and root.deferred_tasks[deferred_task_id] or nil
  }
end

local function resolve_watch_entity(watch)
  if watch.live_entity_unit_number ~= nil then
    local by_unit_number = game.get_entity_by_unit_number(watch.live_entity_unit_number)
    if by_unit_number ~= nil and by_unit_number.valid then
      return by_unit_number
    end
  end

  local surface = game.surfaces[watch.surface_index]
  if surface == nil then
    return nil
  end

  local entities = surface.find_entities_filtered {
    position = watch.position,
    force = watch.force_name,
    type = watch.kind,
    ghost_name = watch.inner_name,
    limit = 1
  }

  return entities[1]
end

local function resolve_mark_target(snapshot)
  return util.find_entity_by_snapshot(snapshot)
end

local function restore_ghost(snapshot)
  local surface = game.surfaces[snapshot.surface_index]
  if surface == nil then
    return nil
  end

  local params = {
    name = snapshot.kind,
    position = snapshot.position,
    inner_name = snapshot.inner_name,
    force = snapshot.force_name,
    quality = snapshot.quality_name,
    raise_built = true
  }

  if snapshot.kind == "entity-ghost" then
    params.direction = snapshot.direction
    params.tags = snapshot.tags
  end

  local entity = surface.create_entity(params)
  if entity ~= nil and entity.valid and snapshot.kind == "entity-ghost" then
    restore_item_requests(entity, snapshot)
  end

  return entity
end

local function reapply_mark(snapshot)
  local entity = resolve_mark_target(snapshot)
  if entity == nil or not entity.valid then
    return nil
  end

  if snapshot.kind == "deconstruction" then
    entity.order_deconstruction(snapshot.force_name, snapshot.player_index)
    return entity
  end

  if snapshot.kind == "upgrade" and snapshot.target_name ~= nil then
    local target = snapshot.target_quality_name ~= nil
      and { name = snapshot.target_name, quality = snapshot.target_quality_name }
      or { name = snapshot.target_name }

    entity.order_upgrade {
      force = snapshot.force_name,
      target = target,
      player = snapshot.player_index
    }

    return entity
  end

  return nil
end

local function cancel_mark(candidate)
  if candidate.kind == "deconstruction" then
    candidate.live_entity.cancel_deconstruction(candidate.live_entity.force)
    return
  end

  if candidate.kind == "upgrade" then
    candidate.live_entity.cancel_upgrade(candidate.live_entity.force, candidate.player_index)
  end
end

local function mark_is_blockable(candidate)
  if candidate.kind == "deconstruction" then
    return candidate.live_entity.is_registered_for_deconstruction(candidate.live_entity.force)
  end

  return candidate.live_entity.is_registered_for_upgrade()
end

local function ghost_is_blockable(entity)
  return entity.is_registered_for_construction()
end

local function choose_network_for_position(context, position)
  local best = nil

  for _, network in ipairs(context.network_list) do
    local covering = network_cache.covering_cells(network, position)
    local cell = covering[1]

    if cell ~= nil then
      local distance_from_seed = cell.distance_from_seed
      local reachable = distance_from_seed ~= nil
      local owner_distance = util.distance_squared(cell.position, position)

      if best == nil then
        best = {
          network = network,
          cell = cell,
          reachable = reachable,
          owner_distance = owner_distance
        }
      else
        local prefer = false

        if reachable ~= best.reachable then
          prefer = reachable
        elseif reachable and best.reachable then
          if distance_from_seed ~= best.cell.distance_from_seed then
            prefer = distance_from_seed < best.cell.distance_from_seed
          else
            prefer = owner_distance < best.owner_distance
          end
        else
          prefer = owner_distance < best.owner_distance
        end

        if prefer then
          best = {
            network = network,
            cell = cell,
            reachable = reachable,
            owner_distance = owner_distance
          }
        end
      end
    end
  end

  return best
end

local function analyze_candidate(force, context, threat, candidate)
  local best = choose_network_for_position(context, candidate.position)
  if best == nil then
    return {
      status = "outside_coverage",
      reason = "outside_coverage"
    }
  end

  if best.cell.distance_from_seed == nil then
    return {
      status = "blocked",
      reason = "blocked_no_route",
      network_key = best.network.network_key,
      distance_from_seed = nil
    }
  end

  if best.cell.distance_from_seed > constants.FRONTIER_DEPTH then
    return {
      status = "blocked",
      reason = "blocked_frontier",
      network_key = best.network.network_key,
      distance_from_seed = best.cell.distance_from_seed
    }
  end

  local safe = network_cache.path_to_position_is_safe(best.network, force, threat, best.cell.id, candidate.position)
  if not safe then
    return {
      status = "blocked",
      reason = "blocked_no_route",
      network_key = best.network.network_key,
      distance_from_seed = best.cell.distance_from_seed
    }
  end

  return {
    status = "released",
    reason = "released",
    network_key = best.network.network_key,
    distance_from_seed = best.cell.distance_from_seed
  }
end

local function keep_live_ghost_visible(root, candidate)
  if candidate.live_entity ~= nil and candidate.live_entity.valid then
    upsert_watch(root, candidate.live_entity)
  end

  if candidate.task ~= nil then
    remove_deferred_task(root, candidate.task.id)
  end
end

local function block_live_ghost(root, candidate, analysis)
  if not ghost_is_blockable(candidate.live_entity) then
    remove_watch(root, candidate.key)
    return "already_dispatched"
  end

  local snapshot = serialize_live_ghost(candidate.live_entity)
  if has_unsupported_item_requests(snapshot) then
    upsert_watch(root, candidate.live_entity)

    if candidate.task ~= nil then
      remove_deferred_task(root, candidate.task.id)
    end

    return "unsupported_item_requests"
  end

  candidate.live_entity.destroy { raise_destroy = true }
  upsert_deferred_task(root, candidate.key, snapshot, analysis.reason, analysis.network_key, nil)
  remove_watch(root, candidate.key)
  return "deferred"
end

local function block_live_mark(root, candidate, analysis)
  if not mark_is_blockable(candidate) then
    return "already_dispatched"
  end

  local snapshot = serialize_marked_entity(
    candidate.live_entity,
    candidate.kind,
    candidate.player_index,
    candidate.target,
    candidate.quality
  )

  cancel_mark(candidate)
  upsert_deferred_task(root, candidate.key, snapshot, analysis.reason, analysis.network_key, candidate.live_entity)
  return "deferred"
end

local function keep_deferred(root, candidate, analysis)
  local task = candidate.task
  if task == nil then
    task = upsert_deferred_task(root, candidate.key, candidate.snapshot, analysis.reason, analysis.network_key, nil)
  else
    task.block_reason = analysis.reason
    task.network_key = analysis.network_key
    task.last_status = analysis.reason
    task.updated_tick = game.tick
  end

  return task
end

local function release_deferred_task(root, candidate)
  if candidate.task.kind == "entity-ghost" or candidate.task.kind == "tile-ghost" then
    local restored = restore_ghost(candidate.task.snapshot)
    if restored ~= nil and restored.valid then
      remove_deferred_task(root, candidate.task.id)
      remove_watch(root, candidate.key)
      return "restored"
    end

    candidate.task.last_status = "restore_failed"
    candidate.task.updated_tick = game.tick
    return "restore_failed"
  end

  local restored_mark = reapply_mark(candidate.task.snapshot)
  if restored_mark ~= nil and restored_mark.valid then
    remove_deferred_task(root, candidate.task.id)
    return "reapplied"
  end

  remove_deferred_task(root, candidate.task.id)
  return "target_missing"
end

local function release_live_candidate(root, candidate)
  remove_watch(root, candidate.key)

  if candidate.task ~= nil then
    remove_deferred_task(root, candidate.task.id)
  end

  return "released"
end

local function evaluate_candidate(root, force, context, threat, candidate)
  local analysis = analyze_candidate(force, context, threat, candidate)

  if candidate.live_entity ~= nil then
    if candidate.kind == "entity-ghost" or candidate.kind == "tile-ghost" then
      if analysis.status == "outside_coverage" then
        keep_live_ghost_visible(root, candidate)
        return analysis.status
      end

      if analysis.status == "blocked" then
        return block_live_ghost(root, candidate, analysis)
      end

      return release_live_candidate(root, candidate)
    end

    if analysis.status ~= "released" then
      return block_live_mark(root, candidate, analysis)
    end

    return release_live_candidate(root, candidate)
  end

  if candidate.task ~= nil then
    if analysis.status == "released" then
      return release_deferred_task(root, candidate)
    end

    keep_deferred(root, candidate, analysis)
    return analysis.reason
  end

  return "ignored"
end

local function add_candidate(seen, ordered, candidate)
  if candidate == nil or seen[candidate.key] ~= nil then
    return
  end

  seen[candidate.key] = candidate
  ordered[#ordered + 1] = candidate
end

local function collect_scanned_candidates(root, force, surface, context)
  local seen = {}
  local ordered = {}
  local force_surface_key = util.force_surface_key(surface.index, force.name)

  if root.full_rescan_force_surfaces[force_surface_key] then
    local ghosts = surface.find_entities_filtered {
      force = force.name,
      type = constants.CONSTRUCTION_GHOST_TYPES
    }

    for _, ghost in ipairs(ghosts) do
      add_candidate(seen, ordered, build_live_ghost_candidate(root, ghost))
    end

    local deconstruction_targets = surface.find_entities_filtered {
      force = force.name,
      to_be_deconstructed = true
    }

    for _, entity in ipairs(deconstruction_targets) do
      add_candidate(seen, ordered, build_live_mark_candidate(root, entity, "deconstruction"))
    end

    local upgrade_targets = surface.find_entities_filtered {
      force = force.name,
      to_be_upgraded = true
    }

    for _, entity in ipairs(upgrade_targets) do
      local target, quality = util.safe_get_upgrade_target(entity)
      add_candidate(seen, ordered, build_live_mark_candidate(root, entity, "upgrade", nil, target, quality))
    end
  end

  for _, network in ipairs(context.network_list) do
    if #ordered >= constants.MAX_CANDIDATES_PER_RECHECK then
      break
    end

    local ghosts = surface.find_entities_filtered {
      area = network.bounds,
      force = force.name,
      type = constants.CONSTRUCTION_GHOST_TYPES
    }

    for _, ghost in ipairs(ghosts) do
      add_candidate(seen, ordered, build_live_ghost_candidate(root, ghost))
    end

    local deconstruction_targets = surface.find_entities_filtered {
      area = network.bounds,
      force = force.name,
      to_be_deconstructed = true
    }

    for _, entity in ipairs(deconstruction_targets) do
      add_candidate(seen, ordered, build_live_mark_candidate(root, entity, "deconstruction"))
    end

    local upgrade_targets = surface.find_entities_filtered {
      area = network.bounds,
      force = force.name,
      to_be_upgraded = true
    }

    for _, entity in ipairs(upgrade_targets) do
      local target, quality = util.safe_get_upgrade_target(entity)
      add_candidate(seen, ordered, build_live_mark_candidate(root, entity, "upgrade", nil, target, quality))
    end
  end

  for key, watch in pairs(root.watch_ghosts) do
    if watch.surface_index == surface.index and watch.force_name == force.name then
      local live_entity = resolve_watch_entity(watch)
      if live_entity ~= nil and live_entity.valid then
        add_candidate(seen, ordered, build_live_ghost_candidate(root, live_entity))
      else
        remove_watch(root, key)
      end
    end
  end

  for _, task in pairs(root.deferred_tasks) do
    if task.surface_index == surface.index and task.force_name == force.name and seen[task.key] == nil then
      add_candidate(seen, ordered, {
        key = task.key,
        kind = task.kind,
        position = util.copy_position(task.position),
        task = task,
        snapshot = util.copy_value(task.snapshot)
      })
    end
  end

  return ordered
end

function tasks.rebuild_indexes(root)
  root.deferred_task_keys = {}
  root.task_counts_by_force_surface = {}
  root.watch_counts_by_force_surface = {}

  for _, task in pairs(root.deferred_tasks) do
    root.deferred_task_keys[task.key] = task.id
    adjust_count(root.task_counts_by_force_surface, task_force_surface_key(task), 1)
  end

  for _, watch in pairs(root.watch_ghosts) do
    adjust_count(root.watch_counts_by_force_surface, util.force_surface_key(watch.surface_index, watch.force_name), 1)
  end
end

function tasks.handle_object_destroyed(root, registration_number)
  local registration = root.object_registrations[registration_number]
  if registration == nil then
    return
  end

  root.object_registrations[registration_number] = nil

  if registration.kind == "watch" then
    remove_watch(root, registration.key)
    return
  end

  if registration.kind == "task" then
    remove_deferred_task(root, registration.task_id)
  end
end

function tasks.evaluate_live_ghost(root, force, context, threat, entity)
  local candidate = build_live_ghost_candidate(root, entity)
  return evaluate_candidate(root, force, context, threat, candidate)
end

function tasks.evaluate_live_mark(root, force, context, threat, entity, kind, player_index, target, quality)
  local candidate = build_live_mark_candidate(root, entity, kind, player_index, target, quality)
  return evaluate_candidate(root, force, context, threat, candidate)
end

function tasks.recheck_force_surface(root, force, surface, context, threat)
  local summary = {
    scanned_candidates = 0,
    deferred = 0,
    restored = 0,
    reapplied = 0,
    watched = 0
  }

  local candidates = collect_scanned_candidates(root, force, surface, context)
  summary.scanned_candidates = #candidates

  for _, candidate in ipairs(candidates) do
    local result = evaluate_candidate(root, force, context, threat, candidate)

    if result == "deferred" or result == "blocked_frontier" or result == "blocked_no_route" then
      summary.deferred = summary.deferred + 1
    elseif result == "restored" then
      summary.restored = summary.restored + 1
    elseif result == "reapplied" then
      summary.reapplied = summary.reapplied + 1
    elseif result == "outside_coverage" then
      summary.watched = summary.watched + 1
    end
  end

  return summary
end

return tasks
