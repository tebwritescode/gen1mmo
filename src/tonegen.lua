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
local BODIES = {
  [0] = { sheet = "assets/generated/sprites/red.png", clothes = { 224, 56, 40 } },
  -- the Girl body rides the brunette-girl walker: a real feminine
  -- silhouette with actual long-hair pixels (operator call: reuse the
  -- game's own NPC sheets rather than paint hair onto the boy base)
  [1] = { sheet = "assets/generated/sprites/brunette_girl.png",
          clothes = { 56, 88, 224 }, headRows = 8, sideHair = true },
}
-- hairColors[1..12] catalog order (0 = Black)
local HAIRC = {
  [0] = { 32, 28, 28 },  [1] = { 72, 48, 32 },   [2] = { 120, 80, 48 },
  [3] = { 152, 88, 40 }, [4] = { 208, 112, 40 }, [5] = { 224, 192, 96 },
  [6] = { 232, 224, 200 },[7] = { 176, 176, 184 },[8] = { 176, 40, 48 },
  [9] = { 48, 104, 176 },[10] = { 48, 128, 80 }, [11] = { 136, 72, 176 },
}
-- pieceColors[1..12] catalog order: hat / shirt / pants / backpack swatches
local PIECES = {
  [0] = { 32, 28, 28 },   [1] = { 104, 72, 48 },  [2] = { 184, 152, 104 },
  [3] = { 224, 56, 40 },  [4] = { 232, 144, 32 }, [5] = { 232, 208, 72 },
  [6] = { 240, 240, 240 },[7] = { 136, 136, 144 },[8] = { 152, 32, 48 },
  [9] = { 56, 88, 224 },  [10] = { 64, 144, 80 }, [11] = { 136, 72, 176 },
}
-- outfits[1..8] legacy presets (0 = Adventurer: the body's classic color).
-- Still honored when a skin carries no per-piece colors (older senders).
local OUTFITS = {
  [1] = { 168, 144,  96 }, [2] = {  64, 128,  72 }, [3] = {  72,  72,  88 },
  [4] = {  96,  64, 144 }, [5] = { 232, 144,  32 }, [6] = {  64, 160, 128 },
  [7] = { 152,  32,  48 },
}
local OUT_DIR = "save/mod-derived/gen1mmo/sprites"
local FRAME_H = 16
-- frame regions (rows within a 16px frame) for the piece recolors
local HEAD_ROWS = 7    -- hat/hair: 0..7
local SHIRT_ROWS = 11  -- shirt: 8..11 (pants below)
-- frames stacked vertically: 0 stand-down, 1 stand-up, 2 stand-left,
-- 3 walk-down, 4 walk-up, 5 walk-left -- the UP frames show the backpack
local UP_FRAMES = { [1] = true, [4] = true }

-- Hair-style accents: ORIGINAL pixel clusters (this table IS the artwork,
-- authored for this mod) stamped in hairColor onto every frame. x from
-- the left of the 16px frame, y from the frame top. Styles 0 (Cropped)
-- and 1 (Cap Hair) add nothing; 9 (Buzzed) also strips the hat's lowest
-- row so the head reads shaved.
local STYLE_PIXELS = {
  [2] = { {5,1},{7,0},{9,1},{11,0} },                                   -- Tousled
  [3] = { {2,6},{2,7},{3,7},{2,8},{3,8},{2,9} },                        -- Ponytail
  [4] = { {1,6},{1,7},{2,7},{1,8}, {14,6},{14,7},{13,7},{14,8} },       -- Twin Tails
  [5] = { {2,6},{2,7},{13,6},{13,7},{3,7},{12,7} },                     -- Bob
  [6] = { {2,6},{2,7},{2,8},{2,9},{2,10},{13,6},{13,7},{13,8},{13,9},{13,10} }, -- Long
  [7] = { {4,0},{6,0},{8,0},{10,0},{12,0},{5,1},{9,1} },               -- Spiked
  [8] = { {3,6},{5,7},{11,7},{12,6},{4,8},{12,8} },                     -- Curls
}

local function loadable(path)
  return (pcall(function() require("src.render.Assets").image(path) end))
end

local function paint(out, x, y, c, srcW, srcH)
  if x >= 0 and y >= 0 and x < srcW and y < srcH then
    out:setPixel(x, y, c[1] / 255, c[2] / 255, c[3] / 255, 1)
  end
end

--- looks: { tone, hairc, hat (bool), hatc, shirt, pants, pack, style, body }
--- every color a {r,g,b} 0..255 triple.
local function build(source, looks)
  local w, h = source:getWidth(), source:getHeight()
  local out = love.image.newImageData(w, h)
  local function n(cc) return { cc[1] / 255, cc[2] / 255, cc[3] / 255 } end
  local t = n(looks.tone)
  local hc = n(looks.hairc)
  local headC = looks.hat and n(looks.hatc) or hc
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
      if frameY <= headRows then                       -- head: hat or hair
        if looks.style == 9 and frameY == headRows and not looks.hat then
          return t[1], t[2], t[3], a                   -- Buzzed shaves the rim
        end
        return headC[1], headC[2], headC[3], a
      elseif looks.sideHair and frameY <= SHIRT_ROWS and (fx <= 3 or fx >= 12) then
        -- long hair falling beside the torso stays HAIR, not shirt
        return hc[1], hc[2], hc[3], a
      elseif frameY <= SHIRT_ROWS then                 -- torso: shirt or pack
        if UP_FRAMES[frame] then return packC[1], packC[2], packC[3], a end
        return shirtC[1], shirtC[2], shirtC[3], a
      end
      return pantsC[1], pantsC[2], pantsC[3], a        -- legs: pants
    end
    -- dark ink: normally the outline -- but the female sheet draws the
    -- HAIR TOP in dark ink, so above the eye line it tints as a deep
    -- shade of the hair color (keeps contour depth, reads as hair)
    if looks.sideHair then
      local frameY = y % FRAME_H
      if frameY <= 4 then
        return hc[1] * 0.55, hc[2] * 0.55, hc[3] * 0.55, a
      end
    end
    return 16 / 255, 24 / 255, 32 / 255, a             -- outline
  end)
  -- hair accents draw when the hair is VISIBLE (no hat) or the style
  -- sticks out anyway (tails, long, bob reach below the hat line)
  local accents = STYLE_PIXELS[looks.style]
  if accents then
    for frame = 0, math.floor(h / FRAME_H) - 1 do
      for _, p in ipairs(accents) do
        if not looks.hat or p[2] > 5 then
          paint(out, p[1], frame * FRAME_H + p[2], looks.hairc, w, h)
        end
      end
    end
  end
  return out
end

--- The derived sheet path for a full skin tuple, generating it on first
--- use. Returns the resolvable asset path, or nil when the base sheet
--- cannot be read.
function Tonegen.ensureFor(skin)
  local body = tonumber(skin.body) or 0
  local tone = tonumber(skin.skin) or 0
  local style = tonumber(skin.hair) or 0
  local hairc = tonumber(skin.hairColor) or 0
  local outfit = tonumber(skin.outfit) or 0
  local hat = (tonumber(skin.hat) or 1) ~= 0
  -- per-piece colors; when absent, the legacy outfit preset colors the
  -- whole set so pre-1.2 skins keep looking as they did
  local legacy = OUTFITS[outfit] or (BODIES[body] or BODIES[0]).clothes
  local hatc  = skin.hatColor ~= nil and PIECES[tonumber(skin.hatColor) or 0] or legacy
  local shirt = skin.shirt ~= nil and PIECES[tonumber(skin.shirt) or 0] or legacy
  local pants = skin.pants ~= nil and PIECES[tonumber(skin.pants) or 0] or legacy
  local pack  = skin.pack ~= nil and PIECES[tonumber(skin.pack) or 0] or legacy
  local name = ("g1mmo_%d_%d_%d_%d_%d_%d_%d_%d_%d.png"):format(
    body, tone, style, hairc, hat and 1 or 0,
    tonumber(skin.hatColor) or -1, tonumber(skin.shirt) or -1,
    tonumber(skin.pants) or -1, tonumber(skin.pack) or -1)
  local resolved = "assets/generated/sprites/" .. name
  if loadable(resolved) then return resolved end
  local got, src = pcall(function()
    return require("src.render.Assets").imageData((BODIES[body] or BODIES[0]).sheet)
  end)
  if not got or not src then return nil end
  local bodyDef = BODIES[body] or BODIES[0]
  local wrote = pcall(function()
    love.filesystem.createDirectory(OUT_DIR)
    build(src, {
      tone = TONES[tone + 1] or TONES[1],
      hairc = HAIRC[hairc] or HAIRC[0],
      hat = hat, hatc = hatc, shirt = shirt, pants = pants, pack = pack,
      style = style, body = body,
      headRows = bodyDef.headRows, sideHair = bodyDef.sideHair,
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
              tone = TONES[t], hairc = classic, hat = true, hatc = classic,
              shirt = classic, pants = classic, pack = classic,
              style = 1, body = body,
              headRows = BODIES[body].headRows, sideHair = BODIES[body].sideHair,
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
