-- Achievements: game-trigger history badges (operator direction 2026-08-08).
-- The engine already narrates the run through Runtime hooks -- catches
-- (with ball + species), evolutions, trades, boulders, steps, fishing --
-- so most of these are EVENT-driven, not save-scans. Item usage has no
-- engine hook; ItemEffects.use is wrapped instead (mods run in the real
-- global env by design). Every handler is pcall'd: the engine kills the
-- app silently on mod errors, and an achievement is never worth a crash.
--
-- Claims go through client:claimMilestone -> local flag + server persist
-- (earned offline is synced on the next connect; the server's INSERT OR
-- IGNORE makes resends harmless).

local Achievements = {}

-- id -> display name, in display order (the My history screen shows
-- these top to bottom). Charmap-safe strings only.
Achievements.LIST = {
  -- story
  { "badge_1", "First gym badge" },
  { "badge_2", "2 gym badges" },
  { "badge_3", "3 gym badges" },
  { "badge_4", "4 gym badges" },
  { "badge_5", "5 gym badges" },
  { "badge_6", "6 gym badges" },
  { "badge_7", "7 gym badges" },
  { "badge_8", "All 8 badges" },
  { "hof", "Hall of Fame" },
  -- collecting
  { "catch_1", "First catch" },
  { "catch_10", "10 catches" },
  { "catch_25", "25 catches" },
  { "catch_50", "50 catches" },
  { "dex_50", "Pokedex: 50" },
  { "dex_100", "Pokedex: 100" },
  { "dex_150", "Pokedex: 150" },
  { "catch_water", "Water type caught" },
  { "catch_fire", "Fire type caught" },
  { "catch_electric", "Electric caught" },
  { "catch_psychic", "Psychic caught" },
  { "catch_ghost", "Ghost caught" },
  { "catch_dragon", "Dragon caught" },
  { "catch_legend", "Legend caught" },
  { "ball_poke", "Poke Ball catch" },
  { "ball_great", "Great Ball catch" },
  { "ball_ultra", "Ultra Ball catch" },
  { "ball_safari", "Safari catch" },
  { "ball_master", "Master Ball used" },
  { "fish_1", "Gone fishing" },
  -- items
  { "use_potion", "Potion used" },
  { "use_super", "Super Potion used" },
  { "use_restore", "Big heal used" },
  { "use_revive", "Revive used" },
  -- money
  { "rich_10k", "\194\16510000 in hand" },
  { "rich_100k", "\194\165100000 in hand" },
  { "rich_max", "\194\165999999 maxed" },
  -- party
  { "party_6", "Full party of 6" },
  { "lvl_50", "Level 50 partner" },
  { "mon_100", "Level 100 partner" },
  -- world
  { "evolve_1", "First evolution" },
  { "trade_1", "First trade" },
  { "boulder_1", "Boulder pusher" },
  { "steps_10k", "10000 steps" },
}

Achievements.IDS = {}
Achievements.NAMES = {}
for _, row in ipairs(Achievements.LIST) do
  Achievements.IDS[#Achievements.IDS + 1] = row[1]
  Achievements.NAMES[row[1]] = row[2]
end

local BALL_ACH = {
  POKE_BALL = "ball_poke", GREAT_BALL = "ball_great",
  ULTRA_BALL = "ball_ultra", MASTER_BALL = "ball_master",
  SAFARI_BALL = "ball_safari",
}
local TYPE_ACH = {
  WATER = "catch_water", FIRE = "catch_fire", ELECTRIC = "catch_electric",
  -- pokered names the TYPE id PSYCHIC_TYPE (the move owns "PSYCHIC")
  PSYCHIC_TYPE = "catch_psychic", PSYCHIC = "catch_psychic",
  GHOST = "catch_ghost", DRAGON = "catch_dragon",
}
local LEGENDS = {
  ARTICUNO = true, ZAPDOS = true, MOLTRES = true, MEWTWO = true, MEW = true,
}

function Achievements.install(mod, client)
  local function claim(id) pcall(function() client:claimMilestone(id) end) end

  -- ---- catches: count, ball, species type, legendaries
  mod.events:on("pokemon.caught", function(ev)
    pcall(function()
      claim("catch_1")
      local n = (mod.save:get("ach_catches", 0) or 0) + 1
      mod.save:set("ach_catches", n)
      if n >= 10 then claim("catch_10") end
      if n >= 25 then claim("catch_25") end
      if n >= 50 then claim("catch_50") end
      if ev and ev.ball and BALL_ACH[ev.ball] then claim(BALL_ACH[ev.ball]) end
      local species = ev and tostring(ev.species or "")
      if LEGENDS[species] then claim("catch_legend") end
      local def = ev and ev.game and ev.game.data
        and ev.game.data.pokemon and ev.game.data.pokemon[species]
      if not def then
        local ok, Game = pcall(require, "src.core.Game")
        def = ok and Game.data and Game.data.pokemon
          and Game.data.pokemon[species] or nil
      end
      for _, t in ipairs((def and def.types) or {}) do
        if TYPE_ACH[t] then claim(TYPE_ACH[t]) end
      end
    end)
  end)

  -- ---- one-shot world moments
  mod.events:on("pokemon.evolved", function() claim("evolve_1") end)
  mod.events:on("trade.completed", function() claim("trade_1") end)
  mod.events:on("world.boulder_moved", function() claim("boulder_1") end)

  -- ---- steps: RAM counter, persisted in strides (a save write per step
  -- would grind flash-backed handhelds)
  local steps = tonumber(mod.save:get("ach_steps", 0)) or 0
  local claimed10k = steps >= 10000
  mod.events:on("world.stepped", function()
    steps = steps + 1
    if steps % 25 == 0 then mod.save:set("ach_steps", steps) end
    if not claimed10k and steps >= 10000 then
      claimed10k = true
      mod.save:set("ach_steps", steps)
      claim("steps_10k")
    end
  end)

  -- ---- fishing: a transform hook, so wrap and pass straight through
  mod.hooks:wrap("encounter.fishing", function(next, ...)
    claim("fish_1")
    return next(...)
  end)

  -- ---- item usage: no engine hook exists; wrap ItemEffects.use and
  -- watch what actually got consumed
  pcall(function()
    local IE = require("src.inventory.ItemEffects")
    if IE.__g1mmo_wrapped then return end
    IE.__g1mmo_wrapped = true
    local orig = IE.use
    IE.use = function(data, save, itemId, ...)
      local result, messages, extra = orig(data, save, itemId, ...)
      pcall(function()
        if result ~= "consumed" then return end
        if itemId == "POTION" then claim("use_potion")
        elseif itemId == "SUPER_POTION" then claim("use_super")
        elseif itemId == "HYPER_POTION" or itemId == "MAX_POTION"
          or itemId == "FULL_RESTORE" then claim("use_restore")
        elseif itemId == "REVIVE" or itemId == "MAX_REVIVE" then claim("use_revive")
        end
      end)
      return result, messages, extra
    end
  end)
end

return Achievements
