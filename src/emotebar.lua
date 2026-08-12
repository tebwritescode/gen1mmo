-- Quick emote bar: a small collapsible button over the live overworld, so
-- sending an emote never needs a menu. Tap the toggle to reveal the three
-- faces, tap a face to send it (closes itself), tap the toggle again (or
-- anywhere else) to close without sending. Screen-space HUD, drawn inside
-- the same playfield transform overlay.lua's connection dot uses, so it
-- stays pixel-true to the 160x144 canvas at any window scale.

local EmoteBar = {}

local BTN = 14  -- canvas px, square
local GAP = 2
local KINDS = { 0, 1, 2 } -- heart, wave, fist -- matches EMOTE_FILES everywhere else
local FILES = { [0] = "heart", [1] = "wave", [2] = "fist" }

--- Button rects for the current state (collapsed = just the toggle,
--- expanded = toggle + one row per emote below it). Pure function of
--- `open` and the fixed layout constants, so draw and hit-test can never
--- disagree about where anything is.
local function rects(open)
  local toggle = { x = 160 - BTN - 2, y = 10, w = BTN, h = BTN }
  local list = { toggle = toggle }
  if open then
    for i, kind in ipairs(KINDS) do
      list[i] = { x = toggle.x, y = toggle.y + i * (BTN + GAP), w = BTN, h = BTN, kind = kind }
    end
  end
  return list
end
EmoteBar.rects = rects -- exposed for tests; pure, no engine deps

local function hit(r, cx, cy)
  return r and cx >= r.x and cx <= r.x + r.w and cy >= r.y and cy <= r.y + r.h
end
EmoteBar.hit = hit

function EmoteBar.install(mod, client)
  local Overlay = GEN1MMO_INCLUDE("src/overlay.lua")
  local images = {}
  local function img(kind)
    local key = FILES[kind] or "heart"
    if images[key] == nil then
      local ok, image = pcall(function()
        local bytes = assert(mod:read("assets/emotes/" .. key .. ".png"))
        local fd = love.filesystem.newFileData(bytes, key .. ".png")
        return love.graphics.newImage(love.image.newImageData(fd))
      end)
      images[key] = ok and image or false
    end
    return images[key] or nil
  end

  -- Only over the live overworld while playing, same guard overlay.lua's
  -- panel and nametags use -- menus/battles own their own screen.
  local function activeOver(game)
    if not mod.options:get("emoteBar") then return false end
    if client.state ~= "playing" then return false end
    local ok, active = pcall(function()
      local Game = require("src.core.Game")
      local ow = Game.overworld
      return ow ~= nil and game.stack:top() == ow
    end)
    return ok and active
  end

  --- Called from main.lua's input.pointer hook for any press that missed
  --- the Gen1MMO screen. Returns true when the tap was ours (so the caller
  --- must NOT also pass it to the engine's own touch controls).
  local function tap(game, cx, cy)
    if not activeOver(game) then return false end
    local rows = rects(client._emoteBarOpen)
    if hit(rows.toggle, cx, cy) then
      client._emoteBarOpen = not client._emoteBarOpen
      return true
    end
    if client._emoteBarOpen then
      for i = 1, #KINDS do
        if hit(rows[i], cx, cy) then
          client:emote(rows[i].kind)
          client._emoteBarOpen = false
          return true
        end
      end
      -- tapped elsewhere while open: close, but let the tap still reach
      -- the world underneath (it may have been a step or an interaction)
      client._emoteBarOpen = false
    end
    return false
  end

  mod.hooks:wrap("render.hud", function(next, game, vp)
    next(game, vp)
    if not activeOver(game) then return end
    vp = Overlay.viewportOr(vp)
    pcall(function()
      local lg = love.graphics
      lg.push("all")
      lg.translate(vp.gameX or 0, vp.gameY or 0)
      lg.scale(vp.scale or 1)
      local function panel(r)
        lg.setColor(0, 0, 0, 0.55)
        lg.rectangle("fill", r.x, r.y, r.w, r.h)
        lg.setColor(1, 1, 1, 0.9)
        lg.rectangle("line", r.x, r.y, r.w, r.h)
      end
      local function icon(r, kind)
        local image = img(kind)
        if not image then return end
        lg.setColor(1, 1, 1, 1)
        lg.draw(image, r.x + 2, r.y + 2, 0,
          (r.w - 4) / image:getWidth(), (r.h - 4) / image:getHeight())
      end
      local rows = rects(client._emoteBarOpen)
      panel(rows.toggle)
      icon(rows.toggle, 0) -- heart doubles as the generic "react" glyph
      if client._emoteBarOpen then
        for i = 1, #KINDS do
          panel(rows[i])
          icon(rows[i], rows[i].kind)
        end
      end
      lg.pop()
    end)
  end)

  return { tap = tap }
end

return EmoteBar
