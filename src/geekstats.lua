-- Stats for geeks: an opt-in debug readout over the whole screen in a
-- small-but-readable font. Everything a bug report needs at a glance --
-- connection, server counts, look/sheet state, render mode -- with no
-- personal data beyond your own name. Toggled from the GEN1MMO menu.

local Geek = {}

function Geek.install(mod, client)
  local font = nil

  mod.hooks:wrap("render.hud", function(next, game, vp)
    next(game, vp)
    if not mod.options:get("geekStats") then return end
    pcall(function()
      font = font or love.graphics.newFont(10)
      local lg = love.graphics
      local prevFont = lg.getFont()
      lg.setFont(font)

      -- keep the server figures fresh while the readout is up
      client._geekTick = (client._geekTick or 0) + 1
      if client._geekTick % 240 == 0 then client:requestStats() end

      local s = client.stats or {}
      local net = client.net
      local now = love.timer.getTime()
      local Game = require("src.core.Game")
      local pipe = "flat"
      pcall(function()
        local P = require("src.render.Pipelines")
        for _, e in ipairs(P.list()) do
          if e.def and e.def.drawWorld and P.level(e.id) > 0 then
            pipe = e.id .. ":" .. P.level(e.id)
          end
        end
      end)

      local lines = {
        ("gen1mmo %s  api2  fps %d"):format(tostring(client.version), love.timer.getFPS()),
        ("state %s  name %s"):format(client.state, tostring(client.name or "-")),
        ("ping %s ms  last tx %s s"):format(tostring(client.pingMs or "-"),
          net and net.lastTx and string.format("%.1f", now - net.lastTx) or "-"),
        ("online %s  channel %d/%d  here %d"):format(
          tostring(s.population or "-"), (client.channel or 0) + 1,
          client.channels or 1, client.players:count() + (client.state == "playing" and 1 or 0)),
        ("map %s  cell %d,%d"):format(tostring(client.mapId or "-"),
          client.x or 0, client.y or 0),
        ("look %s  sheets %s/16"):format(tostring(client._ownSpriteId or "-"),
          tostring(client.diagSheets or "?")),
        ("skin b%d t%d h%d hc%d o%d"):format(client.skin.body, client.skin.skin,
          client.skin.hair, client.skin.hairColor, client.skin.outfit),
        ("render %s  overlay %s"):format(pipe, client:overlayEnabled() and "on" or "off"),
        ("features %s  latest %s"):format(
          client.features and (client.features.stats and "stats " or "") or "-",
          tostring(client.latestMod or "-")),
        ("chat lines %d  remotes %d"):format(#client.chat, client.players:count()),
        ("lua mem %d kb"):format(math.floor(collectgarbage("count"))),
      }

      local x, y = 8, 8
      local step = font:getHeight() + 1
      for i, line in ipairs(lines) do
        lg.setColor(0, 0, 0, 0.75)
        lg.print(line, x + 1, y + (i - 1) * step + 1)
        lg.setColor(0.6, 1, 0.6, 0.85)
        lg.print(line, x, y + (i - 1) * step)
      end
      lg.setColor(1, 1, 1, 1)
      if prevFont then lg.setFont(prevFont) end
    end)
  end)
end

return Geek
