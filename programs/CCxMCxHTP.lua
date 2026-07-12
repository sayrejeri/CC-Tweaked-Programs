-- startup
-- HackThePlanet Colony Supply v3.0.1 bootstrap installer

local VERSION = "3.0.1"
local BASE_INSTALLER_COMMIT = "5fac61ead096bdfdce9dca321ccefb85eda2de8d"
local BASE_INSTALLER_URL = "https://raw.githubusercontent.com/sayrejeri/CC-Tweaked-Programs/" .. BASE_INSTALLER_COMMIT .. "/programs/CCxMCxHTP.lua"

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
print("Preparing Full Automation Suite v" .. VERSION .. "...")

local cache = os.epoch and os.epoch("utc") or math.floor(os.clock() * 1000)
local response, requestError = http.get(BASE_INSTALLER_URL .. "?cache=" .. tostring(cache), nil, true)
if not response then fail(requestError or "Unable to download verified v3 installer") end
local installer = response.readAll()
response.close()
if not installer or installer == "" then fail("Downloaded installer was empty") end

installer = replacePlain(
    installer,
    'local VERSION = "3.0.0"',
    'local VERSION = "3.0.1"',
    "installer version"
)

local syntaxMarker = [[    if entry.syntax then]]
local modulePatches = [====[
    -- v3.0.1 module hotfixes are applied only after the pinned source passes
    -- its original size and checksum verification.
    if entry.source == "programs/htp3/backup.lua" then
        local oldText = [==[
    local function safeName(path)
        return path:gsub("^/", ""):gsub("/", "__")
    end
]==]
        local newText = [==[
    local function safeName(path)
        local cleaned = path:gsub("^/", "")
        cleaned = cleaned:gsub("/", "__")
        return cleaned
    end
]==]
        local first, last = body:find(oldText, 1, true)
        if not first then fail("backup.lua safeName patch point missing") end
        body = body:sub(1, first - 1) .. newText .. body:sub(last + 1)
    elseif entry.source == "programs/htp3/config.lua" then
        local oldText = '        version = "3.0.0",'
        local newText = '        version = "3.0.1",'
        local first, last = body:find(oldText, 1, true)
        if not first then fail("config.lua version patch point missing") end
        body = body:sub(1, first - 1) .. newText .. body:sub(last + 1)
    end

]====]

installer = replacePlain(
    installer,
    syntaxMarker,
    modulePatches .. syntaxMarker,
    "verified module hotfix injection"
)

local compiled, syntaxError = load(installer, "@htp_v301_installer")
if not compiled then fail("Patched installer syntax error: " .. tostring(syntaxError)) end

setColor(colors.lime)
print("Backup filename crash fix loaded.")
print("Launching verified installer...")
setColor(colors.white)
sleep(1)
compiled()
