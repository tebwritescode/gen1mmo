-- The transport, tested on the platform that actually broke.
--
--   luajit tests/net_ios.test.lua
--
-- WHY THIS FILE EXISTS. iOS (Phosphorus) has no LuaSocket -- confirmed by
-- cross-referencing SaveSync's own iOS transport work (a sibling gen1recomp
-- mod): its src/http.lua says outright "Phosphor's iOS build has no
-- love.thread [and] there is no curl to spawn and no bridge exported", and
-- it had to add lua-https as an alternate transport because raw LuaSocket
-- sockets were never on that platform to begin with.
--
-- gen1mmo's protocol is a PERSISTENT bidirectional TCP stream (newline-JSON
-- frames, non-blocking, polled every frame, with its own encrypted tunnel
-- handshake), not periodic REST calls -- so lua-https (a one-shot
-- synchronous HTTPS request/response client) cannot be swapped in the way
-- SaveSync swapped it for GitHub/Dropbox calls. This test locks in that the
-- ABSENCE of LuaSocket degrades SAFELY (no crash, a real status message, no
-- half-connected state) rather than proving the game can connect on iOS --
-- it cannot, right now, and fixing that is a transport-design question
-- (long-polling or WebSocket-over-lua-https, or similar), not a bug in
-- this failure path.

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

print(string.format("\nRESULT %d passed, %d failed", pass, fail))
if fail > 0 then error("net.lua iOS-transport tests failed") end
