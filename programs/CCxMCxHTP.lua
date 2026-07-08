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
    splashSeconds = 15,
    splashTitle = "HackThePlanet",
    splashSubtitle = "CC & MineColonies Program",
    splashFooter = "AE2 Auto-Supply Command Center",

    -- Monitor settings.
    monitorScale = 0.5,

    -- Log files.
    logFile = "htp_colony.log",
    errorLogFile = "htp_colony_errors.log",

    -- Display limits so the monitor does not get too messy.
    maxShownRequests = 8,
    maxRecentActions = 5
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
    term.setBackgroundColor(colors.black)
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
    maxLen = tonumber(maxLen) or 20

    if maxLen <= 3 then
        return string.sub(text, 1, maxLen)
    end

    if #text <= maxLen then
        return text
    end

    return string.sub(text, 1, maxLen - 3) .. "..."
end

local function formatNumber(value, places)
    local n = tonumber(value)

    if not n then
        return tostring(value or "?")
    end

    local mult = 10 ^ (places or 0)
    local rounded = math.floor(n * mult + 0.5) / mult

    if places and places > 0 then
        local s = tostring(rounded)
        if not string.find(s, "%.") then
            s = s .. "."
        end
        local decimals = #string.match(s, "%.(.*)$")
        while decimals < places do
            s = s .. "0"
            decimals = decimals + 1
        end
        return s
    end

    return tostring(rounded)
end

local function formatTime(seconds)
    seconds = math.max(0, tonumber(seconds) or 0)

    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    local s = math.floor(seconds % 60)

    if h > 0 then
        return tostring(h) .. "h " .. tostring(m) .. "m"
    end

    if m > 0 then
        return tostring(m) .. "m " .. tostring(s) .. "s"
    end

    return tostring(s) .. "s"
end

-------------------------
-- PRETTY UI HELPERS
-------------------------

local SESSION = {
    started = nowSeconds(),
    scans = 0,
    sent = 0,
    crafting = 0,
    missing = 0,
    manual = 0,
    waiting = 0,
    bad = 0,
    lastAction = "System booted.",
    actions = {}
}

local function addAction(text)
    text = tostring(text or "")
    SESSION.lastAction = text
    table.insert(SESSION.actions, 1, text)

    while #SESSION.actions > CONFIG.maxRecentActions do
        table.remove(SESSION.actions)
    end
end

local function writeAt(x, y, text, color, bg)
    local w, h = term.getSize()
    if y < 1 or y > h then return end
    if x < 1 then x = 1 end
    if x > w then return end

    text = tostring(text or "")
    text = trimText(text, w - x + 1)

    term.setCursorPos(x, y)
    term.setBackgroundColor(bg or colors.black)
    term.setTextColor(color or colors.white)
    term.write(text)
    term.setBackgroundColor(colors.black)
end

local function fillAt(x, y, width, char, color, bg)
    width = math.max(0, tonumber(width) or 0)
    if width <= 0 then return end
    writeAt(x, y, string.rep(char or " ", width), color, bg)
end

