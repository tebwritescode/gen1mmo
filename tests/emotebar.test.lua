-- Hit-test coverage for the quick action bar's button layout.
--
--   luajit tests/emotebar.test.lua
--
-- rects()/hit() are pure (no love.* deps), loaded for real here rather than
-- re-described, so a layout change that makes two buttons overlap -- or
-- pushes one off the 160x144 canvas -- fails a test instead of shipping.

_G.GEN1MMO_INCLUDE = function(path)
  local chunk = assert(loadfile(path))
  return chunk()
end

local EmoteBar = (function()
  local chunk = assert(loadfile("src/emotebar.lua"))
  return chunk()
end)()
local rects, hit = EmoteBar.rects, EmoteBar.hit

local pass, fail = 0, 0
local function ok(name, cond, detail)
  if cond then pass = pass + 1; print("OK   " .. name)
  else fail = fail + 1; print("FAIL " .. name .. (detail and ("  -- " .. detail) or "")) end
end

-- 1. Both toggles always present, regardless of open/closed.
do
  local closed, open = rects(false), rects(true)
  ok("chat toggle present when collapsed", closed.chat ~= nil)
  ok("emote toggle present when collapsed", closed.toggle ~= nil)
  ok("chat toggle present when expanded", open.chat ~= nil)
  ok("emote toggle present when expanded", open.toggle ~= nil)
end

-- 2. Chat toggle sits immediately LEFT of the emote toggle, same row, no
--    overlap, both fully on-canvas.
do
  local r = rects(false)
  ok("chat toggle left of emote toggle", r.chat.x < r.toggle.x)
  ok("chat toggle adjacent (toggle.x - chat.w - gap)",
    r.chat.x + r.chat.w <= r.toggle.x)
  ok("chat toggle same row as emote toggle", r.chat.y == r.toggle.y)
  ok("chat toggle on-canvas (x)", r.chat.x >= 0 and r.chat.x + r.chat.w <= 160)
  ok("chat toggle on-canvas (y)", r.chat.y >= 0 and r.chat.y + r.chat.h <= 144)
end

-- 3. Expanded: exactly 3 emote rows plus the two toggles, all on-canvas.
do
  local r = rects(true)
  ok("expanded: 3 emote rows", r[1] and r[2] and r[3] and r[4] == nil)
  for i = 1, 3 do
    ok(("row %d stays on-canvas"):format(i),
      r[i].x >= 0 and r[i].x + r[i].w <= 160 and r[i].y >= 0 and r[i].y + r[i].h <= 144)
  end
  ok("row kinds are heart/wave/fist in order", r[1].kind == 0 and r[2].kind == 1 and r[3].kind == 2)
end

-- 4. No overlap between ANY of the up-to-5 buttons when expanded (chat,
--    toggle, heart, wave, fist) -- a fat-finger tap must never resolve to
--    two buttons at once.
local function overlaps(a, b)
  return a.x < b.x + b.w and a.x + a.w > b.x and a.y < b.y + b.h and a.y + a.h > b.y
end
do
  local r = rects(true)
  local all = { r.chat, r.toggle, r[1], r[2], r[3] }
  local clean = true
  for i = 1, #all do
    for j = i + 1, #all do
      if overlaps(all[i], all[j]) then clean = false end
    end
  end
  ok("no two of the 5 expanded buttons overlap", clean)
end

-- 5. Hit-testing the chat toggle doesn't accidentally hit the emote toggle
--    or vice versa.
do
  local r = rects(false)
  local cx, cy = r.chat.x + r.chat.w / 2, r.chat.y + r.chat.h / 2
  local tx, ty = r.toggle.x + r.toggle.w / 2, r.toggle.y + r.toggle.h / 2
  ok("chat center hits chat, not toggle", hit(r.chat, cx, cy) and not hit(r.toggle, cx, cy))
  ok("toggle center hits toggle, not chat", hit(r.toggle, tx, ty) and not hit(r.chat, tx, ty))
end

-- 6. Collapsing after expansion drops the emote rows again (state-driven,
--    not accumulated).
do
  local expanded, collapsed = rects(true), rects(false)
  ok("collapse clears rows[1..3]", collapsed[1] == nil and collapsed[2] == nil and collapsed[3] == nil)
  ok("both toggles keep the same rect open vs closed",
    expanded.toggle.x == collapsed.toggle.x and expanded.toggle.y == collapsed.toggle.y
    and expanded.chat.x == collapsed.chat.x and expanded.chat.y == collapsed.chat.y)
end

print(string.format("\nRESULT %d passed, %d failed", pass, fail))
if fail > 0 then error("emotebar hit-test tests failed") end
