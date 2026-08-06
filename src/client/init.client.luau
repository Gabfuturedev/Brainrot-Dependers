--!strict
-- Client bootstrap. Mirrors the server: each module owns one concern and
-- exposes start().

require(script.Targeting).start()
require(script.Drops).start()
require(script.UI.CoinDisplay).start()
require(script.UI.FloatingText).start()
require(script.UI.HatchPopup).start()
require(script.UI.PetInventory).start()
require(script.UI.Barriers).start()
require(script.UI.StarterPicker).start()
