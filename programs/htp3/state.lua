local function createState(U, C)
    local S = {
        startedAt = U.now(),
        scans = 0,
        nextScanAt = U.now(),
        scanInterval = C.scan.normal,
        idleScans = 0,
        lastScanAt = 0,
        lastAction = "Starting",
        lastError = nil,
        lastErrorAt = 0,
        lastBackup = "Not started",
        colony = {},
        health = {},
        monitors = {},
        racks = {},
        rackStats = {},
        requests = {},
        requestOrder = {},
        batches = {},
        pending = {},
        pendingOrder = {},
        workOrders = {},
        workResources = {},
        citizens = {},
        buildings = {},
        alerts = {},
        actions = {},
        selectedRequest = 1,
        selectedRack = 1,
        selectedStock = 1,
        selectedBuilding = 1,
        page = "DASHBOARD",
        pageNumbers = {},
        remoteSnapshot = nil,
        remoteLastSeen = 0,
        remoteMode = false,
        forceScan = true,
        stop = false,
        stats = {
            total = 0,
            new = 0,
            pending = 0,
            crafting = 0,
            ready = 0,
            sent = 0,
            completed = 0,
            failed = 0,
            ignored = 0,
            simulated = 0,
            batches = 0
        }
    }

    S.ledger = U.readTable(C.files.requestLedger, {})
    S.craftJobs = U.readTable(C.files.craftJobs, {})
    S.deliveries = U.readTable(C.files.deliveries, {})
    S.approvals = U.readTable(C.files.approvals, { once = {}, always = {}, blocked = {}, deniedUntil = {}, urgent = {} })
    S.buildingRules = U.readTable(C.files.buildingRules, {})
    S.rackRules = U.readTable(C.files.rackRules, {})
    S.stockTargets = U.readTable(C.files.stockTargets, {})
    S.runtimeSaved = U.readTable(C.files.runtime, {})

    S.approvals.once = S.approvals.once or {}
    S.approvals.always = S.approvals.always or {}
    S.approvals.blocked = S.approvals.blocked or {}
    S.approvals.deniedUntil = S.approvals.deniedUntil or {}
    S.approvals.urgent = S.approvals.urgent or {}

    if S.runtimeSaved.page then S.page = S.runtimeSaved.page end
    if S.runtimeSaved.selectedRequest then S.selectedRequest = S.runtimeSaved.selectedRequest end
    if S.runtimeSaved.selectedRack then S.selectedRack = S.runtimeSaved.selectedRack end
    if S.runtimeSaved.selectedStock then S.selectedStock = S.runtimeSaved.selectedStock end
    if S.runtimeSaved.selectedBuilding then S.selectedBuilding = S.runtimeSaved.selectedBuilding end
    S.pageNumbers = S.runtimeSaved.pageNumbers or {}

    local legacyWhitelist = U.readSet(C.files.oldWhitelist)
    for key in pairs(legacyWhitelist) do S.approvals.always[key] = true end
    local legacyBlocked = U.readSet(C.files.oldBlocked)
    for key in pairs(legacyBlocked) do S.approvals.blocked[key] = true end
    local legacyReserves = U.readNumberMap(C.files.oldReserves)
    S.reserves = legacyReserves
    if U.tableCount(S.reserves) == 0 then S.reserves = U.readTable(C.dataRoot .. "/reserves.tbl", {}) end

    function S.action(message, color, writeHistory)
        S.lastAction = U.text(message)
        table.insert(S.actions, 1, { time = U.now(), text = S.lastAction, color = color })
        while #S.actions > C.ui.actionRows do table.remove(S.actions) end
        if writeHistory ~= false then U.appendLine(C.files.history, S.lastAction, C.logLimits.history) end
    end

    function S.error(message)
        S.lastError = U.text(message)
        S.lastErrorAt = U.now()
        U.appendLine(C.files.errors, S.lastError, C.logLimits.errors)
        S.action("ERROR: " .. S.lastError, colors.red, false)
    end

    function S.sent(message)
        U.appendLine(C.files.sent, message, C.logLimits.sent)
        S.action(message, colors.lime, true)
    end

    function S.diagnostic(message)
        U.appendLine(C.files.diagnostics, message, C.logLimits.diagnostics)
    end

    function S.saveRuntime()
        local runtime = {
            page = S.page,
            selectedRequest = S.selectedRequest,
            selectedRack = S.selectedRack,
            selectedStock = S.selectedStock,
            selectedBuilding = S.selectedBuilding,
            pageNumbers = S.pageNumbers
        }
        return U.writeTable(C.files.runtime, runtime)
    end

    function S.saveApprovals()
        local ok = U.writeTable(C.files.approvals, S.approvals)
        U.writeSet(C.files.oldWhitelist, S.approvals.always)
        U.writeSet(C.files.oldBlocked, S.approvals.blocked)
        return ok
    end

    function S.saveReserves()
        U.writeNumberMap(C.files.oldReserves, S.reserves)
        return U.writeTable(C.dataRoot .. "/reserves.tbl", S.reserves)
    end

    function S.saveAll()
        local results = {
            U.writeTable(C.files.requestLedger, S.ledger),
            U.writeTable(C.files.craftJobs, S.craftJobs),
            U.writeTable(C.files.deliveries, S.deliveries),
            S.saveApprovals(),
            U.writeTable(C.files.buildingRules, S.buildingRules),
            U.writeTable(C.files.rackRules, S.rackRules),
            U.writeTable(C.files.stockTargets, S.stockTargets),
            S.saveReserves(),
            S.saveRuntime()
        }
        for _, result in ipairs(results) do if result == false then return false end end
        return true
    end

    function S.transition(key, status, fields)
        local current = S.ledger[key] or {
            key = key,
            createdAt = U.now(),
            status = "NEW",
            attempts = 0,
            absentScans = 0,
            sent = 0
        }
        if current.status ~= status then
            current.previousStatus = current.status
            current.status = status
            current.statusAt = U.now()
        end
        current.updatedAt = U.now()
        for field, value in pairs(fields or {}) do current[field] = value end
        S.ledger[key] = current
        return current
    end

    function S.getRecord(key)
        return S.ledger[key]
    end

    function S.approveOnce(key)
        S.approvals.once[key] = true
        S.approvals.deniedUntil[key] = nil
        S.saveApprovals()
        S.forceScan = true
    end

    function S.approveAlways(itemKey)
        S.approvals.always[itemKey] = true
        S.approvals.blocked[itemKey] = nil
        S.saveApprovals()
        S.forceScan = true
    end

    function S.deny(key, seconds)
        S.approvals.deniedUntil[key] = U.now() + (seconds or 300)
        S.approvals.once[key] = nil
        S.saveApprovals()
        S.forceScan = true
    end

    function S.block(itemKey)
        S.approvals.blocked[itemKey] = true
        S.approvals.always[itemKey] = nil
        S.saveApprovals()
        S.forceScan = true
    end

    function S.toggleUrgent(key)
        if S.approvals.urgent[key] then S.approvals.urgent[key] = nil else S.approvals.urgent[key] = true end
        S.saveApprovals()
        S.forceScan = true
    end

    function S.setBuildingRule(buildingKey, rule)
        if not buildingKey or buildingKey == "" then return end
        if rule == nil then S.buildingRules[buildingKey] = nil else S.buildingRules[buildingKey] = rule end
        U.writeTable(C.files.buildingRules, S.buildingRules)
        S.forceScan = true
    end

    function S.setRackRule(rackName, rule)
        if not rackName or rackName == "" then return end
        if rule == nil then S.rackRules[rackName] = nil else S.rackRules[rackName] = rule end
        U.writeTable(C.files.rackRules, S.rackRules)
        S.forceScan = true
    end

    function S.setStockTarget(itemKey, target)
        if target == nil or tonumber(target) == nil or tonumber(target) <= 0 then
            S.stockTargets[itemKey] = nil
        else
            local existing = S.stockTargets[itemKey] or { item = { name = itemKey }, displayName = U.itemDisplay(itemKey) }
            existing.target = math.floor(tonumber(target))
            S.stockTargets[itemKey] = existing
        end
        U.writeTable(C.files.stockTargets, S.stockTargets)
        S.forceScan = true
    end

    function S.setReserve(itemKey, amount)
        amount = math.max(0, math.floor(tonumber(amount) or 0))
        if amount == 0 then S.reserves[itemKey] = nil else S.reserves[itemKey] = amount end
        S.saveReserves()
        S.forceScan = true
    end

    function S.cleanup()
        local cutoff = U.now() - (14 * 86400)
        for key, record in pairs(S.ledger) do
            local completed = record.status == "COMPLETED" or record.status == "IGNORED" or record.status == "SIMULATED"
            if completed and (record.updatedAt or 0) < cutoff then S.ledger[key] = nil end
        end
        local deliveryCutoff = U.now() - (7 * 86400)
        for key, delivery in pairs(S.deliveries) do
            if (delivery.updatedAt or delivery.sentAt or 0) < deliveryCutoff and delivery.status ~= "ACTIVE" then S.deliveries[key] = nil end
        end
        local craftCutoff = U.now() - (3 * 86400)
        for key, job in pairs(S.craftJobs) do
            local done = job.status == "DONE" or job.status == "FAILED" or job.status == "CANCELLED"
            if done and (job.updatedAt or job.createdAt or 0) < craftCutoff then S.craftJobs[key] = nil end
        end
    end

    function S.resetStats()
        for key in pairs(S.stats) do S.stats[key] = 0 end
    end

    function S.recountStats()
        S.resetStats()
        for _, request in ipairs(S.requests or {}) do
            S.stats.total = S.stats.total + 1
            local status = string.lower(request.status or "new")
            if S.stats[status] ~= nil then S.stats[status] = S.stats[status] + 1 end
        end
        S.stats.batches = #(S.batches or {})
    end

    function S.selectedPending()
        if #S.pendingOrder == 0 then return nil end
        if S.selectedRequest < 1 then S.selectedRequest = #S.pendingOrder end
        if S.selectedRequest > #S.pendingOrder then S.selectedRequest = 1 end
        return S.pending[S.pendingOrder[S.selectedRequest]]
    end

    function S.selectedRackInfo()
        if #S.rackStats == 0 then return nil end
        if S.selectedRack < 1 then S.selectedRack = #S.rackStats end
        if S.selectedRack > #S.rackStats then S.selectedRack = 1 end
        return S.rackStats[S.selectedRack]
    end

    function S.selectedStockInfo()
        local keys = U.keys(S.stockTargets)
        if #keys == 0 then return nil end
        if S.selectedStock < 1 then S.selectedStock = #keys end
        if S.selectedStock > #keys then S.selectedStock = 1 end
        return S.stockTargets[keys[S.selectedStock]], keys[S.selectedStock]
    end

    function S.buildingChoices()
        local choices, seen = {}, {}
        for _, building in pairs(S.buildings or {}) do
            local name = U.cleanBuilding(building.name or building.type or building.buildingName)
            local key = U.lower(name):gsub("[^%w]+", "_"):gsub("^_+", ""):gsub("_+$", "")
            if key ~= "" and not seen[key] then
                seen[key] = true
                choices[#choices + 1] = { key = key, name = name, building = building }
            end
        end
        for key in pairs(S.buildingRules) do
            if not seen[key] then choices[#choices + 1] = { key = key, name = U.title(key) }; seen[key] = true end
        end
        table.sort(choices, function(a, b) return a.name < b.name end)
        return choices
    end

    function S.selectedBuildingInfo()
        local choices = S.buildingChoices()
        if #choices == 0 then return nil end
        if S.selectedBuilding < 1 then S.selectedBuilding = #choices end
        if S.selectedBuilding > #choices then S.selectedBuilding = 1 end
        return choices[S.selectedBuilding]
    end

    return S
end

return createState
