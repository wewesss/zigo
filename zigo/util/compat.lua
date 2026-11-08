local M = {}

---@type fun(n: any): "integer"|"float"|nil
M.mathType = math.type or function(n)
    if type(n) ~= "number" then return nil end
    if n ~= n or n == math.huge or n == -math.huge then return "float" end
    return (math.floor(n) == n) and "integer" or "float"
end

local find, byte, sub, gsub = string.find, string.byte, string.sub, string.gsub
local type, tonumber = type, tonumber

local ffi
if type(jit) == "table" then
    local ok, lib = pcall(require, "ffi")
    if ok and type(lib) == "table" and lib.istype then ffi = lib end
end

M.ffi = ffi
M.istype = ffi and ffi.istype or nil
M.int64Type = ffi and ffi.typeof("int64_t") or nil
M.nativeInt64 = math.maxinteger ~= nil and math.maxinteger > 2 ^ 53

local SAFE = 2 ^ 53
local mathType = M.mathType

if M.nativeInt64 then
    M.isInt64 = function(v)
        if type(v) ~= "number" then return false end
        return mathType(v) == "integer" or (v >= -SAFE and v <= SAFE and v % 1 == 0)
    end
elseif ffi then
    local istype, int64T = ffi.istype, M.int64Type
    M.isInt64 = function(v)
        if type(v) == "number" then
            return v >= -SAFE and v <= SAFE and v % 1 == 0
        end
        return istype(int64T, v)
    end
else
    M.isInt64 = function(v)
        return type(v) == "number" and v >= -SAFE and v <= SAFE and v % 1 == 0
    end
end

if M.nativeInt64 then
    M.parseInt64 = function(s)
        if not find(s, "^%-?%d+$") then return false end
        local n = tonumber(s)
        if mathType(n) == "integer" then return true, n end
        if byte(s, 1) == 45 then return false, "too_small", math.mininteger, n, "integer" end
        return false, "too_big", math.maxinteger, n, "integer"
    end
elseif ffi then
    local new, cast, int64T = ffi.new, ffi.cast, M.int64Type
    local uint64T = ffi.typeof("uint64_t")
    local posLimit = new(uint64T, 2147483648) * 4294967296 - 1
    local negLimit = posLimit + 1
    M.parseInt64 = function(s)
        if not find(s, "^%-?%d+$") then return false end
        local neg = byte(s, 1) == 45
        if #s <= 15 then return true, new(int64T, tonumber(s)) end
        local digits = gsub(neg and sub(s, 2) or s, "^0+", "")
        local over = #digits > 19
        local u
        if not over then
            u = new(uint64T, 0)
            for i = 1, #digits do u = u * 10 + (byte(digits, i) - 48) end
            over = u > (neg and negLimit or posLimit)
        end
        if over then
            if neg then return false, "too_small", cast(int64T, negLimit), tonumber(s), "integer" end
            return false, "too_big", cast(int64T, posLimit), tonumber(s), "integer"
        end
        local r = cast(int64T, u)
        if neg then r = -r end
        return true, r
    end
else
    M.parseInt64 = function(s)
        if not find(s, "^%-?%d+$") then return false end
        local neg = byte(s, 1) == 45
        local digits = gsub(neg and sub(s, 2) or s, "^0+", "")
        local n = tonumber(s)
        if #digits > 16 or (#digits == 16 and digits > "9007199254740992") then
            if n == nil then n = neg and -math.huge or math.huge end
            if neg then return false, "too_small", -SAFE, n, "integer" end
            return false, "too_big", SAFE, n, "integer"
        end
        if n == 0 then n = 0 end
        return true, n
    end
end

local HIGH = "[\128-\255]"

---@type fun(s: string): integer|nil
M.utf8Length = function(s)
    local i = find(s, HIGH)
    if not i then return #s end
    local len = #s
    local n = i - 1
    local run = 0
    while i <= len do
        local c = byte(s, i)
        if c < 0x80 then
            n = n + 1
            i = i + 1
            run = run + 1
            if run == 16 then
                local j = find(s, HIGH, i)
                if not j then return n + (len - i + 1) end
                n = n + (j - i)
                i = j
                run = 0
            end
        else
            run = 0
            if c < 0xC2 then
                return nil
            elseif c < 0xE0 then
                local c2 = byte(s, i + 1)
                if not c2 or c2 < 0x80 or c2 > 0xBF then return nil end
                i = i + 2
            elseif c < 0xF0 then
                local c2, c3 = byte(s, i + 1, i + 2)
                if not c3 or c2 < 0x80 or c2 > 0xBF or c3 < 0x80 or c3 > 0xBF then return nil end
                if c == 0xE0 and c2 < 0xA0 then return nil end
                if c == 0xED and c2 > 0x9F then return nil end
                i = i + 3
            elseif c < 0xF5 then
                local c2, c3, c4 = byte(s, i + 1, i + 3)
                if not c4 or c2 < 0x80 or c2 > 0xBF or c3 < 0x80 or c3 > 0xBF or c4 < 0x80 or c4 > 0xBF then
                    return nil
                end
                if c == 0xF0 and c2 < 0x90 then return nil end
                if c == 0xF4 and c2 > 0x8F then return nil end
                i = i + 4
            else
                return nil
            end
            n = n + 1
        end
    end
    return n
end

local nativeTableType = table.type

local function pureIsArray(t)
    local n = #t
    if n == 0 then return next(t) == nil end
    local count = 0
    for k in pairs(t) do
        count = count + 1
        if type(k) ~= "number" or k % 1 ~= 0 or k < 1 or k > n then
            return false
        end
    end
    return count == n
end

---@type fun(t: any): boolean
M.isArray = nativeTableType
    and function(t)
        if type(t) ~= "table" then return false end
        local kind = nativeTableType(t)
        if kind == "hash" or kind == "mixed" then return false end
        return pureIsArray(t)
    end
    or function(t)
        if type(t) ~= "table" then return false end
        return pureIsArray(t)
    end

M.rawlen = rawlen or function(t) return #t end

return M
