-- Encrypted tunnel primitives in pure Lua, matching the server
-- (src/crypto/tunnel.ts + identity.ts): X25519 key agreement, ChaCha20-Poly1305
-- framing, HKDF-SHA256, and Ed25519 signature verification of the pinned key.
--
-- NUMERIC MODEL. LÖVE runs LuaJIT, where Lua numbers are IEEE doubles (exact
-- integers only up to 2^53). Every routine here is written to stay within that
-- budget: ChaCha uses the bit library normalised to unsigned 32-bit, and the
-- curve/field code uses TweetNaCl's 16x16-bit limb layout (products < 2^53).
-- The same code therefore runs identically under Lua 5.4 (the test harness) and
-- LuaJIT (the game) -- validated byte-for-byte against Node's crypto.

local bit = rawget(_G, "bit") or require("bit")
local band, bor, bxor = bit.band, bit.bor, bit.bxor
local lshift, rshift = bit.lshift, bit.rshift

local Tunnel = {}

local TWO32 = 4294967296
local function u32(x) return x % TWO32 end                 -- normalise to [0,2^32)
local function rotl(x, n) return u32(bor(lshift(band(x, 0xFFFFFFFF), n), rshift(band(x, 0xFFFFFFFF), 32 - n))) end

-- ---------------------------------------------------------------- ChaCha20

local function chachaBlock(key, counter, nonce, out)
  -- key: 8 u32 (LE from 32 bytes), counter: u32, nonce: 3 u32
  local s = {
    0x61707865, 0x3320646e, 0x79622d32, 0x6b206574,
    key[1], key[2], key[3], key[4], key[5], key[6], key[7], key[8],
    counter, nonce[1], nonce[2], nonce[3],
  }
  local x = {}
  for i = 1, 16 do x[i] = s[i] end
  local function qr(a, b, c, d)
    x[a] = u32(x[a] + x[b]); x[d] = bxor(x[d], x[a]); x[d] = rotl(x[d], 16)
    x[c] = u32(x[c] + x[d]); x[b] = bxor(x[b], x[c]); x[b] = rotl(x[b], 12)
    x[a] = u32(x[a] + x[b]); x[d] = bxor(x[d], x[a]); x[d] = rotl(x[d], 8)
    x[c] = u32(x[c] + x[d]); x[b] = bxor(x[b], x[c]); x[b] = rotl(x[b], 7)
  end
  for _ = 1, 10 do
    qr(1, 5, 9, 13); qr(2, 6, 10, 14); qr(3, 7, 11, 15); qr(4, 8, 12, 16)
    qr(1, 6, 11, 16); qr(2, 7, 12, 13); qr(3, 8, 9, 14); qr(4, 5, 10, 15)
  end
  for i = 1, 16 do
    local v = u32(x[i] + s[i])
    local o = (i - 1) * 4
    out[o + 1] = band(v, 0xFF); out[o + 2] = band(rshift(v, 8), 0xFF)
    out[o + 3] = band(rshift(v, 16), 0xFF); out[o + 4] = band(rshift(v, 24), 0xFF)
  end
end

local function bytesToKeyWords(key32)
  local k = {}
  for i = 0, 7 do
    local o = i * 4 + 1
    k[i + 1] = u32(key32:byte(o) + key32:byte(o + 1) * 256
      + key32:byte(o + 2) * 65536 + key32:byte(o + 3) * 16777216)
  end
  return k
end

--- ChaCha20 keystream XOR. nonce is 12 bytes; initial counter as given.
local function chacha20(key32, counter0, nonce12, data)
  local key = bytesToKeyWords(key32)
  local nonce = {}
  for i = 0, 2 do
    local o = i * 4 + 1
    nonce[i + 1] = u32(nonce12:byte(o) + nonce12:byte(o + 1) * 256
      + nonce12:byte(o + 2) * 65536 + nonce12:byte(o + 3) * 16777216)
  end
  local out, block = {}, {}
  local counter = counter0
  local n = #data
  local pos = 1
  while pos <= n do
    chachaBlock(key, u32(counter), nonce, block)
    counter = counter + 1
    for i = 1, 64 do
      if pos > n then break end
      out[pos] = string.char(bxor(data:byte(pos), block[i]))
      pos = pos + 1
    end
  end
  return table.concat(out)
end

Tunnel.chacha20 = chacha20

-- ---------------------------------------------------------------- Poly1305

