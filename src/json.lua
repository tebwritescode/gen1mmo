-- Minimal JSON for the Gen1MMO wire protocol.
--
-- Our frames are flat-ish objects of strings, numbers, booleans, null, nested
-- objects, and arrays -- no NaN, no huge precision needs. This encoder/decoder
-- covers exactly that, kept small so it can be read in full.
--
-- Returned as a module: local Json = include("src/json.lua")

local Json = {}

-- ---------------------------------------------------------------- encode

local ESCAPES = {
  ['"'] = '\\"', ['\\'] = '\\\\', ['\n'] = '\\n', ['\r'] = '\\r',
  ['\t'] = '\\t', ['\b'] = '\\b', ['\f'] = '\\f',
}

local function encodeString(s)
  local out = s:gsub('[%z\1-\31\\"]', function(c)
    return ESCAPES[c] or string.format('\\u%04x', c:byte())
  end)
  return '"' .. out .. '"'
end

local function isArray(t)
  local n = 0
  for k in pairs(t) do
    if type(k) ~= "number" then return false end
    n = n + 1
  end
  return n == #t
end

local function encodeValue(v)
  local tv = type(v)
  if tv == "nil" then return "null"
  elseif tv == "boolean" then return v and "true" or "false"
  elseif tv == "number" then
    if v ~= v or v == math.huge or v == -math.huge then return "null" end
    if math.floor(v) == v then return string.format("%d", v) end
    return string.format("%.14g", v)
  elseif tv == "string" then return encodeString(v)
  elseif tv == "table" then
    if isArray(v) then
      local parts = {}
      for i = 1, #v do parts[i] = encodeValue(v[i]) end
      return "[" .. table.concat(parts, ",") .. "]"
    end
    local parts = {}
    for k, val in pairs(v) do
      parts[#parts + 1] = encodeString(tostring(k)) .. ":" .. encodeValue(val)
    end
    return "{" .. table.concat(parts, ",") .. "}"
  end
  return "null"
end

function Json.encode(v)
  return encodeValue(v)
end

-- ---------------------------------------------------------------- decode

local decodeValue

local function skipWs(s, i)
  local _, e = s:find("^[ \t\r\n]*", i)
  return (e or i - 1) + 1
end

local UNESCAPES = {
  ['"'] = '"', ['\\'] = '\\', ['/'] = '/', ['n'] = '\n', ['r'] = '\r',
  ['t'] = '\t', ['b'] = '\b', ['f'] = '\f',
}

local function decodeString(s, i)
  -- s[i] == '"'
  local buf, j = {}, i + 1
  while j <= #s do
    local c = s:sub(j, j)
    if c == '"' then return table.concat(buf), j + 1
    elseif c == '\\' then
      local n = s:sub(j + 1, j + 1)
      if n == 'u' then
        local hex = s:sub(j + 2, j + 5)
        local code = tonumber(hex, 16) or 0
        if code < 128 then buf[#buf + 1] = string.char(code)
        else buf[#buf + 1] = "?" end -- non-ASCII: our charset is ASCII anyway
        j = j + 6
      else
        buf[#buf + 1] = UNESCAPES[n] or n
        j = j + 2
      end
    else
      buf[#buf + 1] = c
      j = j + 1
    end
  end
  error("unterminated string")
end

local function decodeNumber(s, i)
  local _, e = s:find("^-?%d+%.?%d*[eE]?[+-]?%d*", i)
  local num = s:sub(i, e)
  return tonumber(num), e + 1
end

local function decodeArray(s, i)
  local arr, j = {}, skipWs(s, i + 1)
  if s:sub(j, j) == "]" then return arr, j + 1 end
  while true do
    local v
    v, j = decodeValue(s, j)
    arr[#arr + 1] = v
    j = skipWs(s, j)
    local c = s:sub(j, j)
    if c == "]" then return arr, j + 1 end
    if c ~= "," then error("expected , or ] in array") end
    j = skipWs(s, j + 1)
  end
end

local function decodeObject(s, i)
  local obj, j = {}, skipWs(s, i + 1)
  if s:sub(j, j) == "}" then return obj, j + 1 end
  while true do
    if s:sub(j, j) ~= '"' then error("expected string key") end
    local key
    key, j = decodeString(s, j)
    j = skipWs(s, j)
    if s:sub(j, j) ~= ":" then error("expected :") end
    local v
    v, j = decodeValue(s, skipWs(s, j + 1))
    obj[key] = v
    j = skipWs(s, j)
    local c = s:sub(j, j)
    if c == "}" then return obj, j + 1 end
    if c ~= "," then error("expected , or } in object") end
    j = skipWs(s, j + 1)
  end
end

function decodeValue(s, i)
  i = skipWs(s, i)
  local c = s:sub(i, i)
  if c == '"' then return decodeString(s, i)
  elseif c == "{" then return decodeObject(s, i)
  elseif c == "[" then return decodeArray(s, i)
  elseif c == "t" then return true, i + 4
  elseif c == "f" then return false, i + 5
  elseif c == "n" then return nil, i + 4
  else return decodeNumber(s, i) end
end

--- Decode a full JSON string. Returns (value) or (nil, errorMessage).
function Json.decode(s)
  local ok, v = pcall(function()
    local val = decodeValue(s, 1)
    return val
  end)
  if ok then return v end
  return nil, v
end

return Json
