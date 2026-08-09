--!strict
-- Boot order matters. DataService goes LAST: it starts loading profiles the
-- moment it runs, and anything listening for ProfileLoaded must already be
-- connected or it will miss the players who joined first.

local Services = script.Services

-- PlotService goes early: anything that spawns into a plot needs it seated
-- before players arrive.
require(Services.PlotService).start()
require(Services.CurrencyService).start()
require(Services.SkillService).start()
require(Services.VfxService).start()
require(Services.DropService).start()
require(Services.AreaService).start()
require(Services.BreakableService).start()
require(Services.EnemyService).start()
require(Services.PetInventoryService).start()
require(Services.PetService).start()
require(Services.DataService).start()

print("[Server] started")
