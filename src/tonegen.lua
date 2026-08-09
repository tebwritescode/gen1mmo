-- Runtime look-sheet generation: every skin field renders, no shipped art.
--
-- All pixels derive from the player's OWN imported cache at runtime (the
-- project's legal posture: repos never carry ROM-derived pixels), written
-- into save/mod-derived/gen1mmo/ where the engine resolves derived assets.
--
-- How five fields map onto a three-ink GB sprite (face/clothes/outline),
-- 16x16 frames stacked vertically:
--   tone      -> face/hands ink, whole sprite
--   hairColor -> clothes ink in the HEAD region (the hat rows: the cap
--                reads as the character's hair)
--   outfit    -> clothes ink in the BODY region
--   hair      -> small ORIGINAL pixel accents (authored here, in code) in
--                hairColor around the head: tails, spikes, bobs, length
--   body      -> which base sheet (red / blue silhouette)

local Tonegen = {}

local TONES = { -- catalog order: skinTones[1..8] in src/skins.lua
  { 248, 232, 224 }, { 240, 216, 184 }, { 224, 184, 144 }, { 200, 160, 112 },
  { 176, 128,  88 }, { 136,  96,  64 }, { 104,  72,  48 }, {  72,  48,  32 },
}
-- THE ROSTER (skins overhaul, operator direction): a body is one of the
-- game's own people sheets -- authored hair, hats and silhouettes instead
-- of painted accents. Index = the wire `body` id. Flags steer the region
-- recolor per sheet: headRows widens the hair zone, sideHair keeps long
-- hair out of the shirt recolor, darkHead tints dark-ink hair tops.
local ROSTER = {
  [0]  = { name = "Red",       sprite = "SPRITE_RED",           sheet = "assets/generated/sprites/red.png",           clothes = { 224, 56, 40 } },
  [1]  = { name = "Brunette",  sprite = "SPRITE_BRUNETTE_GIRL", sheet = "assets/generated/sprites/brunette_girl.png", clothes = { 56, 88, 224 }, headRows = 8, sideHair = true, darkHead = true },
  [2]  = { name = "Blue",      sprite = "SPRITE_BLUE",          sheet = "assets/generated/sprites/blue.png",          clothes = { 56, 88, 224 } },
  [3]  = { name = "Girl",      sprite = "SPRITE_GIRL",          sheet = "assets/generated/sprites/girl.png",          clothes = { 224, 56, 40 }, headRows = 8, sideHair = true },
  [4]  = { name = "Cool F",    sprite = "SPRITE_COOLTRAINER_F", sheet = "assets/generated/sprites/cooltrainer_f.png", clothes = { 56, 88, 224 }, headRows = 8, sideHair = true, darkHead = true },
  [5]  = { name = "Cool M",    sprite = "SPRITE_COOLTRAINER_M", sheet = "assets/generated/sprites/cooltrainer_m.png", clothes = { 56, 88, 224 } , darkHead = true },
  [6]  = { name = "Beauty",    sprite = "SPRITE_BEAUTY",        sheet = "assets/generated/sprites/beauty.png",        clothes = { 224, 56, 40 }, headRows = 8, sideHair = true, darkHead = true },
  [7]  = { name = "Youngster", sprite = "SPRITE_YOUNGSTER",     sheet = "assets/generated/sprites/youngster.png",     clothes = { 56, 88, 224 } },
  [8]  = { name = "Kid",       sprite = "SPRITE_LITTLE_GIRL",   sheet = "assets/generated/sprites/little_girl.png",   clothes = { 224, 56, 40 }, sideHair = true, darkHead = true, headRows = 6 },
  [9]  = { name = "Hiker",     sprite = "SPRITE_HIKER",         sheet = "assets/generated/sprites/hiker.png",         clothes = { 104, 72, 48 } },
  [10] = { name = "Biker",     sprite = "SPRITE_BIKER",         sheet = "assets/generated/sprites/biker.png",         clothes = { 32, 28, 28 } , darkHead = true },
  [11] = { name = "Fisher",    sprite = "SPRITE_FISHER",        sheet = "assets/generated/sprites/fisher.png",        clothes = { 64, 128, 72 } , darkHead = true },
  [12] = { name = "Sailor",    sprite = "SPRITE_SAILOR",        sheet = "assets/generated/sprites/sailor.png",        clothes = { 240, 240, 240 } },
  [13] = { name = "Rocker",    sprite = "SPRITE_ROCKER",        sheet = "assets/generated/sprites/rocker.png",        clothes = { 32, 28, 28 }, darkHead = true },
  [14] = { name = "Scientist", sprite = "SPRITE_SCIENTIST",     sheet = "assets/generated/sprites/scientist.png",     clothes = { 240, 240, 240 } , darkHead = true },
  [15] = { name = "Gentleman", sprite = "SPRITE_GENTLEMAN",     sheet = "assets/generated/sprites/gentleman.png",     clothes = { 72, 72, 88 } , darkHead = true },
}
Tonegen.ROSTER = ROSTER
local BODIES = { [0] = ROSTER[0], [1] = ROSTER[1] } -- legacy alias
local PIECES = {
  [0] = { 32, 28, 28 },   [1] = { 104, 72, 48 },  [2] = { 184, 152, 104 },
  [3] = { 224, 56, 40 },  [4] = { 232, 144, 32 }, [5] = { 232, 208, 72 },
  [6] = { 240, 240, 240 },[7] = { 136, 136, 144 },[8] = { 152, 32, 48 },
  [9] = { 56, 88, 224 },  [10] = { 64, 144, 80 }, [11] = { 136, 72, 176 },
}
local OUT_DIR = "save/mod-derived/gen1mmo/sprites"
local FRAME_H = 16
-- frame regions (rows within a 16px frame) for the piece recolors
local HEAD_ROWS = 7    -- hat/hair: 0..7
local SHIRT_ROWS = 11  -- shirt: 8..11 (pants below)
-- frames stacked vertically: 0 stand-down, 1 stand-up, 2 stand-left,
-- 3 walk-down, 4 walk-up, 5 walk-left -- the UP frames show the backpack
local UP_FRAMES = { [1] = true, [4] = true }

local function loadable(path)
  return (pcall(function() require("src.render.Assets").image(path) end))
end

--- looks: { tone, head, shirt, pants, pack } as {r,g,b} triples, plus the
--- roster flags { headRows, sideHair, darkHead }. Head means "whatever the
--- sheet wears up top" -- hat, hair, headband; the art stays the art and
--- only its color changes.
local function build(source, looks)
  local w, h = source:getWidth(), source:getHeight()
  local out = love.image.newImageData(w, h)
  local function n(cc) return { cc[1] / 255, cc[2] / 255, cc[3] / 255 } end
  local t = n(looks.tone)
  local headC = n(looks.head)
  local shirtC = n(looks.shirt)
  local pantsC = n(looks.pants)
  local packC = n(looks.pack)
  local headRows = looks.headRows or HEAD_ROWS
  out:mapPixel(function(x, y)
    local r, g, b, a = source:getPixel(x, y)
    if a == 0 then return r, g, b, a end
    if r > 0.83 then return r, g, b, a end             -- background/highlight
    if r > 0.5 then return t[1], t[2], t[3], a end     -- face and hands
    if r > 0.17 then                                   -- clothes ink, by region:
      local frameY = y % FRAME_H
      local frame = math.floor(y / FRAME_H)
      local fx = x % 16
      if frameY <= headRows then
        return headC[1], headC[2], headC[3], a         -- head piece
      elseif looks.sideHair and frameY <= SHIRT_ROWS and (fx <= 3 or fx >= 12) then
        -- long hair falling beside the torso stays head-colored
        return headC[1], headC[2], headC[3], a
      elseif frameY <= SHIRT_ROWS then                 -- torso: shirt or pack
        if UP_FRAMES[frame] then return packC[1], packC[2], packC[3], a end
        return shirtC[1], shirtC[2], shirtC[3], a
      end
      return pantsC[1], pantsC[2], pantsC[3], a        -- legs: pants
    end
    -- dark ink is normally the outline; sheets that draw their hair top
    -- in dark ink (flagged darkHead) tint it as a deep shade of the head
    -- color above the eye line, keeping contour depth
    if looks.darkHead then
      local frameY = y % FRAME_H
      if frameY <= 4 then
        return headC[1] * 0.55, headC[2] * 0.55, headC[3] * 0.55, a
      end
    end
    return 16 / 255, 24 / 255, 32 / 255, a             -- outline
  end)
  return out
end

--- The derived sheet path for a full skin tuple, generating it on first
--- use. Returns the resolvable asset path, or nil when the base sheet
--- cannot be read.
function Tonegen.ensureFor(skin)
  local body = tonumber(skin.body) or 0
  local roster = ROSTER[body] or ROSTER[0]
  local tone = tonumber(skin.skin) or 0
  -- wire mapping: hairColor doubles as the HEAD color (same 12 swatches)
  local headI = tonumber(skin.hairColor) or 0
  local shirtI = tonumber(skin.shirt)
  local pantsI = tonumber(skin.pants)
  local packI = tonumber(skin.pack)
  local head = PIECES[headI] or roster.clothes
  local shirt = shirtI ~= nil and PIECES[shirtI] or roster.clothes
  local pants = pantsI ~= nil and PIECES[pantsI] or roster.clothes
  local pack = packI ~= nil and PIECES[packI] or roster.clothes
  local name = ("g1mmo_v3_%d_%d_%d_%d_%d_%d.png"):format(
    body, tone, headI, shirtI or -1, pantsI or -1, packI or -1)
  local resolved = "assets/generated/sprites/" .. name
  if loadable(resolved) then return resolved end
  local got, src = pcall(function()
    return require("src.render.Assets").imageData(roster.sheet)
  end)
  if not got or not src then return nil end
  local wrote = pcall(function()
    love.filesystem.createDirectory(OUT_DIR)
    build(src, {
      tone = TONES[tone + 1] or TONES[1],
      head = head, shirt = shirt, pants = pants, pack = pack,
      headRows = roster.headRows, sideHair = roster.sideHair,
      darkHead = roster.darkHead,
    }):encode("png", OUT_DIR .. "/" .. name)
  end)
  if wrote and loadable(resolved) then return resolved end
  return nil
end

--- A ready SpriteRenderer def for a skin tuple (runtime, registry-free).
function Tonegen.defFor(skin)
  local path = Tonegen.ensureFor(skin)
  if not path then return nil end
  return { image = path, frames = 6, walker = true, trueColor = true }
end

--- Back-compat pre-generation of the 16 plain tone sheets (the ids the
--- registry knows, used as spawn targets before the runtime swap).
function Tonegen.ensure()
  local ok, made, total = 0, 0, 16
  for body = 0, 1 do
    for t = 1, #TONES do
      local rel = ("%s/g1mmo_b%d_t%d.png"):format(OUT_DIR, body, t - 1)
      local resolved = ("assets/generated/sprites/g1mmo_b%d_t%d.png"):format(body, t - 1)
      if loadable(resolved) then
        ok = ok + 1
      else
        local got, src = pcall(function()
          return require("src.render.Assets").imageData(BODIES[body].sheet)
        end)
        if got and src then
          local wrote = pcall(function()
            love.filesystem.createDirectory(OUT_DIR)
            local classic = BODIES[body].clothes
            build(src, {
              tone = TONES[t], head = classic, shirt = classic,
              pants = classic, pack = classic,
              headRows = BODIES[body].headRows, sideHair = BODIES[body].sideHair,
              darkHead = BODIES[body].darkHead,
            }):encode("png", rel)
          end)
          if wrote and loadable(resolved) then
            ok = ok + 1
            made = made + 1
          end
        end
      end
    end
  end
  local note = made > 0 and (made .. " regenerated")
    or (ok < total and "base sheets unreadable" or "from install")
  return ok, total, note
end

return Tonegen
