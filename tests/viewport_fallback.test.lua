-- Overlay.viewportOr is now load-bearing for EVERY touch path (main.lua's
-- input.pointer hook), not just a rare drawing fallback: chat drag-scroll
-- and the quick action bar both went silently inert on a real device when
-- client._vp was not yet populated at tap time. This locks in that the
-- fallback always produces a usable, correctly-shaped viewport instead of
-- leaving touch dead.
--
--   luajit tests/viewport_fallback.test.lua

local pass, fail = 0, 0
local function ok(name, cond, detail)
  if cond then pass = pass + 1; print("OK   " .. name)
  else fail = fail + 1; print("FAIL " .. name .. (detail and ("  -- " .. detail) or "")) end
end

-- Minimal love stub: only what viewportOr and Overlay.install touch before
-- returning the function -- no window, no graphics, no timer needed for
-- this specific path.
_G.love = {
  graphics = { getDimensions = function() return 480, 432 end },
  timer = { getTime = function() return 0 end },
}
_G.GEN1MMO_INCLUDE = function(path)
  local chunk = assert(loadfile(path))
  return chunk()
end

local Overlay = (function()
  local chunk = assert(loadfile("src/overlay.lua"))
  return chunk()
end)()

-- Overlay.viewportOr only exists after install() runs (it is assigned
-- inside that function, closing over `client`) -- exactly the ordering
-- main.lua relies on, so mirror it instead of poking at internals.
local fakeMod = {
  ui = { Font = {} },
  hooks = { wrap = function() end }, -- render.hud registration, unused here
}
local client = { log = function() end, ovl = {} }
Overlay.install(fakeMod, client)

ok("viewportOr exists after install()", type(Overlay.viewportOr) == "function")

-- 1. A real vp table passed straight through unchanged.
do
  local real = { gameX = 10, gameY = 20, gameWidth = 320, gameHeight = 288, scale = 2 }
  local got = Overlay.viewportOr(real)
  ok("a real vp table passes through as-is", got == real)
end

-- 2. nil vp, but client._vp already cached: falls back to that.
do
  client._vp = { gameX = 5, gameY = 6, gameWidth = 160, gameHeight = 144, scale = 1 }
  local got = Overlay.viewportOr(nil)
  ok("falls back to client._vp when the argument is nil", got == client._vp)
  client._vp = nil
end

-- 3. Neither a real vp NOR a cached client._vp: synthesizes one from the
--    window size -- this is the exact case that left touch dead. Must be
--    a complete, correctly-shaped table, not a partial one a caller's
--    vp.gameWidth/144 math would choke on.
do
  local got = Overlay.viewportOr(nil)
  ok("synthesizes a table when nothing else is available", type(got) == "table")
  ok("has a positive scale", type(got.scale) == "number" and got.scale >= 1)
  ok("has a positive gameWidth", type(got.gameWidth) == "number" and got.gameWidth > 0)
  ok("has a positive gameHeight", type(got.gameHeight) == "number" and got.gameHeight > 0)
  ok("gameWidth is scale * 160 (the GB canvas width)", got.gameWidth == got.scale * 160)
  ok("gameHeight is scale * 144 (the GB canvas height)", got.gameHeight == got.scale * 144)
  ok("gameX/gameY are numbers (letterbox offset), not nil",
    type(got.gameX) == "number" and type(got.gameY) == "number")
  -- the exact math main.lua's input.pointer hook does with this table --
  -- if this divides cleanly, a tap converts to real canvas coordinates
  -- instead of producing nan/inf that never hits any button rect
  local cx = (100 - got.gameX) / (got.gameWidth / 160)
  local cy = (100 - got.gameY) / (got.gameHeight / 144)
  ok("produces finite, usable canvas coordinates from a sample tap",
    cx == cx and cy == cy and cx ~= math.huge and cy ~= math.huge, -- cx==cx false only for NaN
    ("cx=%s cy=%s"):format(tostring(cx), tostring(cy)))
end

print(string.format("\nRESULT %d passed, %d failed", pass, fail))
if fail > 0 then error("viewport fallback tests failed") end
