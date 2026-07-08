-- startup
-- HackThePlanet CC & MineColonies Program
-- CC:Tweaked + Advanced Peripherals + AE2 + MineColonies
-- Auto-supplies MineColonies requests from AE2 using an ME Bridge.

-------------------------
-- CONFIG
-------------------------

local CONFIG = {
    -- Side of the output chest/rack/container relative to the ME Bridge.
    -- Valid sides: "left", "right", "front", "back", "top", "bottom"
    outputTarget = "bottom",

    -- Scan speed.
    scanSeconds = 30,

    -- Stops the script from dumping the same item request over and over.
    requestCooldownSeconds = 120,

    -- Stops repeated craft spam if AE2 is already crafting or failed crafting.
    craftCooldownSeconds = 300,

    -- Max amount to export per request per scan.
    maxExportPerRequest = 512,

    -- Max amount to autocraft per request.
    maxCraftPerRequest = 512,

    -- Turn false if you only want it to use existing AE2 items.
    autoCraft = true,

    -- Safer for MineColonies. Tools, armor, enchanted stuff, special scrolls, etc. can be weird.
    skipNBT = true,

    -- Skips vague MineColonies requests like Food, Fuel, Tool of class, etc.
    skipGenericRequests = true,

    -- Startup screen.
    splashSeconds = 7,
    splashTitle = "HackThePlanet",
    splashSubtitle = "CC & MineColonies Program",

    -- Monitor settings.
    monitorScale = 0.5,

    -- Log files.
    logFile = "htp_colony.log",
    errorLogFile = "htp_colony_errors.log",

    -- Display limits so the monitor does not get too messy.
    maxShownRequests = 13
}

-------------------------
-- PERIPHERALS
-------------------------

local nativeTerm = term.current()

local bridge =
    peripheral.find("me_bridge") or
    peripheral.find("meBridge")

local colony =
    peripheral.find("colony_integrator") or
    peripheral.find("colonyIntegrator")

local monitor = peripheral.find("monitor")

if monitor then
    monitor.setTextScale(CONFIG.monitorScale)
    term.redirect(monitor)
end

if not bridge then
    term.redirect(nativeTerm)
    error("No ME Bridge found. Add/connect an Advanced Peripherals ME Bridge.")
end

if not colony then
    term.redirect(nativeTerm)
    error("No Colony Integrator found. Add/connect an Advanced Peripherals Colony Integrator inside your colony.")
end

-------------------------
-- BASIC HELPERS
-------------------------

local function safe(fn, fallback)
    local ok, result = pcall(fn)
    if ok then
        return result
    end
    return fallback, result
end

local function nowSeconds()
    if os.epoch then
        return math.floor(os.epoch("utc") / 1000)
    end

    return math.floor(os.clock())
end

local function hasMethod(obj, name)
    return type(obj[name]) == "function"
end

local function lower(value)
    return string.lower(tostring(value or ""))
end

local function clearScreen()
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(1, 1)
end

local function printLine(text, color)
    term.setTextColor(color or colors.white)
    print(tostring(text or ""))
end

local function writeFileLine(path, text)
    local f = fs.open(path, "a")
    if f then
        f.writeLine("[" .. tostring(nowSeconds()) .. "] " .. tostring(text))
        f.close()
    end
end

local function logInfo(text)
    writeFileLine(CONFIG.logFile, text)
end

local function logError(text)
    writeFileLine(CONFIG.errorLogFile, text)
end

local function trimText(text, maxLen)
    text = tostring(text or "")
    if #text <= maxLen then
        return text
    end

    return string.sub(text, 1, maxLen - 3) .. "..."
end

-------------------------
-- STARTUP SPLASH
-------------------------

