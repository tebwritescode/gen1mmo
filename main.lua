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
local AuthShare = GEN1MMO_INCLUDE("src/authshare.lua")
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

-- Every Gen1MMO setting lives in the vanilla Options > MODS > GEN1MMO >
-- OPTIONS.. screen -- exactly where every other mod's settings show up,
-- not a bespoke screen of our own. mod.options:get reads it live wherever
-- a setting is needed below, so there is nothing to cache or keep in sync;
-- ManagerState (the mod manager) is the only writer.
mod.options:define({
  { key = "chatSize", label = "CHAT SIZE", type = "choice", default = 0.75,
    choices = { { "50%", 0.5 }, { "65%", 0.65 }, { "75%", 0.75 },
                { "85%", 0.85 }, { "100%", 1.0 } } },
  { key = "chatText", label = "CHAT TEXT", type = "choice", default = 1.0,
    choices = { { "40%", 0.4 }, { "60%", 0.6 }, { "80%", 0.8 }, { "100%", 1.0 } } },
  { key = "chatBg", label = "CHAT BG", type = "choice", default = 0.85,
    choices = { { "0%", 0 }, { "25%", 0.25 }, { "50%", 0.5 },
                { "70%", 0.7 }, { "85%", 0.85 }, { "100%", 1.0 } } },
  { key = "chatLines", label = "CHAT LINES", type = "choice", default = 4,
    choices = { { "2", 2 }, { "3", 3 }, { "4", 4 }, { "6", 6 } } },
  { key = "chatAlwaysOn", label = "CHAT ALWAYS ON", type = "toggle", default = false },
  { key = "chatOverlay", label = "CHAT OVERLAY", type = "toggle", default = true },
  { key = "statusLight", label = "STATUS LIGHT", type = "toggle", default = true },
  { key = "emoteBar", label = "EMOTE BAR", type = "toggle", default = true },
  { key = "geekStats", label = "GEEK STATS", type = "toggle", default = false },
  { key = "autoConnect", label = "AUTO-CONNECT", type = "toggle", default = true },
})

-- The v0.3.3 input mystery is solved (the cursor moved; its ">" glyph
-- doesn't exist in the charmap and drew as a space), so the readout is
-- opt-in again.
client.inputDebug = mod.save:get("input_debug", false)

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
Nametags.install(mod, client)
GEN1MMO_INCLUDE("src/geekstats.lua").install(mod, client)
GEN1MMO_INCLUDE("src/achievements.lua").install(mod, client)
local emoteBar = GEN1MMO_INCLUDE("src/emotebar.lua").install(mod, client)

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
-- password). One attempt per session via this hook; ONGOING reconnection
-- after that is the general watchdog below. Disconnect / Forget login in
-- the menu opts back out.
local triedAutoConnect = false
mod.events:on("map.entered", function()
  if triedAutoConnect or not mod.options:get("autoConnect") then return end
  triedAutoConnect = true
  if client.state == "offline" then
    client:connectStored(client.host, client.port)
  end
end)

