-- HackThePlanet Colony Supply v3.0.5 backup and navigation fix

local VERSION = "3.0.5"
local BACKUP_FILE = "/htp3/backup.lua"
local UI_LAYOUT = "/htp3/ui_parts/04.lua.part"
local CONFIG_FILE = "/htp3/config.lua"
local DATA_CONFIG = "/htp3/data/config.tbl"

local function fail(message)
    term.setTextColor(colors.red)
    print("HTP v" .. VERSION .. " patch failed:")
    print(tostring(message))
    term.setTextColor(colors.white)
    error(message, 0)
end

local function readAll(path)
    if not fs.exists(path) or fs.isDir(path) then return nil end
    local handle = fs.open(path, "r")
    if not handle then return nil end
    local data = handle.readAll()
    handle.close()
    return data
end

local function writeAll(path, data)
    local temporary = path .. ".tmp"
    if fs.exists(temporary) then fs.delete(temporary) end
    local handle = fs.open(temporary, "w")
    if not handle then return false, "could not open " .. temporary end
    local ok, err = pcall(function() handle.write(data) end)
    handle.close()
    if not ok then
        if fs.exists(temporary) then fs.delete(temporary) end
        return false, err
    end
    if fs.exists(path) then fs.delete(path) end
    fs.move(temporary, path)
    return true
end

