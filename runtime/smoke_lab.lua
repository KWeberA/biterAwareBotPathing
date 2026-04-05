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

function smoke_lab.setup(root, player_index)
  local player = player_index ~= nil and game.get_player(player_index) or nil
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

return smoke_lab
