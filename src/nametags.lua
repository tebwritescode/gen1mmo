-- Floating nametags: small screen-space labels above every remote player
-- (and the local one), so real people are instantly distinguishable from
-- NPCs. Drawn in render.hud (window space, AFTER the frame composes), so
-- the text stays crisp at any window scale instead of chunky 8px tiles.
--
-- World->screen projection mirrors Renderer:endFrame's own world blit:
-- worldCanvas centered at Zoom.scale(fit scale), camera in world pixels.
-- Anchors follow the emote bubble (npc.px + 8 center, py - 6 above head).

local Nametags = {}

function Nametags.install(mod, client)
  local font = nil
  local broken = false

  mod.hooks:wrap("render.hud", function(next, game, vp)
    next(game, vp)
    if broken or client.state ~= "playing" then return end
    local ok, err = pcall(function()
      local Game = require("src.core.Game")
      local ow = Game.overworld
      -- only over a live, visible overworld: menus/battles own the screen
      if not ow or game.stack:top() ~= ow then return end
      local cam = ow.camera
      local rend = Game.renderer
      local wc = rend and rend.worldCanvas
      if not (cam and wc and type(vp) == "table") then return end
      -- perspective (tilt) and mod pipelines change the mapping; skip
      if rend.worldOverride then return end
      local Tilt = require("src.render.Tilt")
      if Tilt.active and Tilt.active() then return end

      local Zoom = require("src.render.Zoom")
      local pw = vp.width * (vp.dpiX or 1)
      local ph = vp.height * (vp.dpiY or 1)
      local sp = Zoom.scale(vp.scale)
      local sx = sp / (vp.dpiX or 1)
      local sy = sp / (vp.dpiY or 1)
      local wox = math.floor((pw - wc:getWidth() * sp) / 2) / (vp.dpiX or 1)
      local woy = math.floor((ph - wc:getHeight() * sp) / 2) / (vp.dpiY or 1)

      font = font or love.graphics.newFont(11)
      local lg = love.graphics
      local prevFont = lg.getFont()
      lg.setFont(font)

      local function tag(name, px, py, self_)
        local x = wox + (math.floor(px) + 8 - cam.x) * sx
        local y = woy + (math.floor(py) - 6 - cam.y) * sy
        local w = font:getWidth(name)
        local h = font:getHeight()
        lg.setColor(0, 0, 0, 0.55)
        lg.rectangle("fill", x - w / 2 - 2, y - h - 1, w + 4, h + 2)
        -- the local player's own tag is dimmer: it is orientation, not news
        if self_ then lg.setColor(0.8, 0.9, 1.0, 0.75)
        else lg.setColor(1, 1, 1, 0.95) end
        lg.print(name, math.floor(x - w / 2), math.floor(y - h))
      end

      client.players:eachEntity(function(name, e)
        if e.px and e.py then tag(name, e.px, e.py, false) end
      end)
      local p = ow.player
      if client.name and p and p.px then tag(client.name, p.px, p.py, true) end

      lg.setColor(1, 1, 1, 1)
      if prevFont then lg.setFont(prevFont) end
    end)
    if not ok then
      broken = true -- never take a frame down
      -- surface WHY in the chat log so a device report can quote it
      pcall(function() client:log("Tags off: " .. tostring(err)) end)
    end
  end)
end

return Nametags
