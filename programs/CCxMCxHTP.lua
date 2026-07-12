-- startup
-- HackThePlanet Colony Supply v3.0.6 installer and recovery updater

local VERSION = "3.0.6"
local BASE_INSTALLER_COMMIT = "a2687093cf94b30f24c9e8bae7d92dfc53dfeb8c"
local RECOVERY_COMMIT = "7ce676b5c37f740a775e2f99ea087dfe6ec0c366"
local BASE_INSTALLER_URL = "https://raw.githubusercontent.com/sayrejeri/CC-Tweaked-Programs/" .. BASE_INSTALLER_COMMIT .. "/programs/CCxMCxHTP.lua"
local RECOVERY_URL = "https://raw.githubusercontent.com/sayrejeri/CC-Tweaked-Programs/" .. RECOVERY_COMMIT .. "/programs/htp3/recover_v306.lua"

local function setColor(color)
    if term.isColor and term.isColor() then term.setTextColor(color) end
end

local function fail(message)
    setColor(colors.red)
    print("")
    print("HTP v" .. VERSION .. " update failed:")
    print(tostring(message))
    setColor(colors.white)
    error(message, 0)
end

local function download(url)
    local cache = os.epoch and os.epoch("utc") or math.floor(os.clock() * 1000)
    local response, err = http.get(url .. "?cache=" .. tostring(cache), nil, true)
    if not response then return nil, err or "HTTP request failed" end
    local body = response.readAll()
    response.close()
    if not body or body == "" then return nil, "empty response" end
    return body
end

local function runRecovery()
    local body, err = download(RECOVERY_URL)
    if not body then fail("Recovery download failed: " .. tostring(err)) end
    local compiled, syntaxError = load(body, "@htp3/recover_v306.lua")
    if not compiled then fail("Recovery syntax error: " .. tostring(syntaxError)) end
    local ok, runError = pcall(compiled)
    if not ok then fail("Recovery failed: " .. tostring(runError)) end
end

term.setBackgroundColor(colors.black)
setColor(colors.white)
term.clear()
term.setCursorPos(1, 1)
print("HackThePlanet Colony Supply")
print("Installing recovery update v" .. VERSION .. "...")
print("")

if fs.exists("/htp3/main.lua") then
    runRecovery()
    return
end

print("No existing v3 installation found.")
print("Installing the verified v3 base first...")
local installer, installerError = download(BASE_INSTALLER_URL)
if not installer then fail("Base installer download failed: " .. tostring(installerError)) end
local compiled, syntaxError = load(installer, "@htp_v304_installer")
if not compiled then fail("Base installer syntax error: " .. tostring(syntaxError)) end

local originalReboot = os.reboot
local rebootMarker = "__HTP_V306_CONTINUE__"
os.reboot = function() error(rebootMarker, 0) end
local installOk, installError = pcall(compiled)
os.reboot = originalReboot
if not installOk and tostring(installError) ~= rebootMarker then
    fail("Base installation failed: " .. tostring(installError))
end
if not fs.exists("/htp3/main.lua") then fail("Base installer did not create /htp3/main.lua") end

print("")
print("Applying v3.0.6 recovery...")
runRecovery()
