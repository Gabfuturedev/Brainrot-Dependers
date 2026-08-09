--!strict
-- Client bootstrap. Mirrors the server: each module owns one concern and
-- exposes start().

-- before anything that listens to EggFx.Finished, so the gate is live by the
-- time a hatch can reach it
require(script.UI.EggFx).start()
require(script.Targeting).start()
require(script.Drops).start()
require(script.Audio).start()
require(script.UI.CoinDisplay).start()
require(script.UI.HealthBars).start()
require(script.UI.FloatingText).start()
require(script.UI.HatchPopup).start()
require(script.UI.PetInventory).start()
require(script.UI.UpgradeSigns).start()
require(script.UI.EggBillboard).start()
require(script.UI.EggHatchBar).start()
require(script.UI.WaveBar).start()
require(script.UI.Barriers).start()
require(script.UI.StarterPicker).start()
