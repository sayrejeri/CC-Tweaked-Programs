local function createBackup(U, C, S, I)
    local B = {
        drive = nil,
        mount = nil,
        label = nil,
        lastAt = 0,
        lastSnapshotAt = 0,
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
                if not seen[path] then result[#result + 1] = path; seen[path] = true end
            end
        end
        return result
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

    local function backupRoot()
        if not B.mount then return nil end
        return fs.combine(B.mount, C.backup.folder)
    end

    local function safeName(path)
        local cleaned = path:gsub("^/", "")
        cleaned = cleaned:gsub("/", "__")
        return cleaned
    end

    local function manifestPath(folder)
        return fs.combine(folder, "manifest.tbl")
    end

    local function writeOne(source, destination, maxBytes)
        local data = U.readAll(source)
        if data == nil then return nil end
        if maxBytes and #data > maxBytes then data = data:sub(#data - maxBytes + 1) end
        local ok, err = U.writeAll(destination, data)
        if not ok then return false, err end
        local check = U.readAll(destination)
        if check == nil then return false, "read-back failed" end
        return {
            source = source,
            file = fs.getName(destination),
            size = #check,
            checksum = U.adler32(check)
        }
    end

    local function verifyFolder(folder)
        local manifest = U.readTable(manifestPath(folder), nil)
        if type(manifest) ~= "table" or type(manifest.files) ~= "table" then return false, "manifest missing" end
        for _, entry in ipairs(manifest.files) do
            local path = fs.combine(folder, entry.file)
            local data = U.readAll(path)
            if data == nil then return false, "missing " .. entry.file end
            if #data ~= entry.size then return false, "size mismatch " .. entry.file end
            if U.adler32(data) ~= entry.checksum then return false, "checksum mismatch " .. entry.file end
        end
        return true, "verified " .. #manifest.files .. " files"
    end

    local function pruneSnapshots(root)
        local snapshotsRoot = fs.combine(root, "snapshots")
        if not fs.exists(snapshotsRoot) then return end
        local entries = fs.list(snapshotsRoot)
        table.sort(entries)
        while #entries > C.backup.keepSnapshots do
            local oldest = table.remove(entries, 1)
            U.safeDelete(fs.combine(snapshotsRoot, oldest))
        end
    end

    function B.backup(forceSnapshot, reason)
        if not B.mount and not B.detect() then return false, B.lastStatus end
        local root = backupRoot()
        U.ensureDir(root)

        -- Remove the oversized legacy startup backup left by early versions.
        local legacy = fs.combine(root, "startup")
        if fs.exists(legacy) then U.safeDelete(legacy) end
        local legacyFolder = fs.combine(root, "autosave/startup")
        if fs.exists(legacyFolder) then U.safeDelete(legacyFolder) end

        local now = U.now()
        local makeSnapshot = forceSnapshot == true or (now - B.lastSnapshotAt >= C.backup.snapshotInterval)
        local folder
        if makeSnapshot then
            local name = os.date and os.date("!%Y%m%d-%H%M%S") or tostring(now)
            folder = fs.combine(fs.combine(root, "snapshots"), name)
            B.lastSnapshotAt = now
        else
            folder = fs.combine(root, C.backup.autosaveFolder)
            if fs.exists(folder) then U.safeDelete(folder) end
        end
        U.ensureDir(folder)

        local manifest = {
            version = C.version,
            createdAt = now,
            reason = reason or (makeSnapshot and "snapshot" or "autosave"),
            computer = os.getComputerID(),
            files = {}
        }

        local failures = {}
        for _, source in ipairs(allFiles()) do
            if fs.exists(source) and not fs.isDir(source) then
                local maxBytes = nil
                if source == C.files.history or source == C.files.errors or source == C.files.sent or source == C.files.diagnostics or source == C.files.requestDump then
                    maxBytes = C.backup.maxLogBytes
                end
                local destination = fs.combine(folder, safeName(source))
                local entry, err = writeOne(source, destination, maxBytes)
                if type(entry) == "table" then
                    manifest.files[#manifest.files + 1] = entry
                elseif entry == false then
                    failures[#failures + 1] = source .. ": " .. U.text(err)
                end
            end
        end

        local manifestOk, manifestErr = U.writeTable(manifestPath(folder), manifest)
        if not manifestOk then failures[#failures + 1] = "manifest: " .. U.text(manifestErr) end

        local verified, verifyMessage = verifyFolder(folder)
        B.lastVerified = verified
        B.lastAt = now
        B.lastFiles = #manifest.files
        if verified and #failures == 0 then
            B.lastStatus = (makeSnapshot and "Snapshot " or "Backed up ") .. #manifest.files .. " files"
        elseif verified then
            B.lastStatus = "Verified " .. #manifest.files .. " files; " .. #failures .. " skipped"
        else
            B.lastStatus = "Backup verification failed: " .. verifyMessage
        end

        if makeSnapshot then pruneSnapshots(root) end
        S.lastBackup = B.lastStatus
        if #failures > 0 then S.diagnostic("Backup skipped: " .. table.concat(failures, " | ")) end
        return verified, B.lastStatus
    end

    function B.auto()
        if U.now() - B.lastAt < C.backup.interval then return true, B.lastStatus end
        return B.backup(false, "automatic")
    end

    function B.latestFolder()
        if not B.mount and not B.detect() then return nil end
        local root = backupRoot()
        local snapshotsRoot = fs.combine(root, "snapshots")
        if fs.exists(snapshotsRoot) then
            local entries = fs.list(snapshotsRoot)
            table.sort(entries)
            if #entries > 0 then return fs.combine(snapshotsRoot, entries[#entries]) end
        end
        local autosave = fs.combine(root, C.backup.autosaveFolder)
        if fs.exists(autosave) then return autosave end
        return nil
    end

    function B.listSnapshots()
        if not B.mount and not B.detect() then return {} end
        local root = backupRoot()
        local snapshotsRoot = fs.combine(root, "snapshots")
        local result = {}
        if fs.exists(snapshotsRoot) then
            local entries = fs.list(snapshotsRoot)
            table.sort(entries, function(a, b) return a > b end)
            for _, name in ipairs(entries) do
                local folder = fs.combine(snapshotsRoot, name)
                local manifest = U.readTable(manifestPath(folder), {})
                result[#result + 1] = { name = name, folder = folder, manifest = manifest }
            end
        end
        return result
    end

    local function allowedSources(mode)
        mode = string.upper(mode or "ALL")
        if mode == "ALL" then return allFiles() end
        return fileGroups()[mode] or {}
    end

    function B.restore(mode, folder)
        folder = folder or B.latestFolder()
        if not folder then return false, "no backup found" end
        local verified, verifyMessage = verifyFolder(folder)
        if not verified then return false, "backup is not valid: " .. verifyMessage end
        local manifest = U.readTable(manifestPath(folder), {})
        local bySource = {}
        for _, entry in ipairs(manifest.files or {}) do bySource[entry.source] = entry end
        local restored, failed = 0, {}
        for _, source in ipairs(allowedSources(mode)) do
            local entry = bySource[source]
            if entry then
                local backupFile = fs.combine(folder, entry.file)
                local ok, err = U.copyFile(backupFile, source)
                if ok then restored = restored + 1 else failed[#failed + 1] = source .. ": " .. U.text(err) end
            end
        end
        if #failed > 0 then return false, "restored " .. restored .. "; failed " .. #failed end
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
        B.pendingRestore = mode
        B.pendingRestoreAt = now
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
