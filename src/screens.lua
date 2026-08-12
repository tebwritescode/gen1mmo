-- The Gen1MMO screen: menu, text entry, chat, and the look editor -- all drawn
-- with the confirmed toolkit only (mod.ui.Font + game.input), so no widget API
-- is guessed. Text entry is a self-contained d-pad letter grid, since the GB
-- input model has no keyboard.
--
-- One screen, several "views". B backs out a view or pops the screen.

local Skins = GEN1MMO_INCLUDE("src/skins.lua")
local Overlay = GEN1MMO_INCLUDE("src/overlay.lua") -- shared wrapLine: nothing gets cut off
local Net = GEN1MMO_INCLUDE("src/net.lua") -- transportAvailable/probe: the logged-out pre-flight check

local GRID = {
  "ABCDEFGHIJ",
  "KLMNOPQRST",
  "UVWXYZ0123",
  "456789_.-!",
}

-- The Gen 1 charmap has no tile for ">", "_" or "*": Font.encode silently
-- draws them as spaces, which is why a text ">" cursor was invisible on
-- devices. Selection is drawn the way vanilla menus draw it -- the filled
-- arrow glyph (Theme.cursor, charmap $ED) via Font.drawCode -- and
-- underscores/masks are drawn as strokes or mapped to glyphs that exist.
local MENU_VISIBLE = 8   -- rows y=36..120; row 9 would sit on the border
local CHAT_VISIBLE = 9   -- rows y=22..118, above the footer
local CHAT_MAX_CHARS = 18 -- glyphs that fit the box at this margin

