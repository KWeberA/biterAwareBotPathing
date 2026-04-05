local constants = require("runtime.constants")
local util = require("runtime.util")
local threat_index = require("runtime.threat_index")

local network_cache = {}

local function point_in_cell(cell, position)
  return util.distance_squared(cell.position, position) <= cell.construction_radius * cell.construction_radius
end

local function segment_stays_in_union(cell_a, cell_b, from_position, to_position)
  return util.sample_segment(from_position, to_position, constants.LINE_SAMPLE_STEP, function(point)
    if point_in_cell(cell_a, point) or point_in_cell(cell_b, point) then
      return true
    end

    return false
  end)
end

local function edge_is_safe(force, threat, cell_a, cell_b)
  if not cell_a.transmitting or not cell_b.transmitting then
    return false
  end

  local segment_safe = threat_index.segment_is_safe(threat, force, cell_a.position, cell_b.position)
  if not segment_safe then
    return false
  end

  return segment_stays_in_union(cell_a, cell_b, cell_a.position, cell_b.position)
end

local function build_cells(cache, network)
  local raw_cells = {}
  local identity_to_id = {}

  for _, cell in ipairs(network.cells) do
    local owner = cell.owner
    if owner ~= nil and owner.valid then
      local id = #cache.cells + 1
      local identity = util.cell_identity(cell)

      cache.cells[id] = {
        id = id,
        identity = identity,
        owner_name = owner.name,
        owner_unit_number = owner.unit_number,
        position = util.copy_position(owner.position),
        construction_radius = cell.construction_radius,
        logistic_radius = cell.logistic_radius,
        logistics_connection_distance = cell.logistics_connection_distance,
        stationed_construction_robot_count = cell.stationed_construction_robot_count,
        charging_robot_count = cell.charging_robot_count,
        to_charge_robot_count = cell.to_charge_robot_count,
        transmitting = cell.transmitting,
        mobile = cell.mobile,
        neighbours = {},
        safe_neighbours = {},
        seed = (
          cell.stationed_construction_robot_count
          + cell.charging_robot_count
          + cell.to_charge_robot_count
        ) > 0
      }

      raw_cells[id] = cell
      identity_to_id[identity] = id
      cache.bounds = util.merge_bbox(cache.bounds, util.make_bbox(owner.position, cell.construction_radius))
    end
  end

  for id, cell in ipairs(raw_cells) do
    for _, neighbour in ipairs(cell.neighbours) do
      local neighbour_id = identity_to_id[util.cell_identity(neighbour)]
      if neighbour_id ~= nil and neighbour_id ~= id then
        cache.cells[id].neighbours[#cache.cells[id].neighbours + 1] = neighbour_id
      end
    end
  end
end

local function build_safe_edges(cache, force, threat)
  for _, cell in ipairs(cache.cells) do
    for _, neighbour_id in ipairs(cell.neighbours) do
      if neighbour_id > cell.id then
        local neighbour = cache.cells[neighbour_id]
        if edge_is_safe(force, threat, cell, neighbour) then
          cell.safe_neighbours[#cell.safe_neighbours + 1] = neighbour_id
          neighbour.safe_neighbours[#neighbour.safe_neighbours + 1] = cell.id
        end
      end
    end
  end
end

local function build_seed_distances(cache)
  local queue = {}
  local head = 1

  cache.seed_ids = {}
  cache.allowed_cell_ids = {}

  for _, cell in ipairs(cache.cells) do
    cell.distance_from_seed = nil
    cell.predecessor = nil

    if cell.seed and cell.transmitting then
      cell.distance_from_seed = 0
      cache.seed_ids[#cache.seed_ids + 1] = cell.id
      cache.allowed_cell_ids[cell.id] = true
      queue[#queue + 1] = cell.id
    end
  end

  while head <= #queue do
    local cell_id = queue[head]
    head = head + 1
    local cell = cache.cells[cell_id]

    for _, neighbour_id in ipairs(cell.safe_neighbours) do
      local neighbour = cache.cells[neighbour_id]
      local next_distance = cell.distance_from_seed + 1

      if neighbour.distance_from_seed == nil or next_distance < neighbour.distance_from_seed then
        neighbour.distance_from_seed = next_distance
        neighbour.predecessor = cell_id
        queue[#queue + 1] = neighbour_id
      end
    end
  end

  for _, cell in ipairs(cache.cells) do
    if cell.distance_from_seed ~= nil and cell.distance_from_seed <= constants.FRONTIER_DEPTH then
      cache.allowed_cell_ids[cell.id] = true
    end
  end
end

local function build_network(force, surface, network, threat)
  local cache = {
    network_id = network.network_id,
    network_key = util.network_key(surface.index, force.name, network.network_id),
    surface_index = surface.index,
    force_name = force.name,
    built_tick = game.tick,
    all_construction_robots = network.all_construction_robots,
    available_construction_robots = network.available_construction_robots,
    cells = {},
    seed_ids = {},
    allowed_cell_ids = {},
    bounds = nil
  }

  build_cells(cache, network)
  build_safe_edges(cache, force, threat)
  build_seed_distances(cache)

  if cache.bounds ~= nil then
    cache.bounds = util.expand_bbox(cache.bounds, constants.BOUNDS_PADDING)
  end

  return cache
end

function network_cache.build_context(root, force, surface, threat)
  local context = {
    force_name = force.name,
    surface_index = surface.index,
    network_list = {},
    networks = {}
  }

  local seen_network_ids = {}
  local roboports = surface.find_entities_filtered {
    force = force.name,
    type = "roboport"
  }

  for _, roboport in ipairs(roboports) do
    if roboport.valid then
      local cell = roboport.logistic_cell
      local network = cell and cell.logistic_network

      if network ~= nil and network.valid and not seen_network_ids[network.network_id] then
        seen_network_ids[network.network_id] = true
        local cache = build_network(force, surface, network, threat)
        if cache.bounds ~= nil and #cache.cells > 0 then
          context.networks[cache.network_key] = cache
          context.network_list[#context.network_list + 1] = cache
        end
      end
    end
  end

  table.sort(context.network_list, function(left, right)
    return left.network_id < right.network_id
  end)

  return context
end

function network_cache.covering_cells(network, position)
  local covering = {}

  if network.bounds == nil or not util.bbox_contains(network.bounds, position) then
    return covering
  end

  for _, cell in ipairs(network.cells) do
    if cell.transmitting and point_in_cell(cell, position) then
      covering[#covering + 1] = cell
    end
  end

  table.sort(covering, function(left, right)
    if left.distance_from_seed == right.distance_from_seed then
      return util.distance_squared(left.position, position) < util.distance_squared(right.position, position)
    end

    if left.distance_from_seed == nil then
      return false
    end

    if right.distance_from_seed == nil then
      return true
    end

    return left.distance_from_seed < right.distance_from_seed
  end)

  return covering
end

function network_cache.path_cells(network, target_cell_id)
  local cells = {}
  local current_id = target_cell_id

  while current_id ~= nil do
    cells[#cells + 1] = network.cells[current_id]
    current_id = network.cells[current_id].predecessor
  end

  local forward = {}
  for index = #cells, 1, -1 do
    forward[#forward + 1] = cells[index]
  end

  return forward
end

function network_cache.path_to_position_is_safe(network, force, threat, target_cell_id, position)
  local path = network_cache.path_cells(network, target_cell_id)
  if #path == 0 then
    return false
  end

  for index = 1, #path - 1 do
    local current = path[index]
    local next_cell = path[index + 1]

    local segment_safe = threat_index.segment_is_safe(threat, force, current.position, next_cell.position)
    if not segment_safe or not segment_stays_in_union(current, next_cell, current.position, next_cell.position) then
      return false
    end
  end

  local last_cell = path[#path]
  local final_segment_safe = threat_index.segment_is_safe(threat, force, last_cell.position, position)
  if not final_segment_safe then
    return false
  end

  return util.sample_segment(last_cell.position, position, constants.LINE_SAMPLE_STEP, function(sample)
    return point_in_cell(last_cell, sample)
  end)
end

return network_cache
