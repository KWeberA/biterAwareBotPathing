-- Runtime stage entry point.
-- Keep persistent state inside `global` and register event handlers here.

local function ensure_global_state()
  global.biter_aware_bot_pathing = global.biter_aware_bot_pathing or {}
end

script.on_init(ensure_global_state)
script.on_configuration_changed(ensure_global_state)