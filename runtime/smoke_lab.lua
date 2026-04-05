local constants = require("runtime.constants")
local util = require("runtime.util")

local smoke_lab = {}

local function create_entity(surface, params)
  local entity = surface.create_entity(params)
  if entity ~= nil and entity.valid and params.energy ~= nil then
    entity.energy = params.energy
  end

  return entity
end

local function add_tile_rectangle(tiles, tile_name, left_top, right_bottom)
  for x = left_top.x, right_bottom.x do
    for y = left_top.y, right_bottom.y do
      tiles[#tiles + 1] = {
        name = tile_name,
        position = { x = x, y = y }
      }
    end
  end
end

local function fill(entity, item_name, count)
  if entity ~= nil and entity.valid and count > 0 then
    entity.insert { name = item_name, count = count }
  end
end

local function create_power_block(surface, force, origin)
  local created = {}

  created[#created + 1] = create_entity(surface, {
    name = "substation",
    position = { x = origin.x - 4, y = origin.y - 4 },
    force = force,
    raise_built = true
  })

  for x = -12, -4, 4 do
    created[#created + 1] = create_entity(surface, {
      name = "solar-panel",
      position = { x = origin.x + x, y = origin.y - 14 },
      force = force,
      raise_built = true
    })
  end

  for y = -10, -2, 4 do
    local accumulator = create_entity(surface, {
      name = "accumulator",
      position = { x = origin.x - 14, y = origin.y + y },
      force = force,
      raise_built = true
    })

    if accumulator ~= nil and accumulator.valid then
      accumulator.energy = accumulator.electric_buffer_size
    end

    created[#created + 1] = accumulator
  end

  return created
end

local function create_power_links(surface, force, origin)
  local pole_positions = {
    { x = origin.x + 4, y = origin.y },
    { x = origin.x + 4, y = origin.y + 8 },
    { x = origin.x + 4, y = origin.y + 16 },
    { x = origin.x + 4, y = origin.y + 24 },
    { x = origin.x + 4, y = origin.y + 32 },
    { x = origin.x + 4, y = origin.y + 40 },
    { x = origin.x + 12, y = origin.y + 40 },
    { x = origin.x + 20, y = origin.y + 40 },
    { x = origin.x + 28, y = origin.y + 40 },
    { x = origin.x + 36, y = origin.y + 40 },
    { x = origin.x + 44, y = origin.y + 40 }
  }

  for _, position in ipairs(pole_positions) do
    create_entity(surface, {
      name = "medium-electric-pole",
      position = position,
      force = force,
      raise_built = true
    })
  end
end

local function create_roboport(surface, force, position)
  local roboport = create_entity(surface, {
    name = "roboport",
    position = position,
    force = force,
    raise_built = true
  })

  if roboport ~= nil and roboport.valid then
    roboport.energy = roboport.electric_buffer_size
  end

  return roboport
end

local function create_wall_line(surface, force, from_position, to_position)
  if from_position.x == to_position.x then
    local start_y = math.min(from_position.y, to_position.y)
    local end_y = math.max(from_position.y, to_position.y)

    for y = start_y, end_y do
      create_entity(surface, {
        name = "stone-wall",
        position = { x = from_position.x, y = y },
        force = force,
        raise_built = true
      })
    end

    return
  end

  local start_x = math.min(from_position.x, to_position.x)
  local end_x = math.max(from_position.x, to_position.x)
  for x = start_x, end_x do
    create_entity(surface, {
      name = "stone-wall",
      position = { x = x, y = from_position.y },
      force = force,
      raise_built = true
    })
  end
end

local function create_provider_setup(surface, force, origin)
  local pole = create_entity(surface, {
    name = "medium-electric-pole",
    position = { x = origin.x + 3, y = origin.y + 2 },
    force = force,
    raise_built = true
  })

  local provider = create_entity(surface, {
    name = "logistic-chest-passive-provider",
    position = { x = origin.x + 6, y = origin.y + 2 },
    force = force,
    raise_built = true
  })

  fill(provider, "construction-robot", 60)
  fill(provider, "stone-wall", 200)
  fill(provider, "steel-chest", 40)
  fill(provider, "radar", 10)
  fill(provider, "stone-brick", 400)
  fill(provider, "fast-transport-belt", 80)

  return pole, provider
end

local function create_enemy_ring(surface, origin)
  local enemy_force = game.forces.enemy
  local threats = {
    { name = "medium-worm-turret", position = { x = origin.x + 74, y = origin.y + 44 } },
    { name = "medium-worm-turret", position = { x = origin.x + 84, y = origin.y + 56 } },
    { name = "biter-spawner", position = { x = origin.x + 82, y = origin.y + 48 } }
  }

  for _, threat in ipairs(threats) do
    create_entity(surface, {
      name = threat.name,
      position = threat.position,
      force = enemy_force,
      raise_built = true
    })
  end
end

local function create_smoke_targets(surface, force, origin)
  surface.create_entity {
    name = "entity-ghost",
    inner_name = "stone-wall",
    position = { x = origin.x + 8, y = origin.y + 8 },
    force = force,
    raise_built = true
  }

  surface.create_entity {
    name = "entity-ghost",
    inner_name = "steel-chest",
    position = { x = origin.x + 10, y = origin.y + 42 },
    force = force,
    raise_built = true
  }

  surface.create_entity {
    name = "entity-ghost",
    inner_name = "steel-chest",
    position = { x = origin.x + 42, y = origin.y + 42 },
    force = force,
    raise_built = true
  }

  surface.create_entity {
    name = "entity-ghost",
    inner_name = "radar",
    position = { x = origin.x + 76, y = origin.y + 48 },
    force = force,
    raise_built = true
  }

  surface.create_entity {
    name = "tile-ghost",
    inner_name = "stone-path",
    position = { x = origin.x + 11, y = origin.y + 43 },
    force = force,
    raise_built = true
  }
end

local function create_marked_targets(surface, force, origin)
  local wall = create_entity(surface, {
    name = "stone-wall",
    position = { x = origin.x + 72, y = origin.y + 50 },
    force = force,
    raise_built = true
  })

  local belt = create_entity(surface, {
    name = "transport-belt",
    position = { x = origin.x + 70, y = origin.y + 46 },
    force = force,
    raise_built = true
  })

  if wall ~= nil and wall.valid then
    wall.order_deconstruction(force)
  end

  local technology = force.technologies["logistics-2"]
  if technology ~= nil then
    technology.researched = true
  end

  if belt ~= nil and belt.valid then
    belt.order_upgrade {
      force = force,
      target = { name = "fast-transport-belt" }
    }
  end
end

local function ensure_test_map_surface()
  local surface = game.surfaces[constants.TEST_MAP_SURFACE_NAME]
  if surface == nil then
    surface = game.create_surface(constants.TEST_MAP_SURFACE_NAME)
  end

  surface.request_to_generate_chunks({ 64, 64 }, 8)
  surface.force_generate_chunk_requests()
  surface.always_day = true
  surface.freeze_daytime = true
  surface.daytime = 0.5
  surface.peaceful_mode = false
  surface.no_enemies_mode = false

  return surface
end

local function clear_test_map_area(surface, area)
  local safe_position = {
    x = area.left_top.x - 16,
    y = area.left_top.y - 16
  }

  for _, player in pairs(game.connected_players) do
    if player.valid and player.surface == surface and util.bbox_contains(area, player.position) then
      player.teleport(safe_position, surface)
    end
  end

  for _, entity in ipairs(surface.find_entities(area)) do
    if entity.valid and entity.type ~= "character" then
      entity.destroy()
    end
  end
end

local function pave_test_map(surface, corner, leg_length, arm_half_width, clear_padding)
  local area = {
    left_top = {
      x = corner.x - clear_padding,
      y = corner.y - clear_padding
    },
    right_bottom = {
      x = corner.x + leg_length + clear_padding,
      y = corner.y + leg_length + clear_padding
    }
  }

  clear_test_map_area(surface, area)

  local tiles = {}
  add_tile_rectangle(tiles, "landfill", area.left_top, area.right_bottom)
  add_tile_rectangle(tiles, "refined-concrete", {
    x = corner.x,
    y = corner.y - arm_half_width
  }, {
    x = corner.x + leg_length - 1,
    y = corner.y + arm_half_width
  })
  add_tile_rectangle(tiles, "refined-concrete", {
    x = corner.x - arm_half_width,
    y = corner.y
  }, {
    x = corner.x + arm_half_width,
    y = corner.y + leg_length - 1
  })

  surface.set_tiles(tiles, true)
  return area
end

local function create_test_map_power(surface, force, corner, leg_length)
  create_entity(surface, {
    name = "substation",
    position = { x = corner.x - 12, y = corner.y - 12 },
    force = force,
    raise_built = true
  })

  for x = corner.x - 24, corner.x - 4, 4 do
    for y = corner.y - 24, corner.y - 4, 4 do
      if not (x == corner.x - 12 and y == corner.y - 12) then
        create_entity(surface, {
          name = "solar-panel",
          position = { x = x, y = y },
          force = force,
          raise_built = true
        })
      end
    end
  end

  for _, position in ipairs({
    { x = corner.x - 20, y = corner.y - 12 },
    { x = corner.x - 12, y = corner.y - 20 },
    { x = corner.x - 20, y = corner.y - 20 }
  }) do
    local accumulator = create_entity(surface, {
      name = "accumulator",
      position = position,
      force = force,
      raise_built = true
    })

    if accumulator ~= nil and accumulator.valid then
      accumulator.energy = accumulator.electric_buffer_size
    end
  end

  for x = corner.x - 4, corner.x + leg_length, 9 do
    create_entity(surface, {
      name = "medium-electric-pole",
      position = { x = x, y = corner.y - 4 },
      force = force,
      raise_built = true
    })
  end

  for y = corner.y + 5, corner.y + leg_length, 9 do
    create_entity(surface, {
      name = "medium-electric-pole",
      position = { x = corner.x - 4, y = y },
      force = force,
      raise_built = true
    })
  end
end

local function create_test_map_walls(surface, force, corner, leg_length, arm_half_width)
  local wall_offset = arm_half_width + 2
  create_wall_line(surface, force, {
    x = corner.x - 1,
    y = corner.y - wall_offset
  }, {
    x = corner.x + leg_length,
    y = corner.y - wall_offset
  })
  create_wall_line(surface, force, {
    x = corner.x - 1,
    y = corner.y + wall_offset
  }, {
    x = corner.x + leg_length,
    y = corner.y + wall_offset
  })
  create_wall_line(surface, force, {
    x = corner.x - wall_offset,
    y = corner.y - 1
  }, {
    x = corner.x - wall_offset,
    y = corner.y + leg_length
  })
  create_wall_line(surface, force, {
    x = corner.x + wall_offset,
    y = corner.y - 1
  }, {
    x = corner.x + wall_offset,
    y = corner.y + leg_length
  })
end

local function create_test_map_roboports(surface, force, corner, leg_length, spacing)
  local roboports = {}

  for offset = 0, leg_length - 1, spacing do
    roboports[#roboports + 1] = create_roboport(surface, force, {
      x = corner.x + offset,
      y = corner.y
    })
  end

  for offset = spacing, leg_length - 1, spacing do
    roboports[#roboports + 1] = create_roboport(surface, force, {
      x = corner.x,
      y = corner.y + offset
    })
  end

  return roboports
