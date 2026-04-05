local constants = require("runtime.constants")
local util = require("runtime.util")

local threat_index = {}

local function should_count_threat(entity)
  if entity == nil or not entity.valid then
    return false
  end

  if entity.type == "unit-spawner" then
    return true
  end

  local prototype = entity.prototype
  local attack_parameters = prototype and prototype.attack_parameters
  return attack_parameters ~= nil and attack_parameters.range ~= nil and attack_parameters.range > 0
end

local function add_threat(index, entity, radius, soft)
  local threat_id = #index.threats + 1
  local position = util.copy_position(entity.position)

  index.threats[threat_id] = {
    id = threat_id,
    entity_name = entity.name,
    entity_type = entity.type,
    force_name = entity.force.name,
    position = position,
    radius = radius,
    soft = soft
  }

  local left = util.chunk_index(position.x - radius)
  local right = util.chunk_index(position.x + radius)
  local top = util.chunk_index(position.y - radius)
  local bottom = util.chunk_index(position.y + radius)

  for chunk_x = left, right do
    for chunk_y = top, bottom do
      local key = util.chunk_key(chunk_x, chunk_y)
      index.by_chunk[key] = index.by_chunk[key] or {}
      index.by_chunk[key][#index.by_chunk[key] + 1] = threat_id
    end
  end
end

function threat_index.rebuild(surface)
  local index = {
    surface_index = surface.index,
    built_tick = game.tick,
    threats = {},
    by_chunk = {}
  }

  for _, force in pairs(game.forces) do
    local entities = surface.find_entities_filtered {
      force = force.name,
      type = constants.THREAT_ENTITY_TYPES
    }

    for _, entity in ipairs(entities) do
      if should_count_threat(entity) then
        if entity.type == "unit-spawner" then
          add_threat(index, entity, constants.SPAWNER_RADIUS, true)
        else
          local attack_parameters = entity.prototype.attack_parameters
          local radius = attack_parameters.range + constants.THREAT_MARGIN
          add_threat(index, entity, radius, false)
        end
      end
    end
  end

  return index
end

function threat_index.ensure(root, surface, force_refresh)
  local cached = root.threat_indexes[surface.index]
  if force_refresh or cached == nil or root.dirty_surfaces[surface.index] then
    cached = threat_index.rebuild(surface)
    root.threat_indexes[surface.index] = cached
    root.dirty_surfaces[surface.index] = nil
  end

  return cached
end

local function is_hostile(force, other_force_name)
  if force.name == other_force_name then
    return false
  end

  if force.get_friend(other_force_name) then
    return false
  end

  if force.get_cease_fire(other_force_name) then
    return false
  end

  return true
end

function threat_index.point_is_safe(index, force, position)
  local chunk_key = util.chunk_key_for_position(position)
  local threat_ids = index.by_chunk[chunk_key]

  if threat_ids == nil then
    return true, nil
  end

  for _, threat_id in ipairs(threat_ids) do
    local threat = index.threats[threat_id]
    if threat ~= nil and is_hostile(force, threat.force_name) then
      if util.distance_squared(position, threat.position) <= threat.radius * threat.radius then
        return false, threat
      end
    end
  end

  return true, nil
end

function threat_index.segment_is_safe(index, force, from_position, to_position)
  local unsafe_threat = nil

  local ok = util.sample_segment(from_position, to_position, constants.LINE_SAMPLE_STEP, function(point)
    local point_safe, threat = threat_index.point_is_safe(index, force, point)
    if not point_safe then
      unsafe_threat = threat
      return false
    end

    return true
  end)

  return ok, unsafe_threat
end

return threat_index
