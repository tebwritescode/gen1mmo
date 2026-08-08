-- Remote players: other trainers rendered as live overworld NPCs.
--
-- The server only ever tells us about players in OUR room (same channel, same
-- map), so every join/move/leave here is already for our current map -- we
-- spawn straight onto it. A fresh "roster" is a full resync: clear and respawn.
--
-- Movement animates through the engine's own scripted-walk when a step is
-- adjacent (so remote trainers stride tile-to-tile like everything else), and
-- teleports/warps respawn at the destination.

local Skins = GEN1MMO_INCLUDE("src/skins.lua")

local Players = {}
Players.__index = Players

local DIR_TO_RANGE = { up = "UP", down = "DOWN", left = "LEFT", right = "RIGHT" }

function Players.new(mod)
  return setmetatable({
    mod = mod,
    mapId = nil,
    -- name -> { npcId, x, y, dir, skin }
    remote = {},
    -- name -> last known skin. Survives despawns: a failed respawn (the
    -- engine can refuse a spawn mid-frame) is healed by the next movement
    -- update, and that path must not lose the player's look.
    skins = {},
  }, Players)
end

function Players:setMap(mapId)
  self.mapId = mapId
end

local function spriteFor(skin)
  return Skins.overworldSprite(skin)
end

--- Spawn (or replace) a remote trainer at a tile.
function Players:_spawn(name, x, y, dir, skin)
  skin = skin or self.skins[name]
  if skin then self.skins[name] = skin end
  self:_despawn(name)
  local objDef = {
    sprite = spriteFor(skin),
    x = x, y = y,
    range = DIR_TO_RANGE[dir] or "DOWN",
    name = "g1mmo:" .. name,
    -- movement omitted => STAY: we drive position from the network, no wander.
  }
  local ok, npcId = pcall(function() return self.mod.world:spawnNpc(self.mapId, objDef) end)
  if not (ok and npcId) then
    -- Never let a look make a player invisible: an unregistered sprite id
    -- (engine version drift, modded sprite sets) falls back to the sprite
    -- every cache carries.
    objDef.sprite = "SPRITE_RED"
    ok, npcId = pcall(function() return self.mod.world:spawnNpc(self.mapId, objDef) end)
  end
  if ok and npcId then
    self.remote[name] = { npcId = npcId, x = x, y = y, dir = dir, skin = skin }
  end
end

function Players:_despawn(name)
  local r = self.remote[name]
  if r and r.npcId then
    pcall(function() self.mod.world:removeNpc(r.npcId) end)
  end
  self.remote[name] = nil
end

function Players:_handle(name)
  local r = self.remote[name]
  if not r then return nil end
  local ok, h = pcall(function() return self.mod.world:npc(self.mapId, r.npcId) end)
  if ok then return h end
  return nil
end

--- Full room resync from a roster list ({name,x,y,dir,skin}).
function Players:setRoster(list)
  self:clear()
  for _, p in ipairs(list or {}) do
    self:_spawn(p.name, p.x or 0, p.y or 0, p.dir or "down", p.skin)
  end
end

function Players:join(p)
  self:_spawn(p.name, p.x or 0, p.y or 0, p.dir or "down", p.skin)
end

function Players:leave(name)
  self:_despawn(name)
end

--- Step the NPC entity one tile directly, NEVER via Handle:scriptMove.
--- The engine's scriptMoves queue is cutscene machinery: while it is
--- non-empty the PLAYER'S INPUT IS LOCKED, and a queued step whose NPC
--- despawns mid-walk (roster resync, channel change) never retires --
--- which froze the player permanently. NPC:update self-animates from
--- exactly these fields (the engine's own non-locking "marchers" take
--- the same shortcut), so the walk looks identical without the queue.
local function stepEntity(h, x, y, dir)
  local e = h and h.npc
  if type(e) ~= "table" or e.moving == nil or e.cellX == nil then return false end
  if e.moving then return false end -- mid-step: let the caller respawn
  return (pcall(function()
    e.facing = dir
    e.targetX, e.targetY = x, y
    e.moving = true
    e.progress = 0
  end))
end

--- Apply a movement update, animating adjacent steps.
function Players:move(name, x, y, dir)
  local r = self.remote[name]
  if not r then
    self:_spawn(name, x, y, dir, nil)
    return
  end
  local dx, dy = x - r.x, y - r.y
  if (math.abs(dx) + math.abs(dy)) ~= 1
      or not stepEntity(self:_handle(name), x, y, dir) then
    -- teleport / warp / desync / unsteppable entity: respawn at the
    -- destination.
    self:_spawn(name, x, y, dir, r.skin)
    return
  end
  r.x, r.y, r.dir = x, y, dir
end

function Players:setSkin(name, skin)
  self.skins[name] = skin
  local r = self.remote[name]
  if not r then return end
  -- Re-sprite only if the body (and thus base sprite) changed; otherwise the
  -- tuple is stored for when richer skin rendering lands.
  local before = r.skin and Skins.overworldSprite(r.skin) or nil
  r.skin = skin
  if Skins.overworldSprite(skin) ~= before then
    self:_spawn(name, r.x, r.y, r.dir, skin)
  end
end

function Players:clear()
  for name in pairs(self.remote) do self:_despawn(name) end
  self.remote = {}
end

function Players:count()
  local n = 0
  for _ in pairs(self.remote) do n = n + 1 end
  return n
end

return Players
