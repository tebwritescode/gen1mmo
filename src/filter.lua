-- Receive-side filter: the backstop that runs on YOUR machine, so it protects
-- you even if a message reached the server from a modified client
-- (COMPELLED-DISCLOSURE.md 7 in the server repo). The server already censors
-- public chat; this re-censors on display and is the only filter available for
-- incoming whispers.
--
-- Deliberately light vs the server's version -- it is a safety net, not the
-- primary control. Profanity is starred; obvious links are masked.

local Filter = {}

local LEET = {
  ["0"] = "o", ["1"] = "i", ["3"] = "e", ["4"] = "a",
  ["5"] = "s", ["7"] = "t", ["@"] = "a", ["$"] = "s",
}

-- Small default list; the server carries the authoritative one.
local WORDS = {
  "fuck", "shit", "bitch", "cunt", "faggot", "nigger", "nigga", "asshole",
}

local ALLOW = { "class", "assess", "grass", "pass", "bass" }

local function fold(word)
  local out = word:lower():gsub(".", function(c) return LEET[c] or c end)
  return (out:gsub("[^a-z]", ""))
end

local FOLDED_WORDS = {}
for _, w in ipairs(WORDS) do FOLDED_WORDS[#FOLDED_WORDS + 1] = fold(w) end
local ALLOW_SET = {}
for _, w in ipairs(ALLOW) do ALLOW_SET[fold(w)] = true end

--- Censor profanity in a display string, masking whole tokens with asterisks.
function Filter.censor(text)
  if type(text) ~= "string" then return text end
  return (text:gsub("%S+", function(token)
    local folded = fold(token)
    if folded == "" or ALLOW_SET[folded] then return token end
    for _, w in ipairs(FOLDED_WORDS) do
      if folded:find(w, 1, true) then
        return string.rep("*", #token)
      end
    end
    return token
  end))
end

--- Detect an obvious link/advertisement (for graying out or hiding).
function Filter.looksLikeLink(text)
  if type(text) ~= "string" then return false end
  local t = text:lower():gsub("%s*%.%s*", "."):gsub("%s+dot%s+", ".")
  if t:find("http", 1, true) or t:find("www.", 1, true) then return true end
  if t:find("%d+%.%d+%.%d+%.%d+") then return true end
  for _, host in ipairs({ "discord", "t.me", "youtu", "twitch", "tiktok", "bit.ly" }) do
    if t:find(host, 1, true) then return true end
  end
  -- Lua patterns have no alternation, so check a domained token against a
  -- TLD set explicitly.
  local tld = t:match("[%w%-]+%.([%a]+)")
  if tld then
    local TLDS = { com=1, net=1, org=1, gg=1, io=1, tv=1, xyz=1, link=1, me=1, co=1 }
    if TLDS[tld] then return true end
  end
  return false
end

--- Full display pass: censor, and mask links entirely.
function Filter.display(text)
  if Filter.looksLikeLink(text) then
    return "[link hidden]"
  end
  return Filter.censor(text)
end

return Filter
