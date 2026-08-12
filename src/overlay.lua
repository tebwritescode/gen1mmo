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
-- Hard ceiling on rendered rows so one pile of long messages can't grow the
-- panel past the screen; the server caps a single chat line at 200 chars,
-- which wraps to ~11 rows, so 14 comfortably fits the worst case unwrapped.
local ROW_CAP = 14

--- Greedy word-wrap: never DROPS a character (unlike a hard substring cut).
--- A single token longer than maxChars is hard-split so it still shows in
--- full across rows, rather than vanishing past the panel edge.
local function wrapLine(text, maxChars)
  local rows, cur = {}, ""
  for word in text:gmatch("%S+") do
    while #word > maxChars do
      if #cur > 0 then rows[#rows + 1] = cur; cur = "" end
      rows[#rows + 1] = word:sub(1, maxChars)
      word = word:sub(maxChars + 1)
    end
    if #cur == 0 then cur = word
    elseif #cur + 1 + #word <= maxChars then cur = cur .. " " .. word
    else rows[#rows + 1] = cur; cur = word end
  end
  rows[#rows + 1] = cur -- always at least one row, even for ""
  return rows
end
Overlay.wrapLine = wrapLine -- exposed for tests

function Overlay.install(mod, client)
  local Font = mod.ui.Font
  local recent = {} -- { text, at }

  -- Every chat-log line also lands here with an arrival stamp.
  local origLog = client.log
  client.log = function(self, line)
    recent[#recent + 1] = { text = tostring(line), at = love.timer.getTime() }
    local keep = mod.options:get("chatLines") or 4
    while #recent > math.max(keep, 6) do table.remove(recent, 1) end
    return origLog(self, line)
  end

  -- The panel's own on/off, minus a runtime override: a render crash below
  -- self-disables for the rest of the session (never a persisted write --
  -- mod.options has no mod-facing :set, ManagerState's UI is the only
  -- writer -- so this stays a plain runtime flag on client instead).
  function client:overlayEnabled()
    return not self._overlayCrashed and mod.options:get("chatOverlay") == true
  end

  -- Under render-pipeline mods (worldOverride, e.g. Dramatic Shape Voxel)
  -- the engine calls render.hud with a NIL viewport. Fall back to the last
  -- real one, or synthesize the letterbox from the window -- the overlay
  -- must not die (or silently vanish) just because a pipeline is on.
  local function viewportOr(vp)
    if type(vp) == "table" then return vp end
    if type(client._vp) == "table" then return client._vp end
    local w, h = love.graphics.getDimensions()
    local scale = math.max(1, math.floor(math.min(w / 160, h / 144)))
    return { width = w, height = h, scale = scale,
             gameX = math.floor((w - 160 * scale) / 2),
             gameY = math.floor((h - 144 * scale) / 2),
             gameWidth = 160 * scale, gameHeight = 144 * scale,
             dpiX = 1, dpiY = 1 }
  end
  Overlay.viewportOr = viewportOr -- shared with nametags.lua

  mod.hooks:wrap("render.hud", function(next, game, vp)
    next(game, vp)
    -- Stash the live viewport (LOVE-unit playfield rect + scale) so the
    -- pointer hook can map a screen tap into 160x144 canvas space.
    if type(vp) == "table" then client._vp = vp end
    vp = viewportOr(vp)

    -- Connection dot: corner of the playfield, on by default. Green =
    -- online and snappy, orange = online but slow / still connecting, red
    -- = not connected. THE answer to "am I even online right now?".
    pcall(function()
      if not mod.options:get("statusLight") then return end
      local Game = require("src.core.Game")
      local ow = Game.overworld
      if not ow or game.stack:top() ~= ow then return end
      local lg = love.graphics
      local r, g, b
      if client.state == "playing" then
        if client.pingMs and client.pingMs < 150 then r, g, b = 0.15, 0.85, 0.2
        else r, g, b = 0.95, 0.65, 0.1 end
      elseif client.state == "offline" then r, g, b = 0.9, 0.15, 0.15
      else r, g, b = 0.95, 0.65, 0.1 end
      lg.push("all")
      lg.translate(vp.gameX or 0, vp.gameY or 0)
      lg.scale(vp.scale or 1)
      lg.setColor(0, 0, 0, 0.7)
      lg.rectangle("fill", 152, 2, 6, 6)
      lg.setColor(r, g, b, 0.95)
      lg.rectangle("fill", 153, 3, 4, 4)
      lg.pop()
    end)

    if not client:overlayEnabled() or client.state ~= "playing" then return end
    local ok, err = pcall(function()
      local Game = require("src.core.Game")
      local ow = Game.overworld
      -- only over a live overworld; menus and battles own their screen
      if not ow or game.stack:top() ~= ow then return end
      -- user-tunable panel (Options > MODS > GEN1MMO > OPTIONS..):
      -- size = fraction of the playfield scale, bg/text = opacities
      local sizePct = mod.options:get("chatSize") or 0.75
      local bgA = mod.options:get("chatBg")
      if bgA == nil then bgA = 0.85 end
      local textA = mod.options:get("chatText") or 1.0
      local maxLines = mod.options:get("chatLines") or 4
      -- "Chat always on" in the options: keeps the last maxLines messages up
      -- permanently instead of fading after SHOW_SECONDS. Size/opacity above
      -- still fully apply -- this only removes the timer, not the tuning.
      local alwaysOn = mod.options:get("chatAlwaysOn") == true

      local now = love.timer.getTime()
      local visible = {}
      if alwaysOn then
        local n = #recent
        for i = math.max(1, n - maxLines + 1), n do visible[#visible + 1] = recent[i] end
      else
        for _, e in ipairs(recent) do
          if now - e.at < SHOW_SECONDS then visible[#visible + 1] = e end
        end
        while #visible > maxLines do table.remove(visible, 1) end
      end
      if #visible == 0 then return end

      -- Expand each visible message into its wrapped rows, carrying the SAME
      -- fade alpha (keyed to the message's own arrival time) across every row
      -- it produces, so a long message fades as one unit, not row-by-row.
      -- Nothing is ever cut off; a wrapped message just takes more rows.
      -- In "Always" mode there is no fade at all: full opacity, permanently.
      local function rowsFor(list)
        local rows = {}
        for _, e in ipairs(list) do
          local a = alwaysOn and 1 or math.min(1, (SHOW_SECONDS - (now - e.at)) / FADE_SECONDS)
          local text = (e.text:gsub("%*", "\194\183")) -- censor "*" has no tile; mid-dot does
          for _, wline in ipairs(wrapLine(text, MAX_CHARS)) do
            rows[#rows + 1] = { text = wline, a = a }
          end
        end
        return rows
      end
      local rows = rowsFor(visible)
      -- If wrapping pushed the total past ROW_CAP, drop the OLDEST WHOLE
      -- messages (never a message's tail rows alone -- that would orphan a
      -- fragment that reads like it's missing its start).
      while #rows > ROW_CAP and #visible > 1 do
        table.remove(visible, 1)
        rows = rowsFor(visible)
      end

      local lg = love.graphics
      lg.push("all")
      lg.translate(vp.gameX or 0, vp.gameY or 0)
      lg.scale((vp.scale or 1) * sizePct)

      local panelH = #rows * ROW + 6
      local alphaMax = 0
      for _, r in ipairs(rows) do if r.a > alphaMax then alphaMax = r.a end end
      lg.setColor(1, 1, 1, bgA * alphaMax)
      lg.rectangle("fill", 0, 0, 160, panelH)
      lg.setColor(0, 0, 0, bgA * alphaMax)
      lg.rectangle("fill", 0, panelH, 160, 1) -- the panel's lower rule

      for i, r in ipairs(rows) do
        -- glyph tiles are black ink; setColor's alpha is the only channel
        -- that shows, which is exactly the fade we want
        lg.setColor(0, 0, 0, textA * r.a)
        Font.draw(r.text, 4, 4 + (i - 1) * ROW)
      end
      lg.pop()
    end)
    if not ok then
      -- never let the HUD take a frame down -- but say WHY it went dark,
      -- so a device report can quote the reason instead of "it vanished"
      client._overlayCrashed = true
      pcall(function() client:log("Overlay off: " .. tostring(err)) end)
    end
  end)
end

return Overlay
