-- Client orchestrator: owns the connection, the auth flow, the chat log, and
-- the dispatch of every server message onto the world. The UI (screens.lua)
-- calls into this; the per-frame hook calls :pump(); world events call
-- :onStep()/:onMap(). Nothing here draws.

local Net = GEN1MMO_INCLUDE("src/net.lua")
local Crypto = GEN1MMO_INCLUDE("src/crypto.lua")
local Tunnel = GEN1MMO_INCLUDE("src/tunnel.lua")
local Filter = GEN1MMO_INCLUDE("src/filter.lua")
local Players = GEN1MMO_INCLUDE("src/players.lua")
local Skins = GEN1MMO_INCLUDE("src/skins.lua")

local Client = {}
Client.__index = Client

local CHAT_MAX = 40

function Client.new(mod)
  local self = setmetatable({
    mod = mod,
    net = nil,
    players = Players.new(mod),
    state = "offline", -- offline | connecting | greeted | authing | playing
    status = "Not connected",
    name = nil,
    intent = nil,          -- "register" | "login"
    creds = nil,           -- { name, password, clientSalt }
    powCo = nil,
    chat = {},             -- ring of display lines
    channel = 0,
    channels = 1,
    recoveryCode = nil,    -- shown once after register/recover
    skin = Skins.sanitize(mod.save:get("skin", Skins.DEFAULT)),
    mapId = nil,
    x = 0, y = 0, dir = "down",
    lastError = nil,
  }, Client)
  return self
end

-- ---------------------------------------------------------------- chat log

