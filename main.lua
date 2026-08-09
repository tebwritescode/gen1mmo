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
local Nametags = GEN1MMO_INCLUDE("src/nametags.lua")

-- Skin-tone sprite sheets: transforms.lua derives them from the player's
-- own cache at install (save/mod-derived/gen1mmo/sprites/g1mmo_b<B>_t<T>.png,
-- served through assets/generated/...). Registries FREEZE after load, so
-- every id must exist now; a missing derived file (no ROM import yet) just
-- means spawn falls back to the vanilla RED/BLUE sheets.
for body = 0, 1 do
  for tone = 0, 7 do
    mod.content.sprites:register(("G1MMO_B%d_T%d"):format(body, tone), {
      image = ("assets/generated/sprites/g1mmo_b%d_t%d.png"):format(body, tone),
      frames = 6,
      walker = true,
      -- exact RGB in every color mode; also exempts the sprite from the
      -- SGB zone shader, which is what makes per-player tones possible
      trueColor = true,
    })
  end
end

local client = Client.new(mod)
-- own build string, read from the manifest so it can never drift
client.version = ((mod:read("manifest.json") or ""):match('"version"%s*:%s*"([^"]+)"')) or "?"
client.overlayOn = mod.save:get("chat_overlay", true)
client.autoConnect = mod.save:get("auto_connect", true)
-- The v0.3.3 input mystery is solved (the cursor moved; its ">" glyph
-- doesn't exist in the charmap and drew as a space), so the readout is
-- opt-in again.
client.inputDebug = mod.save:get("input_debug", false)
-- chat-box panel tuning (the "Chat box" settings view persists these)
client.ovl = {
  size = mod.save:get("ovl_size", 0.75),
  bg = mod.save:get("ovl_bg", 0.85),
  text = mod.save:get("ovl_text", 1.0),
  lines = mod.save:get("ovl_lines", 4),
}

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

client.geekStats = mod.save:get("geek_stats", false)

installScreen(mod, client)
Overlay.install(mod, client)
Nametags.install(mod, client)
GEN1MMO_INCLUDE("src/geekstats.lua").install(mod, client)

-- Tone sheets, twice-guaranteed: the install transform derives them, and
-- Tonegen regenerates any sheet that STILL cannot load, at runtime, from
-- the resolvable base sprite -- so a quirky device cache degrades to a
-- one-time regeneration instead of silently stock-red players. The
-- result always lands in the chat log ("Skin sheets: 16/16 ...").
local Tonegen = GEN1MMO_INCLUDE("src/tonegen.lua")
local function ensureTones(label)
  pcall(function()
    local ok, total, note = Tonegen.ensure()
    client.diagSheets = ok
    client:log(("Skin sheets: %d/%d (%s)"):format(ok, total, note))
    if ok > 0 then
      client:applyOwnSprite()
      client.players:respawnAll() -- remotes that fell back pick up looks
    end
  end)
end
mod.events:on("assets.transformed", function(ev)
  if ev.modId ~= mod.id then return end
  ensureTones("post-transform")
end)
local tonesChecked = false
mod.events:on("map.entered", function()
  if tonesChecked then return end
  tonesChecked = true
  ensureTones("first-map")
end)

-- A-press on a remote player: the engine resolves the interaction to our
-- spawned NPC (def.name "g1mmo:<name>"); open the player action menu.
mod.events:on("world.interacted", function(ev)
  pcall(function()
    if not (ev and ev.kind == "npc" and ev.target) then return end
    local def = ev.target.def
    local who = def and def.name and def.name:match("^g1mmo:(.+)$")
    if not who then return end
    -- the screen reads this flag in new() -- Screens.push has no
    -- documented return value, so don't rely on one
    client._openPlayerMenu = who
    client:requestCard(who) -- badges/money/team arrive while it opens
    mod.ui.push(require("src.core.Game"), "Gen1MMO")
  end)
end)

-- Native keyboard for text entry: while the Gen1MMO text view is open,
-- typed characters land in the buffer (Android/iOS soft keyboard included;
-- screens.lua summons it via love.keyboard.setTextInput). Wrapped, never
-- replaced: the engine's own handlers still run.
do
  local ALLOWED = "^[%w_%.%-%!]$"
  local prevTextinput = love.textinput
  love.textinput = function(text, ...)
    pcall(function()
      local scr = client._screen
      if scr and scr.view == "text" and scr.acceptTyped then
        local ch = tostring(text):upper()
        if ch:match(ALLOWED) and #scr.buffer < 24 then
          scr.buffer = scr.buffer .. ch
          scr.typedThisFrame = true -- suppress the same key's GB-button echo
        end
      end
    end)
    if prevTextinput then return prevTextinput(text, ...) end
  end
  local prevKeypressed = love.keypressed
  love.keypressed = function(key, ...)
    local typing = false
    pcall(function()
      local scr = client._screen
      if scr and scr.view == "text" and scr.acceptTyped then
        typing = true
        if key == "backspace" then
          scr.buffer = scr.buffer:sub(1, -2)
          scr.typedThisFrame = true
        elseif key == "return" or key == "kpenter" then
          scr.submitTyped = true
        end
      end
    end)
    -- While typing, the engine must NOT see raw keys: bare digits are its
    -- hotkeys ("1" speed, "2" CYCLES SCREEN COLORS, "3" tilt, -/= zoom),
    -- so typing "2" recolored the whole game. Controllers are unaffected
    -- (they arrive via gamepadpressed).
    if typing then return end
    if prevKeypressed then return prevKeypressed(key, ...) end
  end
end

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
