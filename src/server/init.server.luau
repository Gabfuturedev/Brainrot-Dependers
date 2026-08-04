--!strict
-- Boot order matters: breakables and currency must exist before pets hunt.

local Services = script.Services

require(Services.CurrencyService).start()
require(Services.BreakableService).start()
require(Services.PetService).start()

print("[Server] started")
