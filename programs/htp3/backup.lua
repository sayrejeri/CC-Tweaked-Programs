local function createBackup(U, C, S, I)
    local B = {
        drive = nil,
        mount = nil,
        label = nil,
        lastAt = 0,
        lastSnapshotAt = U.now(),
        lastStatus = "No backup disk",
        lastVerified = false,
        lastFiles = 0,
        pendingRestore = nil,
        pendingRestoreAt = 0
    }

    local function fileGroups()
        return {
            SETTINGS = {
                C.files.config,
                C.files.approvals,
                C.files.buildingRules,
                C.files.rackRules,
                C.files.stockTargets,
                C.dataRoot .. "/reserves.tbl",
                C.files.oldWhitelist,
                C.files.oldBlocked,
                C.files.oldReserves
            },
            STATE = {
                C.files.requestLedger,
                C.files.craftJobs,
                C.files.deliveries,
                C.files.runtime
            },
            LOGS = {
                C.files.history,
                C.files.errors,
                C.files.sent,
                C.files.diagnostics,
                C.files.requestDump
            }
        }
    end

    local function allFiles()
        local result, seen = {}, {}
        for _, group in pairs(fileGroups()) do
            for _, path in ipairs(group) do
                if not seen[path] then
                    seen[path] = true
                    result[#result + 1] = path
                end
            end
        end
        return result
    end

    local function backupRoot()
        return B.mount and fs.combine(B.mount, C.backup.folder) or nil
    end

    local function safeName(path)
        local cleaned = path:gsub("^/", "")
        cleaned = cleaned:gsub("/", "__")
        return cleaned
    end

    local function manifestPath(folder)
        return fs.combine(folder, "manifest.tbl")
    end

    local function freeSpace(path)
        local ok, value = pcall(fs.getFreeSpace, path)
        if ok and type(value) == "number" then return value end
        return math.huge
    end

    local function isLog(path)
        return path == C.files.history
            or path == C.files.errors
            or path == C.files.sent
            or path == C.files.diagnostics
            or path == C.files.requestDump
    end

    local function validFolder(folder)
        if not folder or not fs.exists(folder) or not fs.isDir(folder) then return false end
        local manifest = U.readTable(manifestPath(folder), nil)
        return type(manifest) == "table" and type(manifest.files) == "table"
    end

    local function cleanRoot(root)
        if not root or not fs.exists(root) then return end
        for _, name in ipairs(fs.list(root)) do
            local path = fs.combine(root, name)
            if name ~= C.backup.autosaveFolder and name ~= "snapshots" then
                U.safeDelete(path)
            end
        end

        local autosave = fs.combine(root, C.backup.autosaveFolder)
        if fs.exists(autosave) and not validFolder(autosave) then U.safeDelete(autosave) end

        local snapshots = fs.combine(root, "snapshots")
        if fs.exists(snapshots) then
            for _, name in ipairs(fs.list(snapshots)) do
                local folder = fs.combine(snapshots, name)
                if not validFolder(folder) then U.safeDelete(folder) end
            end
        end
    end

    local function pruneSnapshots(root, keep)
        local snapshots = fs.combine(root, "snapshots")
        if not fs.exists(snapshots) then return end
        local entries = fs.list(snapshots)
        table.sort(entries)
        while #entries > keep do
            U.safeDelete(fs.combine(snapshots, table.remove(entries, 1)))
        end
    end

    local function makeCandidates()
        local result = {}
        local logCap = math.min(tonumber(C.backup.maxLogBytes) or 2048, 2048)
        for _, source in ipairs(allFiles()) do
            if fs.exists(source) and not fs.isDir(source) then
                local data = U.readAll(source)
                if data ~= nil then
                    local logFile = isLog(source)
                    local originalSize = #data
                    if logFile and #data > logCap then data = data:sub(#data - logCap + 1) end
                    result[#result + 1] = {
                        source = source,
                        file = safeName(source),
                        data = data,
                        logFile = logFile,
                        truncated = #data < originalSize
                    }
                end
            end
        end
        return result
    end

    local function makeManifest(candidates, reason, snapshot)
        local manifest = {
            version = C.version,
            createdAt = U.now(),
            reason = reason or (snapshot and "snapshot" or "autosave"),
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

    local function requiredSpace(candidates, manifest)
        local total = 4096 + (#textutils.serialize(manifest, { compact = true }) * 2)
        for _, candidate in ipairs(candidates) do total = total + #candidate.data end
        return total
    end

    local function verifyFolder(folder)
        local manifest = U.readTable(manifestPath(folder), nil)
        if type(manifest) ~= "table" or type(manifest.files) ~= "table" then return false, "manifest missing" end
        for _, entry in ipairs(manifest.files) do
            local data = U.readAll(fs.combine(folder, entry.file))
            if data == nil then return false, "missing " .. U.text(entry.file) end
            if #data ~= tonumber(entry.size) then return false, "size mismatch " .. U.text(entry.file) end
            if U.adler32(data) ~= tonumber(entry.checksum) then return false, "checksum mismatch " .. U.text(entry.file) end
        end
        return true, "verified " .. #manifest.files .. " files"
    end

    function B.detect()
        B.drive, B.mount, B.label = nil, nil, nil
        for _, name in ipairs(I.drives or {}) do
            local okPresent, present = pcall(disk.isPresent, name)
            local okData, hasData = pcall(disk.hasData, name)
            local okMount, mount = pcall(disk.getMountPath, name)
            if okPresent and present and okData and hasData and okMount and mount then
                local okLabel, label = pcall(disk.getLabel, name)
                label = okLabel and U.text(label) or ""
                if label == "" then
                    pcall(disk.setLabel, name, C.backup.diskLabel)
                    label = C.backup.diskLabel
                end
                if label == C.backup.diskLabel then
                    B.drive, B.mount, B.label = name, mount, label
                    B.lastStatus = "Ready on " .. name
                    return true
                end
            end
        end
        B.lastStatus = "Insert " .. C.backup.diskLabel
        return false
    end

    function B.backup(forceSnapshot, reason)
        if not B.mount and not B.detect() then return false, B.lastStatus end
        local root = backupRoot()
        U.ensureDir(root)
        cleanRoot(root)

        local snapshot = forceSnapshot == true or (U.now() - B.lastSnapshotAt >= C.backup.snapshotInterval)
        local target
        if snapshot then
            local snapshots = fs.combine(root, "snapshots")
            U.ensureDir(snapshots)
            pruneSnapshots(root, math.max(0, math.min(1, (C.backup.keepSnapshots or 1) - 1)))
            target = fs.combine(snapshots, tostring(U.now()))
        else
            target = fs.combine(root, C.backup.autosaveFolder)
        end
        if fs.exists(target) then U.safeDelete(target) end

        local candidates = makeCandidates()
        local manifest = makeManifest(candidates, reason, snapshot)
        local needed = requiredSpace(candidates, manifest)

        if freeSpace(root) < needed then
            local snapshots = fs.combine(root, "snapshots")
            if fs.exists(snapshots) then
                local entries = fs.list(snapshots)
                table.sort(entries)
                while freeSpace(root) < needed and #entries > 0 do
                    U.safeDelete(fs.combine(snapshots, table.remove(entries, 1)))
                end
            end
        end

        while freeSpace(root) < needed do
            local removeIndex, largest = nil, -1
            for index, candidate in ipairs(candidates) do
                if candidate.logFile and #candidate.data > largest then
                    removeIndex, largest = index, #candidate.data
                end
            end
            if not removeIndex then break end
            table.remove(candidates, removeIndex)
            manifest = makeManifest(candidates, reason, snapshot)
            needed = requiredSpace(candidates, manifest)
        end

        local available = freeSpace(root)
        if available < needed then
            B.lastVerified = false
            B.lastAt = U.now()
            B.lastStatus = "Backup failed: need " .. needed .. " bytes, only " .. available .. " free"
            S.lastBackup = B.lastStatus
            S.diagnostic(B.lastStatus)
            return false, B.lastStatus
        end

        U.ensureDir(target)
        local okManifest, manifestError = U.writeTable(manifestPath(target), manifest)
        if not okManifest then
            U.safeDelete(target)
            B.lastStatus = "Backup failed writing manifest: " .. U.text(manifestError)
            B.lastVerified = false
            B.lastAt = U.now()
            return false, B.lastStatus
        end

        for _, candidate in ipairs(candidates) do
            local ok, err = U.writeAll(fs.combine(target, candidate.file), candidate.data)
            if not ok then
                U.safeDelete(target)
                B.lastStatus = "Backup failed writing " .. candidate.file .. ": " .. U.text(err)
                B.lastVerified = false
                B.lastAt = U.now()
                S.diagnostic(B.lastStatus)
                return false, B.lastStatus
            end
        end

        local verified, message = verifyFolder(target)
        if not verified then U.safeDelete(target) end
        B.lastVerified = verified
        B.lastAt = U.now()
        B.lastFiles = #manifest.files
        if verified then
            if snapshot then B.lastSnapshotAt = U.now() end
            B.lastStatus = (snapshot and "Snapshot " or "Backed up ") .. #manifest.files .. " files"
        else
            B.lastStatus = "Backup verification failed: " .. message
        end
        S.lastBackup = B.lastStatus
        return verified, B.lastStatus
    end

    function B.auto()
        if U.now() - B.lastAt < C.backup.interval then return true, B.lastStatus end
        return B.backup(false, "automatic")
    end

    function B.listSnapshots()
        if not B.mount and not B.detect() then return {} end
        local root = backupRoot()
        cleanRoot(root)
        local snapshots = fs.combine(root, "snapshots")
        local result = {}
        if fs.exists(snapshots) then
            local entries = fs.list(snapshots)
            table.sort(entries, function(a, b) return a > b end)
            for _, name in ipairs(entries) do
                local folder = fs.combine(snapshots, name)
                if validFolder(folder) then
                    result[#result + 1] = {
                        name = name,
                        folder = folder,
                        manifest = U.readTable(manifestPath(folder), {})
                    }
                end
            end
        end
        return result
    end

    function B.latestFolder()
        local snapshots = B.listSnapshots()
        if #snapshots > 0 then return snapshots[1].folder end
        if not B.mount and not B.detect() then return nil end
        local autosave = fs.combine(backupRoot(), C.backup.autosaveFolder)
        if validFolder(autosave) then return autosave end
        return nil
    end

    local function allowedSources(mode)
        mode = string.upper(mode or "ALL")
        if mode == "ALL" then return allFiles() end
        return fileGroups()[mode] or {}
    end

    function B.restore(mode, folder)
        folder = folder or B.latestFolder()
        if not folder then return false, "no valid backup found" end
        local verified, message = verifyFolder(folder)
        if not verified then return false, "backup invalid: " .. message end
        local manifest = U.readTable(manifestPath(folder), {})
        local entries = {}
        for _, entry in ipairs(manifest.files or {}) do entries[entry.source] = entry end

        local restored, failures = 0, {}
        for _, source in ipairs(allowedSources(mode)) do
            local entry = entries[source]
            if entry then
                local ok, err = U.copyFile(fs.combine(folder, entry.file), source)
                if ok then restored = restored + 1 else failures[#failures + 1] = source .. ": " .. U.text(err) end
            end
        end
        if #failures > 0 then return false, "restored " .. restored .. "; failed " .. #failures end
        B.lastStatus = "Restored " .. restored .. " " .. string.upper(mode or "ALL") .. " files"
        S.lastBackup = B.lastStatus
        return true, B.lastStatus
    end

    function B.requestRestore(mode)
        local now = U.now()
        if B.pendingRestore == mode and now - B.pendingRestoreAt <= 8 then
            B.pendingRestore, B.pendingRestoreAt = nil, 0
            return B.restore(mode)
        end
        B.pendingRestore, B.pendingRestoreAt = mode, now
        return false, "Press restore " .. mode .. " again within 8s to confirm"
    end

    function B.statusRows()
        local rows = {
            "Drive: " .. (B.drive or "Not connected"),
            "Label: " .. (B.label or C.backup.diskLabel),
            "Status: " .. B.lastStatus,
            "Verified: " .. tostring(B.lastVerified),
            "Last files: " .. B.lastFiles,
            "Snapshots: " .. #B.listSnapshots()
        }
        for _, snapshot in ipairs(B.listSnapshots()) do
            rows[#rows + 1] = snapshot.name .. " | v" .. U.text(snapshot.manifest.version) .. " | " .. U.text(snapshot.manifest.reason)
        end
        return rows
    end

    B.verifyFolder = verifyFolder
    B.fileGroups = fileGroups
    return B
end

return createBackup