local function centerAt(y, text, color)
    local w, h = term.getSize()
    text = tostring(text or "")
    local x = math.max(1, math.floor((w - #text) / 2) + 1)
    writeAt(x, y, text, color)
end

local function drawBox(x, y, width, height, title, color)
    color = color or colors.gray
    width = math.max(4, tonumber(width) or 4)
    height = math.max(3, tonumber(height) or 3)

    writeAt(x, y, "+" .. string.rep("-", width - 2) .. "+", color)

    for row = 1, height - 2 do
        writeAt(x, y + row, "|", color)
        fillAt(x + 1, y + row, width - 2, " ", colors.white, colors.black)
        writeAt(x + width - 1, y + row, "|", color)
    end

    writeAt(x, y + height - 1, "+" .. string.rep("-", width - 2) .. "+", color)

    if title and title ~= "" and width > 8 then
        writeAt(x + 2, y, " " .. trimText(title, width - 6) .. " ", colors.yellow)
    end
end

local function drawProgressBar(x, y, width, percent, color)
    percent = math.max(0, math.min(100, tonumber(percent) or 0))
    width = math.max(6, tonumber(width) or 6)

    local filled = math.floor((percent / 100) * width)

    writeAt(x, y, "[", colors.gray)

    for i = 1, width do
        if i <= filled then
            writeAt(x + i, y, "=", color or colors.lime)
        else
            writeAt(x + i, y, "-", colors.gray)
        end
    end

    writeAt(x + width + 1, y, "]", colors.gray)
end

-------------------------
-- STARTUP SPLASH
-------------------------

local function bootSplash()
    local steps = {
        "Booting HackThePlanet systems...",
        "Loading CC:Tweaked services...",
        "Connecting to AE2 network...",
        "Checking ME Bridge peripheral...",
        "Checking MineColonies Integrator...",
        "Loading request filters...",
        "Preparing colony supply cache...",
        "Starting warehouse output controller...",
        "Finalizing command center UI...",
        "System ready."
    }

    local totalTicks = math.max(20, (CONFIG.splashSeconds or 15) * 10)

    for tick = 1, totalTicks do
        local percent = math.floor((tick / totalTicks) * 100)
        local stepIndex = math.min(#steps, math.max(1, math.ceil((percent / 100) * #steps)))

        clearScreen()

        local w, h = term.getSize()
        local startY = math.max(2, math.floor(h / 2) - 7)
        local barWidth = math.min(42, math.max(18, w - 12))
        local barX = math.max(1, math.floor((w - barWidth - 2) / 2) + 1)

        centerAt(startY, "========================================", colors.gray)
        centerAt(startY + 1, CONFIG.splashTitle, colors.lime)
        centerAt(startY + 2, CONFIG.splashSubtitle, colors.cyan)
        centerAt(startY + 3, CONFIG.splashFooter, colors.yellow)
        centerAt(startY + 4, "========================================", colors.gray)

        centerAt(startY + 6, steps[stepIndex], colors.white)
        drawProgressBar(barX, startY + 8, barWidth, percent, colors.lime)
        centerAt(startY + 10, tostring(percent) .. "%", colors.white)

        local dots = string.rep(".", (tick % 4))
        centerAt(startY + 12, "Initializing" .. dots, colors.gray)

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

    local active = safe(function()
        return colony.isActive()
    end, nil)

    local constructionSites = safe(function()
        return colony.amountOfConstructionSites()
    end, "?")

    local graves = safe(function()
        return colony.amountOfGraves()
    end, "?")

    return {
        citizens = citizens,
        maxCitizens = maxCitizens,
        happiness = happiness,
        underAttack = underAttack == true,
        active = active,
        constructionSites = constructionSites,
        graves = graves
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
-- DASHBOARD
-------------------------

local function drawHeader()
    local w, h = term.getSize()

    fillAt(1, 1, w, "=", colors.gray)
    centerAt(1, " HackThePlanet Colony Supply ", colors.lime)
    centerAt(2, "AE2  ->  MineColonies Auto-Supply", colors.cyan)
    fillAt(1, 3, w, "=", colors.gray)
end

local function drawSmallDashboard(colonyName, status, stats, requestRows)
    clearScreen()
    drawHeader()

    printLine("Colony: " .. colonyName, colors.yellow)

    if status.underAttack then
        printLine("Status: UNDER ATTACK", colors.red)
    else
        printLine("Status: Safe", colors.lime)
    end

    printLine("Citizens: " .. tostring(status.citizens) .. " / " .. tostring(status.maxCitizens), colors.white)
    printLine("Happiness: " .. formatNumber(status.happiness, 2), colors.white)
    printLine("Output: ME Bridge/" .. CONFIG.outputTarget, colors.gray)
    printLine("Uptime: " .. formatTime(nowSeconds() - SESSION.started), colors.gray)
    printLine("")

    for _, row in ipairs(requestRows) do
        printLine(row.text, row.color)
    end

    printLine("")
    printLine("Requests: " .. tostring(stats.total), colors.white)
    printLine("Sent: " .. tostring(stats.sent) .. "  Craft: " .. tostring(stats.crafting), colors.green)
    printLine("Wait: " .. tostring(stats.waiting) .. "  Manual: " .. tostring(stats.skipped), colors.gray)
    printLine("Missing: " .. tostring(stats.missing) .. "  Bad: " .. tostring(stats.bad), colors.red)
    printLine("Next scan in " .. tostring(CONFIG.scanSeconds) .. "s", colors.gray)
end

local function drawPrettyDashboard(colonyName, status, stats, requestRows)
    clearScreen()

    local w, h = term.getSize()
    local leftW = math.max(28, math.floor(w * 0.52))
    local rightW = w - leftW - 1

    if rightW < 24 or h < 20 then
        drawSmallDashboard(colonyName, status, stats, requestRows)
        return
    end

    drawHeader()

    drawBox(1, 5, leftW, 9, " Colony Status ", colors.gray)
    drawBox(leftW + 2, 5, rightW, 9, " System Status ", colors.gray)

    writeAt(3, 6, "Colony:", colors.yellow)
    writeAt(12, 6, trimText(colonyName, leftW - 13), colors.white)

    if status.underAttack then
        writeAt(3, 7, "Status:", colors.yellow)
        writeAt(12, 7, "UNDER ATTACK", colors.red)
    else
        writeAt(3, 7, "Status:", colors.yellow)
        writeAt(12, 7, "Safe", colors.lime)
    end

    writeAt(3, 8, "Citizens:", colors.yellow)
    writeAt(13, 8, tostring(status.citizens) .. " / " .. tostring(status.maxCitizens), colors.white)

    writeAt(3, 9, "Happy:", colors.yellow)
    writeAt(11, 9, formatNumber(status.happiness, 2), colors.white)

    writeAt(3, 10, "Active:", colors.yellow)
    if status.active == nil then
        writeAt(11, 10, "Unknown", colors.gray)
    elseif status.active == true then
        writeAt(11, 10, "Yes", colors.lime)
    else
        writeAt(11, 10, "No", colors.red)
    end

    writeAt(3, 11, "Builds:", colors.yellow)
    writeAt(11, 11, tostring(status.constructionSites), colors.white)

    writeAt(3, 12, "Graves:", colors.yellow)
    writeAt(11, 12, tostring(status.graves), colors.white)

    local rx = leftW + 4
    writeAt(rx, 6, "Output:", colors.yellow)
    writeAt(rx + 9, 6, "ME Bridge/" .. CONFIG.outputTarget, colors.white)

    writeAt(rx, 7, "Uptime:", colors.yellow)
    writeAt(rx + 9, 7, formatTime(nowSeconds() - SESSION.started), colors.white)

    writeAt(rx, 8, "Scans:", colors.yellow)
    writeAt(rx + 9, 8, tostring(SESSION.scans), colors.white)

    writeAt(rx, 9, "Session Sent:", colors.yellow)
    writeAt(rx + 14, 9, tostring(SESSION.sent), colors.green)

    writeAt(rx, 10, "Session Craft:", colors.yellow)
    writeAt(rx + 15, 10, tostring(SESSION.crafting), colors.yellow)

    writeAt(rx, 11, "Last:", colors.yellow)
    writeAt(rx + 7, 11, trimText(SESSION.lastAction, rightW - 10), colors.white)

    local reqY = 15
    local reqH = math.max(8, h - reqY - 6)
    drawBox(1, reqY, w, reqH, " Current Requests ", colors.gray)

    local insideW = w - 4

    if #requestRows == 0 then
        centerAt(reqY + 2, "No open colony requests right now.", colors.lime)
        centerAt(reqY + 3, "System idle. Waiting for MineColonies.", colors.gray)
    else
        for i, row in ipairs(requestRows) do
            local y = reqY + i
            if y < reqY + reqH - 1 then
                writeAt(3, y, trimText(row.text, insideW), row.color)
            end
        end
    end

    local footerY = reqY + reqH + 1
    if footerY + 4 <= h then
        drawBox(1, footerY, leftW, 5, " Scan Summary ", colors.gray)
        drawBox(leftW + 2, footerY, rightW, 5, " Recent Actions ", colors.gray)

        writeAt(3, footerY + 1, "Requests: " .. tostring(stats.total), colors.white)
        writeAt(3, footerY + 2, "Sent: " .. tostring(stats.sent) .. "  Craft: " .. tostring(stats.crafting), colors.green)
        writeAt(3, footerY + 3, "Wait: " .. tostring(stats.waiting) .. "  Manual: " .. tostring(stats.skipped), colors.gray)
        writeAt(3, footerY + 4, "Missing: " .. tostring(stats.missing) .. "  Bad: " .. tostring(stats.bad), colors.red)

        local maxActionsToShow = math.min(3, #SESSION.actions)
        for i = 1, maxActionsToShow do
            writeAt(leftW + 4, footerY + i, trimText(SESSION.actions[i], rightW - 4), colors.white)
        end
    else
        writeAt(2, h - 1, "Requests: " .. tostring(stats.total) .. " | Sent: " .. tostring(stats.sent) .. " | Craft: " .. tostring(stats.crafting), colors.white)
        writeAt(2, h, "Next scan in " .. tostring(CONFIG.scanSeconds) .. "s", colors.gray)
    end
end

-------------------------
-- MAIN SCAN
-------------------------

local function scanRequests()
    SESSION.scans = SESSION.scans + 1

    local colonyName = getColonyName()
    local status = getColonyStatus()
    local requests, err = getRequests()

    local stats = {
        total = 0,
        sent = 0,
        crafting = 0,
        skipped = 0,
        waiting = 0,
        missing = 0,
        bad = 0
    }

    local requestRows = {}

    local function addRequestRow(text, color)
        if #requestRows < CONFIG.maxShownRequests then
            table.insert(requestRows, { text = text, color = color })
        end
    end

    if not requests then
        stats.bad = 1
        addRequestRow("[ERROR] Could not read MineColonies requests.", colors.red)
        addRequestRow(trimText(tostring(err), 60), colors.red)
        logError("getRequests failed: " .. tostring(err))
        addAction("getRequests failed")
        drawPrettyDashboard(colonyName, status, stats, requestRows)
        return
    end

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
                addRequestRow("[MANUAL] " .. trimText(parsed.displayName, 54) .. " (" .. trimText(skipReason, 18) .. ")", colors.lightBlue)
            else
                local key = requestKey(parsed)

                if exportOnCooldown(key) then
                    stats.waiting = stats.waiting + 1
                    addRequestRow("[WAIT] " .. tostring(parsed.amount) .. "x " .. trimText(parsed.itemName, 50), colors.gray)
                else
                    local available = getAECount(parsed.itemName)

                    if available > 0 then
                        local moved, exportErr = exportAEItem(parsed.itemName, parsed.amount)

                        if moved > 0 then
                            stats.sent = stats.sent + 1
                            SESSION.sent = SESSION.sent + moved
                            markExported(key)

                            local text = "[SENT] " .. tostring(moved) .. "/" .. tostring(parsed.amount) .. "x " .. trimText(parsed.itemName, 44)
                            addRequestRow(text, colors.lime)
                            addAction("Sent " .. tostring(moved) .. "x " .. parsed.itemName)
                            logInfo("SENT " .. tostring(moved) .. "/" .. tostring(parsed.amount) .. " " .. parsed.itemName .. " -> " .. tostring(parsed.target))
                        else
                            local craftOk, craftMsg = requestAECraft(parsed.itemName, parsed.amount)

                            if craftOk then
                                stats.crafting = stats.crafting + 1
                                SESSION.crafting = SESSION.crafting + 1

                                addRequestRow("[CRAFT] " .. tostring(parsed.amount) .. "x " .. trimText(parsed.itemName, 47), colors.yellow)
                                addAction("Crafting " .. tostring(parsed.amount) .. "x " .. parsed.itemName)
                                logInfo("CRAFT " .. tostring(parsed.amount) .. " " .. parsed.itemName .. " - " .. tostring(craftMsg))
                            else
                                stats.missing = stats.missing + 1
                                SESSION.missing = SESSION.missing + 1

                                addRequestRow("[MISS] " .. tostring(parsed.amount) .. "x " .. trimText(parsed.itemName, 48), colors.red)
                                addAction("Missing " .. parsed.itemName)
                                logInfo("MISS " .. tostring(parsed.amount) .. " " .. parsed.itemName .. " - " .. tostring(exportErr or craftMsg))
                            end
                        end
                    else
                        local craftOk, craftMsg = requestAECraft(parsed.itemName, parsed.amount)

                        if craftOk then
                            stats.crafting = stats.crafting + 1
                            SESSION.crafting = SESSION.crafting + 1

                            addRequestRow("[CRAFT] " .. tostring(parsed.amount) .. "x " .. trimText(parsed.itemName, 47), colors.yellow)
                            addAction("Crafting " .. tostring(parsed.amount) .. "x " .. parsed.itemName)
                            logInfo("CRAFT " .. tostring(parsed.amount) .. " " .. parsed.itemName .. " - " .. tostring(craftMsg))
                        else
                            stats.missing = stats.missing + 1
                            SESSION.missing = SESSION.missing + 1

                            addRequestRow("[MISS] " .. tostring(parsed.amount) .. "x " .. trimText(parsed.itemName, 48), colors.red)
                            addAction("Missing " .. parsed.itemName)
                            logInfo("MISS " .. tostring(parsed.amount) .. " " .. parsed.itemName .. " - " .. tostring(craftMsg))
                        end
                    end
                end
            end
        end
    end

    SESSION.manual = SESSION.manual + stats.skipped
    SESSION.waiting = SESSION.waiting + stats.waiting
    SESSION.bad = SESSION.bad + stats.bad

    if stats.total == 0 then
        addAction("No colony requests")
    elseif stats.sent == 0 and stats.crafting == 0 and stats.missing == 0 then
        addAction("Scanned " .. tostring(stats.total) .. " requests")
    end

    drawPrettyDashboard(colonyName, status, stats, requestRows)
end

-------------------------
-- START
-------------------------

bootSplash()

logInfo("HackThePlanet Colony Supply started.")
logInfo("Output target: " .. tostring(CONFIG.outputTarget))
addAction("Program started")

while true do
    local ok, err = pcall(scanRequests)

    if not ok then
        clearScreen()
        printLine("HackThePlanet Colony Supply", colors.lime)
        printLine("SCRIPT ERROR", colors.red)
        printLine(trimText(err, 45), colors.red)
        logError("Main loop error: " .. tostring(err))
        addAction("Script error")
    end

    sleep(CONFIG.scanSeconds)
end
