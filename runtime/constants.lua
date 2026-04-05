local constants = {}

constants.STORAGE_KEY = "biter_aware_bot_pathing"
constants.STATE_VERSION = 1

constants.FRONTIER_DEPTH = 1
constants.THREAT_MARGIN = 8
constants.SPAWNER_RADIUS = 24
constants.LINE_SAMPLE_STEP = 4
constants.NTH_TICK = 120

constants.MAX_FORCE_SURFACES_PER_CYCLE = 2
constants.MAX_CANDIDATES_PER_RECHECK = 256
constants.BOUNDS_PADDING = 2

constants.DEBUG_FOLDER = "biter-aware-bot-pathing"
constants.SMOKE_LAB_NAME = "construction-frontier-lab"
constants.TEST_MAP_NAME = "right-angle-biter-test-map"
constants.TEST_MAP_SURFACE_NAME = "babp-test-map"

constants.THREAT_ENTITY_TYPES = {
  "turret",
  "ammo-turret",
  "electric-turret",
  "fluid-turret",
  "artillery-turret",
  "unit-spawner"
}

constants.CONSTRUCTION_GHOST_TYPES = {
  "entity-ghost",
  "tile-ghost"
}

return constants
