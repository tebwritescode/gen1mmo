-- Asset transform: skin-tone sprite sheets, derived at install from the
-- player's OWN imported cache (the repo ships the recipe, never a
-- ROM-derived pixel -- same pattern as the engine's example_shiny_palette).
--
-- Buckets (lightest first) follow the importer's 4-gray split. On the
-- people sheets the near-white bucket is the transparent background, the
-- light-gray bucket is FACE/HANDS (SGB "white"), mid-gray is CLOTHES and
-- the darkest is the outline -- so the tone rides bucket 2.
local TONES = { -- catalog order: skinTones[1..8] in src/skins.lua
  { 248, 232, 224 }, -- Porcelain
  { 240, 216, 184 }, -- Fair
  { 224, 184, 144 }, -- Warm
  { 200, 160, 112 }, -- Olive
  { 176, 128,  88 }, -- Bronze
  { 136,  96,  64 }, -- Umber
  { 104,  72,  48 }, -- Deep
  {  72,  48,  32 }, -- Ebony
}

local BODIES = {
  [0] = { sheet = "sprites/red.png",  clothes = { 224, 56, 40 } },
  [1] = { sheet = "sprites/blue.png", clothes = { 56, 88, 224 } },
}

return function(ctx)
  for body = 0, 1 do
    local def = BODIES[body]
    -- no ROM import yet: derive nothing; the mod falls back to the
    -- vanilla RED/BLUE sheets and stays loaded
    if ctx.exists(def.sheet) then
      local img = ctx.readImage(def.sheet)
      for t = 1, #TONES do
        ctx.writeImage(ctx.recolor(img, {
          { 248, 248, 248 }, TONES[t], def.clothes, { 16, 24, 32 },
        }), ("sprites/g1mmo_b%d_t%d.png"):format(body, t - 1))
      end
    end
  end
end
