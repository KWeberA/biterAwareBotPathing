local MOD_NAME = "biter_aware_bot_pathing"

local function fail(message)
  error("BABP validation harness: " .. message)
end

local function require_entity(entity, label)
  if entity == nil or not entity.valid then
    fail(label .. " was not created")
  end

  return entity
end

local function destroy_entities_at(surface, position)
  for _, entity in ipairs(surface.find_entities_filtered { position = position }) do
    if entity.valid then
      entity.destroy { raise_destroy = true }
    end
  end
end

local function create_live_ghost(surface, force, inner_name, position)
  return surface.create_entity {
    name = "entity-ghost",
    inner_name = inner_name,
    position = position,
    force = force,
    raise_built = true
  }
end

local function validate_test_map(summary, run_index)
  if summary == nil then
    fail("test_map_setup returned nil on run " .. run_index)
  end

  local counts = summary.counts or {}
  if summary.surface_name ~= "babp-test-map" then
    fail("unexpected test map surface on run " .. run_index .. ": " .. tostring(summary.surface_name))
  end

  if counts.roboports ~= 15 then
    fail("expected 15 roboports on run " .. run_index .. ", got " .. tostring(counts.roboports))
  end

  if counts.biter_spawners ~= 5 then
    fail("expected 5 biter spawners on run " .. run_index .. ", got " .. tostring(counts.biter_spawners))
  end

  if counts.worms ~= 3 then
    fail("expected 3 worms on run " .. run_index .. ", got " .. tostring(counts.worms))
  end

  if counts.spitters ~= 6 then
    fail("expected 6 spitters on run " .. run_index .. ", got " .. tostring(counts.spitters))
  end

  if counts.construction_robots_in_outer_right_roboport ~= 10 then
    fail("expected 10 construction robots on run " .. run_index .. ", got " .. tostring(counts.construction_robots_in_outer_right_roboport))
  end

  local right_roboport = summary.right_arm_outer_roboport or {}
  if right_roboport.x ~= 172 or right_roboport.y ~= 32 then
    fail("unexpected right roboport position on run " .. run_index)
  end
end

local function run_live_path_validation(summary)
  if summary == nil then
    fail("smoke_setup returned nil")
  end

  local surface = game.surfaces[summary.surface_name]
  local force = game.forces[summary.force_name]
  if surface == nil then
    fail("smoke_setup returned missing surface")
  end

  if force == nil then
    fail("smoke_setup returned missing force")
  end

  local technology = force.technologies["logistics-2"]
  if technology ~= nil then
    technology.researched = true
  end

  local safe_build_position = {
    x = summary.origin.x + 8,
    y = summary.origin.y + 8
  }
  local unsafe_build_position = {
    x = summary.origin.x + 76,
    y = summary.origin.y + 48
  }
  local unsafe_deconstruction_position = {
    x = summary.origin.x + 72,
    y = summary.origin.y + 50
  }

  local resolved_safe_build_position = surface.find_non_colliding_position(
    "steel-chest",
    safe_build_position,
    16,
    1,
    true
  )
  if resolved_safe_build_position == nil then
    fail("could not find a safe live build position near the seeded roboport")
  end

  safe_build_position = resolved_safe_build_position

  destroy_entities_at(surface, safe_build_position)
  local resolved_unsafe_build_position = surface.find_non_colliding_position(
    "stone-wall",
    unsafe_build_position,
    8,
    1,
    true
  )
  if resolved_unsafe_build_position == nil then
    fail("could not find an unsafe live build position near the threat ring")
  end

  unsafe_build_position = resolved_unsafe_build_position

  destroy_entities_at(surface, unsafe_build_position)

  local safe_ghost = create_live_ghost(surface, force, "stone-wall", safe_build_position)
  if safe_ghost == nil then
    fail("safe live build ghost could not be created")
  end

  if not safe_ghost.valid then
    fail("safe live build ghost was unexpectedly deferred")
  end

  local unsafe_ghost = create_live_ghost(surface, force, "stone-wall", unsafe_build_position)
  if unsafe_ghost ~= nil and unsafe_ghost.valid then
    fail("unsafe live build ghost was not deferred")
  end

  local remaining_unsafe_ghost = surface.find_entities_filtered {
    position = unsafe_build_position,
    type = "entity-ghost",
    force = force.name,
    limit = 1
  }[1]
  if remaining_unsafe_ghost ~= nil and remaining_unsafe_ghost.valid then
    fail("unsafe live build ghost is still present after defer")
  end

  local resolved_unsafe_deconstruction_position = surface.find_non_colliding_position(
    "stone-wall",
    unsafe_deconstruction_position,
    8,
    1,
    true
  )
  if resolved_unsafe_deconstruction_position == nil then
    fail("could not find an unsafe deconstruction position near the threat ring")
  end

  unsafe_deconstruction_position = resolved_unsafe_deconstruction_position

  destroy_entities_at(surface, unsafe_deconstruction_position)
  local wall = require_entity(surface.create_entity {
    name = "stone-wall",
    position = unsafe_deconstruction_position,
    force = force,
    raise_built = true
  }, "validation wall")

  if not wall.order_deconstruction(force) then
    fail("unsafe deconstruction target could not be marked")
  end

  if not wall.valid then
    fail("unsafe deconstruction target was destroyed unexpectedly")
  end

  if wall.is_registered_for_deconstruction(force.name) then
    fail("unsafe deconstruction target was not deferred")
  end

  return {
    smoke_setup = summary,
    safe_build_position = safe_build_position,
    safe_build_kept_visible = true,
    unsafe_build_position = unsafe_build_position,
    unsafe_build_deferred = true,
    unsafe_deconstruction_position = unsafe_deconstruction_position,
    unsafe_deconstruction_deferred = true
  }
end

local function run_validation()
  local player_run_index = game.players[1] ~= nil and 1 or nil
  local result = {
    smoke = run_live_path_validation(storage.validation.smoke_setup),
    test_map_runs = {
      remote.call(MOD_NAME, "test_map_setup"),
      remote.call(MOD_NAME, "test_map_setup", player_run_index)
    }
  }

  for index, summary in ipairs(result.test_map_runs) do
    validate_test_map(summary, index)
  end

  if player_run_index ~= nil and type(result.test_map_runs[2].teleported) ~= "boolean" then
    fail("expected player-driven test map run to report a boolean teleported flag")
  end

  helpers.write_file(
    "biter-aware-bot-pathing/validation-test-map.json",
    helpers.table_to_json(result),
    false
  )
end

script.on_init(function()
  storage.validation = {
    completed = false,
    stage = "build-smoke-lab",
    wait_until_tick = nil,
    smoke_setup = nil
  }
end)

script.on_nth_tick(1, function()
  if storage.validation ~= nil and storage.validation.completed then
    script.on_nth_tick(1, nil)
    return
  end

  if storage.validation.stage == "build-smoke-lab" then
    storage.validation.smoke_setup = remote.call(MOD_NAME, "smoke_setup")
    storage.validation.stage = "run-validation"
    storage.validation.wait_until_tick = game.tick + 1
    return
  end

  if storage.validation.wait_until_tick ~= nil and game.tick < storage.validation.wait_until_tick then
    return
  end

  run_validation()
  storage.validation = {
    completed = true
  }
  script.on_nth_tick(1, nil)
end)
