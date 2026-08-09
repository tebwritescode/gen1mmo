-- Floating nametags: small screen-space labels above every remote player
-- (and the local one), so real people are instantly distinguishable from
-- NPCs. Drawn in render.hud (window space, AFTER the frame composes), so
-- the text stays crisp at any window scale instead of chunky 8px tiles.
--
-- Two projections:
--  * FLAT: mirrors Renderer:endFrame's world blit (worldCanvas centered at
--    Zoom scale, camera in world pixels). Anchors follow the emote bubble.
--  * VOXEL (Dramatic Shape): when that mod's pipeline owns the frame it
--    publishes its live camera matrix (Voxel3D.vp) and reads entities at
--    (px+8, groundY, py+8) -- we project the tag anchor through the SAME
--    matrix, so tags track players in every rung, third person included.

local Nametags = {}

function Nametags.install(mod, client)
  local font = nil
  local broken = false
  local dsvV3 -- Dramatic Shape's Voxel3D module; false = looked, absent

  local Overlay = GEN1MMO_INCLUDE("src/overlay.lua")

  -- True when any world-owning render pipeline is at level > 0. Checked
  -- per frame: renderer.worldOverride is already consumed and CLEARED by
  -- the time render.hud fires, so it cannot be the gate.
  local function pipelineActive()
    local active = false
    pcall(function()
      local Pipelines = require("src.render.Pipelines")
      for _, entry in ipairs(Pipelines.list()) do
        if entry.def and entry.def.drawWorld and Pipelines.level(entry.id) > 0 then
          active = true
          return
        end
      end
    end)
    return active
  end

  -- The voxel scene's exact matrix, via the mod's own exported module
  -- loader (mod.exports.lib.require). Row-major 4x4; billboards stand at
  -- (px+8, gh, py+8) with +Y up. The pipeline canvas covers the window,
  -- so NDC maps straight to LOVE units.
  local function voxelProject(game, wx, wy, wz, vp)
    if dsvV3 == nil then
      dsvV3 = false
      pcall(function()
        local dsv = game.mods and game.mods.exports
          and game.mods.exports["DRAMATIC_SHAPE"]
        local lib = dsv and dsv.lib
        if lib and lib.require then dsvV3 = lib.require("Voxel3D") end
      end)
    end
    local m = dsvV3 and dsvV3.vp
    if not m then return nil end
    local cx = m[1] * wx + m[2] * wy + m[3] * wz + m[4]
    local cy = m[5] * wx + m[6] * wy + m[7] * wz + m[8]
    local cw = m[13] * wx + m[14] * wy + m[15] * wz + m[16]
    if cw < 0.001 then return nil end -- behind the camera (first person)
    local ndcX, ndcY = cx / cw, cy / cw
    if ndcX < -1.5 or ndcX > 1.5 or ndcY < -1.5 or ndcY > 1.5 then return nil end
    return (ndcX * 0.5 + 0.5) * vp.width,
           (0.5 - ndcY * 0.5) * vp.height,
           cw
  end

  -- Screen anchor above a voxel billboard's head. World height compresses
  -- at steep camera angles while the LEANED billboard still fills screen
  -- height, so a fixed world-height anchor lands on feet (orbit) or chest
  -- (3rd person). Instead: project the FEET, measure the sprite's actual
  -- on-screen size at that depth (16 world px along camera-right -- the
  -- billboard faces the camera, so width ~ height), and hang the tag one
  -- sprite-height up.
  local dsvScene -- VoxelScene module, for the billboard pull
  local function voxelAnchor(game, e, vp, selfTag)
    -- in the camera-rig modes (1st/3rd person: Voxel3D.camera set) your own
    -- body IS the view anchor; a floating self-label is pure noise there
    if selfTag and dsvV3 and dsvV3.camera then return nil end
    local wx, wy, wz = math.floor(e.px) + 8, (e.gh or 0) + 2, math.floor(e.py) + 8
    local eye = dsvV3 and dsvV3.eye
    if eye then
      local dx, dy, dz = eye[1] - wx, eye[2] - wy, eye[3] - wz
      local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
      -- never tag what the camera is standing in (own head, 1st person)
      if dist < 24 then return nil end
      -- The scene draws billboards PULLED toward the eye (VoxelScene.pull)
      -- so they read in front of their tile; tag the PULLED position or
      -- the label detaches exactly where the pull is big (3rd person).
      if dsvScene == nil then
        dsvScene = false
        pcall(function()
          local dsv = game.mods.exports["DRAMATIC_SHAPE"]
          dsvScene = dsv.lib.require("VoxelScene")
        end)
      end
      local pull = 6
      if dsvScene and dsvScene.pull then
        local lean = math.asin(math.max(0, math.min(1, dsvV3.descent or 1)))
        local okP, p = pcall(dsvScene.pull, math.max(lean, 0.05))
        if okP and type(p) == "number" then pull = p end
      end
      -- pull HORIZONTALLY only: the eye sits above, and pulling along the
      -- full ray lifts the anchor into the sky at close range
      local hl = math.sqrt(dx * dx + dz * dz)
      if hl > 1 then
        pull = math.min(pull, hl * 0.6)
        wx = wx + dx / hl * pull
        wz = wz + dz / hl * pull
      end
    end
    local fxp, fyp, cw = voxelProject(game, wx, wy, wz, vp)
    if not fxp then return nil end
    -- exact perspective size: pixels of a 16-world-px length perpendicular
    -- to the view at this depth = 16 * (H/2) / (tan(fov/2) * w_clip)
    local fov = (dsvV3 and dsvV3.fovY) or 0.5
    local spriteH = 16 * (vp.height * 0.5) / (math.tan(fov / 2) * cw)
    -- close-range degeneracy: a near billboard's focal size explodes past
    -- the frame; cap it, and keep the label on screen rather than gone
    spriteH = math.max(10, math.min(spriteH, vp.height * 0.4))
    local y = fyp - spriteH - 3
    if y < 14 then y = 14 end
    return fxp, y
  end

  mod.hooks:wrap("render.hud", function(next, game, vp)
    next(game, vp)
    if broken or client.state ~= "playing" then return end
    local ok, err = pcall(function()
      -- pipelines call render.hud with a NIL viewport; use the shared
      -- fallback instead of silently bailing
      vp = Overlay.viewportOr(vp)
      local Game = require("src.core.Game")
      local ow = Game.overworld
      -- only over a live, visible overworld: menus/battles own the screen
      if not ow or game.stack:top() ~= ow then return end
      local cam = ow.camera
      local rend = Game.renderer
      local wc = rend and rend.worldCanvas
      if not (cam and wc and type(vp) == "table") then return end
      -- true perspective (engine tilt) has no affine map: skip
      local Tilt = require("src.render.Tilt")
      if Tilt.active and Tilt.active() then return end

      local pipeActive = pipelineActive()

      local Zoom = require("src.render.Zoom")
      local pw = vp.width * (vp.dpiX or 1)
      local ph = vp.height * (vp.dpiY or 1)
      local sp = Zoom.scale(vp.scale)
      local fx = sp / (vp.dpiX or 1)
      local fy = sp / (vp.dpiY or 1)
      local wox = math.floor((pw - wc:getWidth() * sp) / 2) / (vp.dpiX or 1)
      local woy = math.floor((ph - wc:getHeight() * sp) / 2) / (vp.dpiY or 1)

      font = font or love.graphics.newFont(11)
      local lg = love.graphics
      local prevFont = lg.getFont()
      lg.setFont(font)

      -- e: entity (has px/py and, under voxel, gh); returns screen x,y of
      -- the point above its head, or nil when it should not draw
      local function anchor(e, selfTag)
        if pipeActive then
          local sx, sy = voxelAnchor(game, e, vp, selfTag)
          if sx then return sx, sy end
          -- no voxel matrix = some other pipeline mod: flat best-effort
          if not (dsvV3 and dsvV3.vp) then
            return wox + (math.floor(e.px) + 8 - cam.x) * fx,
                   woy + (math.floor(e.py) - 6 - cam.y) * fy
          end
          return nil -- voxel active but point behind/off-screen: hide
        end
        return wox + (math.floor(e.px) + 8 - cam.x) * fx,
               woy + (math.floor(e.py) - 6 - cam.y) * fy
      end

      local function tag(name, e, self_)
        local x, y = anchor(e, self_)
        if not x then return end
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
        if e.px and e.py then tag(name, e, false) end
      end)
      local p = ow.player
      if client.name and p and p.px then tag(client.name, p, true) end

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
