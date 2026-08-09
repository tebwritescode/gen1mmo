-- Runtime tone-sheet generation: the belt to transforms.lua's braces.
--
-- The install-time asset transform derives the 16 tone sheets from the
-- player's imported cache -- when it runs, finds the sheets, and the
-- device's cache uses the expected names. Live testing showed devices
-- where none of that can be counted on, and a missing sheet silently
-- downgraded every look to the stock sprite. So: at load, any tone sheet
-- that cannot actually be LOADED is regenerated right here from the
-- already-resolvable base sheet, written into the same
-- save/mod-derived/gen1mmo/ path the engine resolves derived assets from.
-- Same recolor, same filenames -- just performed where we can see it fail.
--
-- Shade buckets mirror the engine's own 4-gray split (SpriteRenderer
-- getObpImage: r > 0.83 background, > 0.5 face, > 0.17 clothes, else
-- outline). Alpha is preserved throughout.

local Tonegen = {}

local TONES = { -- catalog order: skinTones[1..8] in src/skins.lua
  { 248, 232, 224 }, { 240, 216, 184 }, { 224, 184, 144 }, { 200, 160, 112 },
  { 176, 128,  88 }, { 136,  96,  64 }, { 104,  72,  48 }, {  72,  48,  32 },
}
local BODIES = {
  [0] = { sheet = "assets/generated/sprites/red.png",  clothes = { 224, 56, 40 } },
  [1] = { sheet = "assets/generated/sprites/blue.png", clothes = { 56, 88, 224 } },
}
local OUT_DIR = "save/mod-derived/gen1mmo/sprites"

local function loadable(path)
  return (pcall(function() require("src.render.Assets").image(path) end))
end

local function recolor(source, tone, clothes)
  local out = love.image.newImageData(source:getWidth(), source:getHeight())
  local t = { tone[1] / 255, tone[2] / 255, tone[3] / 255 }
  local c = { clothes[1] / 255, clothes[2] / 255, clothes[3] / 255 }
  out:mapPixel(function(x, y)
    local r, g, b, a = source:getPixel(x, y)
    if a == 0 then return r, g, b, a end
    if r > 0.83 then return r, g, b, a end            -- background/highlight
    if r > 0.5 then return t[1], t[2], t[3], a end    -- face and hands
    if r > 0.17 then return c[1], c[2], c[3], a end   -- clothes
    return 16 / 255, 24 / 255, 32 / 255, a            -- outline
  end)
  return out
end

--- Ensure every tone sheet loads; regenerate the missing ones. Returns
--- (okCount, total, note) for the diagnostics line.
function Tonegen.ensure()
  local ok, made, total = 0, 0, 16
  local sources = {}
  for body = 0, 1 do
    for t = 1, #TONES do
      local rel = ("%s/g1mmo_b%d_t%d.png"):format(OUT_DIR, body, t - 1)
      local resolved = ("assets/generated/sprites/g1mmo_b%d_t%d.png"):format(body, t - 1)
      if loadable(resolved) then
        ok = ok + 1
      else
        local src = sources[body]
        if src == nil then
          local got, data = pcall(function()
            return require("src.render.Assets").imageData(BODIES[body].sheet)
          end)
          src = got and data or false
          sources[body] = src
        end
        if src then
          local wrote = pcall(function()
            love.filesystem.createDirectory(OUT_DIR)
            recolor(src, TONES[t], BODIES[body].clothes):encode("png", rel)
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
