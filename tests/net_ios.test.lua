-- The transport, tested on the platform that actually broke.
--
--   luajit tests/net_ios.test.lua
--
-- WHY THIS FILE EXISTS. A player on iOS (Phosphorus) hit "networking
-- unavailable (luasocket missing)". UNVERIFIED against Phosphorus itself --
-- not yet reproduced or confirmed there -- but a sibling gen1recomp mod's
-- code (SaveSync's src/http.lua) carries a comment claiming "Phosphor's iOS
-- build has no love.thread [and] there is no curl to spawn and no bridge
-- exported", i.e. the same shape of gap. Treat that as a lead, not a fact:
-- it is that mod's own account of its own platform, not something checked
-- against this codebase or this device. No fix should be built on it until
-- it is actually confirmed against Phosphorus.
--
-- gen1mmo's protocol is also a PERSISTENT bidirectional TCP stream
-- (newline-JSON frames, non-blocking, polled every frame, with its own
-- encrypted tunnel handshake), not periodic REST calls -- so even if the
-- lead above holds up, SaveSync's lua-https swap (a one-shot synchronous
-- HTTPS request/response client) would not be a drop-in fix here. This
-- test only locks in that the ABSENCE of LuaSocket degrades SAFELY (no
-- crash, a real status message, no half-connected state); it does NOT
-- claim to explain why the socket is absent, and does not attempt a fix.
-- A real fix needs the cause confirmed on-device first.

_G.GEN1MMO_INCLUDE = function(path)
  local chunk = assert(loadfile(path))
  return chunk()
end

local pass, fail = 0, 0
local function ok(name, cond, detail)
  if cond then pass = pass + 1; print("OK   " .. name)
  else fail = fail + 1; print("FAIL " .. name .. (detail and ("  -- " .. detail) or "")) end
end
local function eq(name, got, want)
  ok(name, got == want, ("got %s, want %s"):format(tostring(got), tostring(want)))
end

-- Load the REAL net.lua once (its own require("socket") call is lazy --
-- Net:connect calls it at CONNECT time, not module-load time -- so the
-- mock has to stay active across the actual connect() call, the same way
-- SaveSync's http.test.lua keeps `require("https")` swapped for the
-- duration of each request it drives).
local Net = (function()
  local chunk = assert(loadfile("src/net.lua"))
  return chunk()
end)()

--- Runs fn() with require("socket") swapped for the duration of the call
--- only, then always restores the real require -- even if fn() throws.
local function withSocket(socketAvailable, fn)
  local realRequire = require
  _G.require = function(name)
    if name == "socket" then
      if not socketAvailable then error("module 'socket' not found", 2) end
      return { tcp = function() error("not exercised in this test") end }
    end
    return realRequire(name)
  end
  local ok, a, b = pcall(fn)
  _G.require = realRequire
  if not ok then error(a, 0) end
  return a, b
end