end

local function create_diagonal_threats(surface, corner)
  local enemy_force = game.forces.enemy
  local nests = {}
  local worms = {}
  local spitters = {}

  for _, position in ipairs({
    { x = corner.x + 24, y = corner.y + 126 },
    { x = corner.x + 48, y = corner.y + 102 },
    { x = corner.x + 75, y = corner.y + 75 },
    { x = corner.x + 102, y = corner.y + 48 },
    { x = corner.x + 126, y = corner.y + 24 }
  }) do
    nests[#nests + 1] = create_entity(surface, {
      name = "biter-spawner",
      position = position,
      force = enemy_force,
      raise_built = true
    })
  end

  for _, position in ipairs({
    { x = corner.x + 40, y = corner.y + 118 },
    { x = corner.x + 75, y = corner.y + 90 },
    { x = corner.x + 118, y = corner.y + 40 }
  }) do
    worms[#worms + 1] = create_entity(surface, {
      name = "medium-worm-turret",
      position = position,
      force = enemy_force,
      raise_built = true
    })
  end

  for _, position in ipairs({
    { x = corner.x + 64, y = corner.y + 84 },
    { x = corner.x + 70, y = corner.y + 78 },
    { x = corner.x + 72, y = corner.y + 84 },
    { x = corner.x + 76, y = corner.y + 72 },
    { x = corner.x + 84, y = corner.y + 64 },
    { x = corner.x + 84, y = corner.y + 72 }
  }) do
    spitters[#spitters + 1] = create_entity(surface, {
      name = "medium-spitter",
      position = position,
      force = enemy_force,
      raise_built = true
    })
  end

  return nests, worms, spitters