return function(mod, client)
  mod.content.screens:register("Gen1MMO", {
    new = function(game)
      local Font = mod.ui.Font
      local Theme = mod.ui.Theme
      local self = { game = game, isOpaque = true }

      self.view = "menu"          -- menu | text | chat | look | player | stats | key
      self.cursor = 1
      self.menuScroll = 0         -- first visible menu row - 1
      self.gx, self.gy = 1, 1     -- grid cursor for text entry
      self.buffer = ""
      self.textPrompt = ""
      self.textOnDone = nil
      self.textMask = false
      self.acceptTyped = false    -- native keyboard feeds the buffer
      self.scope = "map"
      self.chatOff = 0            -- lines scrolled back from the newest
      self.lookIndex = 1
      self.playerTarget = nil     -- name behind the "player" action view

      -- the love.textinput/keypressed wraps in main.lua reach the active
      -- screen through this
      client._screen = self
      -- opened by an A-press on a remote player (world.interacted)
      if client._openPlayerMenu then
        self.view = "player"
        self.playerTarget = client._openPlayerMenu
        client._openPlayerMenu = nil
      elseif client._openChatDirect then
        -- Start Menu's CHAT row: straight into chat, no menu stop first
        self.view = "chat"
        client._openChatDirect = nil
      elseif client._openEmoteDirect then
        -- Start Menu's EMOTE row: straight into the emote picker
        self.view = "emote"
        client._openEmoteDirect = nil
      end

      -- Pre-flight for the logged-out menu: never offer Register/Log in
      -- when tapping them would just fail. Runs once per app session (not
      -- per frame -- menuItems() below is called from draw/update/onTap
      -- every frame, and a blocking probe belongs in exactly one place),
      -- cached on client so every screen re-open sees the same verdict
      -- until "Try again" clears it. transportAvailable() is a platform-
      -- agnostic capability check (can THIS device open a socket at all
      -- right now), not a guess about any specific app or platform.
      local function checkNet()
        local transport = Net.transportAvailable()
        local reachable, reachErr = false, nil
        if transport then
          reachable, reachErr = Net.probe(client.host, client.port, 3)
        end
        client._netCheck = { transport = transport, reachable = reachable }
        if not transport then
          client.status = "No network transport on this device"
        elseif not reachable then
          client.status = reachErr or "Could not reach the server"
        else
          client.status = nil
        end
      end
      if client.state ~= "playing" and not client._netCheck then
        checkNet()
      end

      local input = game.input

      -- ----- helpers
      local function withRecoveryRow(items)
        if mod.save:get("recovery_code", nil) or client.recoveryCode then
          items[#items + 1] = { "Recovery key", function() self.view = "key" end }
        end
        return items
      end

      -- inbound friend requests surface as one menu row each, so an
      -- accept is possible even when the requester has wandered off
      local function withPendingRows(items)
        local names = {}
        for name in pairs(client.pendingFriends or {}) do names[#names + 1] = name end
        table.sort(names)
        for i = #names, 1, -1 do
          local name = names[i]
          table.insert(items, 2, { "Accept: " .. name, function()
            client:acceptFriend(name)
          end })
        end
        return items
      end

      -- Chat and Emote are direct Start Menu rows now (main.lua); this list
      -- is everything else Gen1MMO does, reached via Options > GEN1MMO >
      -- OPEN. Settings (overlay/geek stats/auto-connect/chat panel tuning)
      -- moved to Options > MODS > GEN1MMO > OPTIONS.. -- mod.options owns
      -- them, so there is no row for them here anymore either.
      local function menuItems()
        if client.state == "playing" then
          return withPendingRows(withRecoveryRow {
            { "Say something", function()
              self:enterText("SAY:", false, function(t) client:say(self.scope, t) end)
            end },
            { "Change look", function() self.view = "look" end },
            { "Add friend", function()
              self:enterText("FRIEND:", false, function(t) client:addFriend(t) end)
            end },
            { "Whisper friend", function()
              self:enterText("TO:", false, function(to)
                self:enterText("MSG:", false, function(msg) client:whisper(to, msg) end)
              end)
            end },
            { "Next channel", function()
              client:joinChannel((client.channel + 1) % math.max(1, client.channels))
            end },
            { "My history", function()
              self.histScroll = 0
              self.view = "history"
            end },
            { "Server info", function()
              client:requestStats()
              self.view = "stats"
            end },
            { "Disconnect", function() client:disconnect() end },
          })
        else
          -- Register/Log in only ever appear once the pre-flight check
          -- (above, in new()) confirms this device can actually reach the
          -- server -- tapping either one would otherwise just fail with
          -- the same error a beat later, deeper in the flow.
          local nc = client._netCheck
          if nc and not nc.transport then
            return withRecoveryRow {
              { "No network here", function() end },
              { "Try again", function() checkNet() end },
            }
          elseif nc and not nc.reachable then
            return withRecoveryRow {
              { "Can't reach it", function() end },
              { "Try again", function() checkNet() end },
            }
          end
          return withRecoveryRow {
            { "Register (new)", function()
              self:enterText("USERNAME:", false, function(u)
                self:enterText("PASSWORD:", true, function(p)
                  client:connect(client.host, client.port, "register", u, p)
                end)
              end)
            end },
            (function()
              -- saved login = one press; the prompt flow only appears when
              -- nothing is stored (or after Forget login)
              local saved = client.storedLoginName and client:storedLoginName()
              if saved then
                return { ("Log in: %s"):format(saved), function()
                  client:connectStored(client.host, client.port)
                end }
              end
              return { "Log in", function()
                self:enterText("USERNAME:", false, function(u)
                  self:enterText("PASSWORD:", true, function(p)
                    client:connect(client.host, client.port, "login", u, p)
                  end)
                end, mod.save:get("last_name", "")) -- prefill the last name
              end }
            end)(),
            -- "Set server" is hidden for the beta: the default already points
            -- at the official server, and the row exposed its address. Self-
            -- hosters still override via config.lua / the saved server_host.
            { "Forget login", function()
              client:forgetLogin()
              client.status = "Saved login cleared"
            end },
          }
        end
      end

      function self:enterText(prompt, mask, onDone, initial)
        self.view = "text"
        self.buffer = tostring(initial or "")
        self.textPrompt = prompt
        self.textMask = mask
        self.textOnDone = onDone
        self.gx, self.gy = 1, 1
        -- native typing alongside the grid: summons the soft keyboard on
        -- touch devices, lets hardware keyboards type directly
        self.acceptTyped = true
        self.typedThisFrame = false
        self.submitTyped = false
        -- Reported broken on iOS/Phosphorus: the native soft keyboard pops
        -- up, typed characters never reach the buffer (love.textinput isn't
        -- landing there the way it does on other ports), and the keyboard
        -- physically covers the d-pad grid's own OK prompt -- net negative,
        -- not just unhelpful. Skip SUMMONING it on iOS specifically; the
        -- d-pad grid (confirmed working there) remains the primary path.
        -- love.textinput/keypressed stay wired regardless, so a hardware
        -- keyboard (e.g. an iPad with one attached) still types for free if
        -- the port delivers those events for it.
        local os = "unknown"
        pcall(function() os = love.system.getOS() end)
        if os ~= "iOS" then
          pcall(function() love.keyboard.setTextInput(true) end)
        end
      end

      function self:leaveText(nextView)
        self.acceptTyped = false
        pcall(function() love.keyboard.setTextInput(false) end)
        self.view = nextView or "menu"
      end

      -- "_" has no charmap tile, so wherever it appears (grid key, typed
      -- text) it is drawn as a literal underline stroke instead. Defined
      -- before every draw function that calls it: these are locals, and a
      -- later definition is an invisible nil global to an earlier one.
      local function drawUnderscore(x, y)
        local r, g, b, a = love.graphics.getColor()
        love.graphics.setColor(0, 0, 0, 1)
        love.graphics.rectangle("fill", x, y + 6, 7, 2)
        love.graphics.setColor(r, g, b, a)
      end

      -- "▲" aliases to the RIGHT arrow tile ($ED) in the charmap, so the
      -- more-above marker is a stepped triangle of rectangles, mirroring
      -- moreArrow ($EE)
      local function drawUpArrow(x, y)
        local r, g, b, a = love.graphics.getColor()
        love.graphics.setColor(0, 0, 0, 1)
        love.graphics.rectangle("fill", x + 3, y + 1, 2, 2)
        love.graphics.rectangle("fill", x + 2, y + 3, 4, 2)
        love.graphics.rectangle("fill", x + 1, y + 5, 6, 2)
        love.graphics.setColor(r, g, b, a)
      end

      -- keeps the cursor inside the visible window (vanilla Menu:clampScroll)
      local function clampMenuScroll(count)
        self.menuScroll = math.min(self.menuScroll, math.max(0, count - MENU_VISIBLE))
        if self.cursor - self.menuScroll > MENU_VISIBLE then
          self.menuScroll = self.cursor - MENU_VISIBLE
        elseif self.cursor - self.menuScroll < 1 then
          self.menuScroll = self.cursor - 1
        end
      end

      -- ----- update per view
      local function updateMenu()
        local items = menuItems()
        -- the item list shrinks on disconnect; never strand the cursor
        if self.cursor > #items then self.cursor = #items end
        if input:wasPressed("up") then
          self.cursor = self.cursor > 1 and self.cursor - 1 or #items
        end
        if input:wasPressed("down") then
          self.cursor = self.cursor < #items and self.cursor + 1 or 1
        end
        clampMenuScroll(#items)
        -- Debounce activation: some controller paths deliver one physical
        -- A press as edges in two CONSECUTIVE steps (engine bug620 family),
        -- which made toggle rows flip and instantly flip back. A short
        -- cooldown swallows the ghost edge; 8 steps is ~130ms, far below
        -- an intentional double-tap.
        self._aCool = math.max(0, (self._aCool or 0) - 1)
        if input:wasPressed("a") and self._aCool == 0 and items[self.cursor] then
          self._aCool = 8
          items[self.cursor][2]()
        end
        if input:wasPressed("b") then game.stack:pop() end
      end

      local function updateText()
        -- native-keyboard events first: a typed key may ALSO be bound to a
        -- GB button (z/x/enter/arrows), so a frame that took a typed char
        -- swallows its button echoes entirely
        if self.submitTyped then
          self.submitTyped = false
          self.typedThisFrame = false
          local cb = self.textOnDone
          self:leaveText()
          if cb then cb(self.buffer) end
          return
        end
        if self.typedThisFrame then
          self.typedThisFrame = false
          return
        end
        if input:wasPressed("up") then self.gy = ((self.gy - 2) % #GRID) + 1 end
        if input:wasPressed("down") then self.gy = (self.gy % #GRID) + 1 end
        if input:wasPressed("left") then self.gx = ((self.gx - 2) % #GRID[1]) + 1 end
        if input:wasPressed("right") then self.gx = (self.gx % #GRID[1]) + 1 end
        if input:wasPressed("a") then
          if #self.buffer < 24 then
            self.buffer = self.buffer .. GRID[self.gy]:sub(self.gx, self.gx)
          end
        end
        if input:wasPressed("select") then self.buffer = self.buffer:sub(1, -2) end -- backspace
        if input:wasPressed("start") then
          local cb = self.textOnDone
          self:leaveText()
          if cb then cb(self.buffer) end
        end
        if input:wasPressed("b") then self:leaveText() end
      end

      -- the A-press-on-a-player action menu
      -- Whisper is FRIENDS ONLY (server enforces it; the menu just tells
      -- the truth): strangers get "Add friend", a pending inbound request
      -- gets "Accept friend", and only a made friendship shows "Whisper".
      local function playerItems()
        local who = self.playerTarget or "?"
        local items = {}
        if client.friends and client.friends[who] then
          items[#items + 1] = { "Whisper", function()
            self:enterText("TO " .. who .. ":", false, function(t)
              client:whisper(who, t)
              client:log("(to " .. who .. ") " .. t)
            end)
          end }
        elseif client.pendingFriends and client.pendingFriends[who] then
          items[#items + 1] = { "Accept friend", function()
            client:acceptFriend(who)
          end }
        else
          items[#items + 1] = { "Add friend", function()
            client:addFriend(who)
            client:log("Friend request sent to " .. who .. ".")
          end }
        end
        items[#items + 1] = { "Close", function() game.stack:pop() end }
        return items
      end

      local function updatePlayer()
        local items = playerItems()
        if self.cursor > #items then self.cursor = #items end
        if input:wasPressed("up") then
          self.cursor = self.cursor > 1 and self.cursor - 1 or #items
        end
        if input:wasPressed("down") then
          self.cursor = self.cursor < #items and self.cursor + 1 or 1
        end
        if input:wasPressed("a") and items[self.cursor] then items[self.cursor][2]() end
        if input:wasPressed("b") then game.stack:pop() end
      end

      -- my history: the collectible record, browsable. Earned rows only;
      -- the header carries the score (12/43).
      local Ach = GEN1MMO_INCLUDE("src/achievements.lua")
      local HIST_VISIBLE = 9
      local function earnedHistory()
        local rows = {}
        for _, r in ipairs(Ach.LIST) do
          if mod.save:get("ms_" .. r[1], false) then rows[#rows + 1] = r[2] end
        end
        return rows
      end
      local function updateHistory()
        local rows = earnedHistory()
        local maxScroll = math.max(0, #rows - HIST_VISIBLE)
        self.histScroll = math.min(self.histScroll or 0, maxScroll)
        if input:wasPressed("up") then
          self.histScroll = math.max(0, self.histScroll - 1)
        end
        if input:wasPressed("down") then
          self.histScroll = math.min(maxScroll, self.histScroll + 1)
        end
        if input:wasPressed("b") or input:wasPressed("a") then self.view = "menu" end
      end
      local function drawHistory()
        Font.drawBox(0, 0, 20, 18)
        local rows = earnedHistory()
        Font.draw(("HISTORY %d/%d"):format(#rows, #Ach.LIST), 16, 8)
        if #rows == 0 then
          Font.draw("Nothing yet.", 12, 36)
          Font.draw("Go make some!", 12, 48)
        end
        for i = 1, math.min(HIST_VISIBLE, #rows - (self.histScroll or 0)) do
          Font.draw(rows[i + (self.histScroll or 0)], 12, 22 + (i - 1) * 12)
        end
        if (self.histScroll or 0) + HIST_VISIBLE < #rows then
          Font.drawCode(0xEE, 148, 130) -- vanilla "more" arrow
        end
      end

      -- emote picker: fire and pop straight back to the world, so the
      -- bubble is visible the moment it exists
      local EMOTE_ROWS = { { "Heart", 0 }, { "Wave", 1 }, { "Fist", 2 } }
      local function updateEmote()
        if self.cursor > #EMOTE_ROWS then self.cursor = 1 end
        if input:wasPressed("up") then
          self.cursor = self.cursor > 1 and self.cursor - 1 or #EMOTE_ROWS
        end
        if input:wasPressed("down") then
          self.cursor = self.cursor < #EMOTE_ROWS and self.cursor + 1 or 1
        end
        if input:wasPressed("a") then
          client:emote(EMOTE_ROWS[self.cursor][2])
          game.stack:pop()
        end
        if input:wasPressed("b") then self.view = "menu" end
      end

      local function updateStats()
        -- keep the figures live while the screen is up (server cooldown 2s)
        self._statsTick = (self._statsTick or 0) + 1
        if self._statsTick % 150 == 0 then client:requestStats() end
        if input:wasPressed("a") or input:wasPressed("b") then self.view = "menu" end
      end

      -- Wrapped chat rows: a long message spans several rows instead of being
      -- cut off at CHAT_MAX_CHARS. Scrolling (below) moves by ROW now, not by
      -- raw message, so a wrapped message pages through smoothly. Recomputed
      -- on demand -- client.chat is capped at 40 entries, so this is cheap.
      local function buildChatRows()
        local rows = {}
        for _, msg in ipairs(client.chat) do
          for _, wline in ipairs(Overlay.wrapLine(msg, CHAT_MAX_CHARS)) do
            rows[#rows + 1] = wline
          end
        end
        return rows
      end

      local function updateChat()
        local maxOff = math.max(0, #buildChatRows() - CHAT_VISIBLE)
        if input:wasPressed("up") then self.chatOff = math.min(self.chatOff + 1, maxOff) end
        if input:wasPressed("down") then self.chatOff = math.max(self.chatOff - 1, 0) end
        if input:wasPressed("b") then self.view = "menu" end
        if input:wasPressed("a") then
          self:enterText("SAY:", false, function(t) client:say(self.scope, t) end)
        end
        if input:wasPressed("left") or input:wasPressed("right") then
          self.scope = (self.scope == "map") and "channel"
            or (self.scope == "channel") and "global" or "map"
        end
      end

      -- field, catalog list, short row label -- one source for update,
      -- draw, and tap (legacy "outfit" stays in the tuple, no row: the
      -- per-piece colors supersede it)
      -- skins overhaul: BODY picks one of the game's own people sheets;
      -- the color rows repaint that sheet's regions. hair/hat/outfit ride
      -- the wire for compatibility but have no rows.
      local CATS = {
        { "body",      "bodies",      "Body" },
        { "skin",      "skinTones",   "Tone" },
        { "hairColor", "pieceColors", "Head" },
        { "shirt",     "pieceColors", "Shirt" },
        { "pants",     "pieceColors", "Pants" },
        { "pack",      "pieceColors", "Pack" },
      }
      local function updateLook()
        -- the preview mannequin turns and steps in place
        self._lookTick = (self._lookTick or 0) + 1
        if input:wasPressed("up") then self.lookIndex = ((self.lookIndex - 2) % #CATS) + 1 end
        if input:wasPressed("down") then self.lookIndex = (self.lookIndex % #CATS) + 1 end
        local cat = CATS[self.lookIndex]
        local field, list = cat[1], Skins.catalog[cat[2]]
        if input:wasPressed("left") then
          client.skin[field] = (((client.skin[field] or 0) - 1) % #list)
        end
        if input:wasPressed("right") then
          client.skin[field] = (((client.skin[field] or 0) + 1) % #list)
        end
        if input:wasPressed("a") then client:applySkin(client.skin) end
        if input:wasPressed("b") then client:applySkin(client.skin); self.view = "menu" end
      end

      -- Diagnostic latch: record EVERY button edge this screen actually
      -- receives, so a device can show whether input reaches us at all.
      -- Toggle off from the menu once the input bug is understood.
      local DBG_BUTTONS = { "up", "down", "left", "right", "a", "b", "start", "select" }
      local function noteInput()
        for _, btn in ipairs(DBG_BUTTONS) do
          if input:wasPressed(btn) then
            self._dbgLast = btn
            self._dbgCount = (self._dbgCount or 0) + 1
          end
        end
      end

      function self:update(dt)
        if client.inputDebug then noteInput() end
        -- A fresh recovery key OWNS the screen until the player confirms:
        -- it is the only thing that can restore a lost account, so it must
        -- be impossible to miss (and a copy sits in the mod save).
        if client.recoveryCode and not client.keyAcknowledged then
          if input:wasPressed("a") then client.keyAcknowledged = true end
          return
        end
        if self.view == "key" then
          if input:wasPressed("a") or input:wasPressed("b") then self.view = "menu" end
          return
        end
        if self.view == "menu" then updateMenu()
        elseif self.view == "text" then updateText()
        elseif self.view == "chat" then updateChat()
        elseif self.view == "look" then updateLook()
        elseif self.view == "player" then updatePlayer()
        elseif self.view == "stats" then updateStats()
        elseif self.view == "emote" then updateEmote()
        elseif self.view == "history" then updateHistory() end
      end

      -- ----- touch: tap items/letters directly (cx,cy in 160x144 canvas
      -- space; the mod loader maps the screen tap for us). Essential on
      -- phones, where a controller's d-pad may not reach menus but the
      -- touchscreen always works. Mirrors the draw layout below exactly.
      function self:onTap(cx, cy)
        if client.recoveryCode and not client.keyAcknowledged then
          client.keyAcknowledged = true
          return
        end
        if self.view == "key" then self.view = "menu"; return end
        if self.view == "menu" then
          local items = menuItems()
          -- scroll-arrow zones before the rows: top border scrolls up,
          -- bottom border scrolls down (touch users have no d-pad)
          if self.menuScroll > 0 and cy <= 12 then
            self.menuScroll = self.menuScroll - 1
            self.cursor = math.min(self.cursor, self.menuScroll + MENU_VISIBLE)
            return
          end
          if self.menuScroll + MENU_VISIBLE < #items and cy >= 134 then
            self.menuScroll = self.menuScroll + 1
            self.cursor = math.max(self.cursor, self.menuScroll + 1)
            return
          end
          for row = 1, MENU_VISIBLE do
            local i = self.menuScroll + row
            if not items[i] then break end
            local y = 36 + (row - 1) * 12
            if cy >= y - 4 and cy <= y + 9 then
              self.cursor = i
              items[i][2]()
              return
            end
          end
        elseif self.view == "text" then
          -- tap the typed line to (re)summon the soft keyboard
          if cy <= 36 then
            pcall(function() love.keyboard.setTextInput(true) end)
            return
          end
          -- footer actions first (y ~128): left third deletes, right third confirms
          if cy >= 122 then
            if cx <= 54 then
              self.buffer = self.buffer:sub(1, -2)         -- DEL
            elseif cx >= 104 then
              local cb = self.textOnDone; self:leaveText(); if cb then cb(self.buffer) end
            end
            return
          end
          for r = 1, #GRID do
            for c = 1, #GRID[r] do
              local x = 8 + (c - 1) * 14
              local y = 44 + (r - 1) * 16
              if cx >= x - 4 and cx <= x + 11 and cy >= y - 3 and cy <= y + 13 then
                self.gx, self.gy = c, r
                if #self.buffer < 24 then
                  self.buffer = self.buffer .. GRID[r]:sub(c, c)
                end
                return
              end
            end
          end
        elseif self.view == "player" then
          local items = playerItems()
          for i = 1, #items do
            local y = 96 + (i - 1) * 12
            if cy >= y - 3 and cy <= y + 9 then
              self.cursor = i
              items[i][2]()
              return
            end
          end
        elseif self.view == "stats" or self.view == "history" then
          self.view = "menu"
        elseif self.view == "emote" then
          for i = 1, #EMOTE_ROWS do
            local y = 36 + (i - 1) * 14
            if cy >= y - 3 and cy <= y + 11 then
              client:emote(EMOTE_ROWS[i][2])
              game.stack:pop()
              return
            end
          end
        elseif self.view == "chat" then
          -- Chat is a direct Start Menu destination now (no menu stop
          -- first), so touch needs its own way back to the rest of Gen1MMO
          -- (login, friends, whisper, look, disconnect) -- a controller
          -- already has B for that (updateChat). A fixed corner, checked
          -- before the scroll zones below, so it works regardless of
          -- whether there is anything to scroll.
          if cy >= 122 and cx >= 112 then
            self.view = "menu"
            return
          end
          -- top edge pages back through history, bottom edge pages forward
          local maxOff = math.max(0, #buildChatRows() - CHAT_VISIBLE)
          if cy <= 16 and maxOff > 0 then
            self.chatOff = math.min(self.chatOff + CHAT_VISIBLE, maxOff)
            return
          end
          if cy >= 122 and self.chatOff > 0 then
            self.chatOff = math.max(self.chatOff - CHAT_VISIBLE, 0)
            return
          end
          -- Anywhere else: do NOT act yet -- this press might be the START
          -- of a drag-to-scroll rather than a tap to open Say. onRelease
          -- (below) decides which, based on whether onDrag saw real
          -- movement in between. Acting here (the old behavior) would open
          -- Say on every drag's very first frame, before it could move.
          self._chatDragAccum = 0
          self._chatDragMoved = false
        elseif self.view == "look" then
          for i, c in ipairs(CATS) do
            local y = 22 + (i - 1) * 13
            if cy >= y - 2 and cy <= y + 10 and cx < 152 then
              self.lookIndex = i
              local list = Skins.catalog[c[2]]
              local step = (cx >= 64) and 1 or -1    -- tap right side = next
              client.skin[c[1]] = (((client.skin[c[1]] or 0) + step) % #list)
              client:applySkin(client.skin)
              return
            end
          end
        end
      end

      --- Touch drag-to-scroll for the Chat log. cdy is the frame's vertical
      --- movement in CANVAS units (same 160x144 space as onTap's cx/cy) --
      --- main.lua converts LOVE window pixels before calling this. Standard
      --- mobile chat convention: dragging DOWN reveals OLDER messages
      --- (chatOff increases), matching the d-pad UP button's existing
      --- meaning and how pull-to-see-history already works elsewhere.
      function self:onDrag(cdy)
        if self.view ~= "chat" then return end
        self._chatDragAccum = (self._chatDragAccum or 0) + cdy
        if math.abs(self._chatDragAccum) > 4 then self._chatDragMoved = true end
        local ROWH = 12 -- matches drawChat's row spacing
        local maxOff = math.max(0, #buildChatRows() - CHAT_VISIBLE)
        while self._chatDragAccum >= ROWH do
          self.chatOff = math.min(self.chatOff + 1, maxOff)
          self._chatDragAccum = self._chatDragAccum - ROWH
        end
        while self._chatDragAccum <= -ROWH do
          self.chatOff = math.max(self.chatOff - 1, 0)
          self._chatDragAccum = self._chatDragAccum + ROWH
        end
      end

      --- Fires on touch release. Only acts on the Chat view's deferred
      --- middle-of-screen tap (see onTap): opens Say, but ONLY if the
      --- gesture never turned into a drag -- a genuine tap-and-release,
      --- not a scroll that happened to end mid-screen.
      function self:onRelease(cx, cy)
        if self.view == "chat" and not self._chatDragMoved and cy > 16 and cy < 122 then
          self:enterText("SAY:", false, function(t) client:say(self.scope, t) end)
        end
        self._chatDragMoved = false
      end

      -- ----- draw per view
      local function drawMenu()
        Font.drawBox(0, 0, 20, 18)
        Font.draw("GEN1MMO", 16, 8)
        Font.draw(client.status or "", 8, 20)
        local items = menuItems()
        clampMenuScroll(#items)
        for row = 1, MENU_VISIBLE do
          local it = items[self.menuScroll + row]
          if not it then break end
          local y = 36 + (row - 1) * 12
          Font.draw(it[1], 20, y)
          if self.cursor == self.menuScroll + row then
            Font.drawCode(Theme.cursor, 12, y)
          end
        end
        -- scroll indicators on the border rows (also the tap zones)
        if self.menuScroll > 0 then drawUpArrow(144, 0) end
        if self.menuScroll + MENU_VISIBLE < #items then
          Font.drawCode(Theme.moreArrow, 144, 136)
        end
        -- Input diagnostic: shows the last button this screen received and a
        -- counter. If pressing the d-pad here does NOT change "in:.. #.." then
        -- the press is not reaching the mod screen (report this).
        if client.inputDebug then
          Font.draw("in:" .. tostring(self._dbgLast or "-")
            .. " #" .. tostring(self._dbgCount or 0)
            .. " cur:" .. tostring(self.cursor), 8, 138)
        end
      end

      local function drawText()
        Font.drawBox(0, 0, 20, 18)
        Font.draw(self.textPrompt, 8, 8)
        -- show the tail that fits the box (17 glyphs); mask with the
        -- mid-dot, which has a tile ("*" does not)
        local tail = self.buffer:sub(-17)
        local shown = self.textMask and string.rep("·", #tail)
          or (tail:gsub("_", " "))
        Font.draw(shown, 8, 22)
        if not self.textMask then
          for i = 1, #tail do
            if tail:sub(i, i) == "_" then drawUnderscore(8 + (i - 1) * 8, 22) end
          end
        end
        drawUnderscore(8 + #tail * 8, 22) -- the caret
        for r = 1, #GRID do
          for c = 1, #GRID[r] do
            local ch = GRID[r]:sub(c, c)
            local x = 8 + (c - 1) * 14
            local y = 44 + (r - 1) * 16
            local sel = self.gx == c and self.gy == r
            if ch == "_" then
              if sel then Font.draw("[", x - 2, y); Font.draw("]", x + 14, y) end
              drawUnderscore(x + (sel and 6 or 0), y)
            elseif sel then
              Font.draw("[" .. ch .. "]", x - 2, y)
            else
              Font.draw(ch, x, y)
            end
          end
        end
        -- tap zones mirror onTap: left = delete, right = confirm
        Font.draw("DEL", 8, 128)
        Font.draw("tap letters", 52, 128)
        Font.draw("OK", 140, 128)
      end

      local function drawChat()
        Font.drawBox(0, 0, 20, 18)
        -- ">" has no tile; "<scope>" drew as "scope " anyway, so skip it
        Font.draw("CHAT: " .. self.scope, 8, 6)
        -- wrapped rows: nothing is cut off anymore, just paged across rows
        local lines = buildChatRows()
        local maxOff = math.max(0, #lines - CHAT_VISIBLE)
        if self.chatOff > maxOff then self.chatOff = maxOff end
        local last = #lines - self.chatOff
        local start = math.max(1, last - CHAT_VISIBLE + 1)
        for i = start, last do
          local y = 22 + (i - start) * 12
          local line = lines[i]
          -- the server censors profanity to "*", which has no tile; show dots
          Font.draw((line:gsub("%*", "·")), 6, y)
        end
        if self.chatOff < maxOff then drawUpArrow(144, 6) end
        if self.chatOff > 0 then Font.draw("▼", 144, 130) end
        Font.draw("A:say L/R:scp", 6, 130)
        Font.draw("MENU", 116, 130) -- tap zone: onTap's chat branch, cx>=112
      end

      local function drawLook()
        Font.drawBox(0, 0, 20, 18)
        Font.draw("YOUR LOOK", 16, 6)
        for i, c in ipairs(CATS) do
          local list = Skins.catalog[c[2]]
          local val = list[(client.skin[c[1]] or 0) + 1] or "?"
          local y = 22 + (i - 1) * 13
          Font.draw((c[3] .. ": " .. val):sub(1, 17), 16, y)
          if self.lookIndex == i then Font.drawCode(Theme.cursor, 8, y) end
        end
        -- live mannequin, ALL FOUR SIDES at once, stepping in place --
        -- what you will look like from every direction, no guessing
        pcall(function()
          local Tonegen = GEN1MMO_INCLUDE("src/tonegen.lua")
          local def = Tonegen.defFor(client.skin)
          if not def then return end
          if self._previewImage ~= def.image then
            self._previewSR = require("src.render.SpriteRenderer").new(def, "preview")
            self._previewImage = def.image
          end
          local tick = self._lookTick or 0
          local phase = (math.floor(tick / 16) % 2 == 0) and 0 or 1
          local flip = math.floor(tick / 32) % 2 == 0
          local lg = love.graphics
          lg.setColor(0, 0, 0, 1)
          lg.rectangle("line", 34.5, 100.5, 91, 23)
          lg.setColor(1, 1, 1, 1)
          local DIRS = { "down", "left", "up", "right" }
          for d, facing in ipairs(DIRS) do
            self._previewSR:draw(40 + (d - 1) * 22, 104, 0, 0, facing, phase,
              facing == "right" and true or (phase == 1 and flip))
          end
        end)
        Font.draw("L/R:change A:apply", 6, 128)
      end

      -- best milestone becomes the TITLE under the name
      local TITLES = {
        { "hof", "CHAMPION" }, { "dex_150", "DEX MASTER" },
        { "mon_100", "CENTURION" }, { "rich_max", "TYCOON" },
        { "catch_50", "COLLECTOR" }, { "badge_8", "8 BADGES" },
        { "catch_legend", "LEGEND" }, { "dex_100", "DEX 100" },
        { "steps_10k", "WANDERER" }, { "badge_4", "4 BADGES" },
        { "dex_50", "DEX 50" }, { "catch_1", "CATCHER" },
        { "badge_1", "ROOKIE" },
      }
      local function titleFor(milestones)
        local have = {}
        for _, ms in ipairs(milestones or {}) do have[tostring(ms.id)] = true end
        for _, t in ipairs(TITLES) do
          if have[t[1]] then return t[2] end
        end
        return nil
      end

      local function drawPlayer()
        Font.drawBox(0, 0, 20, 18)
        local who = tostring(self.playerTarget or "?")
        Font.draw(who, 16, 6)
        -- trainer card: what they carry, what they've done
        local card = client.cards and client.cards[who]
        local title = card and titleFor(card.milestones)
        -- the title draws beside the name only when it fits WHOLE; a
        -- long name pushes it down to lead the Hist line instead --
        -- never truncated, never clipped
        local titleDrawn = false
        if title then
          local tx = math.max(16 + 8 * #who + 8, 152 - 8 * #title)
          if 152 - tx >= 8 * #title then
            Font.draw(title, tx, 6)
            titleDrawn = true
          end
        end
        local prof = card and card.profile
        if prof then
          Font.draw(("Badges:%d"):format(tonumber(prof.badges) or 0), 12, 18)
          -- the Pokedollar: "$" has no charmap tile, the yen glyph does
          Font.draw(("\194\165%d"):format(tonumber(prof.money) or 0), 92, 18)
          local team = prof.team or {}
          if #team == 0 then Font.draw("No team data", 12, 30) end
          for i = 1, math.min(#team, 6) do
            local mon = team[i]
            Font.draw((tostring(mon.species or "?"):sub(1, 11)
              .. " L" .. tostring(mon.level or 0)), 12, 30 + (i - 1) * 10)
          end
        else
          Font.draw("...", 12, 24)
        end
        -- history badges: the collectible record. One 17-column line, so
        -- show the count plus the most impressive marks first, not the
        -- first 4 the server happened to list.
        if card and card.milestones and #card.milestones > 0 then
          local earned = {}
          for _, ms in ipairs(card.milestones) do earned[tostring(ms.id)] = true end
          local line = (title and not titleDrawn)
            and ("%s %d:"):format(title, #card.milestones)
            or ("Hist %d:"):format(#card.milestones)
          for _, m in ipairs({
            { "hof", "HOF" }, { "dex_150", "D150" }, { "mon_100", "C100" },
            { "rich_max", "TY" }, { "catch_legend", "LGD" }, { "ball_master", "MB" },
            { "catch_50", "C50" },
            { "badge_8", "B8" }, { "dex_100", "D100" }, { "badge_7", "B7" },
            { "badge_6", "B6" }, { "badge_5", "B5" }, { "dex_50", "D50" },
            { "badge_4", "B4" }, { "badge_3", "B3" }, { "badge_2", "B2" },
            { "badge_1", "B1" },
          }) do
            if earned[m[1]] and #line + 1 + #m[2] <= 17 then
              line = line .. " " .. m[2]
            end
          end
          Font.draw(line, 12, 88)
        end
        local items = playerItems()
        for i, it in ipairs(items) do
          local y = 96 + (i - 1) * 12
          Font.draw(it[1], 24, y)
          if self.cursor == i then Font.drawCode(Theme.cursor, 16, y) end
        end
      end

      local function drawEmote()
        Font.drawBox(0, 0, 20, 18)
        Font.draw("EMOTE", 16, 8)
        for i, row in ipairs(EMOTE_ROWS) do
          local y = 36 + (i - 1) * 14
          Font.draw(row[1], 24, y)
          if self.cursor == i then Font.drawCode(Theme.cursor, 16, y) end
        end
        Font.draw("A:send B:back", 12, 128)
      end

      local function drawStats()
        Font.drawBox(0, 0, 20, 18)
        Font.draw("SERVER INFO", 16, 8)
        local s = client.stats
        local hasStats = client.features and client.features.stats
        local rows = {
          "Online: " .. tostring(s and s.population
            or (hasStats and "..." or "n/a")),
          "Channel: " .. tostring((client.channel or 0) + 1)
            .. "/" .. tostring(client.channels or 1),
          "Here: " .. tostring(client.players:count() + 1) .. " players",
          "Ping: " .. (client.pingMs and (client.pingMs .. " ms") or "..."),
          "Mod: " .. tostring(client.version or "?"),
        }
        for i, row in ipairs(rows) do
          Font.draw(row, 12, 28 + (i - 1) * 14)
        end
        Font.draw("A/B: back", 12, 128)
      end

      local function drawKey(code)
        Font.drawBox(0, 0, 20, 18)
        Font.draw("YOUR RECOVERY KEY", 12, 10)
        code = tostring(code or "?")
        -- The full key is wider than the canvas: wrap at the hyphen nearest
        -- the middle so both halves stay inside the 20-tile box.
        local cut = nil
        local mid = math.floor(#code / 2)
        for i = mid, #code do
          if code:sub(i, i) == "-" then cut = i; break end
        end
        if cut then
          Font.draw(code:sub(1, cut - 1), 8, 34)
          Font.draw(code:sub(cut + 1), 8, 48)
        else
          Font.draw(code, 8, 34)
        end
        Font.draw("WRITE IT DOWN NOW.", 8, 72)
        Font.draw("It is the ONLY way", 8, 88)
        Font.draw("to get your account", 8, 100)
        Font.draw("back. No resets.", 8, 112)
        Font.draw("A: I WROTE IT DOWN", 8, 132)
      end

      function self:draw()
        if client.recoveryCode and not client.keyAcknowledged then
          drawKey(client.recoveryCode)
          return
        end
        if self.view == "key" then
          drawKey(mod.save:get("recovery_code", nil) or client.recoveryCode)
          return
        end
        if self.view == "menu" then drawMenu()
        elseif self.view == "text" then drawText()
        elseif self.view == "chat" then drawChat()
        elseif self.view == "look" then drawLook()
        elseif self.view == "player" then drawPlayer()
        elseif self.view == "stats" then drawStats()
        elseif self.view == "emote" then drawEmote()
        elseif self.view == "history" then drawHistory() end
      end

      return self
    end,
  })
end