-- 1. iOS shape: no LuaSocket. connect() must fail CLEANLY -- no throw, a
--    real error string, connected/sock left in their initial (unset) state.
do
  local net = Net.new()
  local succeeded, result = pcall(withSocket, false, function()
    return net:connect("example.com", 7878)
  end)
  ok("connect() never throws when socket is missing", succeeded, tostring(result))
  eq("connect() reports failure", result, false)
  ok("a real, non-empty error is set", type(net.error) == "string" and #net.error > 0, net.error)
  ok("the error names the actual cause (not a generic blank)",
    net.error:lower():find("network", 1, true) ~= nil, net.error)
  eq("no socket object was left lying around", net.sock, nil)
  eq("connected stays false", net.connected, false)
end

-- 2. desktop/Android shape: LuaSocket present. connect() must still take
--    the real path and reach the (deliberately throwing) tcp() stub --
--    proof it got PAST the availability check, not the "socket missing"
--    branch -- rather than short-circuiting before ever trying.
do
  local net = Net.new()
  local succeeded, resultOrErr = pcall(withSocket, true, function()
    return net:connect("192.0.2.1", 7878)
  end)
  ok("reaches the real connect path and calls socket.tcp() (past the availability check)",
    not succeeded and tostring(resultOrErr):find("not exercised", 1, true) ~= nil,
    tostring(resultOrErr))
  ok("does not fall into the 'socket missing' branch",
    net.error == nil or not net.error:find("missing", 1, true), net.error)
end

-- 3. Client:connect propagates a missing-socket failure into a clean
--    offline state, the same shape src/client.lua's connect() guard
--    already checks -- verified against the REAL guard, not a
--    re-description of it, since this exact code path is what draws
--    client.status on screen (the "networking unavailable" text a player
--    on iOS actually sees).
do
  local src = assert(io.open("src/client.lua", "r")):read("*a")
  local guard = src:match('if not self%.net:connect%(host, port%) then%s*\n%s*self%.status = self%.net%.error or "connection failed"%s*\n%s*self%.state = "offline"%s*\n%s*return false')
  ok("Client:connect still checks connect()'s return value before touching net state",
    guard ~= nil, "the exact guard text in src/client.lua moved or was removed")
end

-- 4. Net.transportAvailable(): the pure, instant capability check the
--    Register/Log in pre-flight (src/screens.lua) runs before showing any
--    UI that would let a player tap into a doomed connect. No I/O, so no
--    mock socket needed -- only require("socket") itself is swapped.
do
  local succeeded, avail = pcall(withSocket, false, Net.transportAvailable)
  ok("reports unavailable, and never throws, when socket is missing", succeeded, tostring(avail))
  eq("and says so plainly", avail, false)

  local succeeded2, avail2 = pcall(withSocket, true, Net.transportAvailable)
  ok("reports available when socket IS present", succeeded2, tostring(avail2))
  eq("and says so plainly", avail2, true)
end

-- 5. Net.probe(): a throwaway reachability check, separate from :connect,
--    so a pre-flight probe never leaves a half-set-up Net instance behind.
do
  -- 5a. No transport at all: fails immediately with the same wording
  --     Net:connect uses, no socket.tcp() ever touched.
  local succeeded, reachable, err = pcall(withSocket, false, function()
    return Net.probe("example.com", 7878, 1)
  end)
  ok("probe() never throws when socket is missing", succeeded, tostring(reachable))
  eq("probe() reports unreachable", reachable, false)
  ok("with the transport-missing reason", err ~= nil and err:find("missing", 1, true) ~= nil, tostring(err))

  -- 5b. Transport present, connect succeeds: probe reports reachable AND
  --     closes what it opened (a probe that leaks a live socket would
  --     make every pre-flight check leave a connection behind).
  local realRequire = require
  local closed = false
  _G.require = function(name)
    if name == "socket" then
      return { tcp = function()
        return {
          settimeout = function() end,
          connect = function() return true end,
          close = function() closed = true end,
        }
      end }
    end
    return realRequire(name)
  end
  local ok2, reachable2 = pcall(function() return Net.probe("192.0.2.1", 7878, 1) end)
  _G.require = realRequire
  ok("probe() succeeds through a mock socket that connects", ok2 and reachable2 == true, tostring(reachable2))
  ok("and closes the probe socket instead of leaking it", closed)

  -- 5c. Transport present, connect fails (unreachable host): a real
  --     failure reason, not a false positive.
  _G.require = function(name)
    if name == "socket" then
      return { tcp = function()
        return {
          settimeout = function() end,
          connect = function() return nil, "timeout" end,
          close = function() end,
        }
      end }
    end
    return realRequire(name)
  end
  local ok3, reachable3, err3 = pcall(function() return Net.probe("192.0.2.1", 7878, 1) end)
  _G.require = realRequire
  ok("probe() reports unreachable through a mock socket that fails to connect",
    ok3 and reachable3 == false, tostring(reachable3))
  ok("with a real reason naming the host", err3 ~= nil and err3:find("192.0.2.1", 1, true) ~= nil, tostring(err3))
end

print(string.format("\nRESULT %d passed, %d failed", pass, fail))
if fail > 0 then error("net.lua iOS-transport tests failed") end