end

local function count_valid(entities)
  local count = 0
  for _, entity in ipairs(entities) do
    if entity ~= nil and entity.valid then
      count = count + 1
    end
  end

  return count
end

local function find_player(player_index)
  if player_index == nil then
    return nil
  end

  local player = game.get_player(player_index)
  if player ~= nil and player.valid then
    return player
  end

  return nil
end

local function run_setup_step(step_name, work)
  local ok, result_a, result_b, result_c = pcall(work)
  if not ok then
    error("test map step '" .. step_name .. "' failed: " .. result_a)
  end

  return result_a, result_b, result_c
end

function smoke_lab.setup(root, player_index)
  local player = find_player(player_index)
  local surface = player and player.valid and player.surface or game.surfaces[1]
  local force = player and player.valid and player.force or game.forces.player
  local origin = {
    x = math.floor((player and player.position.x or 0) / 32) * 32 + 32,
    y = math.floor((player and player.position.y or 0) / 32) * 32 + 32
  }

  create_power_block(surface, force, origin)
  create_power_links(surface, force, origin)
  create_provider_setup(surface, force, origin)

  local roboport_positions = {
    { x = origin.x, y = origin.y },
    { x = origin.x, y = origin.y + 40 },
    { x = origin.x + 40, y = origin.y + 40 }
  }

  for index, position in ipairs(roboport_positions) do
    local roboport = create_roboport(surface, force, position)
    if index == 1 then
      fill(roboport, "construction-robot", 50)
    end
  end

  create_enemy_ring(surface, origin)
  create_smoke_targets(surface, force, origin)
  create_marked_targets(surface, force, origin)

  local force_surface_key = util.force_surface_key(surface.index, force.name)
  root.smoke_labs[force_surface_key] = {
    name = constants.SMOKE_LAB_NAME,
    origin = util.copy_position(origin),
    surface_index = surface.index,
    force_name = force.name,
    built_tick = game.tick
  }

  return {
    surface_name = surface.name,
    force_name = force.name,
    origin = origin
  }
