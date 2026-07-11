-- startup
-- HackThePlanet CC & MineColonies Program installer
-- Installs verified version 2.1.0

local VERSION = "2.1.0"
local PART_COUNT = 10
local EXPECTED_SIZE = 84156
local EXPECTED_ADLER32 = 978141490
local BASE_URL = "https://raw.githubusercontent.com/sayrejeri/CC-Tweaked-Programs/main/.htp_patch_v210/"

local function fail(message)
    term.setTextColor(colors.red)
    print("HTP v" .. VERSION .. " install failed:")
    print(tostring(message))
    term.setTextColor(colors.white)
    print("Your current installer was not replaced. Reboot or run startup to retry.")
    error(message, 0)
end

local function download(url)
    local response, err = http.get(url, nil, true)
    if not response then return nil, err or "HTTP request failed" end
    local body = response.readAll()
    response.close()
    if not body or body == "" then return nil, "empty response" end
    return body
end

local function decodeBase64(data)
    if textutils.decodeBase64 then
        local ok, decoded = pcall(textutils.decodeBase64, data)
        if ok and decoded then return decoded end
    end

    local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    data = data:gsub("[^" .. alphabet .. "=]", "")
    local bits = data:gsub(".", function(character)
        if character == "=" then return "" end
        local value = alphabet:find(character, 1, true)
        if not value then return "" end
        value = value - 1
        local output = ""
        for bit = 6, 1, -1 do
            output = output .. (value % (2 ^ bit) - value % (2 ^ (bit - 1)) > 0 and "1" or "0")
        end
        return output
    end)

    return bits:gsub("%d%d%d?%d?%d?%d?%d?%d?", function(byteBits)
        if #byteBits ~= 8 then return "" end
        local value = 0
        for index = 1, 8 do
            if byteBits:sub(index, index) == "1" then value = value + 2 ^ (8 - index) end
        end
        return string.char(value)
    end)
end

local function adler32(data)
    local a, b = 1, 0
    for index = 1, #data do
        a = (a + data:byte(index)) % 65521
        b = (b + a) % 65521
    end
    return b * 65536 + a
end

term.setBackgroundColor(colors.black)
term.setTextColor(colors.white)
term.clear()
term.setCursorPos(1, 1)
print("HackThePlanet Colony Supply")
print("Installing verified v" .. VERSION .. "...")
print("")

local encodedParts = {}
for index = 0, PART_COUNT - 1 do
    local filename = string.format("part%02d.txt", index)
    write("Downloading " .. filename .. "... ")
    local body, err = download(BASE_URL .. filename)
    if not body then
        print("FAILED")
        fail(filename .. ": " .. tostring(err))
    end
    encodedParts[#encodedParts + 1] = body:gsub("%s+", "")
    print("OK")
end

print("Assembling program...")
local decoded = decodeBase64(table.concat(encodedParts))
if not decoded then fail("Base64 decoding returned no data") end
if #decoded ~= EXPECTED_SIZE then
    fail("Size mismatch: expected " .. EXPECTED_SIZE .. ", got " .. #decoded)
end

local checksum = adler32(decoded)
if checksum ~= EXPECTED_ADLER32 then
    fail("Checksum mismatch: expected " .. EXPECTED_ADLER32 .. ", got " .. checksum)
end

if not decoded:find("%-%- Version: 2%.1%.0", 1) then
    fail("Version marker is missing")
end

local compiled, compileError = load(decoded, "@startup.new", "t", _ENV)
if not compiled then fail("Lua syntax check failed: " .. tostring(compileError)) end

local temporary = "startup.new"
local backup = "startup.v2-backup"
if fs.exists(temporary) then fs.delete(temporary) end
local file = fs.open(temporary, "wb") or fs.open(temporary, "w")
if not file then fail("Could not create " .. temporary) end
file.write(decoded)
file.close()

if fs.exists(backup) then fs.delete(backup) end
if fs.exists("startup") then fs.move("startup", backup) end
fs.move(temporary, "startup")

term.setTextColor(colors.lime)
print("")
print("HTP Colony Supply v" .. VERSION .. " installed successfully.")
print("Exact framed variants and multi-rack warehouse output are enabled.")
term.setTextColor(colors.white)
print("Rebooting...")
sleep(2)
os.reboot()
