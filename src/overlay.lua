-- Chat overlay: the last few lines floating over the vanilla overworld,
-- fading out after a few seconds. Screen-space (render.hud runs after the
-- frame composes), anchored to the playfield corner. The full log stays in
-- the GEN1MMO menu; this is just ambient chat while you play.

local Overlay = {}

local SHOW_SECONDS = 6
local FADE_SECONDS = 1.5
local MAX_LINES = 4
local MAX_CHARS = 44

function Overlay.install(mod, client)
  local font = nil
  local recent = {} -- { text, at }

  -- Every chat-log line also lands here with an arrival stamp.
  local origLog = client.log
  client.log = function(self, line)
    recent[#recent + 1] = { text = tostring(line), at = love.timer.getTime() }
    while #recent > MAX_LINES do table.remove(recent, 1) end
    return origLog(self, line)
  end

  mod.hooks:wrap("render.hud", function(next, game, vp)
    next(game, vp)
    if not client.overlayOn or client.state ~= "playing" then return end
    local ok = pcall(function()
      local now = love.timer.getTime()
      local visible = {}
      for _, e in ipairs(recent) do
        if now - e.at < SHOW_SECONDS then visible[#visible + 1] = e end
      end
      if #visible == 0 then return end
      font = font or love.graphics.newFont(13)
      local lg = love.graphics
      local oldFont = lg.getFont()
      lg.setFont(font)
      local x = (vp.gameX or 0) + 8
      local y = (vp.gameY or 0) + 8
      for _, e in ipairs(visible) do
        local alpha = math.min(1, (SHOW_SECONDS - (now - e.at)) / FADE_SECONDS)
        local text = e.text
        if #text > MAX_CHARS then text = text:sub(1, MAX_CHARS) .. "…" end
        lg.setColor(0, 0, 0, 0.55 * alpha)
        lg.rectangle("fill", x - 4, y - 2, font:getWidth(text) + 8, font:getHeight() + 4)
        lg.setColor(1, 1, 1, alpha)
        lg.print(text, x, y)
        y = y + font:getHeight() + 6
      end
      lg.setColor(1, 1, 1, 1)
      lg.setFont(oldFont)
    end)
    if not ok then client.overlayOn = false end -- never let the HUD take a frame down
  end)
end

return Overlay
