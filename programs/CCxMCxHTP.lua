-- startup
-- HackThePlanet CC & MineColonies Program installer
-- Installs v2.2.4 by patching the verified v2.2.0 installer.

local VERSION = "2.2.4"
local SOURCE_URL = "https://raw.githubusercontent.com/sayrejeri/CC-Tweaked-Programs/5ef48867ea72b1f857cd61c47375042b5dc90b59/programs/CCxMCxHTP.lua"

local function fail(message)
    term.setTextColor(colors.red)
    print("")
    print("HTP v" .. VERSION .. " install failed:")
    print(tostring(message))
    term.setTextColor(colors.white)
    error(message, 0)
end

local function replaceFirst(source, oldText, newText, label)
    local first, last = source:find(oldText, 1, true)
    if not first then fail("Patch point missing: " .. label) end
    return source:sub(1, first - 1) .. newText .. source:sub(last + 1)
end

term.setBackgroundColor(colors.black)
term.setTextColor(colors.white)
term.clear()
term.setCursorPos(1, 1)
print("HackThePlanet Colony Supply")
print("Preparing verified v" .. VERSION .. " installer...")

local response, requestError = http.get(SOURCE_URL, nil, true)
if not response then fail(requestError or "Unable to download verified v2.2.0 installer") end
local installer = response.readAll()
response.close()
if not installer or installer == "" then fail("Downloaded installer was empty") end

installer = replaceFirst(
    installer,
    "-- Installs verified version 2.2.0 from the verified v2.1.0 source bundle.",
    "-- Installs verified version 2.2.4 from the verified v2.1.0 source bundle.",
    "installer comment"
)

installer = replaceFirst(
    installer,
    'local VERSION = "2.2.0"\nlocal SOURCE_VERSION = "2.1.0"',
    'local VERSION = "2.2.4"\nlocal SOURCE_VERSION = "2.1.0"',
    "installer version"
)

installer = replaceFirst(
    installer,
    'decoded = replaceLiteral(decoded, "-- Version: 2.1.0", "-- Version: 2.2.0", "version comment")',
    'decoded = replaceLiteral(decoded, "-- Version: 2.1.0", "-- Version: 2.2.4", "version comment")',
    "runtime version comment"
)

installer = replaceFirst(
    installer,
    [[decoded = replaceLiteral(decoded, 'local VERSION = "2.1.0"', 'local VERSION = "2.2.0"', "runtime version")]],
    [[decoded = replaceLiteral(decoded, 'local VERSION = "2.1.0"', 'local VERSION = "2.2.4"', "runtime version")]],
    "runtime version"
)

local insertionPoint = [[decoded = replaceLiteral(decoded,
    '    craftJobsFile = "htp_craft_jobs.cfg",\n',]]

local rackPatch = [[decoded = replaceLiteral(decoded,
    '        "^entangledtile_",\n',
    '        "^entangledtile_",\n' ..
    '        "^entangled:tile_",\n',
    "colon Entangled Block peripheral names"
)

]]

installer = replaceFirst(
    installer,
    insertionPoint,
    rackPatch .. insertionPoint,
    "warehouse rack name matcher"
)

local backupListPatchPoint = [[    local files = {
        "startup",
        CONFIG.settingsFile,]]

local backupListReplacement = [[    local files = {
        CONFIG.settingsFile,]]

installer = replaceFirst(
    installer,
    backupListPatchPoint,
    backupListReplacement,
    "exclude startup from floppy backup"
)

local backupRootPoint = [[    local root = fs.combine(BACKUP.mount, CONFIG.backupFolder)
    if not fs.exists(root) then fs.makeDir(root) end

    local files = {]]

local backupRootReplacement = [[    local root = fs.combine(BACKUP.mount, CONFIG.backupFolder)
    if not fs.exists(root) then fs.makeDir(root) end

    -- Older versions copied the full startup program to the floppy and could fill it.
    local oldStartupBackup = fs.combine(root, "startup")
    if fs.exists(oldStartupBackup) then pcall(function() fs.delete(oldStartupBackup) end) end

    local files = {]]

installer = replaceFirst(
    installer,
    backupRootPoint,
    backupRootReplacement,
    "remove oversized legacy startup backup"
)

local unsafeWritePoint = [[    output.write(data or "")
    output.close()
    return true]]

local safeWriteReplacement = [[    local okWrite = pcall(function()
        output.write(data or "")
    end)
    output.close()

    if not okWrite then
        pcall(function()
            if fs.exists(destination) then fs.delete(destination) end
        end)
        return false
    end
    return true]]

installer = replaceFirst(
    installer,
    unsafeWritePoint,
    safeWriteReplacement,
    "safe floppy write"
)

local compilePoint = [[local compiled, compileError = load(decoded, "@startup.new")]]

local cacheSafeUpdaterPatch = [====[
local cacheSafeUpdateCode = [==[
local function updateProgram()
    local temp = "startup.new"
    if fs.exists(temp) then fs.delete(temp) end

    local freshUrl = RAW_URL .. "?cache=" .. tostring(now())
    local response, requestError = http.get(freshUrl, nil, true)
    if not response then
        recordError("Update download failed: " .. text(requestError))
        action("Update download failed", colors.red, true)
        return
    end

    local body = response.readAll()
    response.close()
    if not body or body == "" then
        recordError("Update download returned an empty file")
        action("Update file was empty", colors.red, true)
        return
    end

    local compiled, syntaxError = load(body, "@startup.new")
    if not compiled then
        recordError("Downloaded updater syntax error: " .. text(syntaxError))
        action("Downloaded update failed syntax check", colors.red, true)
        return
    end

    local file = fs.open(temp, "wb") or fs.open(temp, "w")
    if not file then
        recordError("Could not create " .. temp)
        action("Could not save update", colors.red, true)
        return
    end
    file.write(body)
    file.close()

    pcall(function() backupNow(true) end)
    if fs.exists("startup.bak") then fs.delete("startup.bak") end
    if fs.exists("startup") then fs.move("startup", "startup.bak") end
    fs.move(temp, "startup")
    action("Fresh updater downloaded. Rebooting.", colors.lime, true)
    sleep(1)
    os.reboot()
end

]==]

decoded = replaceBetween(
    decoded,
    "local function updateProgram()",
    "local function drawControl(countdown)",
    cacheSafeUpdateCode,
    "cache-safe program updater"
)

]====]

installer = replaceFirst(
    installer,
    compilePoint,
    cacheSafeUpdaterPatch .. compilePoint,
    "cache-safe updater patch"
)

local compiled, compileError = load(installer, "@htp_v224_installer")
if not compiled then fail("Patched installer syntax error: " .. tostring(compileError)) end

term.setTextColor(colors.lime)
print("Rack detection patch loaded.")
print("Oversized floppy startup backup removed.")
print("Disk-full backup crashes are now handled safely.")
print("Future updates will bypass raw GitHub cache.")
term.setTextColor(colors.white)
compiled()
