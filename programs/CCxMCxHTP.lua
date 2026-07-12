-- startup
-- HackThePlanet Colony Supply v3.0.4 installer and updater

local VERSION = "3.0.4"
local BASE_INSTALLER_COMMIT = "9e02be2ebf256e76d8618dded824c57b1a723c18"
local PATCH_COMMIT = "472313f78aea563bf5b1ad863f832af2d9d3fe96"
local BASE_INSTALLER_URL = "https://raw.githubusercontent.com/sayrejeri/CC-Tweaked-Programs/" .. BASE_INSTALLER_COMMIT .. "/programs/CCxMCxHTP.lua"
local PATCH_URL = "https://raw.githubusercontent.com/sayrejeri/CC-Tweaked-Programs/" .. PATCH_COMMIT .. "/programs/htp3/fix_button_render_v304.lua"

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

local function runPatch()
    local body, err = download(PATCH_URL)
    if not body then fail("Button patch download failed: " .. tostring(err)) end
    local compiled, syntaxError = load(body, "@htp3/fix_button_render_v304.lua")
    if not compiled then fail("Button patch syntax error: " .. tostring(syntaxError)) end
    local ok, runError = pcall(compiled)
    if not ok then fail("Button patch failed: " .. tostring(runError)) end
end

term.setBackgroundColor(colors.black)
setColor(colors.white)
term.clear()
term.setCursorPos(1, 1)
print("HackThePlanet Colony Supply")
print("Installing button rendering fix v" .. VERSION .. "...")
print("")

if fs.exists("/htp3/main.lua") and fs.exists("/htp3/ui_parts/01.lua.part") then
    runPatch()
    setColor(colors.lime)
    print("")
    print("HTP Colony Supply v" .. VERSION .. " installed.")
    setColor(colors.white)
    print("Rebooting...")
    sleep(2)
    os.reboot()
end

print("No existing v3 installation found.")
print("Installing the verified v3 base first...")
local installer, installerError = download(BASE_INSTALLER_URL)
if not installer then fail("Base installer download failed: " .. tostring(installerError)) end

local oldTail = [[print("Rebooting...")
sleep(2)
os.reboot()]]

local newTail = [[print("Applying v3.0.4 button rendering fix...")
local patchUrl = "]] .. PATCH_URL .. [["
local patchCache = os.epoch and os.epoch("utc") or math.floor(os.clock() * 1000)
local patchResponse, patchError = http.get(patchUrl .. "?cache=" .. tostring(patchCache), nil, true)
if not patchResponse then fail(patchError or "Unable to download v3.0.4 button patch") end
local patchBody = patchResponse.readAll()
patchResponse.close()
if not patchBody or patchBody == "" then fail("v3.0.4 button patch was empty") end
local patchCompiled, patchSyntaxError = load(patchBody, "@htp3/fix_button_render_v304.lua")
if not patchCompiled then fail("v3.0.4 button patch syntax error: " .. tostring(patchSyntaxError)) end
local patchOk, patchRunError = pcall(patchCompiled)
if not patchOk then fail("v3.0.4 button patch failed: " .. tostring(patchRunError)) end
print("Rebooting...")
sleep(2)
os.reboot()]]

local first, last = installer:find(oldTail, 1, true)
if not first then fail("Base installer reboot patch point missing") end
installer = installer:sub(1, first - 1) .. newTail .. installer:sub(last + 1)

local compiled, syntaxError = load(installer, "@htp_v304_installer")
if not compiled then fail("Combined installer syntax error: " .. tostring(syntaxError)) end
compiled()