end

function smoke_lab.setup_test_map(root, player_index)
  local leg_length = 150
  local roboport_spacing = 20
  local arm_half_width = 10
  local clear_padding = 40
  local player = find_player(player_index)
  local force = player and player.force or game.forces.player
  local surface = ensure_test_map_surface()
  local corner = { x = 32, y = 32 }

  local area = run_setup_step("pave surface", function()
    return pave_test_map(surface, corner, leg_length, arm_half_width, clear_padding)
  end)
  run_setup_step("place power", function()
    create_test_map_power(surface, force, corner, leg_length)
  end)
  run_setup_step("place walls", function()
    create_test_map_walls(surface, force, corner, leg_length, arm_half_width)
  end)

  local roboports = run_setup_step("place roboports", function()
    return create_test_map_roboports(surface, force, corner, leg_length, roboport_spacing)
  end)
  local rightmost_roboport = roboports[math.floor(leg_length / roboport_spacing) + 1]
  fill(rightmost_roboport, "construction-robot", 10)

  local nests, worms, spitters = run_setup_step("place threats", function()
    return create_diagonal_threats(surface, corner)
  end)
  run_setup_step("chart area", function()
    force.chart(surface, area)
  end)

  if player ~= nil then
    run_setup_step("teleport player", function()
      player.teleport({ x = corner.x + 8, y = corner.y - 8 }, surface)
    end)
  end

  local force_surface_key = util.force_surface_key(surface.index, force.name)
  root.smoke_labs[force_surface_key] = {
    name = constants.TEST_MAP_NAME,
    origin = util.copy_position(corner),
    surface_index = surface.index,
    force_name = force.name,
    built_tick = game.tick,
    leg_length = leg_length,
    roboport_spacing = roboport_spacing,
    roboport_count = count_valid(roboports),
    enemy_counts = {
      biter_spawners = count_valid(nests),
      worms = count_valid(worms),
      spitters = count_valid(spitters)
    }
  }

  return {
    surface_name = surface.name,
    surface_index = surface.index,
    force_name = force.name,
    origin = corner,
    area = area,
    leg_length = leg_length,
    roboport_spacing = roboport_spacing,
    right_arm_outer_roboport = util.copy_position(rightmost_roboport.position),
    counts = {
      roboports = count_valid(roboports),
      biter_spawners = count_valid(nests),
      worms = count_valid(worms),
      spitters = count_valid(spitters),
      construction_robots_in_outer_right_roboport = 10
    }
  }
end

return smoke_lab