local function centerText(y, text, color)
    local w, h = term.getSize()
    text = tostring(text or "")

    local x = math.max(1, math.floor((w - #text) / 2) + 1)
    term.setCursorPos(x, y)
    term.setTextColor(color or colors.white)
    term.write(text)
end

local function drawBar(y, percent)
    local w, h = term.getSize()
    local barWidth = math.min(34, math.max(10, w - 8))
    local x = math.max(1, math.floor((w - barWidth - 2) / 2) + 1)
    local filled = math.floor((percent / 100) * barWidth)

    term.setCursorPos(x, y)
    term.setTextColor(colors.gray)
    term.write("[")

    for i = 1, barWidth do
        if i <= filled then
            term.setTextColor(colors.lime)
            term.write("=")
        else
            term.setTextColor(colors.gray)
            term.write("-")
        end
    end

    term.setTextColor(colors.gray)
    term.write("]")

    local percentText = tostring(percent) .. "%"
    term.setCursorPos(math.max(1, math.floor((w - #percentText) / 2) + 1), y + 1)
    term.setTextColor(colors.white)
    term.write(percentText)
end

local function bootSplash()
    local steps = {
        "Starting colony command system...",
        "Linking AE2 ME Bridge...",
        "Checking MineColonies Integrator...",
        "Loading request filters...",
        "Preparing warehouse output...",
        "Starting auto-supply loop..."
    }

    local totalTicks = math.max(20, (CONFIG.splashSeconds or 7) * 10)

    for tick = 1, totalTicks do
        local percent = math.floor((tick / totalTicks) * 100)
        local stepIndex = math.min(#steps, math.max(1, math.ceil((percent / 100) * #steps)))

        clearScreen()

        local w, h = term.getSize()
        local startY = math.max(2, math.floor(h / 2) - 5)

        centerText(startY, CONFIG.splashTitle, colors.lime)
        centerText(startY + 1, CONFIG.splashSubtitle, colors.cyan)
        centerText(startY + 3, steps[stepIndex], colors.yellow)

        drawBar(startY + 5, percent)

        centerText(startY + 8, "AE2  ->  MineColonies", colors.gray)

        sleep(0.1)
    end

    clearScreen()
end

-------------------------
-- AE2 HELPERS
-------------------------

local function getAEItem(itemName)
    local result, err = safe(function()
        return bridge.getItem({ name = itemName })
    end, nil)

    if type(result) == "table" then
        return result
    end

    return nil
end

local function getAECount(itemName)
    local item = getAEItem(itemName)

    if type(item) ~= "table" then
        return 0
    end

    return tonumber(item.amount or item.count or 0) or 0
end

local function isAEItemCraftable(itemName)
    if hasMethod(bridge, "isCraftable") then
        local result = safe(function()
            return bridge.isCraftable({ name = itemName })
        end, false)

        if result == true then
            return true
        end
    end

    if hasMethod(bridge, "isItemCraftable") then
        local result = safe(function()
            return bridge.isItemCraftable({ name = itemName })
        end, false)

        if result == true then
            return true
        end
    end

    local item = getAEItem(itemName)
    if type(item) == "table" and item.isCraftable == true then
        return true
    end

    -- Some Advanced Peripherals versions do not report craftability cleanly.
    -- In that case, craftItem itself is the final test.
    return false
end

local function isAEItemCrafting(itemName)
    if hasMethod(bridge, "isCrafting") then
        local result = safe(function()
            return bridge.isCrafting({ name = itemName })
        end, false)

        if result == true then
            return true
        end
    end

    if hasMethod(bridge, "isItemCrafting") then
        local result = safe(function()
            return bridge.isItemCrafting({ name = itemName })
        end, false)

        if result == true then
            return true
        end
    end

    return false
end

local function exportAEItem(itemName, amount)
    amount = math.max(1, tonumber(amount) or 1)
    amount = math.min(amount, CONFIG.maxExportPerRequest)

    local before = getAECount(itemName)

    if before <= 0 then
        return 0, "none in AE2"
    end

    amount = math.min(amount, before)

    local result, err

    if hasMethod(bridge, "exportItem") then
        result, err = safe(function()
            return bridge.exportItem({ name = itemName, count = amount }, CONFIG.outputTarget)
        end, nil)
    elseif hasMethod(bridge, "exportItemToPeripheral") then
        result, err = safe(function()
            return bridge.exportItemToPeripheral({ name = itemName, count = amount }, CONFIG.outputTarget)
        end, nil)
    else
        return 0, "ME Bridge has no exportItem/exportItemToPeripheral method"
    end

    if type(result) == "number" then
        return result, nil
    end

    if type(result) == "table" then
        local moved = tonumber(result.amount or result.count or result.transferred or result.exported or 0) or 0

        if moved > 0 then
            return moved, nil
        end
    end

    sleep(0.15)

    local after = getAECount(itemName)
    local movedByCount = math.max(0, before - after)

    if movedByCount > 0 then
        return movedByCount, nil
    end

    return 0, tostring(err or result or "export failed")
end

-------------------------
-- CRAFTING HELPERS
-------------------------

local recentCrafts = {}

local function craftKey(itemName, amount)
    return tostring(itemName) .. "|" .. tostring(amount)
end

local function craftOnCooldown(key)
    local last = recentCrafts[key]

    if not last then
        return false
    end

    return nowSeconds() - last < CONFIG.craftCooldownSeconds
end

local function markCrafted(key)
    recentCrafts[key] = nowSeconds()
end

local function requestAECraft(itemName, amount)
    if not CONFIG.autoCraft then
        return false, "autocraft disabled"
    end

    amount = math.max(1, tonumber(amount) or 1)
    amount = math.min(amount, CONFIG.maxCraftPerRequest)

    local key = craftKey(itemName, amount)

    if craftOnCooldown(key) then
        return true, "craft cooldown"
    end

    if isAEItemCrafting(itemName) then
        markCrafted(key)
        return true, "already crafting"
    end

    local result, err

    if hasMethod(bridge, "craftItem") then
        result, err = safe(function()
            return bridge.craftItem({ name = itemName, count = amount })
        end, nil)
    else
        return false, "ME Bridge has no craftItem method"
    end

    if result == true or type(result) == "table" then
        markCrafted(key)
        return true, "craft scheduled"
    end

    -- Some versions return nil but still start the job. Mark it briefly so it does not spam.
    if result == nil and err == nil then
        markCrafted(key)
        return true, "craft maybe scheduled"
    end

    return false, tostring(err or result or "craft failed")
end

-------------------------
-- MINECOLONIES REQUEST PARSING
-------------------------

local genericSkipWords = {
    "tool of class",
    "of class",
    "minimum level",
    "maximum level",
    "armor",
    "equipment",
    "repair",
    "food",
    "fuel",
    "compostable",
    "fertilizer",
    "flowers",
    "smeltable ore",
    "stack list",
    "rallying banner",
    "guard tool",
    "crafter"
}

local itemNameSkipWords = {
    "sword",
    "pickaxe",
    "axe",
    "shovel",
    "hoe",
    "helmet",
    "chestplate",
    "leggings",
    "boots",
    "shield",
    "bow",
    "crossbow",
    "trident"
}

local function requestText(req)
    local parts = {
        req.name,
        req.desc,
        req.description,
        req.target,
        req.state,
        req.id
    }

    local text = ""

    for _, part in ipairs(parts) do
        text = text .. " " .. tostring(part or "")
    end

    return lower(text)
end

local function findFirstItemTable(req)
    local candidates = {}

    if type(req.items) == "table" then
        if #req.items > 0 then
            for _, item in ipairs(req.items) do
                table.insert(candidates, item)
            end
        else
            table.insert(candidates, req.items)
        end
    end

    if type(req.item) == "table" then
        table.insert(candidates, req.item)
    end

    if type(req.stack) == "table" then
        table.insert(candidates, req.stack)
    end

    if type(req.requestedItem) == "table" then
        table.insert(candidates, req.requestedItem)
    end

    for _, item in ipairs(candidates) do
        if type(item) == "table" then
            local name = item.name or item.item or item.id or item.itemName

            if type(name) == "string" and name ~= "" and name ~= "minecraft:air" then
                return item
            end
        end
    end

    return nil
end

local function getRequestAmount(req, item)
    local possible = {
        req.count,
        req.amount,
        req.quantity,
        req.qty,
        req.minCount,
        req.missing,
        req.needed,
        item and item.count,
        item and item.amount,
        item and item.quantity,
        item and item.qty,
        item and item.minCount
    }

    for _, value in ipairs(possible) do
        local n = tonumber(value)

        if n and n > 0 then
            return math.floor(n)
        end
    end

    return 1
end

local function parseRequest(req)
    if type(req) ~= "table" then
        return nil, "request was not a table"
    end

    local item = findFirstItemTable(req)

    if not item then
        return nil, "no item table"
    end

    local itemName = item.name or item.item or item.id or item.itemName

    if type(itemName) ~= "string" or itemName == "" or itemName == "minecraft:air" then
        return nil, "bad item name"
    end

    local amount = getRequestAmount(req, item)

    return {
        item = item,
        itemName = itemName,
        amount = amount,
        displayName = req.name or req.desc or req.description or item.displayName or itemName,
        target = req.target or req.building or req.resolver or "Unknown target",
        id = req.id or req.token or req.name or req.desc or itemName
    }, nil
end

local function shouldSkipRequest(req, parsed)
    local text = requestText(req)
    local itemName = lower(parsed.itemName)

    if CONFIG.skipNBT then
        local item = parsed.item

        if item.nbt or item.tag or item.fingerprint then
            return true, "NBT/special item"
        end
    end

    if CONFIG.skipGenericRequests then
        for _, word in ipairs(genericSkipWords) do
            if string.find(text, word, 1, true) then
                return true, "generic/manual: " .. word
            end
        end
    end

    for _, word in ipairs(itemNameSkipWords) do
        if string.find(itemName, word, 1, true) then
            return true, "tool/armor item"
        end
    end

    return false, nil
end

-------------------------
-- REQUEST COOLDOWN
-------------------------

local recentExports = {}

local function requestKey(parsed)
    return tostring(parsed.id) .. "|" .. tostring(parsed.itemName) .. "|" .. tostring(parsed.amount)
end

local function exportOnCooldown(key)
    local last = recentExports[key]

    if not last then
        return false
    end

    return nowSeconds() - last < CONFIG.requestCooldownSeconds
end

local function markExported(key)
    recentExports[key] = nowSeconds()
end

-------------------------
-- COLONY HELPERS
-------------------------

local function getColonyName()
    local name = safe(function()
        return colony.getColonyName()
    end, "Unknown Colony")

    return tostring(name or "Unknown Colony")
end

local function getColonyStatus()
    local citizens = safe(function()
        return colony.amountOfCitizens()
    end, "?")

    local maxCitizens = safe(function()
        return colony.maxOfCitizens()
    end, "?")

    local happiness = safe(function()
        return colony.getHappiness()
    end, "?")

    local underAttack = safe(function()
        return colony.isUnderAttack()
    end, false)

    return {
        citizens = citizens,
        maxCitizens = maxCitizens,
        happiness = happiness,
        underAttack = underAttack == true
    }
end

local function getRequests()
    local requests, err = safe(function()
        return colony.getRequests()
    end, nil)

    if type(requests) ~= "table" then
        return nil, tostring(err or "getRequests returned no table")
    end

    return requests, nil
end

-------------------------
-- MAIN SCAN
-------------------------

local function scanRequests()
    clearScreen()

    local colonyName = getColonyName()
    local status = getColonyStatus()

    printLine("HackThePlanet Colony Supply", colors.lime)
    printLine("AE2 -> MineColonies", colors.cyan)
    printLine("Colony: " .. colonyName, colors.yellow)
    printLine("Output: ME Bridge/" .. CONFIG.outputTarget, colors.gray)

    if status.underAttack then
        printLine("ALERT: COLONY UNDER ATTACK", colors.red)
    else
        printLine("Status: Safe", colors.green)
    end

    printLine("Citizens: " .. tostring(status.citizens) .. " / " .. tostring(status.maxCitizens), colors.white)
    printLine("Happiness: " .. tostring(status.happiness), colors.white)
    printLine("")

    local requests, err = getRequests()

    if not requests then
        printLine("Could not read MineColonies requests.", colors.red)
        printLine(trimText(err, 40), colors.red)
        logError("getRequests failed: " .. tostring(err))
        return
    end

    local stats = {
        total = 0,
        sent = 0,
        crafting = 0,
        skipped = 0,
        waiting = 0,
        missing = 0,
        bad = 0
    }

    local shown = 0

    for _, req in pairs(requests) do
        stats.total = stats.total + 1

        local parsed, parseErr = parseRequest(req)

        if not parsed then
            stats.bad = stats.bad + 1
            logError("Bad request: " .. tostring(parseErr))
        else
            local skip, skipReason = shouldSkipRequest(req, parsed)

            if skip then
                stats.skipped = stats.skipped + 1

                if shown < CONFIG.maxShownRequests then
                    shown = shown + 1
                    printLine("[MANUAL] " .. trimText(parsed.displayName, 32), colors.lightBlue)
                end
            else
                local key = requestKey(parsed)

                if exportOnCooldown(key) then
                    stats.waiting = stats.waiting + 1

                    if shown < CONFIG.maxShownRequests then
                        shown = shown + 1
                        printLine("[WAIT] " .. tostring(parsed.amount) .. "x " .. trimText(parsed.itemName, 28), colors.gray)
                    end
                else
                    local available = getAECount(parsed.itemName)

                    if available > 0 then
                        local moved, exportErr = exportAEItem(parsed.itemName, parsed.amount)

                        if moved > 0 then
                            stats.sent = stats.sent + 1
                            markExported(key)

                            if shown < CONFIG.maxShownRequests then
                                shown = shown + 1
                                printLine("[SENT] " .. tostring(moved) .. "/" .. tostring(parsed.amount) .. "x " .. trimText(parsed.itemName, 25), colors.green)
                            end

                            logInfo("SENT " .. tostring(moved) .. "/" .. tostring(parsed.amount) .. " " .. parsed.itemName .. " -> " .. tostring(parsed.target))
                        else
                            local craftOk, craftMsg = requestAECraft(parsed.itemName, parsed.amount)

                            if craftOk then
                                stats.crafting = stats.crafting + 1

                                if shown < CONFIG.maxShownRequests then
                                    shown = shown + 1
                                    printLine("[CRAFT] " .. tostring(parsed.amount) .. "x " .. trimText(parsed.itemName, 25), colors.yellow)
                                end

                                logInfo("CRAFT " .. tostring(parsed.amount) .. " " .. parsed.itemName .. " - " .. tostring(craftMsg))
                            else
                                stats.missing = stats.missing + 1

                                if shown < CONFIG.maxShownRequests then
                                    shown = shown + 1
                                    printLine("[MISS] " .. tostring(parsed.amount) .. "x " .. trimText(parsed.itemName, 25), colors.red)
                                end

                                logInfo("MISS " .. tostring(parsed.amount) .. " " .. parsed.itemName .. " - " .. tostring(exportErr or craftMsg))
                            end
                        end
                    else
                        local craftOk, craftMsg = requestAECraft(parsed.itemName, parsed.amount)

                        if craftOk then
                            stats.crafting = stats.crafting + 1

                            if shown < CONFIG.maxShownRequests then
                                shown = shown + 1
                                printLine("[CRAFT] " .. tostring(parsed.amount) .. "x " .. trimText(parsed.itemName, 25), colors.yellow)
                            end

                            logInfo("CRAFT " .. tostring(parsed.amount) .. " " .. parsed.itemName .. " - " .. tostring(craftMsg))
                        else
                            stats.missing = stats.missing + 1

                            if shown < CONFIG.maxShownRequests then
                                shown = shown + 1
                                printLine("[MISS] " .. tostring(parsed.amount) .. "x " .. trimText(parsed.itemName, 25), colors.red)
                            end

                            logInfo("MISS " .. tostring(parsed.amount) .. " " .. parsed.itemName .. " - " .. tostring(craftMsg))
                        end
                    end
                end
            end
        end
    end

    printLine("")
    printLine("Requests: " .. tostring(stats.total), colors.white)
    printLine("Sent: " .. tostring(stats.sent) .. "  Craft: " .. tostring(stats.crafting), colors.green)
    printLine("Wait: " .. tostring(stats.waiting) .. "  Manual: " .. tostring(stats.skipped), colors.gray)
    printLine("Missing: " .. tostring(stats.missing) .. "  Bad: " .. tostring(stats.bad), colors.red)
    printLine("")
    printLine("Next scan in " .. tostring(CONFIG.scanSeconds) .. "s", colors.gray)
end

-------------------------
-- START
-------------------------

bootSplash()

logInfo("HackThePlanet Colony Supply started.")
logInfo("Output target: " .. tostring(CONFIG.outputTarget))

while true do
    local ok, err = pcall(scanRequests)

    if not ok then
        clearScreen()
        printLine("HackThePlanet Colony Supply", colors.lime)
        printLine("SCRIPT ERROR", colors.red)
        printLine(trimText(err, 45), colors.red)
        logError("Main loop error: " .. tostring(err))
    end

    sleep(CONFIG.scanSeconds)
end
