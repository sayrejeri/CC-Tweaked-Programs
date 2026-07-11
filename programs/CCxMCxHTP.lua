-- startup
-- HackThePlanet CC & MineColonies Program installer
-- Installs verified version 2.2.0 from the verified v2.1.0 source bundle.

local VERSION = "2.2.0"
local SOURCE_VERSION = "2.1.0"
local EXPECTED_SIZE = 84156
local EXPECTED_ADLER32 = 978141490
local BASE_URL = "https://raw.githubusercontent.com/sayrejeri/CC-Tweaked-Programs/main/.htp_patch_v210/"

local PART_FILES = {
    "part00_0.txt", "part00_1.txt", "part00_2.txt",
    "part01.txt",
    "part02_0.txt", "part02_1.txt", "part02_2.txt",
    "part03.txt",
    "part04_0.txt", "part04_1.txt", "part04_2.txt",
    "part05.txt", "part06.txt", "part07.txt", "part08.txt", "part09.txt"
}

local function fail(message)
    term.setTextColor(colors.red)
    print("")
    print("HTP v" .. VERSION .. " install failed:")
    print(tostring(message))
    term.setTextColor(colors.white)
    print("")
    print("The verified program was not installed.")
    print("Run startup again to retry.")
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
        local position = alphabet:find(character, 1, true)
        if not position then return "" end
        local value = position - 1
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
            if byteBits:sub(index, index) == "1" then
                value = value + 2 ^ (8 - index)
            end
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

local function replaceLiteral(source, oldText, newText, label)
    local first, last = source:find(oldText, 1, true)
    if not first then fail("Patch point missing: " .. label) end
    return source:sub(1, first - 1) .. newText .. source:sub(last + 1)
end