-- Poly1305 in base 2^26 limbs (5 limbs), products fit in doubles.
local function poly1305(msg, key32)
  local r0 = band(key32:byte(1) + key32:byte(2) * 256 + key32:byte(3) * 65536 + key32:byte(4) * 16777216, 0x3ffffff)
  local r1 = band(rshift(key32:byte(4) + key32:byte(5) * 256 + key32:byte(6) * 65536 + key32:byte(7) * 16777216, 2), 0x3ffff03)
  -- simpler: derive r as 4 32-bit words then clamp, then split -- do it explicitly
  local function le32(s, o) return s:byte(o) + s:byte(o + 1) * 256 + s:byte(o + 2) * 65536 + s:byte(o + 3) * 16777216 end
  local t0, t1, t2, t3 = le32(key32, 1), le32(key32, 5), le32(key32, 9), le32(key32, 13)
  -- clamp
  local rr0 = band(t0, 0x0fffffff)
  local rr1 = band(t1, 0x0ffffffc)
  local rr2 = band(t2, 0x0ffffffc)
  local rr3 = band(t3, 0x0ffffffc)
  -- split into 5 base-2^26 limbs
  local R0 = band(rr0, 0x3ffffff)
  local R1 = band(bor(rshift(rr0, 26), lshift(rr1, 6)), 0x3ffffff)
  local R2 = band(bor(rshift(rr1, 20), lshift(rr2, 12)), 0x3ffffff)
  local R3 = band(bor(rshift(rr2, 14), lshift(rr3, 18)), 0x3ffffff)
  local R4 = band(rshift(rr3, 8), 0x3ffffff)
  local S1, S2, S3, S4 = R1 * 5, R2 * 5, R3 * 5, R4 * 5
  local h0, h1, h2, h3, h4 = 0, 0, 0, 0, 0
  local pos, n = 1, #msg
  while pos <= n do
    local blk = {}
    local len = math.min(16, n - pos + 1)
    for i = 1, 16 do blk[i] = (i <= len) and msg:byte(pos + i - 1) or 0 end
    local m0 = blk[1] + blk[2] * 256 + blk[3] * 65536 + blk[4] * 16777216
    local m1 = blk[5] + blk[6] * 256 + blk[7] * 65536 + blk[8] * 16777216
    local m2 = blk[9] + blk[10] * 256 + blk[11] * 65536 + blk[12] * 16777216
    local m3 = blk[13] + blk[14] * 256 + blk[15] * 65536 + blk[16] * 16777216
    h0 = h0 + band(m0, 0x3ffffff)
    h1 = h1 + band(bor(rshift(m0, 26), lshift(m1, 6)), 0x3ffffff)
    h2 = h2 + band(bor(rshift(m1, 20), lshift(m2, 12)), 0x3ffffff)
    h3 = h3 + band(bor(rshift(m2, 14), lshift(m3, 18)), 0x3ffffff)
    local hibit = (len == 16) and 0x1000000 or 0
    -- add the 2^128 bit only for full blocks; for the final short block set at bit 8*len
    if len < 16 then
      -- set bit at position 8*len within the 130-bit number
      local bitpos = 8 * len
      local limb = math.floor(bitpos / 26)
      local off = bitpos % 26
      local addv = lshift(1, off)
      if limb == 0 then h0 = h0 + addv elseif limb == 1 then h1 = h1 + addv
      elseif limb == 2 then h2 = h2 + addv elseif limb == 3 then h3 = h3 + addv
      else h4 = h4 + addv end
      h4 = h4 + band(rshift(m3, 8), 0x3ffffff)
    else
      h4 = h4 + band(rshift(m3, 8), 0x3ffffff) + hibit
    end
    -- multiply (h * r) mod p
    local d0 = h0 * R0 + h1 * S4 + h2 * S3 + h3 * S2 + h4 * S1
    local d1 = h0 * R1 + h1 * R0 + h2 * S4 + h3 * S3 + h4 * S2
    local d2 = h0 * R2 + h1 * R1 + h2 * R0 + h3 * S4 + h4 * S3
    local d3 = h0 * R3 + h1 * R2 + h2 * R1 + h3 * R0 + h4 * S4
    local d4 = h0 * R4 + h1 * R3 + h2 * R2 + h3 * R1 + h4 * R0
    -- carry
    local c
    c = math.floor(d0 / 0x4000000); h0 = d0 % 0x4000000; d1 = d1 + c
    c = math.floor(d1 / 0x4000000); h1 = d1 % 0x4000000; d2 = d2 + c
    c = math.floor(d2 / 0x4000000); h2 = d2 % 0x4000000; d3 = d3 + c
    c = math.floor(d3 / 0x4000000); h3 = d3 % 0x4000000; d4 = d4 + c
    c = math.floor(d4 / 0x4000000); h4 = d4 % 0x4000000; h0 = h0 + c * 5
    c = math.floor(h0 / 0x4000000); h0 = h0 % 0x4000000; h1 = h1 + c
    pos = pos + 16
  end
  -- final carry/reduce
  local c
  c = math.floor(h1 / 0x4000000); h1 = h1 % 0x4000000; h2 = h2 + c
  c = math.floor(h2 / 0x4000000); h2 = h2 % 0x4000000; h3 = h3 + c
  c = math.floor(h3 / 0x4000000); h3 = h3 % 0x4000000; h4 = h4 + c
  c = math.floor(h4 / 0x4000000); h4 = h4 % 0x4000000; h0 = h0 + c * 5
  c = math.floor(h0 / 0x4000000); h0 = h0 % 0x4000000; h1 = h1 + c
  -- compute h + -p to check if >= p, then select
  local g0 = h0 + 5; c = math.floor(g0 / 0x4000000); g0 = g0 % 0x4000000
  local g1 = h1 + c; c = math.floor(g1 / 0x4000000); g1 = g1 % 0x4000000
  local g2 = h2 + c; c = math.floor(g2 / 0x4000000); g2 = g2 % 0x4000000
  local g3 = h3 + c; c = math.floor(g3 / 0x4000000); g3 = g3 % 0x4000000
  local g4 = h4 + c - 0x4000000
  local mask = (g4 < 0) and 0xffffffff or 0  -- if g4 negative, h < p, keep h
  -- select g if mask==0 (h>=p)
  local nmask = bxor(mask, 0xffffffff)
  h0 = bor(band(h0, mask), band(g0, nmask))
  h1 = bor(band(h1, mask), band(g1, nmask))
  h2 = bor(band(h2, mask), band(g2, nmask))
  h3 = bor(band(h3, mask), band(g3, nmask))
  h4 = bor(band(h4, mask), band(g4 % 0x4000000, nmask))
  -- serialize h as 128-bit little-endian, then add s (key[17..32])
  local f0 = bor(h0, band(lshift(h1, 26), 0xFFFFFFFF)) % TWO32
  local f1 = bor(bor(rshift(h1, 6), lshift(h2, 20)), 0) % TWO32
  local f2 = bor(bor(rshift(h2, 12), lshift(h3, 14)), 0) % TWO32
  local f3 = bor(bor(rshift(h3, 18), lshift(h4, 8)), 0) % TWO32
  local function le32k(o) return key32:byte(o) + key32:byte(o + 1) * 256 + key32:byte(o + 2) * 65536 + key32:byte(o + 3) * 16777216 end
  local acc = { f0, f1, f2, f3 }
  local s = { le32k(17), le32k(21), le32k(25), le32k(29) }
  local tag = {}
  local carry = 0
  for i = 1, 4 do
    local v = acc[i] + s[i] + carry
    carry = math.floor(v / TWO32)
    v = v % TWO32
    local o = (i - 1) * 4
    tag[o + 1] = band(v, 0xFF); tag[o + 2] = band(rshift(v, 8), 0xFF)
    tag[o + 3] = band(rshift(v, 16), 0xFF); tag[o + 4] = band(rshift(v, 24), 0xFF)
  end
  local out = {}
  for i = 1, 16 do out[i] = string.char(tag[i]) end
  return table.concat(out)
