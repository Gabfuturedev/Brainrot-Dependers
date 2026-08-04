--!strict
-- Boot order matters. DataService goes LAST: it starts loading profiles the
-- moment it runs, and anything listening for ProfileLoaded must already be
-- connected or it will miss the players who joined first.

local Services = script.Services

require(Services.CurrencyService).start()
require(Services.BreakableService).start()
require(Services.PetInventoryService).start()
require(Services.PetService).start()
require(Services.DataService).start()

print("[Server] started")
