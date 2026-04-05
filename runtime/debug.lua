local constants = require("runtime.constants")

local debug_tools = {}

function debug_tools.write_state_dump(payload, suffix, player_index)
  local filename = string.format(
    "%s/%s-%d.json",
    constants.DEBUG_FOLDER,
    suffix,
    game.tick
  )

  helpers.write_file(filename, helpers.table_to_json(payload), false, player_index)
  return filename
end

return debug_tools