-- General reconnect watchdog: covers EVERY reason the connection ends up
-- down, not just resuming from sleep -- a dropped WiFi/mobile network while
-- the app stays in the foreground the whole time, a server-side kick, a
-- network blip that silently stalls one side without ever producing a
-- socket error. Checked every frame from the pump hook below; a state check
-- plus a growing backoff (so a genuinely down server is not hammered
-- forever) covers all of those with ONE mechanism instead of reacting to
-- specific transitions like focus/visible alone would.
local reconnectBackoff = 5 -- seconds; doubles after each attempt that doesn't reach "playing"
local RECONNECT_MAX_BACKOFF = 60
local lastReconnectAttempt = 0
-- Same zombie-socket problem as a resume: a connection can LOOK alive
-- (state stays "playing"/"authing"/"greeted") while actually being dead --
-- OS-suspended networking, or a drop that never produced a proper TCP error
-- on this side. net.lastRx (net.lua) is the real liveness signal; 90s of
-- total silence (3x the 30s ping interval) means something is wrong.
local STALE_AFTER = 90
local function pollReconnect()
  if not triedAutoConnect then return end -- let the boot attempt above go first
  if client.state == "playing" then
    reconnectBackoff = 5 -- fully online: reset the backoff for next time
    return
  end
  if not mod.options:get("autoConnect") or not client:storedLoginName() then return end
  local now = love.timer.getTime()

  if client.state == "offline" then
    if now - lastReconnectAttempt < reconnectBackoff then return end
    lastReconnectAttempt = now
    reconnectBackoff = math.min(reconnectBackoff * 2, RECONNECT_MAX_BACKOFF)
    client:connectStored(client.host, client.port)
  elseif client.state ~= "connecting" then
    -- greeted/authing: looks mid-handshake, but that is indistinguishable
    -- from wedged until lastRx has a first real value to judge against
    local net = client.net
    if net and net.lastRx and (now - net.lastRx) > STALE_AFTER
       and now - lastReconnectAttempt >= reconnectBackoff then
      lastReconnectAttempt = now
      reconnectBackoff = math.min(reconnectBackoff * 2, RECONNECT_MAX_BACKOFF)
      client:disconnect()
      client:connectStored(client.host, client.port)
    end
  end
end

-- Touch: taps AND drags that miss the on-screen controls are routed here.
-- When the GEN1MMO screen is open, map them into 160x144 canvas space and
-- let it select items / letters / scroll directly -- so phone players are
-- never stranded by a controller whose d-pad doesn't drive menus. Over the
-- live overworld instead, the same tap is offered to the quick emote bar
-- (src/emotebar.lua) before falling through to the engine's own touch
-- controls. Additive either way: buttons still work.
--
-- viewportOr (not a bare client._vp read): render.hud stashes client._vp
-- itself, and on some devices/pipelines a tap can land before that has ever
-- fired (or between frames where it goes stale), which left every touch
-- path here silently inert while the SAME screens still drew fine -- their
-- render.hud hook already falls back through viewportOr, so drawing never
-- exposed the gap. Chat drag-to-scroll and the quick action bar both go
-- through this one hook, so both go dead together and come back together.
mod.hooks:wrap("input.pointer", function(next, game, ev)
  local consumed = false
  pcall(function()
    if not ev then return end
    local top = game.stack and game.stack:top()
    local vp = Overlay.viewportOr(client._vp)
    local vpOk = vp and vp.gameWidth and vp.gameWidth > 0
      and vp.gameHeight and vp.gameHeight > 0
    if top and top.screenId == "Gen1MMO" and vpOk then
      local scaleY = vp.gameHeight / 144
      if ev.phase == "pressed" and top.onTap then
        local cx = (ev.x - (vp.gameX or 0)) / (vp.gameWidth / 160)
        local cy = (ev.y - (vp.gameY or 0)) / scaleY
        top:onTap(cx, cy)
      elseif ev.phase == "moved" and top.onDrag then
        top:onDrag((ev.dy or 0) / scaleY)
      elseif ev.phase == "released" and top.onRelease then
        local cx = (ev.x - (vp.gameX or 0)) / (vp.gameWidth / 160)
        local cy = (ev.y - (vp.gameY or 0)) / scaleY
        top:onRelease(cx, cy)
      end
      return
    end
    if ev.phase == "pressed" and vpOk then
      local cx = (ev.x - (vp.gameX or 0)) / (vp.gameWidth / 160)
      local cy = (ev.y - (vp.gameY or 0)) / (vp.gameHeight / 144)
      consumed = emoteBar.tap(game, cx, cy)
    end
  end)
  if consumed then return end
  return next(game, ev)
end)

