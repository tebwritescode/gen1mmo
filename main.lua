-- Gen1MMO entry point.
--
-- Wires the client orchestrator into the engine: a per-frame network pump, our
-- movement broadcast, remote-player pass-through, and the Start-menu screen.
-- All confirmed mod-API surfaces (Reference-Mod-Object / Reference-Hooks).

local mod = ...

-- Module loader: mods are single-entry, so we load our own files via mod:read
-- + load(), caching each as a singleton. Exposed as a global so submodules can
-- pull their own dependencies the same way.
local _cache = {}
function GEN1MMO_INCLUDE(path)
  if _cache[path] then return _cache[path] end
  local src, err = mod:read(path)
  if not src then error("gen1mmo: cannot read " .. path .. ": " .. tostring(err)) end
  local chunk = assert(load(src, "@gen1mmo/" .. path))
  local result = chunk()
  _cache[path] = result
  return result
end

local Client = GEN1MMO_INCLUDE("src/client.lua")
local installScreen = GEN1MMO_INCLUDE("src/screens.lua")
local Overlay = GEN1MMO_INCLUDE("src/overlay.lua")

local client = Client.new(mod)
client.overlayOn = mod.save:get("chat_overlay", true)
client.autoConnect = mod.save:get("auto_connect", true)
-- Beta: on by default so the input readout is visible without navigating a
-- menu that may be the very thing that isn't responding.
client.inputDebug = mod.save:get("input_debug", true)

-- Default server: the official beta VPS, with its identity pin baked in so
-- the encrypted tunnel verifies out of the box (the pin is the server's
-- PUBLIC key -- safe to ship; it is what makes MITM fail closed). The VPS is
-- a bare, isolated host with no link to the operator's identity, so this
-- carries no infrastructure secret. Players can still point elsewhere via
-- "Set server" (persisted) or a private config.lua. Self-hosters override the
-- pin with their own from first-boot logs.
local DEFAULT_HOST = "89.125.35.98"
local DEFAULT_PORT = 7878
local DEFAULT_PIN  = "iekSvOIqGT14GiJ6EOoTnw8+SKv93Zw0aCdMOeF4T+A="
client.host = mod.save:get("server_host", DEFAULT_HOST)
client.port = mod.save:get("server_port", DEFAULT_PORT)
client.pin = mod.save:get("server_pin", DEFAULT_PIN)
function client:setServer(host, port)
  self.host = host
  self.port = tonumber(port) or 7878
  mod.save:set("server_host", self.host)
  mod.save:set("server_port", self.port)
end

-- Optional drop-in config (config.lua beside main.lua, NEVER committed): a
-- server operator hands players/testers a tiny file with their address and
-- identity pin. Shape: return { host = "...", port = 7878, pin = "base64" }.
-- It overrides the saved values above; absence is completely fine.
do
  local ok, cfg = pcall(GEN1MMO_INCLUDE, "config.lua")
  if ok and type(cfg) == "table" then
    if cfg.host then client.host = tostring(cfg.host) end
    if cfg.port then client.port = tonumber(cfg.port) or client.port end
    if cfg.pin then client.pin = tostring(cfg.pin) end
  end
end

installScreen(mod, client)
Overlay.install(mod, client)

-- Auto-connect: once someone has logged in before, later sessions go online
-- on their own as soon as the world is up (stored verifier, never the
-- password). One attempt per session; Disconnect / Forget login in the menu.
local triedAutoConnect = false
mod.events:on("map.entered", function()
  if triedAutoConnect or not client.autoConnect then return end
  triedAutoConnect = true
  if client.state == "offline" then
    client:connectStored(client.host, client.port)
  end
end)

-- Touch: a tap that misses the on-screen controls is routed here. When the
-- GEN1MMO screen is open, map the tap into 160x144 canvas space and let it
-- select items / letters directly -- so phone players are never stranded by
-- a controller whose d-pad doesn't drive menus. Additive: buttons still work.
mod.hooks:wrap("input.pointer", function(next, game, ev)
  pcall(function()
    if ev and ev.phase == "pressed" then
      local top = game.stack and game.stack:top()
      local vp = client._vp
      if top and top.screenId == "Gen1MMO" and top.onTap
         and vp and vp.gameWidth and vp.gameWidth > 0 and vp.gameHeight and vp.gameHeight > 0 then
        local cx = (ev.x - (vp.gameX or 0)) / (vp.gameWidth / 160)
        local cy = (ev.y - (vp.gameY or 0)) / (vp.gameHeight / 144)
        top:onTap(cx, cy)
      end
    end
  end)
  return next(game, ev)
end)

-- Start-menu row that opens Gen1MMO: this release ships the classic overlay
-- (play normally, connect from this menu, see other trainers in your world).
-- The dedicated ONLINE title-menu mode with server-side characters lives on
-- the `online-mode` branch for a later release.
mod.hooks:wrap("ui.start_menu.items", function(next, game, items)
  pcall(function()
    mod.ui.insertBefore(items, "OPTION", {
      label = "GEN1MMO",
      onSelect = function() mod.ui.push(game, "Gen1MMO") end,
    })
  end)
  return next(game, items)
end)

-- Per-frame pump: render.zones runs every overworld frame. We do the network
-- pump here and pass the zones through untouched.
mod.hooks:wrap("render.zones", function(next, game, zones)
  client:pump()
  return next(game, zones)
end)

-- Broadcast our own steps.
mod.events:on("world.stepped", function(e)
  client:onStep(e.mapId, e.x, e.y)
end)

-- Track map changes (resyncs the roster for the new room).
mod.events:on("map.entered", function(e)
  client:onMap(e.mapId)
end)

-- Never block on another player: a remote trainer stands only on a walkable
-- tile (they walked there), so allowing movement into an occupied tile is safe.
mod.hooks:wrap("movement.collision", function(next, allowed, ctx)
  allowed = next(allowed, ctx)
  if ctx and ctx.toX and ctx.toY then
    for _, r in pairs(client.players.remote) do
      if r.x == ctx.toX and r.y == ctx.toY then return true end
    end
  end
  return allowed
end)

-- Publish the client for other mods / tooling. The loader reads mod.exports;
-- a chunk's return value is NOT what dependents see (verified in-engine).
mod.exports = client
return client
