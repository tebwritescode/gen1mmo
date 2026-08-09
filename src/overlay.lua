-- Chat + notification overlay, drawn in the GAME'S OWN menu style: the GB
-- tile font on a white panel over the playfield corner, fading out after a
-- few seconds. Everything that lands in the chat log rides it -- player
-- chat AND system notices (connected, disconnected, joins, leaves, channel
-- moves), which client.lua routes through client:log.
--
-- Screen-space hook (render.hud), but the panel is drawn INSIDE the
-- playfield transform (translate gameX/gameY, scale) so it is pixel-true
-- to the 160x144 canvas like every engine menu.

local Overlay = {}

local SHOW_SECONDS = 6
local FADE_SECONDS = 1.5
local MAX_CHARS = 19 -- 160px wide panel, 4px margins, 8px glyphs
local ROW = 12

function Overlay.install(mod, client)
  local Font = mod.ui.Font
  local recent = {} -- { text, at }

  -- Every chat-log line also lands here with an arrival stamp.
  local origLog = client.log
  client.log = function(self, line)
    recent[#recent + 1] = { text = tostring(line), at = love.timer.getTime() }
    local keep = (client.ovl and client.ovl.lines) or 4
    while #recent > math.max(keep, 6) do table.remove(recent, 1) end
    return origLog(self, line)
  end

  mod.hooks:wrap("render.hud", function(next, game, vp)
    next(game, vp)
    -- Stash the live viewport (LOVE-unit playfield rect + scale) so the
    -- pointer hook can map a screen tap into 160x144 canvas space.
    if type(vp) == "table" then client._vp = vp end
    if not client.overlayOn or client.state ~= "playing" then return end
    local ok, err = pcall(function()
      local Game = require("src.core.Game")
      local ow = Game.overworld
      -- only over a live overworld; menus and battles own their screen
      if not ow or game.stack:top() ~= ow then return end
      -- user-tunable panel (Chat box settings in the GEN1MMO menu):
      -- size = fraction of the playfield scale, bg/text = opacities
      local cfg = client.ovl or {}
      local sizePct = cfg.size or 0.75
      local bgA = cfg.bg == nil and 0.85 or cfg.bg
      local textA = cfg.text or 1.0
      local maxLines = cfg.lines or 4

      local now = love.timer.getTime()
      local visible = {}
      for _, e in ipairs(recent) do
        if now - e.at < SHOW_SECONDS then visible[#visible + 1] = e end
      end
      while #visible > maxLines do table.remove(visible, 1) end
      if #visible == 0 then return end

      local lg = love.graphics
      lg.push("all")
      lg.translate(vp.gameX or 0, vp.gameY or 0)
      lg.scale((vp.scale or 1) * sizePct)

      local panelH = #visible * ROW + 6
      local alphaMax = 0
      for _, e in ipairs(visible) do
        local a = math.min(1, (SHOW_SECONDS - (now - e.at)) / FADE_SECONDS)
        if a > alphaMax then alphaMax = a end
      end
      lg.setColor(1, 1, 1, bgA * alphaMax)
      lg.rectangle("fill", 0, 0, 160, panelH)
      lg.setColor(0, 0, 0, bgA * alphaMax)
      lg.rectangle("fill", 0, panelH, 160, 1) -- the panel's lower rule

      for i, e in ipairs(visible) do
        local a = math.min(1, (SHOW_SECONDS - (now - e.at)) / FADE_SECONDS)
        -- glyph tiles are black ink; setColor's alpha is the only channel
        -- that shows, which is exactly the fade we want
        lg.setColor(0, 0, 0, textA * a)
        local line = e.text
        if #line > MAX_CHARS then line = line:sub(1, MAX_CHARS) end
        -- censor "*" has no tile; the mid-dot does
        Font.draw((line:gsub("%*", "\194\183")), 4, 4 + (i - 1) * ROW)
      end
      lg.pop()
    end)
    if not ok then
      -- never let the HUD take a frame down -- but say WHY it went dark,
      -- so a device report can quote the reason instead of "it vanished"
      client.overlayOn = false
      pcall(function() client:log("Overlay off: " .. tostring(err)) end)
    end
  end)
end

return Overlay