-- Start-menu rows for the two things worth a direct tap: sending a message
-- and sending an emote. Everything else Gen1MMO does (login, friends,
-- whisper, look, server info, disconnect) lives under OPTION now (see the
-- ui.options.rows hook below) -- the same place any other mod's own screen
-- is one tap from, not a special branch of the Start Menu.
mod.hooks:wrap("ui.start_menu.items", function(next, game, items)
  pcall(function()
    -- Grouped with LINK, not the generic OPTION/MODS/QUIT tail: this IS a
    -- way to reach other players, same as vanilla LINK, so it reads
    -- naturally right below it rather than off among unrelated settings.
    -- LINK itself is conditional (vanilla: only shows with a non-empty
    -- party -- src/ui/StartMenu.lua), and Gen1MMO must NOT inherit that
    -- gate (you should be able to log in and chat before catching
    -- anything), so: anchor after LINK when it's present, or fall back to
    -- the previous OPTION-anchored spot when it's not (a missing anchor in
    -- insertAfter would otherwise silently append past QUIT, which reads
    -- like a broken/forgotten row on a fresh, party-less save).
    local hasLink = false
    for _, it in ipairs(items) do
      if it.label == "LINK" then hasLink = true; break end
    end
    local chatRow = { label = "CHAT", onSelect = function()
      client._openChatDirect = true
      mod.ui.push(game, "Gen1MMO")
    end }
    local emoteRow = { label = "EMOTE", onSelect = function()
      client._openEmoteDirect = true
      mod.ui.push(game, "Gen1MMO")
    end }
    if hasLink then
      mod.ui.insertAfter(items, "LINK", chatRow)
      mod.ui.insertAfter(items, "CHAT", emoteRow)
    else
      mod.ui.insertBefore(items, "OPTION", chatRow)
      mod.ui.insertBefore(items, "OPTION", emoteRow)
    end
  end)
  return next(game, items)
end)

-- The rest of Gen1MMO (login, friends, whisper, look, server info,
-- disconnect) is one row in the vanilla Options screen -- the standard spot
-- a mod's own screen is reached from (alongside MODS, CONTROLS), not a
-- special Start Menu branch. The per-mod settings above show up separately,
-- under Options > MODS > GEN1MMO > OPTIONS.., same as any other mod.
mod.hooks:wrap("ui.options.rows", function(next, game, rows)
  pcall(function()
    rows[#rows + 1] = {
      id = "gen1mmo_open", label = "GEN1MMO",
      value = function() return "OPEN" end,
      activate = function(g) mod.ui.push(g, "Gen1MMO") end,
    }
  end)
  return next(game, rows)
end)

-- Per-frame pump: render.zones runs every overworld frame. We do the network
-- pump here, then the reconnect watchdog (needs pump to have already
-- processed this frame's net.closed/state transitions), and pass the zones
-- through untouched.
mod.hooks:wrap("render.zones", function(next, game, zones)
  client:pump()
  pollReconnect()
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

-- SHARED LOGIN. If Gen1MMO has no stored login but SaveSync (or a future
-- mod on this server) is signed in, adopt its credential so logging into one
-- mod logs into both. Runs at game.ready, once both mods have loaded.
mod.events:on("game.ready", function()
  if not client:storedLoginName() then
    local cred = AuthShare.adopt(mod, "gen1mmo")
    if cred then
      pcall(function()
        mod.save:set("auth_name", cred.name)
        mod.save:set("auth_verifier", cred.verifier)
      end)
    end
  end
end)

-- Publish the client for other mods / tooling. The loader reads mod.exports;
-- a chunk's return value is NOT what dependents see (verified in-engine).
mod.exports = client
-- ...and publish this account for shared login. get() reads mod.save live, so
-- a sign-in AFTER load is visible to a sibling that checks later.
AuthShare.publish(mod, function()
  local name = mod.save:get("auth_name", nil)
  local verifier = mod.save:get("auth_verifier", nil)
  if name and verifier then return { name = name, verifier = verifier } end
  return nil
end)
return client
