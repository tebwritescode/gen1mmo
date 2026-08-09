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

-- Labels mirror catalog/cosmetics.json in the server repo (catalogVersion 2).
Skins.catalog = {
  bodies      = { "Boy", "Girl" },
  skinTones   = { "Porcelain", "Fair", "Warm", "Olive", "Bronze", "Umber", "Deep", "Ebony" },
  hairStyles  = { "Cropped", "Cap Hair", "Tousled", "Ponytail", "Twin Tails",
                  "Bob", "Long", "Spiked", "Curls", "Buzzed" },
  hairColors  = { "Black", "Dark Brown", "Brown", "Auburn", "Ginger", "Blonde",
                  "Platinum", "Silver", "Crimson", "Ocean", "Forest", "Violet" },
  outfits     = { "Adventurer", "Explorer", "Hiker", "Ace", "Nightfall",
                  "Sunburst", "Meadow", "Ember" },
  hats        = { "No", "Yes" },
  pieceColors = { "Black", "Brown", "Tan", "Red", "Orange", "Yellow",
                  "White", "Gray", "Crimson", "Blue", "Green", "Violet" },
}

Skins.DEFAULT = { body = 0, skin = 1, hair = 1, hairColor = 0, outfit = 0,
                  hat = 1, hatColor = 3, shirt = 3, pants = 9, pack = 2 }

--- Clamp a tuple into the catalog ranges (defensive; the server validates
--- too). New piece fields default sensibly when absent, so skins from
--- older clients and servers still sanitize cleanly.
function Skins.sanitize(t)
  t = t or {}
  local function clamp(v, list, fallback)
    v = tonumber(v)
    if v == nil then return fallback end
    if v < 0 then v = 0 end
    if v > #list - 1 then v = #list - 1 end
    return math.floor(v)
  end
  local c = Skins.catalog
  return {
    body      = clamp(t.body, c.bodies, 0),
    skin      = clamp(t.skin, c.skinTones, 1),
    hair      = clamp(t.hair, c.hairStyles, 1),
    hairColor = clamp(t.hairColor, c.hairColors, 0),
    outfit    = clamp(t.outfit, c.outfits, 0),
    hat       = clamp(t.hat, c.hats, 1),
    hatColor  = clamp(t.hatColor, c.pieceColors, 3),
    shirt     = clamp(t.shirt, c.pieceColors, 3),
    pants     = clamp(t.pants, c.pieceColors, 9),
    pack      = clamp(t.pack, c.pieceColors, 2),
  }
end

--- Base engine sprite for a body (always present in the cache registry).
--- The Girl body rides the brunette-girl walker: a real feminine
--- silhouette with actual hair, straight from the game's own sheets.
function Skins.baseSprite(skin)
  skin = skin or Skins.DEFAULT
  if (tonumber(skin.body) or 0) == 1 then return "SPRITE_BRUNETTE_GIRL" end
  return "SPRITE_RED"
end

--- Preferred overworld sprite ids for a skin, best first: the full
--- body+tone+outfit combo sheet (outfit 0 = classic body colors, so it
--- rides the plain tone sheet), then the tone sheet, then the vanilla
--- body sheet, then RED (the sprite every cache carries). Callers walk
--- the list because a variant can legitimately be missing and a look
--- must never make a player invisible.
function Skins.spriteCandidates(skin)
  skin = Skins.sanitize(skin)
  local list = {}
  if skin.outfit > 0 then
    list[#list + 1] = ("G1MMO_B%d_T%d_O%d"):format(skin.body, skin.skin, skin.outfit)
  end
  list[#list + 1] = ("G1MMO_B%d_T%d"):format(skin.body, skin.skin)
  list[#list + 1] = Skins.baseSprite(skin)
  list[#list + 1] = "SPRITE_RED"
  return list
end

--- Back-compat single-id accessor (the base body sheet).
function Skins.overworldSprite(skin)
  return Skins.baseSprite(skin)
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
