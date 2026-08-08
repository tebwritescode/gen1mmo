-- Character customisation, client side.
--
-- The full catalog (bodies, skin tones, hair, colours, outfits) is the
-- server's source of truth; this mirrors the LABELS so the editor UI can show
-- names, and holds the local player's chosen tuple (persisted via mod.save).
--
-- 0.1.0-beta rendering note: the tuple is chosen, saved, sent, stored, and
-- broadcast end-to-end. Distinct overworld rendering currently varies the base
-- trainer sprite by body type; per-tone/hair/outfit palette recolour is the
-- next step (needs the palette-layer integration + art) and is tracked as a
-- follow-up. Nothing about the data path changes when that lands.

local Skins = {}

-- Labels mirror catalog/cosmetics.json in the server repo (catalogVersion 1).
Skins.catalog = {
  bodies      = { "Boy", "Girl" },
  skinTones   = { "Porcelain", "Fair", "Warm", "Olive", "Bronze", "Umber", "Deep", "Ebony" },
  hairStyles  = { "Cropped", "Cap Hair", "Tousled", "Ponytail", "Twin Tails",
                  "Bob", "Long", "Spiked", "Curls", "Buzzed" },
  hairColors  = { "Black", "Dark Brown", "Brown", "Auburn", "Ginger", "Blonde",
                  "Platinum", "Silver", "Crimson", "Ocean", "Forest", "Violet" },
  outfits     = { "Adventurer", "Explorer", "Hiker", "Ace", "Nightfall",
                  "Sunburst", "Meadow", "Ember" },
}

Skins.DEFAULT = { body = 0, skin = 1, hair = 1, hairColor = 0, outfit = 0 }

--- Clamp a tuple into the catalog ranges (defensive; the server validates too).
function Skins.sanitize(t)
  t = t or {}
  local function clamp(v, list) v = tonumber(v) or 0; if v < 0 then v = 0 end
    if v > #list - 1 then v = #list - 1 end; return math.floor(v) end
  return {
    body      = clamp(t.body, Skins.catalog.bodies),
    skin      = clamp(t.skin, Skins.catalog.skinTones),
    hair      = clamp(t.hair, Skins.catalog.hairStyles),
    hairColor = clamp(t.hairColor, Skins.catalog.hairColors),
    outfit    = clamp(t.outfit, Skins.catalog.outfits),
  }
end

--- Overworld sprite id for a skin. Built-in engine sprites for the beta so no
--- art needs to ship; body type gives a visible distinction today.
--- (Verified against the Red cache's sprites registry: SPRITE_RED and
--- SPRITE_BLUE exist; the once-assumed SPRITE_HERO does not.)
function Skins.overworldSprite(skin)
  skin = skin or Skins.DEFAULT
  local body = tonumber(skin.body) or 0
  if body == 1 then return "SPRITE_BLUE" end
  return "SPRITE_RED"
end

--- Human-readable summary for the editor.
function Skins.describe(skin)
  local c = Skins.catalog
  local function name(list, i) return list[(tonumber(i) or 0) + 1] or "?" end
  return string.format("%s / %s skin / %s %s hair / %s",
    name(c.bodies, skin.body), name(c.skinTones, skin.skin),
    name(c.hairColors, skin.hairColor), name(c.hairStyles, skin.hair),
    name(c.outfits, skin.outfit))
end

return Skins
