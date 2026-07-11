local function createIntegrations(U, C, S)
    local I = {
        bridge = nil,
        bridgeName = nil,
        colony = nil,
        colonyName = nil,
        drives = {},
        modems = {},
        monitors = {},
        mainMonitor = nil,
        controlMonitor = nil,
        alertMonitor = nil,
        lastDetection = 0
    }

    local function peripheralHas(name, typeName)
        if peripheral.hasType then
            local ok, result = pcall(peripheral.hasType, name, typeName)
            if ok and result then return true end
        end
        local ok, first = pcall(peripheral.getType, name)
        return ok and first == typeName
    end

    local function hasMethod(name, method)
        local ok, methods = pcall(peripheral.getMethods, name)
        if not ok or type(methods) ~= "table" then return false end
        for _, candidate in ipairs(methods) do if candidate == method then return true end end
        return false
    end

    local function matchesRackName(name)
        for _, pattern in ipairs(C.warehouse.patterns or {}) do
            if name:match(pattern) then return true end
        end
        return false
    end

    function I.detect()
        I.bridge, I.bridgeName = nil, nil
        I.colony, I.colonyName = nil, nil
        I.drives, I.modems, I.monitors = {}, {}, {}

        for _, name in ipairs(peripheral.getNames()) do
            if not I.bridge and (peripheralHas(name, "me_bridge") or peripheralHas(name, "meBridge")) then
                I.bridge, I.bridgeName = peripheral.wrap(name), name
            elseif not I.colony and (peripheralHas(name, "colony_integrator") or peripheralHas(name, "colonyIntegrator")) then
                I.colony, I.colonyName = peripheral.wrap(name), name
            end

            if peripheralHas(name, "drive") then I.drives[#I.drives + 1] = name end
            if peripheralHas(name, "modem") then I.modems[#I.modems + 1] = name end
            if peripheralHas(name, "monitor") then
                local monitor = peripheral.wrap(name)
                pcall(function() monitor.setTextScale(C.ui.monitorScale) end)
                local ok, width, height = pcall(function() return monitor.getSize() end)
                if ok then I.monitors[#I.monitors + 1] = { name = name, object = monitor, width = width, height = height, area = width * height, aspect = width / math.max(1, height) } end
            end
        end

        table.sort(I.monitors, function(a, b) return a.area > b.area end)
        I.mainMonitor = I.monitors[1]
        I.controlMonitor = I.monitors[2]
        I.alertMonitor = I.monitors[3]
        if #I.monitors >= 3 then
            local candidates = { I.monitors[2], I.monitors[3] }
            table.sort(candidates, function(a, b) return a.aspect > b.aspect end)
            I.alertMonitor = candidates[1]
            I.controlMonitor = candidates[2]
        end

        I.detectRacks()
        I.lastDetection = U.now()
        S.health.bridge = I.bridge ~= nil
        S.health.colony = I.colony ~= nil
        S.health.monitors = #I.monitors
        S.health.drives = #I.drives
        S.health.modems = #I.modems
        return I.bridge ~= nil, I.colony ~= nil
    end

    function I.detectRacks()
        local racks = {}
        for _, name in ipairs(peripheral.getNames()) do
            if matchesRackName(name) and hasMethod(name, "list") and hasMethod(name, "size") then
                racks[#racks + 1] = name
            end
        end
        table.sort(racks)
        S.racks = racks
        return racks
    end

    local function itemDetail(inventory, slot, basic)
        if type(inventory.getItemDetail) ~= "function" then return basic end
        local ok, detail = pcall(function() return inventory.getItemDetail(slot) end)
        if ok and type(detail) == "table" then return detail end
        return basic
    end

    local function detailKey(detail)
        if type(detail) ~= "table" then return "" end
        if detail.fingerprint then return U.itemName(detail) .. "#fp:" .. tostring(detail.fingerprint) end
        if detail.components then return U.itemName(detail) .. "#cmp:" .. tostring(U.adler32(U.stableSerialize(detail.components))) end
        if detail.nbt then return U.itemName(detail) .. "#nbt:" .. tostring(detail.nbt) end
        return U.itemName(detail)
    end

    local function canUsePartial(detail, requestedItem)
        if U.itemName(detail) ~= U.itemName(requestedItem) then return false end
        local exactRequested = U.itemFingerprint(requestedItem) ~= nil or U.itemComponents(requestedItem) ~= nil
        if not exactRequested then return true end
        return detailKey(detail) == U.itemKey(requestedItem)
    end

    function I.inspectRack(name, requestedItem)
        local inventory = peripheral.wrap(name)
        if not inventory then return nil, "unavailable" end
        local okSize, size = pcall(function() return inventory.size() end)
        local okList, listing = pcall(function() return inventory.list() end)
        if not okSize or not okList or type(size) ~= "number" or type(listing) ~= "table" then return nil, "not an inventory" end

        local usedSlots, itemCount, partialCapacity = 0, 0, 0
        local matchingSlots = 0
        local totalItems = 0
        local contents = {}
        for slot, basic in pairs(listing) do
            usedSlots = usedSlots + 1
            local detail = itemDetail(inventory, slot, basic)
            detail.slot = slot
            contents[#contents + 1] = detail
            local count = tonumber(detail.count or basic.count or 0) or 0
            totalItems = totalItems + count
            if requestedItem and canUsePartial(detail, requestedItem) then
                matchingSlots = matchingSlots + 1
                itemCount = itemCount + count
                local maxCount = tonumber(detail.maxCount or detail.maxStackSize or C.warehouse.assumedStackSize) or C.warehouse.assumedStackSize
                partialCapacity = partialCapacity + math.max(0, maxCount - count)
            end
        end
        local freeSlots = math.max(0, size - usedSlots)
        local emptyCapacity = freeSlots * C.warehouse.assumedStackSize
        local capacity = requestedItem and (partialCapacity + emptyCapacity) or emptyCapacity
        local rule = S.rackRules[name] or { group = "ANY", enabled = true }
        if rule.enabled == nil then rule.enabled = true end
        return {
            name = name,
            size = size,
            used = usedSlots,
            free = freeSlots,
            slotPercent = size > 0 and usedSlots / size or 1,
            itemCount = itemCount,
            totalItems = totalItems,
            matchingSlots = matchingSlots,
            partialCapacity = partialCapacity,
            emptyCapacity = emptyCapacity,
            capacity = capacity,
            contents = contents,
            rule = rule
        }
    end

    function I.refreshRackStats(requestedItem)
        local stats = {}
        local totalUsed, totalSize, totalFree, totalCapacity = 0, 0, 0, 0
        for _, name in ipairs(S.racks or {}) do
            local info = I.inspectRack(name, requestedItem)
            if info then
                stats[#stats + 1] = info
                totalUsed = totalUsed + info.used
                totalSize = totalSize + info.size
                totalFree = totalFree + info.free
                totalCapacity = totalCapacity + info.capacity
            end
        end
        S.rackStats = stats
        S.health.racks = #stats
        S.health.rackSlots = totalSize
        S.health.rackFree = totalFree
        S.health.rackCapacity = totalCapacity
        S.health.rackPercent = totalSize > 0 and totalUsed / totalSize or 0
        return stats
    end

    function I.rackItemCount(item)
        local total = 0
        for _, name in ipairs(S.racks or {}) do
            local info = I.inspectRack(name, item)
            if info then total = total + info.itemCount end
        end
        return total
    end

    local function rackGroupAllowed(info, category, buildingKey)
        local rule = info.rule or {}
        if rule.enabled == false then return false end
        local group = string.upper(U.text(rule.group or "ANY"))
        if group == "ANY" or group == "" then return true end
        if group == string.upper(U.text(category)) then return true end
        if group == "BUILDING" and rule.buildingKey and rule.buildingKey == buildingKey then return true end
        return false
    end

    function I.rankRacks(item, category, buildingKey)
        local ranked = {}
        for _, name in ipairs(S.racks or {}) do
            local info = I.inspectRack(name, item)
            if info and info.capacity > 0 and rackGroupAllowed(info, category, buildingKey) then
                local score = info.capacity
                if C.warehouse.preferMatchingStacks then score = score + (info.matchingSlots * 100000) + (info.partialCapacity * 100) end
                if info.rule and string.upper(U.text(info.rule.group or "ANY")) == string.upper(U.text(category)) then score = score + 1000000 end
                info.score = score
                ranked[#ranked + 1] = info
            end
        end
        table.sort(ranked, function(a, b)
            if a.score == b.score then return a.name < b.name end
            return a.score > b.score
        end)
        return ranked
    end

    function I.exportToRack(item, amount, rackName)
        if not I.bridge then return 0, "ME Bridge unavailable" end
        local filter = U.itemFilter(item, amount)
        local ok, moved, err = pcall(function() return I.bridge.exportItem(filter, rackName) end)
        if not ok then return 0, U.text(moved) end
        if type(moved) == "table" then moved = moved.amount or moved.count or moved.transferred or moved.exported or 0 end
        return tonumber(moved) or 0, U.text(err)
    end

    function I.exportItem(item, amount, category, buildingKey)
        local wanted = math.max(0, math.floor(tonumber(amount) or 0))
        if wanted <= 0 then return 0, {}, nil end
        local movedTotal, destinations = 0, {}
        local ranked = I.rankRacks(item, category, buildingKey)
        for _, info in ipairs(ranked) do
            if movedTotal >= wanted then break end
            local toMove = math.min(wanted - movedTotal, info.capacity)
            local moved, err = I.exportToRack(item, toMove, info.name)
            if moved > 0 then
                movedTotal = movedTotal + moved
                destinations[#destinations + 1] = { rack = info.name, amount = moved }
            elseif err ~= "" then
                S.diagnostic("Rack export " .. info.name .. " failed: " .. err)
            end
        end

        if movedTotal < wanted and C.processing.directFallbackSide and C.processing.directFallbackSide ~= "" then
            local filter = U.itemFilter(item, wanted - movedTotal)
            local ok, moved, err = pcall(function() return I.bridge.exportItem(filter, C.processing.directFallbackSide) end)
            if ok then
                if type(moved) == "table" then moved = moved.amount or moved.count or moved.transferred or moved.exported or 0 end
                moved = tonumber(moved) or 0
                if moved > 0 then
                    movedTotal = movedTotal + moved
                    destinations[#destinations + 1] = { rack = C.processing.directFallbackSide, amount = moved, fallback = true }
                end
            elseif err then
                S.diagnostic("Fallback export failed: " .. U.text(moved))
            end
        end
        I.refreshRackStats()
        if movedTotal <= 0 then return 0, destinations, "no output accepted the item" end
        return movedTotal, destinations, nil
    end

    function I.importItem(item, amount, rackName)
        if not I.bridge then return 0, "ME Bridge unavailable" end
        local filter = U.itemFilter(item, amount)
        local ok, moved, err = pcall(function() return I.bridge.importItem(filter, rackName) end)
        if not ok then return 0, U.text(moved) end
        if type(moved) == "table" then moved = moved.amount or moved.count or moved.transferred or moved.imported or 0 end
        return tonumber(moved) or 0, U.text(err)
    end

    function I.aeItem(item)
        if not I.bridge then return nil, "ME Bridge unavailable" end
        local ok, result, err = pcall(function() return I.bridge.getItem(U.itemFilter(item, 1)) end)
        if not ok then return nil, U.text(result) end
        return result, U.text(err)
    end

    function I.aeCount(item)
        local result = I.aeItem(item)
        if type(result) ~= "table" then return 0 end
        return tonumber(result.amount or result.count or result.quantity or 0) or 0
    end

    function I.isCraftable(item)
        if not I.bridge then return false, "ME Bridge unavailable" end
        if type(I.bridge.isCraftable) == "function" then
            local ok, result, err = pcall(function() return I.bridge.isCraftable(U.itemFilter(item, 1)) end)
            if ok then return result == true, U.text(err) end
        end
        local ok, list = pcall(function() return I.bridge.getCraftableItems(U.itemFilter(item, 1)) end)
        return ok and type(list) == "table" and next(list) ~= nil, ok and "" or U.text(list)
    end

    function I.isCrafting(item)
        if not I.bridge or type(I.bridge.isCrafting) ~= "function" then return false end
        local ok, result = pcall(function() return I.bridge.isCrafting(U.itemFilter(item, 1)) end)
        return ok and result == true
    end

    function I.craftingCPUs()
        if not I.bridge or type(I.bridge.getCraftingCPUs) ~= "function" then return {}, "unsupported" end
        local ok, cpus, err = pcall(function() return I.bridge.getCraftingCPUs() end)
        if not ok or type(cpus) ~= "table" then return {}, U.text(cpus or err) end
        return cpus, U.text(err)
    end

    function I.cpuStatus()
        local cpus = I.craftingCPUs()
        local total, busy, available = 0, 0, 0
        for _, cpu in pairs(cpus or {}) do
            total = total + 1
            local isBusy = cpu.isBusy == true or cpu.busy == true or cpu.crafting == true
            if isBusy then busy = busy + 1 else available = available + 1 end
        end
        S.health.craftingCPUs = total
        S.health.craftingBusy = busy
        S.health.craftingAvailable = available
        return total, busy, available
    end

    function I.craftItem(item, amount, cpuName)
        if not I.bridge then return nil, "ME Bridge unavailable" end
        local filter = U.itemFilter(item, amount)
        local ok, job, err = pcall(function()
            if cpuName and cpuName ~= "" then return I.bridge.craftItem(filter, cpuName) end
            return I.bridge.craftItem(filter)
        end)
        if not ok then return nil, U.text(job) end
        if job == nil or job == false then return nil, U.text(err ~= "" and err or "craft rejected") end
        local jobId = nil
        if type(job) == "table" and type(job.getId) == "function" then
            local idOk, id = pcall(function() return job.getId() end)
            if idOk then jobId = id end
        elseif type(job) == "table" then
            jobId = job.id
        end
        return { object = job, id = jobId }, U.text(err)
    end

    function I.craftTask(jobId)
        if not I.bridge or not jobId or type(I.bridge.getCraftingTask) ~= "function" then return nil end
        local ok, task = pcall(function() return I.bridge.getCraftingTask(jobId) end)
        if ok then return task end
        return nil
    end

    function I.readCraftTask(jobId)
        local task = I.craftTask(jobId)
        if not task then return nil end
        local result = { id = jobId }
        local methods = {
            done = "isDone",
            canceled = "isCanceled",
            craftingStarted = "isCraftingStarted",
            calculationStarted = "isCalculationStarted",
            calculationFailed = "isCalculationNotSuccessful",
            error = "hasErrorOccurred",
            message = "getDebugMessage",
            progress = "getItemProgress",
            totalItems = "getTotalItems",
            missingItems = "getMissingItems",
            elapsed = "getElapsedTime"
        }
        for key, method in pairs(methods) do
            if type(task[method]) == "function" then
                local ok, value = pcall(function() return task[method]() end)
                if ok then result[key] = value end
            end
        end
        return result
    end

    function I.cancelCraft(item)
        if not I.bridge or type(I.bridge.cancelCraftingTasks) ~= "function" then return 0 end
        local ok, count = pcall(function() return I.bridge.cancelCraftingTasks(U.itemFilter(item, 1)) end)
        return ok and (tonumber(count) or 0) or 0
    end

    function I.collectColonyStatus()
        if not I.colony then return { connected = false } end
        local status = { connected = true }
        local methods = {
            name = "getColonyName",
            id = "getColonyID",
            active = "isActive",
            happiness = "getHappiness",
            underAttack = "isUnderAttack",
            underRaid = "isUnderRaid",
            citizens = "amountOfCitizens",
            maxCitizens = "maxOfCitizens",
            graves = "amountOfGraves",
            constructionSites = "amountOfConstructionSites"
        }
        for key, method in pairs(methods) do
            if type(I.colony[method]) == "function" then
                local ok, value = pcall(function() return I.colony[method]() end)
                if ok then status[key] = value end
            end
        end
        S.colony = status
        return status
    end

    function I.getRequests()
        if not I.colony or type(I.colony.getRequests) ~= "function" then return {}, "unsupported" end
        local ok, result = pcall(function() return I.colony.getRequests() end)
        if not ok or type(result) ~= "table" then return {}, U.text(result) end
        return result, nil
    end

    function I.getWorkOrders()
        if not I.colony or type(I.colony.getWorkOrders) ~= "function" then return {}, "unsupported" end
        local ok, result = pcall(function() return I.colony.getWorkOrders() end)
        if not ok or type(result) ~= "table" then return {}, U.text(result) end
        return result, nil
    end

    function I.getWorkOrderResources(id)
        if not I.colony or type(I.colony.getWorkOrderResources) ~= "function" then return {}, "unsupported" end
        local ok, result = pcall(function() return I.colony.getWorkOrderResources(id) end)
        if not ok or type(result) ~= "table" then return {}, U.text(result) end
        return result, nil
    end

    function I.getBuildings()
        if not I.colony or type(I.colony.getBuildings) ~= "function" then return {}, "unsupported" end
        local ok, result = pcall(function() return I.colony.getBuildings() end)
        if not ok or type(result) ~= "table" then return {}, U.text(result) end
        return result, nil
    end

    function I.getCitizens()
        if not I.colony or type(I.colony.getCitizens) ~= "function" then return {}, "unsupported" end
        local ok, result = pcall(function() return I.colony.getCitizens() end)
        if not ok or type(result) ~= "table" then return {}, U.text(result) end
        return result, nil
    end

    function I.testRack(name)
        local info, err = I.inspectRack(name)
        if not info then return false, err end
        if info.free <= 0 then return false, "rack has no free slots" end
        local testItem = { name = "minecraft:dirt", displayName = "Dirt" }
        local available = I.aeCount(testItem)
        if available <= 0 then return false, "no Dirt in AE2 for test" end
        local moved, moveError = I.exportToRack(testItem, 1, name)
        if moved <= 0 then return false, moveError end
        local returned, returnError = I.importItem(testItem, moved, name)
        if returned < moved then return true, "export passed; return moved " .. returned .. "/" .. moved .. " (" .. returnError .. ")" end
        return true, "export/import passed"
    end

    function I.healthCheck()
        local health = {
            bridge = I.bridge ~= nil,
            colony = I.colony ~= nil,
            monitors = #I.monitors,
            racks = #S.racks,
            drives = #I.drives,
            modems = #I.modems,
            bridgeConnected = false,
            bridgeOnline = false,
            colonyInRange = false,
            lastCheck = U.now()
        }
        if I.bridge then
            local ok, result = pcall(function() return I.bridge.isConnected() end)
            health.bridgeConnected = ok and result == true
            local onlineOk, online = pcall(function() return I.bridge.isOnline() end)
            health.bridgeOnline = onlineOk and online == true
        end
        if I.colony and type(I.colony.isInColony) == "function" then
            local ok, result = pcall(function() return I.colony.isInColony() end)
            health.colonyInRange = ok and result == true
        end
        local total, busy, available = I.cpuStatus()
        health.craftingCPUs, health.craftingBusy, health.craftingAvailable = total, busy, available
        I.refreshRackStats()
        for key, value in pairs(S.health) do if health[key] == nil then health[key] = value end end
        S.health = health
        return health
    end

    function I.openRemoteChannels()
        if not C.remote.enabled then return end
        for _, name in ipairs(I.modems) do
            local modem = peripheral.wrap(name)
            if modem and type(modem.open) == "function" then
                pcall(function() modem.open(C.remote.channel) end)
                pcall(function() modem.open(C.remote.replyChannel) end)
            end
        end
    end

    function I.remoteTransmit(channel, replyChannel, payload)
        for _, name in ipairs(I.modems) do
            local modem = peripheral.wrap(name)
            if modem and type(modem.transmit) == "function" then
                pcall(function() modem.transmit(channel, replyChannel, payload) end)
            end
        end
    end

    function I.broadcastSnapshot(snapshot)
        if not C.remote.enabled then return end
        I.remoteTransmit(C.remote.channel, C.remote.replyChannel, {
            protocol = "HTP_COLONY_V3",
            kind = "snapshot",
            secret = C.remote.secret,
            sender = os.getComputerID(),
            name = C.remote.computerName,
            data = snapshot
        })
    end

    function I.sendRemoteCommand(command, arguments)
        I.remoteTransmit(C.remote.replyChannel, C.remote.channel, {
            protocol = "HTP_COLONY_V3",
            kind = "command",
            secret = C.remote.secret,
            sender = os.getComputerID(),
            command = command,
            arguments = arguments or {}
        })
    end

    I.peripheralHas = peripheralHas
    I.hasMethod = hasMethod
    return I
end

return createIntegrations
