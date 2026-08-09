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
  [0] = { sheet = "assets/generated/sprites/red.png",  clothes = { 224, 56, 40 } },
  [1] = { sheet = "assets/generated/sprites/blue.png", clothes = { 56, 88, 224 } },
}
-- hairColors[1..12] catalog order (0 = Black)
local HAIRC = {
  [0] = { 32, 28, 28 },  [1] = { 72, 48, 32 },   [2] = { 120, 80, 48 },
  [3] = { 152, 88, 40 }, [4] = { 208, 112, 40 }, [5] = { 224, 192, 96 },
  [6] = { 232, 224, 200 },[7] = { 176, 176, 184 },[8] = { 176, 40, 48 },
  [9] = { 48, 104, 176 },[10] = { 48, 128, 80 }, [11] = { 136, 72, 176 },
}
-- outfits[1..8] catalog order (0 = Adventurer: the body's classic color)
local OUTFITS = {
  [1] = { 168, 144,  96 }, [2] = {  64, 128,  72 }, [3] = {  72,  72,  88 },
  [4] = {  96,  64, 144 }, [5] = { 232, 144,  32 }, [6] = {  64, 160, 128 },
  [7] = { 152,  32,  48 },
}
local OUT_DIR = "save/mod-derived/gen1mmo/sprites"
local FRAME_H = 16
-- head/body split inside a frame: hat rows end here on both base sheets
local HEAD_ROWS = 7

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

local function build(source, tone, clothes, hairc, style)
  local w, h = source:getWidth(), source:getHeight()
  local out = love.image.newImageData(w, h)
  local t = { tone[1] / 255, tone[2] / 255, tone[3] / 255 }
  local c = { clothes[1] / 255, clothes[2] / 255, clothes[3] / 255 }
  local hc = { hairc[1] / 255, hairc[2] / 255, hairc[3] / 255 }
  out:mapPixel(function(x, y)
    local r, g, b, a = source:getPixel(x, y)
    if a == 0 then return r, g, b, a end
    if r > 0.83 then return r, g, b, a end             -- background/highlight
    if r > 0.5 then return t[1], t[2], t[3], a end     -- face and hands
    if r > 0.17 then                                   -- clothes ink...
      local frameY = y % FRAME_H
      if frameY <= HEAD_ROWS then                      -- ...hat = hair
        if style == 9 and frameY == HEAD_ROWS then     -- Buzzed: shave the rim
          return t[1], t[2], t[3], a
        end
        return hc[1], hc[2], hc[3], a
      end
      return c[1], c[2], c[3], a                       -- ...torso = outfit
    end
    return 16 / 255, 24 / 255, 32 / 255, a             -- outline
  end)
  local accents = STYLE_PIXELS[style]
  if accents then
    for frame = 0, math.floor(h / FRAME_H) - 1 do
      for _, p in ipairs(accents) do
        paint(out, p[1], frame * FRAME_H + p[2], hairc, w, h)
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
  local outfit = tonumber(skin.outfit) or 0
  local hairc = tonumber(skin.hairColor) or 0
  local style = tonumber(skin.hair) or 0
  local name = ("g1mmo_b%d_t%d_o%d_h%d_c%d.png"):format(body, tone, outfit, style, hairc)
  local resolved = "assets/generated/sprites/" .. name
  if loadable(resolved) then return resolved end
  local got, src = pcall(function()
    return require("src.render.Assets").imageData((BODIES[body] or BODIES[0]).sheet)
  end)
  if not got or not src then return nil end
  local clothes = OUTFITS[outfit] or (BODIES[body] or BODIES[0]).clothes
  local wrote = pcall(function()
    love.filesystem.createDirectory(OUT_DIR)
    build(src, TONES[tone + 1] or TONES[1], clothes, HAIRC[hairc] or HAIRC[0], style)
      :encode("png", OUT_DIR .. "/" .. name)
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
            build(src, TONES[t], BODIES[body].clothes, BODIES[body].clothes, 1)
              :encode("png", rel)
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
