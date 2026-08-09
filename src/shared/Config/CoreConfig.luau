--!strict
-- The thing being defended.
--
-- Core health is the run's life total. Brainrots going down is a setback -
-- they get back up between waves - but every enemy that walks past them takes
-- a permanent bite out of this, and at zero the run is over. That makes losing
-- your line the cause of losing rather than the definition of it, which is the
-- difference between "you failed" and "watch what your failure costs you".
--
-- One tier for now. The box-to-chest-to-vault upgrade goes here, raising health
-- and eventually the number of brainrots that can be deployed at once.

local CoreConfig = {}

-- Tuned against a Shambler's 5 core damage: twenty get through before the run
-- ends. Enough that one leaking past is a warning rather than a verdict.
CoreConfig.Health = 100

return CoreConfig
