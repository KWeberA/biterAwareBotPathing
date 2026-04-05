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

local function run_mark_path_validation()
  local summary = remote.call(MOD_NAME, "smoke_setup")
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

  local wall_position = {
    x = summary.origin.x + 60,
    y = summary.origin.y + 52
  }
  local belt_position = {
    x = summary.origin.x + 60,
    y = summary.origin.y + 48
  }

  local wall = require_entity(surface.create_entity {
    name = "stone-wall",
    position = wall_position,
    force = force,
    raise_built = true
  }, "validation wall")
  local belt = require_entity(surface.create_entity {
    name = "transport-belt",
    position = belt_position,
    force = force,
    raise_built = true
  }, "validation belt")

  wall.order_deconstruction(force)
  belt.order_upgrade {
    force = force,
    target = { name = "fast-transport-belt" }
  }

  return {
    smoke_setup = summary,
    deconstruction_order_called = true,
    upgrade_order_called = true,
    wall_position = wall_position,
    belt_position = belt_position
  }
end

local function run_validation()
  local player_run_index = game.players[1] ~= nil and 1 or nil
  local result = {
    smoke = run_mark_path_validation(),
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
    completed = false
  }
end)

script.on_nth_tick(1, function()
  if storage.validation ~= nil and storage.validation.completed then
    script.on_nth_tick(1, nil)
    return
  end

  run_validation()
  storage.validation = {
    completed = true
  }
  script.on_nth_tick(1, nil)
end)
