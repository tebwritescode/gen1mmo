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
local installBootMenu = GEN1MMO_INCLUDE("src/bootmenu.lua")

local client = Client.new(mod)

-- Persisted server address (no infrastructure baked into the public mod; the
-- player points it at a server). Default is localhost for self-hosting/testing.
client.host = mod.save:get("server_host", "127.0.0.1")
client.port = mod.save:get("server_port", 7878)
client.pin = mod.save:get("server_pin", nil)
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
installBootMenu(mod, client)

-- Start-menu row that opens Gen1MMO.
mod.hooks:wrap("ui.start_menu.items", function(next, game, items)
  pcall(function()
    mod.ui.insertBefore(items, "OPTION", {
      label = "GEN1MMO",
      onSelect = function() mod.ui.push(game, "Gen1MMO") end,
    })
  end)
  return next(game, items)
end)

-- ONLINE on the TITLE menu (before any game exists): auth with the server
-- right there, then continue or start the SERVER-SIDE character. The vanilla
-- NEW GAME action is captured from the items so online play boots through
-- the engine's own fresh-game path -- local saves are never loaded.
mod.hooks:wrap("ui.title_menu.items", function(next, game, items)
  pcall(function()
    local newGameAction = nil
    for _, it in ipairs(items) do
      if tostring(it.label) == "NEW GAME" then newGameAction = it.onSelect end
    end
    mod.ui.insertBefore(items, "OPTION", {
      label = "ONLINE",
      onSelect = function()
        mod.ui.push(game, "Gen1MMOOnline", newGameAction)
      end,
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
