--!strict
-- Number formatting shared by anything that shows one to a player.
--
-- Simulators outgrow plain digits fast: an Area 3 breakable has five figures of
-- health and a late-game balance has nine, and "12480" reads as noise where
-- "12.5K" reads as a quantity.

local Format = {}

function Format.abbreviate(value: number): string
	local n = math.floor(value)
	if n >= 1_000_000_000 then
		return string.format("%.1fB", n / 1_000_000_000)
	elseif n >= 1_000_000 then
		return string.format("%.1fM", n / 1_000_000)
	elseif n >= 1_000 then
		return string.format("%.1fK", n / 1_000)
	end
	return tostring(n)
end

return Format