local function replaceBetween(source, startMarker, endMarker, replacement, label)
    local first = source:find(startMarker, 1, true)
    if not first then fail("Patch start missing: " .. label) end
    local last = source:find(endMarker, first + #startMarker, true)
    if not last then fail("Patch end missing: " .. label) end
    return source:sub(1, first - 1) .. replacement .. source:sub(last)
end

local function replacePlain(source, oldText, newText, label)
    local first, last = source:find(oldText, 1, true)
    if not first then
        if source:find(newText, 1, true) then return source end
        fail("Patch point missing: " .. label)
    end
    return source:sub(1, first - 1) .. newText .. source:sub(last + 1)
end

local function replaceAllPlain(source, oldText, newText)
    local output = {}
    local position = 1
    while true do
        local first, last = source:find(oldText, position, true)
        if not first then
            output[#output + 1] = source:sub(position)
            break
        end
        output[#output + 1] = source:sub(position, first - 1)
        output[#output + 1] = newText
        position = last + 1
    end
    return table.concat(output)
end

local function backupOnce(path, suffix)
    local backup = path .. suffix
    if fs.exists(path) and not fs.exists(backup) then fs.copy(path, backup) end
end

term.setBackgroundColor(colors.black)
term.setTextColor(colors.white)
term.clear()
term.setCursorPos(1, 1)
print("HackThePlanet Colony Supply")
print("Applying backup and centered navigation fix v" .. VERSION .. "...")
print("")

local backupSource = readAll(BACKUP_FILE)
if not backupSource then fail("Missing " .. BACKUP_FILE) end
backupOnce(BACKUP_FILE, ".v304.bak")

local backupReplacement = [====[
    local function isLogSource(source)
        return source == C.files.history
            or source == C.files.errors
            or source == C.files.sent
            or source == C.files.diagnostics
            or source == C.files.requestDump
    end

    local function availableSpace(path)
        local ok, value = pcall(fs.getFreeSpace, path)
        if ok and type(value) == "number" then return value end
        return math.huge
    end

    local function cleanupBackupRoot(root)
        if not fs.exists(root) then return end

        -- Remove direct legacy v2 files. v3 stores everything in autosave/snapshots.
        for _, name in ipairs(fs.list(root)) do
            if name ~= C.backup.autosaveFolder and name ~= "snapshots" then
                U.safeDelete(fs.combine(root, name))
            end
        end

        local autosave = fs.combine(root, C.backup.autosaveFolder)
        if fs.exists(autosave) and not fs.exists(manifestPath(autosave)) then
            U.safeDelete(autosave)
        end

        local snapshotsRoot = fs.combine(root, "snapshots")
        if fs.exists(snapshotsRoot) then
            for _, name in ipairs(fs.list(snapshotsRoot)) do
                local folder = fs.combine(snapshotsRoot, name)
                if fs.isDir(folder) and not fs.exists(manifestPath(folder)) then
                    U.safeDelete(folder)
                end
            end
        end
    end

    local function reclaimSpace(root, required, destination)
        cleanupBackupRoot(root)
        local snapshotsRoot = fs.combine(root, "snapshots")
        local entries = fs.exists(snapshotsRoot) and fs.list(snapshotsRoot) or {}
        table.sort(entries)

        while availableSpace(root) < required and #entries > 0 do
            local oldest = table.remove(entries, 1)
            local folder = fs.combine(snapshotsRoot, oldest)
            if folder ~= destination then U.safeDelete(folder) end
        end

        local autosave = fs.combine(root, C.backup.autosaveFolder)
        if availableSpace(root) < required and autosave ~= destination and fs.exists(autosave) then
            U.safeDelete(autosave)
        end
        return availableSpace(root)
    end

    local function prepareCandidates()
        local candidates = {}
        for _, source in ipairs(allFiles()) do
            if fs.exists(source) and not fs.isDir(source) then
                local data = U.readAll(source)
                if data ~= nil then
                    local logFile = isLogSource(source)
                    if logFile then
                        local cap = math.min(tonumber(C.backup.maxLogBytes) or 8192, 8192)
                        if #data > cap then data = data:sub(#data - cap + 1) end
                    end
                    candidates[#candidates + 1] = {
                        source = source,
                        file = safeName(source),
                        data = data,
                        logFile = logFile,
                        truncated = logFile and #data < (fs.getSize(source) or #data)
                    }
                end
            end
        end
        return candidates
    end

    local function makeManifest(candidates, now, makeSnapshot, reason)
        local manifest = {
            version = C.version,
            createdAt = now,
            reason = reason or (makeSnapshot and "snapshot" or "autosave"),
            computer = os.getComputerID(),
            files = {}
        }
        for _, candidate in ipairs(candidates) do
            manifest.files[#manifest.files + 1] = {
                source = candidate.source,
                file = candidate.file,
                size = #candidate.data,
                checksum = U.adler32(candidate.data),
                truncated = candidate.truncated == true
            }
        end
        return manifest
    end

    local function requiredBytes(candidates, manifest)
        local total = 8192 -- room for folder metadata and atomic manifest write
        for _, candidate in ipairs(candidates) do total = total + #candidate.data end
        total = total + #textutils.serialize(manifest, { compact = true })
        return total
    end

    function B.backup(forceSnapshot, reason)
        if not B.mount and not B.detect() then return false, B.lastStatus end
        local root = backupRoot()
        U.ensureDir(root)
        cleanupBackupRoot(root)

        local now = U.now()
        local makeSnapshot = forceSnapshot == true or (now - B.lastSnapshotAt >= C.backup.snapshotInterval)
        local folder
        if makeSnapshot then
            local name = os.date and os.date("!%Y%m%d-%H%M%S") or tostring(now)
            local snapshotsRoot = fs.combine(root, "snapshots")
            U.ensureDir(snapshotsRoot)
            folder = fs.combine(snapshotsRoot, name)
        else
            folder = fs.combine(root, C.backup.autosaveFolder)
        end
        if fs.exists(folder) then U.safeDelete(folder) end

        local candidates = prepareCandidates()
        local manifest = makeManifest(candidates, now, makeSnapshot, reason)
        local required = requiredBytes(candidates, manifest)
        local free = reclaimSpace(root, required, folder)
        local trimmedLogs = 0

        -- A standard CC floppy is small. Shrink or omit logs before sacrificing state.
        while free < required do
            local largestIndex, largestSize = nil, 0
            for index, candidate in ipairs(candidates) do
                if candidate.logFile and #candidate.data > largestSize then
                    largestIndex, largestSize = index, #candidate.data
                end
            end
            if not largestIndex then break end
            local candidate = candidates[largestIndex]
            if #candidate.data > 1024 then
                local newSize = math.max(1024, math.floor(#candidate.data / 2))
                candidate.data = candidate.data:sub(#candidate.data - newSize + 1)
                candidate.truncated = true
            else
                table.remove(candidates, largestIndex)
            end
            trimmedLogs = trimmedLogs + 1
            manifest = makeManifest(candidates, now, makeSnapshot, reason)
            required = requiredBytes(candidates, manifest)
            free = availableSpace(root)
        end

        if free < required then
            B.lastVerified = false
            B.lastAt = now
            B.lastStatus = "Backup failed: need " .. required .. " bytes, only " .. free .. " free"
            S.lastBackup = B.lastStatus
            S.diagnostic(B.lastStatus)
            return false, B.lastStatus
        end

        U.ensureDir(folder)
        for _, candidate in ipairs(candidates) do
            local destination = fs.combine(folder, candidate.file)
            local ok, err = U.writeAll(destination, candidate.data)
            if not ok then
                U.safeDelete(folder)
                B.lastVerified = false
                B.lastAt = now
                B.lastStatus = "Backup failed writing " .. candidate.file .. ": " .. U.text(err)
                S.lastBackup = B.lastStatus
                S.diagnostic(B.lastStatus)
                return false, B.lastStatus
            end
        end

        local manifestOk, manifestErr = U.writeTable(manifestPath(folder), manifest)
        if not manifestOk then
            U.safeDelete(folder)
            B.lastVerified = false
            B.lastAt = now
            B.lastStatus = "Backup failed writing manifest: " .. U.text(manifestErr)
            S.lastBackup = B.lastStatus
            S.diagnostic(B.lastStatus)
            return false, B.lastStatus
        end

        local verified, verifyMessage = verifyFolder(folder)
        if not verified then U.safeDelete(folder) end
        B.lastVerified = verified
        B.lastAt = now
        B.lastFiles = #manifest.files
        if verified then
            if makeSnapshot then B.lastSnapshotAt = now end
            B.lastStatus = (makeSnapshot and "Snapshot " or "Backed up ") .. #manifest.files .. " files"
            if trimmedLogs > 0 then B.lastStatus = B.lastStatus .. " | logs trimmed for floppy" end
            if makeSnapshot then pruneSnapshots(root) end
        else
            B.lastStatus = "Backup verification failed: " .. verifyMessage
        end
        S.lastBackup = B.lastStatus
        return verified, B.lastStatus
    end

]====]

backupSource = replaceBetween(
    backupSource,
    "    function B.backup(forceSnapshot, reason)",
    "    function B.auto()",
    backupReplacement,
    "capacity-aware backup"
)

local latestReplacement = [====[
    function B.latestFolder()
        if not B.mount and not B.detect() then return nil end
        local root = backupRoot()
        cleanupBackupRoot(root)
        local snapshotsRoot = fs.combine(root, "snapshots")
        if fs.exists(snapshotsRoot) then
            local entries = fs.list(snapshotsRoot)
            table.sort(entries, function(a, b) return a > b end)
            for _, name in ipairs(entries) do
                local folder = fs.combine(snapshotsRoot, name)
                if fs.exists(manifestPath(folder)) then return folder end
            end
        end
        local autosave = fs.combine(root, C.backup.autosaveFolder)
        if fs.exists(manifestPath(autosave)) then return autosave end
        return nil
    end

    function B.listSnapshots()
        if not B.mount and not B.detect() then return {} end
        local root = backupRoot()
        cleanupBackupRoot(root)
        local snapshotsRoot = fs.combine(root, "snapshots")
        local result = {}
        if fs.exists(snapshotsRoot) then
            local entries = fs.list(snapshotsRoot)
            table.sort(entries, function(a, b) return a > b end)
            for _, name in ipairs(entries) do
                local folder = fs.combine(snapshotsRoot, name)
                local manifest = U.readTable(manifestPath(folder), nil)
                if type(manifest) == "table" and type(manifest.files) == "table" then
                    result[#result + 1] = { name = name, folder = folder, manifest = manifest }
                end
            end
        end
        return result
    end

]====]

backupSource = replaceBetween(
    backupSource,
    "    function B.latestFolder()",
    "    local function allowedSources(mode)",
    latestReplacement,
    "valid backup selection"
)

local backupCompiled, backupError = load(backupSource, "@htp3/backup.lua")
if not backupCompiled then fail("Patched backup syntax error: " .. tostring(backupError)) end
local okBackup, backupWriteError = writeAll(BACKUP_FILE, backupSource)
if not okBackup then fail(backupWriteError) end
print("Backup cleanup, capacity checks, and manifest handling fixed.")

local uiSource = readAll(UI_LAYOUT)
if not uiSource then fail("Missing " .. UI_LAYOUT) end
backupOnce(UI_LAYOUT, ".v304.bak")

local oldNavigation = [==[
            local navColumns = 5
            local navGap = 1
            local navButtonHeight = height >= 38 and 3 or 2
            local navButtonWidth = math.floor((width - 2 - ((navColumns - 1) * navGap)) / navColumns)
            local navY = cardY + cardHeight + 1
]==]

local newNavigation = [==[
            local navColumns = 5
            local navGap = 1
            local navButtonHeight = height >= 38 and 3 or 2
            local navSidePadding = math.max(3, math.floor(width * 0.03))
            local navAvailableWidth = width - (navSidePadding * 2)
            local navButtonWidth = math.floor((navAvailableWidth - ((navColumns - 1) * navGap)) / navColumns)
            local navTotalWidth = (navButtonWidth * navColumns) + ((navColumns - 1) * navGap)
            local navStartX = math.floor((width - navTotalWidth) / 2) + 1
            local navY = cardY + cardHeight + 1
]==]

uiSource = replacePlain(uiSource, oldNavigation, newNavigation, "centered navigation sizing")
uiSource = replacePlain(
    uiSource,
    "                local x = 1 + column * (navButtonWidth + navGap)",
    "                local x = navStartX + column * (navButtonWidth + navGap)",
    "centered navigation position"
)

local uiBundle = {}
for index = 1, 4 do
    local path = "/htp3/ui_parts/0" .. index .. ".lua.part"
    local part = index == 4 and uiSource or readAll(path)
    if not part then fail("Missing UI bundle part " .. path) end
    uiBundle[#uiBundle + 1] = part
end
local uiCompiled, uiError = load(table.concat(uiBundle, "\n"), "@htp3/ui.bundle")
if not uiCompiled then fail("Patched UI syntax error: " .. tostring(uiError)) end
local okUi, uiWriteError = writeAll(UI_LAYOUT, uiSource)
if not okUi then fail(uiWriteError) end
print("Top navigation grid centered with equal left and right margins.")

local config = readAll(CONFIG_FILE)
if config then
    backupOnce(CONFIG_FILE, ".v304.bak")
    for _, oldVersion in ipairs({ "3.0.0", "3.0.1", "3.0.2", "3.0.3", "3.0.4" }) do
        config = replaceAllPlain(config, 'version = "' .. oldVersion .. '"', 'version = "' .. VERSION .. '"')
        config = replaceAllPlain(config, 'C.version = "' .. oldVersion .. '"', 'C.version = "' .. VERSION .. '"')
    end
    local configCompiled, configError = load(config, "@htp3/config.lua")
    if not configCompiled then fail("Patched config syntax error: " .. tostring(configError)) end
    local okConfig, configWriteError = writeAll(CONFIG_FILE, config)
    if not okConfig then fail(configWriteError) end
end

if fs.exists(DATA_CONFIG) then
    local storedText = readAll(DATA_CONFIG)
    local ok, stored = pcall(textutils.unserialize, storedText or "")
    if ok and type(stored) == "table" then
        stored.version = VERSION
        local okData, dataError = writeAll(DATA_CONFIG, textutils.serialize(stored, { compact = true }))
        if not okData then fail(dataError) end
    end
end

term.setTextColor(colors.lime)
print("")
print("HTP Colony Supply v" .. VERSION .. " patch complete.")
term.setTextColor(colors.white)
print("Reboot the computer, then press BACKUP NOW once.")