function Client:log(line)
  self.chat[#self.chat + 1] = line
  while #self.chat > CHAT_MAX do table.remove(self.chat, 1) end
end

-- ---------------------------------------------------------------- connect

local function isLoopback(host)
  return host == "localhost" or host == "::1" or host:sub(1, 4) == "127."
end

--- Base64-decode that never raises (LOVE errors on malformed input).
local function b64maybe(s)
  if type(s) ~= "string" then return nil end
  local ok, raw = pcall(Crypto.fromBase64, s)
  if ok and type(raw) == "string" then return raw end
  return nil
end

function Client:connect(host, port, intent, name, password)
  if self.net then self.net:close() end
  self.net = Net.new()
  self.intent = intent
  self.creds = { name = name, password = password }
  self.status = "Connecting to " .. host .. "..."
  self.state = "connecting"
  if not self.net:connect(host, port) then
    self.status = self.net.error or "connection failed"
    self.state = "offline"
    return false
  end
  -- Always OFFER the tunnel: a fresh ephemeral key rides in the hello. What
  -- we accept back is decided in the hello_ack handler (pinned > unpinned >
  -- plaintext-on-loopback-only).
  self._connHost = tostring(host)
  self._hs = Tunnel.start(Tunnel.gatherEntropy(self._connHost .. ":" .. tostring(port)))
  self.net:send({ type = "hello", v = 1, cpub = Crypto.toBase64(self._hs.cpub) })
  self.state = "greeted"
  self.status = "Handshaking..."
  return true
end

function Client:disconnect()
  if self.net then self.net:close() end
  self.players:clear()
  self._hs = nil
  self.state = "offline"
  self.status = "Disconnected"
  self.name = nil
end

-- ---------------------------------------------------------------- auth flow

function Client:_beginAuth()
  if self.intent == "register" then
    self.status = "Requesting registration..."
    self.net:send({ type = "pow_get" })
  else
    self.status = "Logging in..."
    self.net:send({ type = "salt_get", name = self.creds.name })
  end
  self.state = "authing"
end

function Client:_finishRegister(powId, powNonce)
  local clientSalt = Crypto.randomHex(16)
  local verifier = Crypto.verifier(self.creds.password, clientSalt)
  self.creds.password = nil -- discarded the moment the verifier exists
  self.net:send({
    type = "register", name = self.creds.name,
    clientSalt = clientSalt, verifier = verifier,
    powId = powId, powNonce = powNonce,
  })
  self.status = "Creating account..."
end

function Client:_finishLogin(saltHex)
  local verifier = Crypto.verifier(self.creds.password, saltHex)
  self.creds.password = nil
  self.net:send({ type = "login", name = self.creds.name, verifier = verifier })
  self.status = "Signing in..."
end

-- ---------------------------------------------------------------- actions

function Client:say(scope, text)
  if self.state ~= "playing" or #text == 0 then return end
  self.net:send({ type = "chat", scope = scope, text = text })
end

function Client:whisper(to, text)
  if self.state ~= "playing" then return end
  -- Beta: whispers relay as plaintext payload (E2EE lands with the tunnel).
  self.net:send({ type = "whisper", to = to, payload = text })
end

function Client:applySkin(skin)
  self.skin = Skins.sanitize(skin)
  self.mod.save:set("skin", self.skin)
  if self.state == "playing" then
    self.net:send({ type = "set_skin", skin = self.skin })
  end
end

function Client:addFriend(name)
  if self.state == "playing" then self.net:send({ type = "friend_request", to = name }) end
end

function Client:report(accused, category, messages)
  if self.state == "playing" then
    self.net:send({ type = "report", accused = accused, category = category, messages = messages })
  end
end

function Client:joinChannel(n)
  if self.state == "playing" then self.net:send({ type = "join_channel", channel = n }) end
end

-- ---------------------------------------------------------------- world events

function Client:onStep(mapId, x, y)
  if self.state ~= "playing" then return end
  if self.x ~= x or self.y ~= y then
    if x > self.x then self.dir = "right" elseif x < self.x then self.dir = "left"
    elseif y > self.y then self.dir = "down" elseif y < self.y then self.dir = "up" end
  end
  self.x, self.y = x, y
  if mapId ~= self.mapId then self:onMap(mapId) end
  -- Map ids ride as strings on the wire (server-side room keys are
  -- format-checked strings; engines may hand us numbers).
  self.net:send({ type = "move", x = x, y = y, dir = self.dir, map = tostring(mapId) })
end

function Client:onMap(mapId)
  self.mapId = mapId
  self.players:setMap(mapId)
  self.players:clear()
  if self.state == "playing" then
    -- Trigger a re-home + fresh roster for the new map.
    self.net:send({ type = "move", x = self.x, y = self.y, dir = self.dir, map = tostring(mapId) })
  end
end

-- ---------------------------------------------------------------- pump

-- Keepalive cadence: well under the server's 90s transport idle reaper, and
-- friendly to consumer NAT table lifetimes.
local PING_EVERY = 30

function Client:pump()
  if not self.net then return end
  self.net:update()
  -- A player standing still sends nothing; without this the transport reaper
  -- (or their router's NAT) would drop them. Pings deliberately do NOT count
  -- as presence server-side: truly AFK players still get the idle disconnect.
  -- Only while PLAYING: the auth exchange is its own traffic, and older
  -- servers refuse pings before the welcome.
  if self.net.connected and self.state == "playing" then
    local now = love.timer and love.timer.getTime() or os.clock()
    if self.net.lastTx and (now - self.net.lastTx) > PING_EVERY then
      self.net:send({ type = "ping" })
    end
  end
  if self.net.closed then
    if self.state ~= "offline" then
      self.status = self.net.error or "connection lost"
      self.state = "offline"
      self.players:clear()
    end
    return
  end
  -- advance a proof-of-work solve, sliced so the frame never stalls
  if self.powCo then
    local ok, nonce = coroutine.resume(self.powCo)
    if ok and nonce then
      self.powCo = nil
      self:_finishRegister(self._powId, nonce)
    elseif not ok then
      self.powCo = nil
      self.status = "proof-of-work failed"
    end
  end
  local batch = self.net:poll()
  if batch then
    for _, msg in ipairs(batch) do self:_dispatch(msg) end
  end
end

-- ---------------------------------------------------------------- dispatch

--- hello_ack policy, strictest applicable path wins:
---   pin configured        -> signature MUST verify against it (else refuse)
---   no pin, remote host   -> encrypted but UNVERIFIED (beta posture, said so)
---   no pin, loopback      -> unverified tunnel, or plaintext (dev servers)
---   plaintext, remote     -> REFUSED (the real server encrypts; this is a
---                            downgrade or a misconfiguration)
function Client:_onHelloAck(m)
  local loop = isLoopback(self._connHost or "")
  if m.spub then
    local pin = self.pin and b64maybe(self.pin) or nil
    local sess = self._hs and Tunnel.finish(self._hs, b64maybe(m.spub), b64maybe(m.sig), pin)
    self._hs = nil
    if not sess then
      self.status = "Server identity check FAILED"
      self:log("! server identity check failed (wrong pin or interception)")
      self:disconnect()
      return
    end
    self.net.tunnel = sess
    if pin then
      self:log("Encrypted; server identity verified.")
    else
      self:log(loop and "Encrypted (loopback, no pin)."
        or "Encrypted; server UNVERIFIED (no pin configured).")
    end
    self:_beginAuth()
  elseif loop then
    self:log("Plaintext loopback connection (dev server).")
    self:_beginAuth()
  else
    self.status = "Server refused encryption"
    self:log("! remote server would not encrypt; refusing to continue")
    self:disconnect()
  end
end

function Client:_dispatch(m)
  local t = m.type
  if t == "hello_ack" then
    -- Beta refuses to speak to an age-verification-demanding server: there is
    -- no such message in the protocol, and if one ever appears we bail.
    self:_onHelloAck(m)
  elseif t == "pow" then
    self._powId = m.id
    self.powCo = Crypto.powSolver(m.challenge, m.bits)
    self.status = "Proving you're human..."
  elseif t == "salt" then
    self:_finishLogin(m.salt)
  elseif t == "registered" or t == "recovered" then
    self.recoveryCode = m.recoveryCode
    -- Shown full-screen until acknowledged (screens.lua), and copied into
    -- the mod save so it stays re-readable from the menu (RECOVERY.md).
    self.keyAcknowledged = false
    if m.recoveryCode then
      pcall(function() self.mod.save:set("recovery_code", m.recoveryCode) end)
    end
    self:log("*** SAVE YOUR RECOVERY CODE ***")
    self:log(m.recoveryCode or "?")
  elseif t == "welcome" then
    self.state = "playing"
    self.name = m.name
    self.channel = m.channel or 0
    self.channels = m.channels or 1
    self.status = "Online as " .. tostring(m.name)
    if m.skin then self.skin = Skins.sanitize(m.skin) end
    -- push our chosen look to the world
    self.net:send({ type = "set_skin", skin = self.skin })
    self:log("Welcome, " .. tostring(m.name) .. "!")
  elseif t == "roster" then
    self.players:setMap(m.mapId or self.mapId)
    self.players:setRoster(m.players or {})
  elseif t == "player_join" then
    self.players:join(m)
    self:log(tostring(m.name) .. " appeared.")
  elseif t == "player_leave" then
    self.players:leave(m.name)
  elseif t == "player_move" then
    self.players:move(m.name, m.x, m.y, m.dir)
  elseif t == "player_skin" then
    self.players:setSkin(m.name, m.skin)
  elseif t == "chat" then
    local text = Filter.display(m.text or "")
    self:log(string.format("[%s] %s: %s", tostring(m.scope), tostring(m.from), text))
  elseif t == "whisper" then
    self:log(string.format("(whisper) %s: %s", tostring(m.from), Filter.display(m.payload or "")))
  elseif t == "friend_request" then
    self:log(tostring(m.from) .. " wants to be friends (open Friends to accept).")
    self._pendingFriend = m.from
  elseif t == "friend_added" then
    self:log("You and " .. tostring(m.name) .. " are now friends.")
  elseif t == "reported" then
    self:log("Report submitted. Thank you.")
  elseif t == "channel_joined" then
    self.channel = m.channel
    self:log("Joined channel " .. tostring(m.channel))
  elseif t == "pong" then
    -- keepalive answer; nothing to do
  elseif t == "resync" then
    if m.x then self.x = m.x end
    if m.y then self.y = m.y end
  elseif t == "error" then
    self.lastError = m.code
    self:log("! " .. tostring(m.code) .. (m.reason and (" (" .. m.reason .. ")") or ""))
  elseif t == "kick" then
    self.status = "Kicked: " .. tostring(m.reason)
    self:disconnect()
  end
end

return Client
