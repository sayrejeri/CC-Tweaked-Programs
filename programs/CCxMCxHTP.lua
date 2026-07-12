-- startup
-- HackThePlanet Colony Supply v3.0.3 bootstrap installer

local VERSION = "3.0.3"
local BASE_INSTALLER_COMMIT = "9e02be2ebf256e76d8618dded824c57b1a723c18"
local PATCH_COMMIT = "57673d3156c300c4bc8b4529666e05d2cd0b5a98"
local BASE_INSTALLER_URL = "https://raw.githubusercontent.com/sayrejeri/CC-Tweaked-Programs/" .. BASE_INSTALLER_COMMIT .. "/programs/CCxMCxHTP.lua"
local PATCH_URL = "https://raw.githubusercontent.com/sayrejeri/CC-Tweaked-Programs/" .. PATCH_COMMIT .. "/programs/htp3/fix_buttons_v303.lua"

local function setColor(color)
    if term.isColor and term.isColor() then term.setTextColor(color) end
end

local function fail(message)
    setColor(colors.red)
    print("")
    print("HTP v" .. VERSION .. " bootstrap failed:")
    print(tostring(message))
    setColor(colors.white)
    error(message, 0)
end

local function replacePlain(source, oldText, newText, label)
    local first, last = source:find(oldText, 1, true)
    if not first then fail("Patch point missing: " .. label) end
    return source:sub(1, first - 1) .. newText .. source:sub(last + 1)
end

term.setBackgroundColor(colors.black)
setColor(colors.white)
term.clear()
term.setCursorPos(1, 1)
print("HackThePlanet Colony Supply")
print("Preparing larger-button command center v" .. VERSION .. "...")

local cache = os.epoch and os.epoch("utc") or math.floor(os.clock() * 1000)
local response, requestError = http.get(BASE_INSTALLER_URL .. "?cache=" .. tostring(cache), nil, true)
if not response then fail(requestError or "Unable to download verified v3.0.2 installer") end
local installer = response.readAll()
response.close()
if not installer or installer == "" then fail("Downloaded installer was empty") end

installer = replacePlain(installer, 'local VERSION = "3.0.2"', 'local VERSION = "3.0.3"', "installer version")
installer = replacePlain(installer, 'print("Installing Responsive Command Center v" .. VERSION)', 'print("Installing Larger Button Command Center v" .. VERSION)', "installer title")
installer = replacePlain(installer, 'if fs.exists("startup.pre-v302") then fs.delete("startup.pre-v302") end', 'if fs.exists("startup.pre-v303") then fs.delete("startup.pre-v303") end', "startup backup delete")
installer = replacePlain(installer, 'if fs.exists("startup") then fs.move("startup", "startup.pre-v302") end', 'if fs.exists("startup") then fs.move("startup", "startup.pre-v303") end', "startup backup move")
installer = replacePlain(installer, 'print("Large control monitors now use the full responsive command center.")', 'print("Large control monitor buttons are taller and separated from status text.")', "success message")

local installMarker = [[for _, entry in ipairs(FILES) do
    local source = stagedPath(entry.destination)
    local destination = entry.destination
    local parent = fs.getDir(destination)
    if parent ~= "" then ensureDir(parent) end
    if fs.exists(destination) then fs.delete(destination) end
    fs.move(source, destination)
end

cleanupStage()]]

local installReplacement = [[for _, entry in ipairs(FILES) do
    local source = stagedPath(entry.destination)
    local destination = entry.destination
    local parent = fs.getDir(destination)
    if parent ~= "" then ensureDir(parent) end
    if fs.exists(destination) then fs.delete(destination) end
    fs.move(source, destination)
end

print("Applying v3.0.3 button layout patch...")
local patchResponse, patchRequestError = http.get("]] .. PATCH_URL .. [[?cache=" .. tostring(os.epoch and os.epoch("utc") or math.floor(os.clock() * 1000)), nil, true)
if not patchResponse then fail(patchRequestError or "Unable to download v3.0.3 button patch") end
local patchBody = patchResponse.readAll()
patchResponse.close()
if not patchBody or patchBody == "" then fail("Button patch download was empty") end
local patchCompiled, patchSyntaxError = load(patchBody, "@htp3/fix_buttons_v303.lua")
if not patchCompiled then fail("Button patch syntax error: " .. tostring(patchSyntaxError)) end
local patchSaved, patchSaveError = writeAll("/htp3/fix_buttons_v303.lua", patchBody)
if not patchSaved then fail(patchSaveError) end
local patchOk, patchRunError = pcall(patchCompiled)
if not patchOk then fail("Button patch failed: " .. tostring(patchRunError)) end

cleanupStage()]]

installer = replacePlain(installer, installMarker, installReplacement, "button patch installation")

local compiled, syntaxError = load(installer, "@htp_v303_installer")
if not compiled then fail("Patched installer syntax error: " .. tostring(syntaxError)) end

setColor(colors.lime)
print("Larger button patch loaded.")
print("Launching verified installer...")
setColor(colors.white)
sleep(1)
compiled()
