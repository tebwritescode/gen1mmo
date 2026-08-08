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

return function(mod, client)
  mod.content.screens:register("Gen1MMO", {
    new = function(game)
      local Font = mod.ui.Font
      local self = { game = game, isOpaque = true }

      self.view = "menu"          -- menu | text | chat | look | friends
      self.cursor = 1
      self.gx, self.gy = 1, 1     -- grid cursor for text entry
      self.buffer = ""
      self.textPrompt = ""
      self.textOnDone = nil
      self.textMask = false
      self.scope = "map"
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
            { "Set server (" .. tostring(client.host) .. ")", function()
              self:enterText("HOST:", false, function(h)
                if #h > 0 then client:setServer(h, client.port) end
              end)
            end },
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

      -- ----- update per view
      local function updateMenu()
        local items = menuItems()
        if input:wasPressed("up") then self.cursor = math.max(1, self.cursor - 1) end
        if input:wasPressed("down") then self.cursor = math.min(#items, self.cursor + 1) end
        if input:wasPressed("a") and items[self.cursor] then items[self.cursor][2]() end
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

      function self:update(dt)
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

      -- ----- draw per view
      local function drawMenu()
        Font.drawBox(0, 0, 20, 18)
        Font.draw("GEN1MMO", 16, 8)
        Font.draw(client.status or "", 8, 20)
        local items = menuItems()
        for i, it in ipairs(items) do
          local y = 36 + (i - 1) * 12
          Font.draw((self.cursor == i and ">" or " ") .. it[1], 12, y)
        end
      end

      local function drawText()
        Font.drawBox(0, 0, 20, 18)
        Font.draw(self.textPrompt, 8, 8)
        local shown = self.textMask and string.rep("*", #self.buffer) or self.buffer
        Font.draw(shown .. "_", 8, 22)
        for r = 1, #GRID do
          for c = 1, #GRID[r] do
            local ch = GRID[r]:sub(c, c)
            local x = 8 + (c - 1) * 14
            local y = 44 + (r - 1) * 16
            if self.gx == c and self.gy == r then
              Font.draw("[" .. ch .. "]", x - 2, y)
            else
              Font.draw(ch, x, y)
            end
          end
        end
        Font.draw("A=pick SEL=del START=ok", 8, 128)
      end

      local function drawChat()
        Font.drawBox(0, 0, 20, 18)
        Font.draw("CHAT <" .. self.scope .. ">", 8, 6)
        local lines = client.chat
        local start = math.max(1, #lines - 8)
        for i = start, #lines do
          local y = 22 + (i - start) * 12
          local line = lines[i]
          if #line > 26 then line = line:sub(1, 26) end
          Font.draw(line, 6, y)
        end
        Font.draw("A=say L/R=scope B=back", 6, 130)
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
          Font.draw((self.lookIndex == i and ">" or " ") .. c[1] .. ": " .. val, 8, y)
        end
        Font.draw("L/R change A=apply B=back", 6, 128)
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
