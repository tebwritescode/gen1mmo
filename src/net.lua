-- TCP transport for Gen1MMO: newline-delimited JSON over luasocket, the same
-- idiom the engine's own link relay uses (src/link/Net.lua). Non-blocking after
-- connect, pumped once per frame.
--
-- Connect is triggered by an explicit user action (pressing Connect), so a
-- short blocking connect is fine -- exactly the engine's own reasoning for the
-- relay. Everything after is settimeout(0) and polled.

local Json = GEN1MMO_INCLUDE("src/json.lua")

local Net = {}
Net.__index = Net

local MAX_LINE = 8192 -- mirror the server's reader ceiling; drop a bloated peer

function Net.new()
  return setmetatable({
    sock = nil,
    rxBuf = "",
    txBuf = "",
    inbox = {},
    connected = false,
    closed = false,
    error = nil,
  }, Net)
end

--- Blocking connect with a short timeout, then switch to non-blocking.
function Net:connect(host, port)
  local ok, socket = pcall(require, "socket")
  if not ok or not socket then
    self.error = "networking unavailable (luasocket missing)"
    return false
  end
  local sock = socket.tcp()
  sock:settimeout(4)
  local success, err = sock:connect(host, tonumber(port))
  if not success then
    self.error = "cannot reach server " .. tostring(host) .. ":" .. tostring(port)
    pcall(function() sock:close() end)
    return false
  end
  sock:settimeout(0)
  sock:setoption("tcp-nodelay", true)
  self.sock = sock
  self.connected = true
  return true
end

--- Queue a table to send (encoded + newline).
function Net:send(msg)
  if not self.connected then return end
  self.txBuf = self.txBuf .. Json.encode(msg) .. "\n"
end

--- Pump: flush outbound, drain inbound, split lines, decode. Call every frame.
function Net:update()
  if not self.sock or self.closed then return end

  -- flush tx
  if #self.txBuf > 0 then
    local sent, err = self.sock:send(self.txBuf)
    if sent then
      self.txBuf = self.txBuf:sub(sent + 1)
    elseif err == "closed" then
      self:_die("connection closed")
      return
    elseif err == "timeout" and type(sent) == "nil" then
      -- partial send is reported via the 3rd return in some builds; keep buf
    end
  end

  -- drain rx (a few reads per frame)
  for _ = 1, 8 do
    local chunk, err, partial = self.sock:receive(2048)
    local data = chunk or partial
    if data and #data > 0 then
      self.rxBuf = self.rxBuf .. data
      if #self.rxBuf > MAX_LINE and not self.rxBuf:find("\n") then
        self:_die("server sent an oversized frame")
        return
      end
    end
    if err == "closed" then
      self:_die("connection closed")
      return
    end
    if not chunk then break end -- timeout / nothing more this frame
  end

  -- split complete lines
  while true do
    local nl = self.rxBuf:find("\n", 1, true)
    if not nl then break end
    local line = self.rxBuf:sub(1, nl - 1)
    self.rxBuf = self.rxBuf:sub(nl + 1)
    if #line > 0 then
      local msg = Json.decode(line)
      if type(msg) == "table" and msg.type then
        self.inbox[#self.inbox + 1] = msg
      end
    end
  end
end

--- Return and clear the queued decoded messages.
function Net:poll()
  if #self.inbox == 0 then return nil end
  local batch = self.inbox
  self.inbox = {}
  return batch
end

function Net:_die(reason)
  self.error = reason
  self.closed = true
  self.connected = false
  pcall(function() self.sock:close() end)
end

function Net:close()
  if self.sock then pcall(function() self.sock:close() end) end
  self.closed = true
  self.connected = false
end

return Net
