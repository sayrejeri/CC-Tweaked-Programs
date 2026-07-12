local function createConfig(U)
    local C = {
        version = "3.0.2",
        root = "/htp3",
        dataRoot = "/htp3/data",
        logRoot = "/htp3/logs",

        scan = {
            busy = 5,
            pending = 15,
            normal = 30,
            idle = 60,
            deepIdle = 120,
            deepIdleAfter = 6
        },

        processing = {
            maxBatchesPerScan = 8,
            maxExportPerBatch = 2048,
            maxCraftPerBatch = 2048,
            requestCooldown = 15,
            absentScansToComplete = 2,
            sentWaitSeconds = 20,
            deliveryWarningSeconds = 3600,
            deliveryReclaimSeconds = 7200,
            autoReclaimStale = false,
            dryRun = false,
            paused = false,
            globalMode = "AUTO",
            useWorkOrderResources = true,
            useGeneralRequests = true,
            directFallbackSide = "bottom",
            exactVariants = true,
            retrySchedule = { 30, 120, 600, 1800 },
            craftStuckSeconds = 1800,
            craftProgressTimeout = 600,
            stockEnabled = false,
            stockOnlyWhenIdle = true,
            stockBatchLimit = 1024
        },

        modes = {
            BUILD = "AUTO",
            TOOL = "APPROVAL",
            ARMOR = "APPROVAL",
            FOOD = "APPROVAL",
            FUEL = "AUTO",
            SPECIAL = "OFF",
            OTHER = "APPROVAL",
            STOCK = "AUTO"
        },

        categoryPriority = {
            ATTACK = 120,
            FOOD = 95,
            ARMOR = 90,
            TOOL = 85,
            FUEL = 70,
            BUILD = 60,
            SPECIAL = 40,
            OTHER = 50,
            STOCK = 10
        },

        warehouse = {
            patterns = {
                "^entangled:tile_",
                "^entangledtile_",
                "^warehouse_",
                "^rack_"
            },
            preferMatchingStacks = true,
            assignmentsEnabled = true,
            warningPercent = 0.80,
            criticalPercent = 0.95,
            assumedStackSize = 64
        },

        backup = {
            diskLabel = "HTP_COLONY_BACKUP",
            folder = "htp_colony_backup",
            autosaveFolder = "autosave",
            interval = 300,
            snapshotInterval = 1800,
            keepSnapshots = 3,
            maxLogBytes = 32768,
            verify = true
        },

        remote = {
            enabled = true,
            channel = 49210,
            replyChannel = 49211,
            broadcastSeconds = 5,
            secret = "",
            allowCommands = true,
            computerName = "HTP Colony Supply"
        },

        ui = {
            monitorScale = 0.5,
            splashSeconds = 8,
            pageSize = 16,
            actionRows = 8,
            refreshSeconds = 1
        },

        files = {
            config = "/htp3/data/config.tbl",
            requestLedger = "/htp3/data/requests.tbl",
            craftJobs = "/htp3/data/craft_jobs.tbl",
            deliveries = "/htp3/data/deliveries.tbl",
            approvals = "/htp3/data/approvals.tbl",
            buildingRules = "/htp3/data/building_rules.tbl",
            rackRules = "/htp3/data/rack_rules.tbl",
            stockTargets = "/htp3/data/stock_targets.tbl",
            runtime = "/htp3/data/runtime.tbl",
            history = "/htp3/logs/history.log",
            errors = "/htp3/logs/errors.log",
            sent = "/htp3/logs/sent.log",
            diagnostics = "/htp3/logs/diagnostics.log",
            requestDump = "/htp3/logs/request_dump.txt",
            oldSettings = "htp_settings.cfg",
            oldWhitelist = "htp_whitelist.txt",
            oldBlocked = "htp_blacklist.txt",
            oldReserves = "htp_reserves.cfg",
            oldHistory = "htp_history.log",
            oldErrors = "htp_colony_errors.log",
            oldSent = "htp_colony_sent.log",
            oldCraftJobs = "htp_craft_jobs.cfg"
        },

        logLimits = {
            history = 1000,
            errors = 500,
            sent = 750,
            diagnostics = 500
        }
    }

    local function normalizeMode(mode, fallback)
        mode = string.upper(U.text(mode))
        if mode == "AUTO" or mode == "APPROVAL" or mode == "OFF" or mode == "WHITELIST" then return mode end
        return fallback or "APPROVAL"
    end

    function C.ensureFolders()
        U.ensureDir(C.root)
        U.ensureDir(C.dataRoot)
        U.ensureDir(C.logRoot)
    end

    function C.load()
        C.ensureFolders()
        local codeVersion = C.version
        local stored = U.readTable(C.files.config, {})
        if U.tableCount(stored) > 0 then
            local merged = U.merge(C, stored)
            for key, value in pairs(merged) do C[key] = value end
        else
            C.migrateLegacy()
        end
        -- The installed code controls the displayed/runtime version. Older
        -- config.tbl files must not force a stale version number forever.
        C.version = codeVersion
        C.processing.globalMode = normalizeMode(C.processing.globalMode, "AUTO")
        for category, mode in pairs(C.modes) do C.modes[category] = normalizeMode(mode, "APPROVAL") end
        C.save()
        return C
    end

    function C.save()
        local persist = {
            version = C.version,
            scan = C.scan,
            processing = C.processing,
            modes = C.modes,
            categoryPriority = C.categoryPriority,
            warehouse = C.warehouse,
            backup = C.backup,
            remote = C.remote,
            ui = C.ui
        }
        return U.writeTable(C.files.config, persist)
    end

    function C.migrateLegacy()
        local legacy = U.parseKeyValues(C.files.oldSettings)
        if legacy.mode then C.processing.globalMode = normalizeMode(legacy.mode, "AUTO") end
        if legacy.paused then C.processing.paused = legacy.paused == "true" end
        for category in pairs(C.modes) do
            local value = legacy["type_" .. category]
            if value then C.modes[category] = normalizeMode(value, C.modes[category]) end
        end
        if fs.exists(C.files.oldHistory) and not fs.exists(C.files.history) then U.copyFile(C.files.oldHistory, C.files.history) end
        if fs.exists(C.files.oldErrors) and not fs.exists(C.files.errors) then U.copyFile(C.files.oldErrors, C.files.errors) end
        if fs.exists(C.files.oldSent) and not fs.exists(C.files.sent) then U.copyFile(C.files.oldSent, C.files.sent) end
    end

    function C.setMode(category, mode)
        mode = normalizeMode(mode, "APPROVAL")
        if category == "GLOBAL" then C.processing.globalMode = mode else C.modes[category] = mode end
        C.save()
        return mode
    end

    function C.cycleMode(category)
        local order = { "AUTO", "APPROVAL", "OFF" }
        local current = category == "GLOBAL" and C.processing.globalMode or C.modes[category]
        local index = 1
        for i, value in ipairs(order) do if value == current then index = i break end end
        index = (index % #order) + 1
        return C.setMode(category, order[index])
    end

    function C.toggle(key)
        if key == "paused" then C.processing.paused = not C.processing.paused end
        if key == "dryRun" then C.processing.dryRun = not C.processing.dryRun end
        if key == "stockEnabled" then C.processing.stockEnabled = not C.processing.stockEnabled end
        if key == "autoReclaimStale" then C.processing.autoReclaimStale = not C.processing.autoReclaimStale end
        if key == "remoteEnabled" then C.remote.enabled = not C.remote.enabled end
        C.save()
    end

    return C
end

return createConfig
