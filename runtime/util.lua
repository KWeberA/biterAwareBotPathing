local constants = require("runtime.constants")

local util = {}

local function ensure_table(parent, key, default)
  if parent[key] == nil then
    parent[key] = default
  end

  return parent[key]
end

function util.ensure_root()
  storage[constants.STORAGE_KEY] = storage[constants.STORAGE_KEY] or {}

  local root = storage[constants.STORAGE_KEY]
  root.version = constants.STATE_VERSION
  root.next_task_id = root.next_task_id or 1

  ensure_table(root, "threat_indexes", {})
  ensure_table(root, "networks", {})
  ensure_table(root, "deferred_tasks", {})
  ensure_table(root, "deferred_task_keys", {})
  ensure_table(root, "watch_ghosts", {})
  ensure_table(root, "object_registrations", {})
  ensure_table(root, "task_counts_by_force_surface", {})
  ensure_table(root, "watch_counts_by_force_surface", {})
  ensure_table(root, "dirty_surfaces", {})
  ensure_table(root, "dirty_force_surfaces", {})
  ensure_table(root, "active_force_surfaces", {})
  ensure_table(root, "smoke_labs", {})
  ensure_table(root, "stats", {})
  ensure_table(root, "full_rescan_force_surfaces", {})

  return root
end

function util.force_surface_key(surface_index, force_name)
  return table.concat({ surface_index, force_name }, ":")
end

function util.network_key(surface_index, force_name, network_id)
  return table.concat({ surface_index, force_name, network_id }, ":")
end

function util.chunk_index(value)
  return math.floor(value / 32)
end

function util.chunk_key(x, y)
  return table.concat({ x, y }, ":")
end

function util.chunk_key_for_position(position)
  return util.chunk_key(util.chunk_index(position.x), util.chunk_index(position.y))
end

function util.copy_position(position)
  return { x = position.x, y = position.y }
end

function util.named_object_name(value)
  if value == nil then
    return nil
  end

  if type(value) == "string" then
    return value
  end

  local ok, name = pcall(function()
    return value.name
  end)

  if ok and type(name) == "string" then
    return name
  end

  return nil
end

function util.force_name(force)
  return util.named_object_name(force)
end

function util.quality_name(quality)
  return util.named_object_name(quality)
end

function util.copy_value(value)
  if type(value) ~= "table" then
    return value
  end

  local copy = {}
  for key, nested in pairs(value) do
    copy[key] = util.copy_value(nested)
  end

  return copy
end

function util.round_to(value, precision)
  local scale = 10 ^ precision
  return math.floor(value * scale + 0.5) / scale
end

function util.position_key(position)
  local x = util.round_to(position.x, 3)
  local y = util.round_to(position.y, 3)
  return string.format("%.3f:%.3f", x, y)
end

function util.tile_position_key(position)
  local x = math.floor(position.x)
  local y = math.floor(position.y)
  return table.concat({ x, y }, ":")
end

function util.distance_squared(a, b)
  local dx = a.x - b.x
  local dy = a.y - b.y
  return dx * dx + dy * dy
end

function util.make_bbox(position, radius)
  return {
    left_top = { x = position.x - radius, y = position.y - radius },
    right_bottom = { x = position.x + radius, y = position.y + radius }
  }
end

function util.copy_bbox(area)
  return {
    left_top = util.copy_position(area.left_top),
    right_bottom = util.copy_position(area.right_bottom)
  }
end

function util.expand_bbox(area, padding)
  return {
    left_top = { x = area.left_top.x - padding, y = area.left_top.y - padding },
    right_bottom = { x = area.right_bottom.x + padding, y = area.right_bottom.y + padding }
  }
end

function util.merge_bbox(current, extra)
  if current == nil then
    return util.copy_bbox(extra)
  end

  return {
    left_top = {
      x = math.min(current.left_top.x, extra.left_top.x),
      y = math.min(current.left_top.y, extra.left_top.y)
    },
    right_bottom = {
      x = math.max(current.right_bottom.x, extra.right_bottom.x),
      y = math.max(current.right_bottom.y, extra.right_bottom.y)
    }
  }
