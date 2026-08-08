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

      self.view = "menu"          -- menu | text | chat | look | friends
      self.cursor = 1
      self.menuScroll = 0         -- first visible menu row - 1
      self.gx, self.gy = 1, 1     -- grid cursor for text entry
      self.buffer = ""
      self.textPrompt = ""
      self.textOnDone = nil
      self.textMask = false
      self.scope = "map"
      self.chatOff = 0            -- lines scrolled back from the newest
      self.lookIndex = 1

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
            { "Overlay: " .. (client.overlayOn and "ON" or "OFF"), function()
              client.overlayOn = not client.overlayOn
              mod.save:set("chat_overlay", client.overlayOn)
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
            { "Log in", function()
              self:enterText("USERNAME:", false, function(u)
                self:enterText("PASSWORD:", true, function(p)
                  client:connect(client.host, client.port, "login", u, p)
                end)
              end)
            end },
            -- "Set server" is hidden for the beta: the default already points
            -- at the official server, and the row exposed its address. Self-
            -- hosters still override via config.lua / the saved server_host.
            { "Auto-connect: " .. (client.autoConnect and "ON" or "OFF"), function()
              client.autoConnect = not client.autoConnect
              mod.save:set("auto_connect", client.autoConnect)
            end },
            { "Forget login", function()
              client:forgetLogin()
              client.status = "Saved login cleared"
            end },
          }
        end
      end

      function self:enterText(prompt, mask, onDone)
        self.view = "text"
        self.buffer = ""
        self.textPrompt = prompt
        self.textMask = mask
        self.textOnDone = onDone
        self.gx, self.gy = 1, 1
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
          self.view = "menu"
          if cb then cb(self.buffer) end
        end
        if input:wasPressed("b") then self.view = "menu" end
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

      local CATS = { "body", "skin", "hair", "hairColor", "outfit" }
      local CATLIST = { body = "bodies", skin = "skinTones", hair = "hairStyles",
                        hairColor = "hairColors", outfit = "outfits" }
      local function updateLook()
        if input:wasPressed("up") then self.lookIndex = ((self.lookIndex - 2) % #CATS) + 1 end
        if input:wasPressed("down") then self.lookIndex = (self.lookIndex % #CATS) + 1 end
        local cat = CATS[self.lookIndex]
        local list = Skins.catalog[CATLIST[cat]]
        if input:wasPressed("left") then
          client.skin[cat] = ((client.skin[cat] - 1) % #list)
        end
        if input:wasPressed("right") then
          client.skin[cat] = ((client.skin[cat] + 1) % #list)
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
        elseif self.view == "look" then updateLook() end
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
          -- footer actions first (y ~128): left third deletes, right third confirms
          if cy >= 122 then
            if cx <= 54 then
              self.buffer = self.buffer:sub(1, -2)         -- DEL
            elseif cx >= 104 then
              local cb = self.textOnDone; self.view = "menu"; if cb then cb(self.buffer) end
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
          local CATS = { "body", "skin", "hair", "hairColor", "outfit" }
          for i = 1, #CATS do
            local y = 26 + (i - 1) * 14
            if cy >= y - 3 and cy <= y + 11 then
              self.lookIndex = i
              local cat = CATS[i]
              local listName = ({ body = "bodies", skin = "skinTones", hair = "hairStyles",
                hairColor = "hairColors", outfit = "outfits" })[cat]
              local list = Skins.catalog[listName]
              local step = (cx >= 80) and 1 or -1     -- tap right half = next, left = prev
              client.skin[cat] = ((client.skin[cat] + step) % #list)
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
        local CATS2 = { { "Body", "body", "bodies" }, { "Skin", "skin", "skinTones" },
          { "Hair", "hair", "hairStyles" }, { "Colour", "hairColor", "hairColors" },
          { "Outfit", "outfit", "outfits" } }
        for i, c in ipairs(CATS2) do
          local list = Skins.catalog[c[3]]
          local val = list[(client.skin[c[2]] or 0) + 1] or "?"
          local y = 26 + (i - 1) * 14
          Font.draw(c[1] .. ": " .. val, 16, y)
          if self.lookIndex == i then Font.drawCode(Theme.cursor, 8, y) end
        end
        Font.draw("L/R:change A:apply", 6, 128)
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
        elseif self.view == "look" then drawLook() end
      end

      return self
    end,
  })
end
