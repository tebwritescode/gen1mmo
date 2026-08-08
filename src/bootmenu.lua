-- The ONLINE entry on the title menu (before any game exists): register or
-- log in with the server RIGHT THERE, then either continue the SERVER-SIDE
-- character or start a new one (starter picked here, recorded by the server
-- via char_new). There is no local-save loading in online mode: the vanilla
-- NEW GAME path boots a fresh world and the server owns the character.
--
-- Same self-contained toolkit as screens.lua: Font + game.input + a d-pad
-- letter grid. B backs out a view or pops back to the title.

local GRID = {
  "ABCDEFGHIJ",
  "KLMNOPQRST",
  "UVWXYZ0123",
  "456789_.-!",
}

return function(mod, client)
  mod.content.screens:register("Gen1MMOOnline", {
    new = function(game, launchNewGame)
      local Font = mod.ui.Font
      local self = { game = game, isOpaque = true }

      self.view = "menu" -- menu | text | starter | summary
      self.cursor = 1
      self.gx, self.gy = 1, 1
      self.buffer = ""
      self.textPrompt = ""
      self.textOnDone = nil
      self.textMask = false
      self.starterIndex = 1
      self.phase = "auth" -- auth -> char (after welcome + char_get)

      local input = game.input
      local STARTERS = { "BULBASAUR", "CHARMANDER", "SQUIRTLE" }

      -- launch the engine's own fresh-game path, flagged online
      local function launch()
        client.online = true
        if launchNewGame then launchNewGame() end
      end

      local function menuItems()
        if client.state ~= "playing" then
          return {
            { "Log in", function()
              self:enterText("USERNAME:", false, function(u)
                self:enterText("PASSWORD:", true, function(p)
                  client:connect(client.host, client.port, "login", u, p)
                end)
              end)
            end },
            { "Register (new)", function()
              self:enterText("USERNAME:", false, function(u)
                self:enterText("PASSWORD:", true, function(p)
                  client:connect(client.host, client.port, "register", u, p)
                end)
              end)
            end },
            { "Set server (" .. tostring(client.host) .. ")", function()
              self:enterText("HOST:", false, function(h)
                if #h > 0 then client:setServer(h, client.port) end
              end)
            end },
          }
        end
        -- authenticated: offer the server character
        if client.charState then
          return {
            { "Continue (online)", function() self.view = "summary" end },
            { "New game (wipes character)", function() self.view = "starter" end },
            { "Log out", function() client:disconnect(); self.phase = "auth" end,
            },
          }
        end
        return {
          { "New game (online)", function() self.view = "starter" end },
          { "Log out", function() client:disconnect(); self.phase = "auth" end },
        }
      end

      function self:enterText(prompt, mask, onDone)
        self.view = "text"
        self.buffer = ""
        self.textPrompt = prompt
        self.textMask = mask
        self.textOnDone = onDone
        self.gx, self.gy = 1, 1
      end

      -- ----- update
      local function updateMenu()
        -- once authenticated, fetch the character exactly once
        if client.state == "playing" and self.phase == "auth" then
          self.phase = "char"
          client:charGet()
        end
        local items = menuItems()
        if self.cursor > #items then self.cursor = #items end
        if input:wasPressed("up") then self.cursor = math.max(1, self.cursor - 1) end
        if input:wasPressed("down") then self.cursor = math.min(#items, self.cursor + 1) end
        if input:wasPressed("a") and items[self.cursor] then items[self.cursor][2]() end
        if input:wasPressed("b") then
          game.stack:pop()
        end
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
        if input:wasPressed("select") then self.buffer = self.buffer:sub(1, -2) end
        if input:wasPressed("start") then
          local cb = self.textOnDone
          self.view = "menu"
          if cb then cb(self.buffer) end
        end
        if input:wasPressed("b") then self.view = "menu" end
      end

      local function updateStarter()
        if input:wasPressed("up") then self.starterIndex = ((self.starterIndex - 2) % #STARTERS) + 1 end
        if input:wasPressed("down") then self.starterIndex = (self.starterIndex % #STARTERS) + 1 end
        if input:wasPressed("a") then
          -- confirm = true also covers the wipe-and-restart path
          client:charNew(STARTERS[self.starterIndex], client.charState ~= nil)
          self.view = "menu"
          self.launchOnOk = true
        end
        if input:wasPressed("b") then self.view = "menu" end
      end

      local function updateSummary()
        if input:wasPressed("a") then launch() end
        if input:wasPressed("b") then self.view = "menu" end
      end

      function self:update(dt)
        -- a fresh recovery key owns the screen until acknowledged
        if client.recoveryCode and not client.keyAcknowledged then
          if input:wasPressed("a") then client.keyAcknowledged = true end
          return
        end
        -- char_new acknowledged -> boot the fresh world
        if self.launchOnOk and client.charRev and client.charRev >= 1 then
          self.launchOnOk = nil
          launch()
          return
        end
        if self.view == "menu" then updateMenu()
        elseif self.view == "text" then updateText()
        elseif self.view == "starter" then updateStarter()
        elseif self.view == "summary" then updateSummary() end
      end

      -- ----- draw
      local function drawKey(code)
        Font.drawBox(0, 0, 20, 18)
        Font.draw("YOUR RECOVERY KEY", 12, 10)
        code = tostring(code or "?")
        local cut = nil
        for i = math.floor(#code / 2), #code do
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

      local function drawMenu()
        Font.drawBox(0, 0, 20, 18)
        Font.draw("GEN1MMO ONLINE", 16, 8)
        Font.draw(client.status or "", 8, 22)
        local items = menuItems()
        for i, it in ipairs(items) do
          Font.draw((self.cursor == i and ">" or " ") .. it[1], 10, 40 + (i - 1) * 14)
        end
        Font.draw("Your save lives on", 8, 108)
        Font.draw("the server.", 8, 120)
        Font.draw("B: back to title", 8, 136)
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
        Font.draw("A:pick SEL:del ST:ok", 8, 128)
      end

      local function drawStarter()
        Font.drawBox(0, 0, 20, 18)
        Font.draw("CHOOSE YOUR STARTER", 8, 10)
        for i, s in ipairs(STARTERS) do
          Font.draw((self.starterIndex == i and ">" or " ") .. s, 16, 34 + (i - 1) * 16)
        end
        Font.draw("The server records", 8, 96)
        Font.draw("your choice.", 8, 108)
        Font.draw("A: begin  B: back", 8, 132)
      end

      local function drawSummary()
        Font.drawBox(0, 0, 20, 18)
        Font.draw("SERVER CHARACTER", 12, 8)
        local st = client.charState
        if st then
          local y = 26
          for i, mon in ipairs(st.party or {}) do
            if i <= 6 then
              Font.draw(tostring(mon.species) .. " L" .. tostring(mon.level), 10, y)
              y = y + 12
            end
          end
          Font.draw("MONEY " .. tostring(st.money or 0), 10, y + 4)
          Font.draw("MAP " .. tostring(st.map or "?"), 10, y + 16)
        end
        Font.draw("A: play  B: back", 8, 136)
      end

      function self:draw()
        if client.recoveryCode and not client.keyAcknowledged then
          drawKey(client.recoveryCode)
          return
        end
        if self.view == "menu" then drawMenu()
        elseif self.view == "text" then drawText()
        elseif self.view == "starter" then drawStarter()
        elseif self.view == "summary" then drawSummary() end
      end

      return self
    end,
  })
end