end

Tunnel.poly1305 = poly1305

-- ---------------------------------------------------------------- AEAD

local function pad16(n) local r = n % 16; return r == 0 and 0 or (16 - r) end

--- ChaCha20-Poly1305 (RFC 8439). Returns ciphertext .. tag(16). No AAD (the
--- server uses none). nonce is 12 bytes.
function Tunnel.aeadSeal(key32, nonce12, plaintext)
  local polyKey = chacha20(key32, 0, nonce12, string.rep("\0", 32))
  local ct = chacha20(key32, 1, nonce12, plaintext)
  local mac = string.rep("\0", pad16(#ct))
  local lenBlock = {}
  local aadLen, ctLen = 0, #ct
  for i = 0, 7 do lenBlock[i + 1] = string.char(band(rshift(aadLen, i * 8), 0xFF)) end
  for i = 0, 7 do lenBlock[i + 9] = string.char(band(math.floor(ctLen / (2 ^ (i * 8))), 0xFF)) end
  local tag = poly1305(ct .. mac .. table.concat(lenBlock), polyKey)
  return ct .. tag
end

--- Returns plaintext, or nil on tag mismatch.
function Tunnel.aeadOpen(key32, nonce12, sealed)
  if #sealed < 16 then return nil end
  local ct = sealed:sub(1, #sealed - 16)
  local tag = sealed:sub(#sealed - 15)
  local polyKey = chacha20(key32, 0, nonce12, string.rep("\0", 32))
  local mac = string.rep("\0", pad16(#ct))
  local lenBlock = {}
  local ctLen = #ct
  for i = 0, 7 do lenBlock[i + 1] = "\0" end
  for i = 0, 7 do lenBlock[i + 9] = string.char(band(math.floor(ctLen / (2 ^ (i * 8))), 0xFF)) end
  local expect = poly1305(ct .. mac .. table.concat(lenBlock), polyKey)
  if expect ~= tag then return nil end
  return chacha20(key32, 1, nonce12, ct)
end

return Tunnel