end

function util.bbox_contains(area, position)
  if area == nil then
    return false
  end

  return position.x >= area.left_top.x and position.x <= area.right_bottom.x
    and position.y >= area.left_top.y and position.y <= area.right_bottom.y
end

function util.area_intersects(a, b)
  if a == nil or b == nil then
    return false
  end

  return not (
    a.right_bottom.x < b.left_top.x
    or a.left_top.x > b.right_bottom.x
    or a.right_bottom.y < b.left_top.y
    or a.left_top.y > b.right_bottom.y
  )
end

function util.sample_segment(from_position, to_position, step, callback)
  local dx = to_position.x - from_position.x
  local dy = to_position.y - from_position.y
  local distance = math.sqrt(dx * dx + dy * dy)
  local samples = math.max(1, math.ceil(distance / step))

  for index = 0, samples do
    local ratio = index / samples
    local point = {
      x = from_position.x + dx * ratio,
      y = from_position.y + dy * ratio
    }

    if callback(point, ratio) == false then
      return false
    end
  end

  return true
end

function util.array_contains(array, value)
  for _, entry in ipairs(array) do
    if entry == value then
      return true
    end
  end

  return false
end

function util.entity_identity(entity)
  if entity == nil or not entity.valid then
    return nil
  end

  if entity.unit_number ~= nil then
    return "u:" .. entity.unit_number
  end

  return table.concat({
    entity.name,
    util.position_key(entity.position)
  }, "@")
end

function util.cell_identity(cell)
  if cell == nil or not cell.valid then
    return nil
  end

  return util.entity_identity(cell.owner)
end

function util.safe_get_upgrade_target(entity)
  if entity == nil or not entity.valid then
    return nil, nil
  end

  local target, quality = entity.get_upgrade_target()
  return target, quality
end

function util.copy_item_requests(item_requests)
  if item_requests == nil then
    return {}
  end

  local requests = {}
  for _, request in ipairs(item_requests) do
    requests[#requests + 1] = {
      name = request.name,
      quality = util.quality_name(request.quality),
      count = request.count
    }
  end

  return requests
end

function util.resolve_surface(surface_name_or_index)
  if surface_name_or_index == nil then
    return nil
  end

  return game.surfaces[surface_name_or_index]
end

function util.resolve_force(force_name)
  if force_name == nil then
    return nil
  end

  return game.forces[force_name]
end

function util.parse_scope_args(parameter)
  if parameter == nil or parameter == "" then
    return nil, nil
  end

  local words = {}
  for word in string.gmatch(parameter, "%S+") do
    words[#words + 1] = word
  end

  if #words == 1 then
    if game.surfaces[words[1]] ~= nil then
      return words[1], nil
    end

    if game.forces[words[1]] ~= nil then
      return nil, words[1]
    end

    return words[1], nil
  end

  return words[1], words[2]
end

function util.print_to_player(player_index, message)
  if player_index ~= nil then
    local player = game.get_player(player_index)
    if player ~= nil then
      player.print(message)
      return
    end
  end

  game.print(message)
end

function util.find_entity_by_snapshot(snapshot)
  if snapshot == nil then
    return nil
  end

  if snapshot.entity_unit_number ~= nil then
    local by_unit_number = game.get_entity_by_unit_number(snapshot.entity_unit_number)
    if by_unit_number ~= nil and by_unit_number.valid then
      return by_unit_number
    end
  end

  local surface = game.surfaces[snapshot.surface_index]
  if surface == nil then
    return nil
  end

  local entities = surface.find_entities_filtered {
    position = snapshot.position,
    force = snapshot.force_name,
    name = snapshot.entity_name,
    limit = 1
  }

  return entities[1]
end

return util