local function replaceBetween(source, startMarker, endMarker, replacement, label)
    local first = source:find(startMarker, 1, true)
    if not first then fail("Patch start missing: " .. label) end
    local last = source:find(endMarker, first + #startMarker, true)
    if not last then fail("Patch end missing: " .. label) end
    return source:sub(1, first - 1) .. replacement .. source:sub(last)
end

term.setBackgroundColor(colors.black)
term.setTextColor(colors.white)
term.clear()
term.setCursorPos(1, 1)
print("HackThePlanet Colony Supply")
print("Installing verified v" .. VERSION .. "...")
print("")

local encodedParts = {}
for index, filename in ipairs(PART_FILES) do
    write("[" .. index .. "/" .. #PART_FILES .. "] " .. filename .. "... ")
    local body, err = download(BASE_URL .. filename)
    if not body then
        print("FAILED")
        fail(filename .. ": " .. tostring(err))
    end
    encodedParts[#encodedParts + 1] = body:gsub("%s+", "")
    print("OK")
end

print("Assembling verified source...")
local decoded = decodeBase64(table.concat(encodedParts))
if not decoded then fail("Base64 decoding returned no data") end
if #decoded ~= EXPECTED_SIZE then
    fail("Size mismatch: expected " .. EXPECTED_SIZE .. ", got " .. #decoded)
end

local checksum = adler32(decoded)
if checksum ~= EXPECTED_ADLER32 then
    fail("Checksum mismatch: expected " .. EXPECTED_ADLER32 .. ", got " .. checksum)
end
if not decoded:find("%-%- Version: 2%.1%.0") then
    fail("Verified source version marker is missing")
end

print("Applying v" .. VERSION .. " features...")

decoded = replaceLiteral(decoded, "-- Version: 2.1.0", "-- Version: 2.2.0", "version comment")
decoded = replaceLiteral(decoded, 'local VERSION = "2.1.0"', 'local VERSION = "2.2.0"', "runtime version")

decoded = replaceLiteral(decoded,
    '    craftJobsFile = "htp_craft_jobs.cfg",\n',
    '    craftJobsFile = "htp_craft_jobs.cfg",\n\n' ..
    '    backupDiskLabel = "HTP_COLONY_BACKUP",\n' ..
    '    backupFolder = "htp_colony_backup",\n' ..
    '    backupSeconds = 300,\n',
    "backup configuration"
)

local backupCode = [==[
local BACKUP = {
    drive = nil,
    mount = nil,
    label = nil,
    lastAt = 0,
    lastStatus = "No backup disk",
    lastFileCount = 0
}

local function findBackupDisk()
    BACKUP.drive = nil
    BACKUP.mount = nil
    BACKUP.label = nil

    for _, name in ipairs(peripheral.getNames()) do
        if peripheral.getType(name) == "drive" then
            local okPresent, present = attempt(function() return disk.isPresent(name) end)
            local okData, hasData = attempt(function() return disk.hasData(name) end)
            local okMount, mount = attempt(function() return disk.getMountPath(name) end)
            if okPresent and present and okData and hasData and okMount and mount then
                local okLabel, label = attempt(function() return disk.getLabel(name) end)
                label = okLabel and text(label) or ""
                if label == "" then
                    pcall(function() disk.setLabel(name, CONFIG.backupDiskLabel) end)
                    label = CONFIG.backupDiskLabel
                end
                if label == CONFIG.backupDiskLabel then
                    BACKUP.drive = name
                    BACKUP.mount = mount
                    BACKUP.label = label
                    BACKUP.lastStatus = "Ready on " .. name
                    return true
                end
            end
        end
    end

    BACKUP.lastStatus = "Insert " .. CONFIG.backupDiskLabel
    return false
end

local function copyBackupFile(source, destination)
    if not fs.exists(source) or fs.isDir(source) then return false end
    local input = fs.open(source, "rb") or fs.open(source, "r")
    if not input then return false end
    local data = input.readAll()
    input.close()

    local parent = fs.getDir(destination)
    if parent ~= "" and not fs.exists(parent) then fs.makeDir(parent) end
    local output = fs.open(destination, "wb") or fs.open(destination, "w")
    if not output then return false end
    output.write(data or "")
    output.close()
    return true
end

local function backupNow(force)
    if not BACKUP.mount and not findBackupDisk() then return false, BACKUP.lastStatus end
    if not force and now() - BACKUP.lastAt < CONFIG.backupSeconds then
        return true, BACKUP.lastStatus
    end

    local root = fs.combine(BACKUP.mount, CONFIG.backupFolder)
    if not fs.exists(root) then fs.makeDir(root) end

    local files = {
        "startup",
        CONFIG.settingsFile,
        CONFIG.whitelistFile,
        CONFIG.blockedFile,
        CONFIG.reservesFile,
        CONFIG.historyFile,
        CONFIG.errorFile,
        CONFIG.sentFile,
        CONFIG.craftJobsFile
    }

    local copied = 0
    for _, source in ipairs(files) do
        if copyBackupFile(source, fs.combine(root, fs.getName(source))) then copied = copied + 1 end
    end

    local manifest = fs.open(fs.combine(root, "backup_manifest.txt"), "w")
    if manifest then
        manifest.writeLine("HackThePlanet Colony Supply Backup")
        manifest.writeLine("version=" .. VERSION)
        manifest.writeLine("timestamp=" .. now())
        manifest.writeLine("drive=" .. text(BACKUP.drive))
        manifest.writeLine("files=" .. copied)
        manifest.close()
    end

    BACKUP.lastAt = now()
    BACKUP.lastFileCount = copied
    BACKUP.lastStatus = "Backed up " .. copied .. " files"
    return true, BACKUP.lastStatus
end

]==]

decoded = replaceLiteral(decoded, "local function labelValue(value)", backupCode .. "local function labelValue(value)", "disk backup support")

local warehouseHelpers = [==[
local function warehouseTotals()
    local used, size, free = 0, 0, 0
    for _, info in ipairs(STATE.warehouseStats or {}) do
        used = used + (tonumber(info.used) or 0)
        size = size + (tonumber(info.size) or 0)
        free = free + (tonumber(info.free) or 0)
    end
    local percent = size > 0 and (used / size) or 0
    return used, size, free, math.max(0, math.min(1, percent))
end

local function progressBar(percent, width)
    local barWidth = math.max(1, math.floor(tonumber(width) or 10))
    local filled = math.floor(math.max(0, math.min(1, tonumber(percent) or 0)) * barWidth + 0.5)
    return string.rep("#", filled) .. string.rep("-", barWidth - filled)
end

local function warehouseColor(percent)
    local value = tonumber(percent) or 0
    if value >= 0.95 then return now() % 2 == 0 and colors.red or colors.white end
    if value >= 0.80 then return colors.orange end
    if value >= 0.60 then return colors.yellow end
    return colors.lime
end

]==]

decoded = replaceLiteral(decoded, "local function exportToTarget(filter, target)", warehouseHelpers .. "local function exportToTarget(filter, target)", "warehouse fullness helpers")

local warehouseRowsCode = [==[
local function warehouseRows()
    local used, size, free, percent = warehouseTotals()
    local percentInt = math.floor(percent * 100 + 0.5)
    local color = warehouseColor(percent)
    local rows = {
        { text = "Overall: [" .. progressBar(percent, 30) .. "] " .. percentInt .. "%", color = color },
        { text = "Slots: " .. used .. "/" .. size .. " used | " .. free .. " free", color = color },
        { text = "Detected warehouse outputs: " .. #STATE.warehouseTargets, color = #STATE.warehouseTargets > 0 and colors.lime or colors.orange },
        { text = "Items are split across connected Entangled Blocks, then the direct " .. CONFIG.outputTarget .. " side is used as fallback.", color = colors.gray },
        { text = "", color = colors.white }
    }

    for _, info in ipairs(STATE.warehouseStats) do
        local rackPercent = tonumber(info.percent) or 0
        local rackColor = warehouseColor(rackPercent)
        local rackPercentInt = math.floor(rackPercent * 100 + 0.5)
        table.insert(rows, {
            text = info.name .. " | [" .. progressBar(rackPercent, 12) .. "] " .. rackPercentInt .. "% | Free " .. info.free .. "/" .. info.size,
            color = rackColor
        })
    end
    return rows
end

]==]

decoded = replaceBetween(decoded, "local function warehouseRows()", "local function craftRows()", warehouseRowsCode, "warehouse page")

decoded = replaceLiteral(decoded,
    '        { text = "Last output: " .. STATE.lastWarehouseTarget, color = colors.white },\n',
    '        { text = "Last output: " .. STATE.lastWarehouseTarget, color = colors.white },\n' ..
    '        { text = "Backup Disk: " .. (BACKUP.drive or "Not connected"), color = BACKUP.drive and colors.lime or colors.orange },\n' ..
    '        { text = "Backup Label: " .. (BACKUP.label or CONFIG.backupDiskLabel), color = colors.white },\n' ..
    '        { text = "Backup Status: " .. BACKUP.lastStatus, color = BACKUP.drive and colors.lime or colors.orange },\n',
    "backup settings status"
)

local dashboardWarehouseBlock = [==[
    local usedSlots, totalSlots, freeSlots, warehousePercent = warehouseTotals()
    local warehousePercentInt = math.floor(warehousePercent * 100 + 0.5)
    local warehouseBarColor = warehouseColor(warehousePercent)
    local warehouseBarWidth = math.max(8, math.min(24, right - 4))

    writeAt(rx, 6, "Mode:", colors.yellow); writeAt(rx + 7, 6, STATE.mode .. (STATE.paused and " PAUSED" or ""), STATE.paused and colors.orange or colors.lime)
    writeAt(rx, 7, "Racks:", colors.yellow); writeAt(rx + 8, 7, tostring(#STATE.warehouseTargets), #STATE.warehouseTargets > 0 and colors.lime or colors.orange)
    writeAt(rx, 8, "Last rack:", colors.yellow); writeAt(rx + 11, 8, trim(STATE.lastWarehouseTarget, right - 14), colors.white)
    writeAt(rx, 9, "Warehouse:", colors.yellow); writeAt(rx + 11, 9, warehousePercentInt .. "%", warehouseBarColor)
    writeAt(rx, 10, "[" .. progressBar(warehousePercent, warehouseBarWidth) .. "]", warehouseBarColor)
    writeAt(rx, 11, "Free slots: " .. freeSlots .. "/" .. totalSlots .. " | Pending: " .. #STATE.pendingOrder, colors.white)
    writeAt(rx, 12, "Backup: " .. (BACKUP.drive and BACKUP.lastStatus or "NO DISK"), BACKUP.drive and colors.lime or colors.orange)
]==]

decoded = replaceBetween(decoded,
    '    writeAt(rx, 6, "Mode:", colors.yellow);',
    '\n\n    if #STATE.citizenAlerts > 0 then',
    dashboardWarehouseBlock,
    "dashboard warehouse bar"
)

local manualBackupCode = [==[
local function manualBackup()
    local ok, status = backupNow(true)
    action(status, ok and colors.lime or colors.red, true)
end

]==]

decoded = replaceLiteral(decoded, "local function updateProgram()", manualBackupCode .. "local function updateProgram()", "manual backup action")

local controlFooterCode = [==[
    if height >= 36 then
        local available = width - 4
        local buttonWidth = math.max(8, math.floor((available - 2) / 3))
        addButton(CONTROL.name, 2, height - 6, buttonWidth, 2, "TEST OUTPUT", outputTest, colors.lightBlue)
        addButton(CONTROL.name, 3 + buttonWidth, height - 6, buttonWidth, 2, "BACKUP", manualBackup, colors.green)
        addButton(CONTROL.name, 4 + (buttonWidth * 2), height - 6, buttonWidth, 2, "UPDATE", updateProgram, colors.purple)
    end

    local _, totalSlots, freeSlots, fullness = warehouseTotals()
    local fullnessPercent = math.floor(fullness * 100 + 0.5)
    local footer = "WH " .. fullnessPercent .. "% (" .. freeSlots .. "/" .. totalSlots .. " free) | BK " .. (BACKUP.drive and "OK" or "NONE")
    center(height - 1, footer, warehouseColor(fullness))
]==]

decoded = replaceBetween(decoded,
    "    if height >= 36 then",
    "\nend\n\nlocal function render(countdown)",
    controlFooterCode,
    "control backup button and footer"
)

decoded = replaceLiteral(decoded,
    "    STATE.alerts = makeAlerts()\nend\n\n",
    "    backupNow(false)\n    STATE.alerts = makeAlerts()\nend\n\n",
    "scheduled backup"
)

decoded = replaceLiteral(decoded,
    "detectMonitors()\ndetectWarehouseTargets()\nbootSplash()",
    "detectMonitors()\ndetectWarehouseTargets()\nfindBackupDisk()\nbackupNow(true)\nbootSplash()",
    "startup backup detection"
)

decoded = replaceLiteral(decoded,
    "        detectWarehouseTargets()\n        STATE.alerts = makeAlerts()",
    "        detectWarehouseTargets()\n        findBackupDisk()\n        backupNow(false)\n        STATE.alerts = makeAlerts()",
    "peripheral backup refresh"
)

local compiled, compileError = load(decoded, "@startup.new")
if not compiled then
    fail("Lua syntax check failed after v" .. VERSION .. " patch: " .. tostring(compileError))
end

local temporary = "startup.new"
local backup = "startup.v21-backup"
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
print("Networked floppy backup: ENABLED")
print("Warehouse fullness bars: ENABLED")
print("External alerts: unchanged/held")
term.setTextColor(colors.white)
print("Rebooting into the full program...")
sleep(2)
os.reboot()
