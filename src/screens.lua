-- The Gen1MMO screen: menu, text entry, chat, and the look editor -- all drawn
-- with the confirmed toolkit only (mod.ui.Font + game.input), so no widget API
-- is guessed. Text entry is a self-contained d-pad letter grid, since the GB
-- input model has no keyboard.
--
-- One screen, several "views". B backs out a view or pops the screen.

local Skins = GEN1MMO_INCLUDE("src/skins.lua")

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
      end

      local input = game.input

      -- ----- helpers
      local function withRecoveryRow(items)
        if mod.save:get("recovery_code", nil) or client.recoveryCode then
          items[#items + 1] = { "Recovery key", function() self.view = "key" end }
        end
        return items
      end

      local function menuItems()
        if client.state == "playing" then
          return withRecoveryRow {
            { "Chat", function() self.view = "chat" end },
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
            { "Server info", function()
              client:requestStats()
              self.view = "stats"
            end },
            { "Overlay: " .. (client.overlayOn and "ON" or "OFF"), function()
              client.overlayOn = not client.overlayOn
              mod.save:set("chat_overlay", client.overlayOn)
            end },
            { "Chat box", function() self.view = "chatbox" end },
            { "Geek stats: " .. (client.geekStats and "ON" or "OFF"), function()
              client.geekStats = not client.geekStats
              mod.save:set("geek_stats", client.geekStats)
            end },
            { "Disconnect", function() client:disconnect() end },
          }
        else
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
            { "Auto-connect: " .. (client.autoConnect and "ON" or "OFF"), function()
              client.autoConnect = not client.autoConnect
              mod.save:set("auto_connect", client.autoConnect)
            end },
            { "Chat box", function() self.view = "chatbox" end },
            { "Geek stats: " .. (client.geekStats and "ON" or "OFF"), function()
              client.geekStats = not client.geekStats
              mod.save:set("geek_stats", client.geekStats)
            end },
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
        pcall(function() love.keyboard.setTextInput(true) end)
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
      local function playerItems()
        local who = self.playerTarget or "?"
        return {
          { "Whisper", function()
            self:enterText("TO " .. who .. ":", false, function(t)
              client:whisper(who, t)
              client:log("(to " .. who .. ") " .. t)
            end)
          end },
          { "Add friend", function()
            client:addFriend(who)
            client:log("Friend request sent to " .. who .. ".")
          end },
          { "Close", function() game.stack:pop() end },
        }
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

      local function updateStats()
        -- keep the figures live while the screen is up (server cooldown 2s)
        self._statsTick = (self._statsTick or 0) + 1
        if self._statsTick % 150 == 0 then client:requestStats() end
        if input:wasPressed("a") or input:wasPressed("b") then self.view = "menu" end
      end

      -- chat-box panel tuning: each row cycles through fixed steps
      local CHATBOX_ROWS = {
        { "Size",   "size",  { 0.5, 0.65, 0.75, 0.85, 1.0 }, "%d%%" },
        { "Text",   "text",  { 0.4, 0.6, 0.8, 1.0 },          "%d%%" },
        { "Backgr", "bg",    { 0, 0.25, 0.5, 0.7, 0.85, 1.0 }, "%d%%" },
        { "Lines",  "lines", { 2, 3, 4, 6 },                   "%d" },
      }
      self.cbIndex = 1

      local function cbStep(row, dirn)
        local steps = row[3]
        local cur = client.ovl[row[2]]
        local at = 1
        for i, v in ipairs(steps) do
          if math.abs(v - (cur or steps[1])) < 0.001 then at = i break end
        end
        at = ((at - 1 + dirn) % #steps) + 1
        client.ovl[row[2]] = steps[at]
        mod.save:set("ovl_" .. row[2], steps[at])
      end

      local function updateChatbox()
        if input:wasPressed("up") then
          self.cbIndex = self.cbIndex > 1 and self.cbIndex - 1 or #CHATBOX_ROWS
        end
        if input:wasPressed("down") then
          self.cbIndex = self.cbIndex < #CHATBOX_ROWS and self.cbIndex + 1 or 1
        end
        if input:wasPressed("left") then cbStep(CHATBOX_ROWS[self.cbIndex], -1) end
        if input:wasPressed("right") then cbStep(CHATBOX_ROWS[self.cbIndex], 1) end
        if input:wasPressed("b") or input:wasPressed("a") then self.view = "menu" end
      end

      local function updateChat()
        local maxOff = math.max(0, #client.chat - CHAT_VISIBLE)
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
        elseif self.view == "chatbox" then updateChatbox() end
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
        elseif self.view == "stats" then
          self.view = "menu"
        elseif self.view == "chatbox" then
          for i = 1, #CHATBOX_ROWS do
            local y = 28 + (i - 1) * 14
            if cy >= y - 3 and cy <= y + 11 then
              self.cbIndex = i
              cbStep(CHATBOX_ROWS[i], (cx >= 80) and 1 or -1)
              return
            end
          end
          self.view = "menu" -- tap outside the rows backs out
        elseif self.view == "chat" then
          -- top edge pages back through history, bottom edge pages forward;
          -- anywhere else opens Say (the pre-scroll behavior)
          local maxOff = math.max(0, #client.chat - CHAT_VISIBLE)
          if cy <= 16 and maxOff > 0 then
            self.chatOff = math.min(self.chatOff + CHAT_VISIBLE, maxOff)
            return
          end
          if cy >= 122 and self.chatOff > 0 then
            self.chatOff = math.max(self.chatOff - CHAT_VISIBLE, 0)
            return
          end
          self:enterText("SAY:", false, function(t) client:say(self.scope, t) end)
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
        local lines = client.chat
        local maxOff = math.max(0, #lines - CHAT_VISIBLE)
        if self.chatOff > maxOff then self.chatOff = maxOff end
        local last = #lines - self.chatOff
        local start = math.max(1, last - CHAT_VISIBLE + 1)
        for i = start, last do
          local y = 22 + (i - start) * 12
          local line = lines[i]
          if #line > 18 then line = line:sub(1, 18) end -- 18 glyphs fit the box
          -- the server censors profanity to "*", which has no tile; show dots
          Font.draw((line:gsub("%*", "·")), 6, y)
        end
        if self.chatOff < maxOff then drawUpArrow(144, 6) end
        if self.chatOff > 0 then Font.draw("▼", 144, 130) end
        -- "=" has no tile either; ":" does
        Font.draw("A:say L/R:scope", 6, 130)
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

      local function drawPlayer()
        Font.drawBox(0, 0, 20, 18)
        local who = tostring(self.playerTarget or "?")
        Font.draw(who, 16, 6)
        -- trainer card: what they carry, what they've done
        local card = client.cards and client.cards[who]
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
        local items = playerItems()
        for i, it in ipairs(items) do
          local y = 96 + (i - 1) * 12
          Font.draw(it[1], 24, y)
          if self.cursor == i then Font.drawCode(Theme.cursor, 16, y) end
        end
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

      local function drawChatbox()
        Font.drawBox(0, 0, 20, 18)
        Font.draw("CHAT BOX", 16, 8)
        for i, row in ipairs(CHATBOX_ROWS) do
          local v = client.ovl[row[2]] or row[3][1]
          local shown = row[2] == "lines" and tostring(v)
            or (tostring(math.floor(v * 100 + 0.5)) .. " pct")
          local y = 28 + (i - 1) * 14
          Font.draw(row[1] .. ": " .. shown, 16, y)
          if self.cbIndex == i then Font.drawCode(Theme.cursor, 8, y) end
        end
        Font.draw("L/R:adjust A/B:back", 8, 116)
        -- live preview of the current opacity/size mix
        Font.draw("Sample chat line", 8, 132)
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
        elseif self.view == "chatbox" then drawChatbox() end
      end

      return self
    end,
  })
end
