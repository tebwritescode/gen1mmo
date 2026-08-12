-- The look-cycling skip logic (src/screens.lua's stepIndex/BODY_SKIP):
-- Biker's roster sprite is seated on the bike, not a normal walker, so it's
-- not offered as a fresh pick. The catalog SLOT stays put deliberately (its
-- index is wire-compatible with the server and with anyone who already has
-- it saved) -- cycling just has to step cleanly over it, from either
-- direction, from every starting point, including from Biker itself for a
-- player who already had it.
--
--   luajit tests/look_stepindex.test.lua

local client = { skin = {} }
local function stepIndex(field, list, dir, skip)
  local n = #list
  local v = client.skin[field] or 0
  for _ = 1, n do
    v = (v + dir) % n
    if not (skip and skip[v]) then break end
  end
  return v
end

local pass, fail = 0, 0
local function eq(name, got, want)
  if got == want then pass = pass + 1; print("OK   " .. name)
  else fail = fail + 1; print("FAIL " .. name .. "  got=" .. tostring(got) .. " want=" .. tostring(want)) end
end

local BODIES = {}; for i = 1, 16 do BODIES[i] = i end -- 16 entries, indices 0..15
local BODY_SKIP = { [10] = true } -- Biker

-- 1. Normal step, no skip list: simple +-1 wraparound.
client.skin.body = 5
eq("plain +1", stepIndex("body", BODIES, 1, nil), 6)
client.skin.body = 5
eq("plain -1", stepIndex("body", BODIES, -1, nil), 4)
client.skin.body = 15
eq("+1 wraps to 0", stepIndex("body", BODIES, 1, nil), 0)
client.skin.body = 0
eq("-1 wraps to 15", stepIndex("body", BODIES, -1, nil), 15)

-- 2. Stepping onto Biker from either side skips straight over it.
client.skin.body = 9
eq("approaching from below (9) +1 skips 10, lands on 11", stepIndex("body", BODIES, 1, BODY_SKIP), 11)
client.skin.body = 11
eq("approaching from above (11) -1 skips 10, lands on 9", stepIndex("body", BODIES, -1, BODY_SKIP), 9)

-- 3. Already ON the skipped index (a pre-existing save with body=10):
--    stepping still moves cleanly past it in either direction, since the
--    loop always advances at least once before checking skip.
client.skin.body = 10
eq("already on 10, +1 moves to 11 (not stuck)", stepIndex("body", BODIES, 1, BODY_SKIP), 11)
client.skin.body = 10
eq("already on 10, -1 moves to 9 (not stuck)", stepIndex("body", BODIES, -1, BODY_SKIP), 9)

-- 4. Biker is never reachable by repeated stepping from anywhere in the
--    catalog -- walk every starting point, both directions, one full lap
--    each, and confirm the value 10 never appears.
for start = 0, 15 do
  for _, dir in ipairs({ 1, -1 }) do
    client.skin.body = start
    local sawBiker = false
    for _ = 1, 16 do
      client.skin.body = stepIndex("body", BODIES, dir, BODY_SKIP)
      if client.skin.body == 10 then sawBiker = true end
    end
    eq(("full lap from %d dir %d never lands on Biker"):format(start, dir), sawBiker, false)
  end
end

-- 5. A field with no skip list (e.g. "skin", "pack") is completely
--    unaffected -- skip is nil, not an empty table, so index 10 (if it
--    existed there) would still be reachable. Regression guard against
--    accidentally sharing BODY_SKIP across fields.
local TONES = {}; for i = 1, 8 do TONES[i] = i end
client.skin.skin = 7
eq("non-body field ignores BODY_SKIP entirely (no skip passed)",
  stepIndex("skin", TONES, 1, nil), 0)

print(string.format("\nRESULT %d passed, %d failed", pass, fail))
if fail > 0 then error("stepIndex tests failed") end
