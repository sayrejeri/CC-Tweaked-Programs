-- startup
-- HackThePlanet CC & MineColonies Program
-- CC:Tweaked + Advanced Peripherals + AE2 + MineColonies
-- Dual-monitor AE2 auto-supply dashboard + touch control panel.

-------------------------
-- CONFIG
-------------------------

local CONFIG = {
    outputTarget = "bottom",
    scanSeconds = 30,
    requestCooldownSeconds = 120,
    craftCooldownSeconds = 300,
    denyCooldownSeconds = 300,
    maxExportPerRequest = 512,
    maxCraftPerRequest = 512,
    autoCraft = true,
    skipNBT = true,
    skipGenericRequests = true,

    -- AUTO = safe requests send automatically unless blacklisted/protected
    -- APPROVAL = requests wait for monitor approval
    -- WHITELIST = only whitelisted/ALWAYS-approved items send automatically
    defaultMode = "AUTO",

    splashSeconds = 15,
    splashTitle = "HackThePlanet",
    splashSubtitle = "CC & MineColonies Program",
    splashFooter = "AE2 Auto-Supply Command Center",

    monitorScale = 0.5,
    mainMonitorName = nil,
    controlMonitorName = nil,

    settingsFile = "htp_settings.cfg",
    whitelistFile = "htp_whitelist.txt",
    blacklistFile = "htp_blacklist.txt",
    protectedFile = "htp_protected.txt",
    logFile = "htp_colony.log",
    errorLogFile = "htp_colony_errors.log",
    historyFile = "htp_history.log",

    maxShownRequests = 10,
    maxRecentActions = 6,
    maxHistoryLines = 40,
    maxBuildRows = 32
}

local DEFAULT_PROTECTED = {
    ["minecraft:diamond"] = true,
    ["minecraft:diamond_block"] = true,
    ["minecraft:emerald"] = true,
    ["minecraft:emerald_block"] = true,
    ["minecraft:netherite_ingot"] = true,
    ["minecraft:netherite_block"] = true,
    ["minecraft:nether_star"] = true,
    ["minecraft:dragon_egg"] = true,
    ["allthemodium:allthemodium_ingot"] = true,
    ["allthemodium:allthemodium_block"] = true,
    ["allthemodium:vibranium_ingot"] = true,
    ["allthemodium:vibranium_block"] = true,
    ["allthemodium:unobtainium_ingot"] = true,
    ["allthemodium:unobtainium_block"] = true
}

-------------------------
-- PERIPHERALS
-------------------------

local nativeTerm = term.current()
local bridge = peripheral.find("me_bridge") or peripheral.find("meBridge")
local colony = peripheral.find("colony_integrator") or peripheral.find("colonyIntegrator")

if not bridge then error("No ME Bridge found. Add/connect an Advanced Peripherals ME Bridge.") end
if not colony then error("No Colony Integrator found. Add/connect a Colony Integrator inside your colony.") end

-------------------------
-- HELPERS
-------------------------

local function safe(fn, fallback)
    local ok, result = pcall(fn)
    if ok then return result end
    return fallback, result
end

local function nowSeconds()
    if os.epoch then return math.floor(os.epoch("utc") / 1000) end
    return math.floor(os.clock())
end

local function hasMethod(obj, name)
    return type(obj[name]) == "function"
end

local function lower(value)
    return string.lower(tostring(value or ""))
end

local function trimText(text, maxLen)
    text = tostring(text or "")
    maxLen = tonumber(maxLen) or 20
    if maxLen <= 0 then return "" end
    if #text <= maxLen then return text end
    if maxLen <= 3 then return string.sub(text, 1, maxLen) end
    return string.sub(text, 1, maxLen - 3) .. "..."
end

local function formatNumber(value, places)
    local n = tonumber(value)
    if not n then return tostring(value or "?") end
    if places and places > 0 then return string.format("%." .. tostring(places) .. "f", n) end
    return tostring(math.floor(n + 0.5))
end

local function formatTime(seconds)
    seconds = math.max(0, tonumber(seconds) or 0)
    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    local s = math.floor(seconds % 60)
    if h > 0 then return tostring(h) .. "h " .. tostring(m) .. "m" end
    if m > 0 then return tostring(m) .. "m " .. tostring(s) .. "s" end
    return tostring(s) .. "s"
end

local function writeFileLine(path, text)
    local f = fs.open(path, "a")
    if f then
        f.writeLine("[" .. tostring(nowSeconds()) .. "] " .. tostring(text))
        f.close()
    end
end

local function logInfo(text) writeFileLine(CONFIG.logFile, text) end
local function logError(text) writeFileLine(CONFIG.errorLogFile, text) end
local function logHistory(text) writeFileLine(CONFIG.historyFile, text) end

local function readLines(path, limit)
    local lines = {}
    if not fs.exists(path) then return lines end
    local f = fs.open(path, "r")
    if not f then return lines end
    while true do
        local line = f.readLine()
        if not line then break end
        table.insert(lines, line)
    end
    f.close()

    if limit and #lines > limit then
        local out = {}
        for i = math.max(1, #lines - limit + 1), #lines do table.insert(out, lines[i]) end
        return out
    end

    return lines
end

local function loadSet(path)
    local set = {}
    for _, line in ipairs(readLines(path)) do
        line = string.gsub(line, "^%s+", "")
        line = string.gsub(line, "%s+$", "")
        if line ~= "" and string.sub(line, 1, 1) ~= "#" then set[line] = true end
    end
    return set
end

local function saveSet(path, set)
    local f = fs.open(path, "w")
    if not f then return end
    local list = {}
    for key, value in pairs(set) do if value == true then table.insert(list, key) end end
    table.sort(list)
    for _, item in ipairs(list) do f.writeLine(item) end
    f.close()
end

local function mergeSets(a, b)
    local out = {}
    for k, v in pairs(a or {}) do if v then out[k] = true end end
    for k, v in pairs(b or {}) do if v then out[k] = true end end
    return out
end

local function loadSettings()
    local settings = {}
    for _, line in ipairs(readLines(CONFIG.settingsFile)) do
        local key, value = string.match(line, "^([%w_]+)%s*=%s*(.-)%s*$")
        if key and value then settings[key] = value end
    end
    return settings
end

local function saveSettings(settings)
    local f = fs.open(CONFIG.settingsFile, "w")
    if not f then return end
    local keys = {}
    for key, _ in pairs(settings) do table.insert(keys, key) end
    table.sort(keys)
    for _, key in ipairs(keys) do f.writeLine(key .. "=" .. tostring(settings[key])) end
    f.close()
end

-------------------------
-- MONITORS / UI HELPERS
-------------------------

local MAIN = { name = "terminal", object = nativeTerm, w = 51, h = 19, area = 0 }
local CONTROL = nil
local BUTTONS = {}

local function getMonitorSize(mon)
    local ok, w, h = pcall(function() return mon.getSize() end)
    if ok and type(w) == "number" and type(h) == "number" then return w, h end
    return nil, nil
end

local function initMonitors()
    local monitors = {}

    for _, name in ipairs(peripheral.getNames()) do
        if peripheral.getType(name) == "monitor" then
            local m = peripheral.wrap(name)
            pcall(function() m.setTextScale(CONFIG.monitorScale) end)
            local w, h = getMonitorSize(m)
            if w and h then
                table.insert(monitors, { name = name, object = m, w = w, h = h, area = w * h })
            end
        end
    end

    table.sort(monitors, function(a, b) return a.area > b.area end)

    if CONFIG.mainMonitorName then
        for _, mon in ipairs(monitors) do if mon.name == CONFIG.mainMonitorName then MAIN = mon end end
    elseif #monitors >= 1 then
        MAIN = monitors[1]
    end

    if CONFIG.controlMonitorName then
        for _, mon in ipairs(monitors) do if mon.name == CONFIG.controlMonitorName then CONTROL = mon end end
    elseif #monitors >= 2 then
        CONTROL = monitors[2]
    end

    if MAIN.object == nativeTerm then
        local w, h = term.getSize()
        MAIN.w, MAIN.h, MAIN.area = w, h, w * h
    end
end

local function withScreen(screen, fn)
    local old = term.current()
    term.redirect(screen.object)
    local ok, err = pcall(fn)
    term.redirect(old or nativeTerm)
    if not ok then error(err) end
end

local function clearScreen()
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(1, 1)
end

local function writeAt(x, y, text, color, bg)
    local w, h = term.getSize()
    if y < 1 or y > h then return end
    if x < 1 then x = 1 end
    if x > w then return end
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
    writeAt(math.max(1, math.floor((w - #text) / 2) + 1), y, text, color)
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
    if title and title ~= "" and width > 8 then writeAt(x + 2, y, " " .. trimText(title, width - 6) .. " ", colors.yellow) end
end

local function drawProgressBar(x, y, width, percent, color)
    percent = math.max(0, math.min(100, tonumber(percent) or 0))
    width = math.max(6, tonumber(width) or 6)
    local filled = math.floor((percent / 100) * width)
    writeAt(x, y, "[", colors.gray)
    for i = 1, width do
        if i <= filled then writeAt(x + i, y, "=", color or colors.lime) else writeAt(x + i, y, "-", colors.gray) end
    end
    writeAt(x + width + 1, y, "]", colors.gray)
end

local function addButton(screenName, x, y, width, height, label, action, color)
    width = math.max(4, width)
    height = math.max(1, height)
    table.insert(BUTTONS, { screen = screenName, x1 = x, y1 = y, x2 = x + width - 1, y2 = y + height - 1, action = action, label = label })
    color = color or colors.gray
    for row = 0, height - 1 do writeAt(x, y + row, string.rep(" ", width), colors.white, color) end
    local tx = x + math.max(0, math.floor((width - #label) / 2))
    local ty = y + math.floor(height / 2)
    writeAt(tx, ty, label, colors.black, color)
end

-------------------------
-- STATE
-------------------------

local SETTINGS = loadSettings()
local WHITELIST = loadSet(CONFIG.whitelistFile)
local BLACKLIST = loadSet(CONFIG.blacklistFile)
local PROTECTED = mergeSets(DEFAULT_PROTECTED, loadSet(CONFIG.protectedFile))

local STATE = {
    mode = SETTINGS.mode or CONFIG.defaultMode,
    page = SETTINGS.page or "DASHBOARD",
    paused = SETTINGS.paused == "true",
    selectedPending = tonumber(SETTINGS.selectedPending or "1") or 1,
    started = nowSeconds(),
    scans = 0,
    sent = 0,
    crafting = 0,
    missing = 0,
    manual = 0,
    waiting = 0,
    bad = 0,
    actions = {},
    lastAction = "Program started",
    pending = {},
    pendingOrder = {},
    approvedOnce = {},
    deniedUntil = {},
    requestRows = {},
    buildRows = {},
    workOrderRows = {},
    stats = { total = 0, sent = 0, crafting = 0, skipped = 0, waiting = 0, missing = 0, bad = 0, pending = 0 },
    colonyName = "Unknown Colony",
    status = { citizens = "?", maxCitizens = "?", happiness = "?", underAttack = false, active = nil, constructionSites = "?", graves = "?" },
    nextScanNow = false
}

local function saveModeAndPage()
    SETTINGS.mode = STATE.mode
    SETTINGS.page = STATE.page
    SETTINGS.paused = tostring(STATE.paused)
    SETTINGS.selectedPending = tostring(STATE.selectedPending)
    saveSettings(SETTINGS)
end

local function addAction(text)
    text = tostring(text or "")
    STATE.lastAction = text
    table.insert(STATE.actions, 1, text)
    while #STATE.actions > CONFIG.maxRecentActions do table.remove(STATE.actions) end
    logHistory(text)
end

local function setMode(mode)
    if mode ~= "AUTO" and mode ~= "APPROVAL" and mode ~= "WHITELIST" then return end
    STATE.mode = mode
    saveModeAndPage()
    addAction("Mode set to " .. mode)
end

local function setPage(page)
    STATE.page = page
    saveModeAndPage()
    addAction("Page: " .. page)
end

local function setPaused(paused)
    STATE.paused = paused == true
    saveModeAndPage()
    if STATE.paused then addAction("Auto supply paused") else addAction("Auto supply resumed") end
end

local function clearHistory()
    local f = fs.open(CONFIG.historyFile, "w")
    if f then f.close() end
    STATE.actions = {}
    STATE.lastAction = "History cleared"
    logHistory("History cleared")
end

-------------------------
-- BOOT SPLASH
-------------------------

local function drawBoot(percent, step)
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
    centerAt(startY + 6, step, colors.white)
    drawProgressBar(barX, startY + 8, barWidth, percent, colors.lime)
    centerAt(startY + 10, tostring(percent) .. "%", colors.white)
    centerAt(startY + 12, "Initializing" .. string.rep(".", percent % 4), colors.gray)
end

local function bootSplash()
    local steps = {
        "Booting HackThePlanet systems...",
        "Loading CC:Tweaked services...",
        "Connecting to AE2 network...",
        "Checking ME Bridge peripheral...",
        "Checking MineColonies Integrator...",
        "Detecting dual monitors...",
        "Loading whitelist / blacklist / protected rules...",
        "Preparing approval controls...",
        "Reading building request pages...",
        "System ready."
    }

    local totalTicks = math.max(20, (CONFIG.splashSeconds or 15) * 10)
    for tick = 1, totalTicks do
        local percent = math.floor((tick / totalTicks) * 100)
        local stepIndex = math.min(#steps, math.max(1, math.ceil((percent / 100) * #steps)))
        withScreen(MAIN, function() drawBoot(percent, steps[stepIndex]) end)
        if CONTROL then withScreen(CONTROL, function() drawBoot(percent, "Control Panel: " .. steps[stepIndex]) end) end
        sleep(0.1)
    end
end

-------------------------
-- AE2
-------------------------

local function getAEItem(itemName)
    local result = safe(function() return bridge.getItem({ name = itemName }) end, nil)
    if type(result) == "table" then return result end
    return nil
end

local function getAECount(itemName)
    local item = getAEItem(itemName)
    if type(item) ~= "table" then return 0 end
    return tonumber(item.amount or item.count or 0) or 0
end

local function isAEItemCrafting(itemName)
    if hasMethod(bridge, "isCrafting") and safe(function() return bridge.isCrafting({ name = itemName }) end, false) == true then return true end
    if hasMethod(bridge, "isItemCrafting") and safe(function() return bridge.isItemCrafting({ name = itemName }) end, false) == true then return true end
    return false
end

local function exportAEItem(itemName, amount)
    amount = math.max(1, tonumber(amount) or 1)
    amount = math.min(amount, CONFIG.maxExportPerRequest)
    local before = getAECount(itemName)
    if before <= 0 then return 0, "none in AE2" end
    amount = math.min(amount, before)

    local result, err
    if hasMethod(bridge, "exportItem") then
        result, err = safe(function() return bridge.exportItem({ name = itemName, count = amount }, CONFIG.outputTarget) end, nil)
    elseif hasMethod(bridge, "exportItemToPeripheral") then
        result, err = safe(function() return bridge.exportItemToPeripheral({ name = itemName, count = amount }, CONFIG.outputTarget) end, nil)
    else
        return 0, "ME Bridge has no export method"
    end

    if type(result) == "number" then return result, nil end
    if type(result) == "table" then
        local moved = tonumber(result.amount or result.count or result.transferred or result.exported or 0) or 0
        if moved > 0 then return moved, nil end
    end

    sleep(0.15)
    local after = getAECount(itemName)
    local movedByCount = math.max(0, before - after)
    if movedByCount > 0 then return movedByCount, nil end
    return 0, tostring(err or result or "export failed")
end

local recentCrafts = {}
local function craftKey(itemName, amount) return tostring(itemName) .. "|" .. tostring(amount) end
local function craftOnCooldown(key) local last = recentCrafts[key]; return last and (nowSeconds() - last < CONFIG.craftCooldownSeconds) end

local function requestAECraft(itemName, amount)
    if not CONFIG.autoCraft then return false, "autocraft disabled" end
    amount = math.max(1, tonumber(amount) or 1)
    amount = math.min(amount, CONFIG.maxCraftPerRequest)
    local key = craftKey(itemName, amount)
    if craftOnCooldown(key) then return true, "craft cooldown" end
    if isAEItemCrafting(itemName) then recentCrafts[key] = nowSeconds(); return true, "already crafting" end
    if not hasMethod(bridge, "craftItem") then return false, "ME Bridge has no craftItem method" end

    local result, err = safe(function() return bridge.craftItem({ name = itemName, count = amount }) end, nil)
    if result == true or type(result) == "table" or (result == nil and err == nil) then
        recentCrafts[key] = nowSeconds()
        return true, "craft scheduled"
    end
    return false, tostring(err or result or "craft failed")
end

-------------------------
-- MINECOLONIES PARSING
-------------------------

local genericSkipWords = {
    "tool of class", "of class", "minimum level", "maximum level", "armor", "equipment", "repair",
    "food", "fuel", "compostable", "fertilizer", "flowers", "smeltable ore", "stack list",
    "rallying banner", "guard tool", "crafter"
}

local itemNameSkipWords = {
    "sword", "pickaxe", "axe", "shovel", "hoe", "helmet", "chestplate", "leggings", "boots",
    "shield", "bow", "crossbow", "trident"
}

local function requestText(req)
    local parts = { req.name, req.desc, req.description, req.target, req.state, req.id }
    local text = ""
    for _, part in ipairs(parts) do text = text .. " " .. tostring(part or "") end
    return lower(text)
end

local function findFirstItemTable(req)
    local candidates = {}
    if type(req.items) == "table" then
        if #req.items > 0 then for _, item in ipairs(req.items) do table.insert(candidates, item) end else table.insert(candidates, req.items) end
    end
    if type(req.item) == "table" then table.insert(candidates, req.item) end
    if type(req.stack) == "table" then table.insert(candidates, req.stack) end
    if type(req.requestedItem) == "table" then table.insert(candidates, req.requestedItem) end

    for _, item in ipairs(candidates) do
        if type(item) == "table" then
            local name = item.name or item.item or item.id or item.itemName
            if type(name) == "string" and name ~= "" and name ~= "minecraft:air" then return item end
        end
    end
    return nil
end

local function getRequestAmount(req, item)
    local possible = { req.count, req.amount, req.quantity, req.qty, req.minCount, req.missing, req.needed,
        item and item.count, item and item.amount, item and item.quantity, item and item.qty, item and item.minCount }
    for _, value in ipairs(possible) do
        local n = tonumber(value)
        if n and n > 0 then return math.floor(n) end
    end
    return 1
end

local function parseRequest(req)
    if type(req) ~= "table" then return nil, "request was not a table" end
    local item = findFirstItemTable(req)
    if not item then return nil, "no item table" end
    local itemName = item.name or item.item or item.id or item.itemName
    if type(itemName) ~= "string" or itemName == "" or itemName == "minecraft:air" then return nil, "bad item name" end
    return {
        item = item,
        itemName = itemName,
        amount = getRequestAmount(req, item),
        displayName = req.name or req.desc or req.description or item.displayName or itemName,
        target = req.target or req.building or req.resolver or "Unknown target",
        id = req.id or req.token or req.name or req.desc or itemName,
        rawText = requestText(req)
    }, nil
end

local function shouldSkipRequest(req, parsed)
    local text = requestText(req)
    local itemName = lower(parsed.itemName)
    if CONFIG.skipNBT then
        local item = parsed.item
        if item.nbt or item.tag or item.fingerprint then return true, "NBT/special item" end
    end
    if CONFIG.skipGenericRequests then
        for _, word in ipairs(genericSkipWords) do
            if string.find(text, word, 1, true) then return true, "manual: " .. word end
        end
    end
    for _, word in ipairs(itemNameSkipWords) do
        if string.find(itemName, word, 1, true) then return true, "tool/armor item" end
    end
    return false, nil
end

-------------------------
-- COLONY
-------------------------

local function getColonyName()
    local name = safe(function() return colony.getColonyName() end, "Unknown Colony")
    return tostring(name or "Unknown Colony")
end

local function getColonyStatus()
    return {
        citizens = safe(function() return colony.amountOfCitizens() end, "?"),
        maxCitizens = safe(function() return colony.maxOfCitizens() end, "?"),
        happiness = safe(function() return colony.getHappiness() end, "?"),
        underAttack = safe(function() return colony.isUnderAttack() end, false) == true,
        active = safe(function() return colony.isActive() end, nil),
        constructionSites = safe(function() return colony.amountOfConstructionSites() end, "?"),
        graves = safe(function() return colony.amountOfGraves() end, "?")
    }
end

local function getRequests()
    local requests, err = safe(function() return colony.getRequests() end, nil)
    if type(requests) ~= "table" then return nil, tostring(err or "getRequests returned no table") end
    return requests, nil
end

local function stringifyWorkOrder(order)
    if type(order) ~= "table" then return tostring(order) end
    local title = order.name or order.displayName or order.type or order.workOrderType or order.buildingName or order.structurePack or order.id or "Work Order"
    local level = order.level or order.targetLevel or order.buildLevel or order.currentLevel
    local state = order.state or order.status or order.priority or order.claimedBy
    local out = tostring(title)
    if level then out = out .. " L" .. tostring(level) end
    if state then out = out .. " - " .. tostring(state) end
    return out
end

local function getWorkOrderRows()
    local rows = {}
    local methodNames = { "getWorkOrders", "getWorkorders", "getConstructionSites", "getBuildings" }

    for _, method in ipairs(methodNames) do
        if hasMethod(colony, method) then
            local result = safe(function() return colony[method]() end, nil)
            if type(result) == "table" then
                for _, order in pairs(result) do
                    table.insert(rows, "[" .. method .. "] " .. stringifyWorkOrder(order))
                    if #rows >= 12 then return rows end
                end
                if #rows > 0 then return rows end
            end
        end
    end

    return rows
end

-------------------------
-- APPROVAL / RULES
-------------------------

local recentExports = {}
local function requestKey(parsed) return tostring(parsed.id) .. "|" .. tostring(parsed.itemName) .. "|" .. tostring(parsed.amount) end
local function exportOnCooldown(key) local last = recentExports[key]; return last and (nowSeconds() - last < CONFIG.requestCooldownSeconds) end
local function markExported(key) recentExports[key] = nowSeconds() end

local function addPending(newPending, newOrder, key, parsed, reason)
    newPending[key] = { parsed = parsed, time = nowSeconds(), reason = reason or "approval" }
    table.insert(newOrder, key)
end

local function normalizeSelectedPending()
    if #STATE.pendingOrder <= 0 then STATE.selectedPending = 1; return end
    if STATE.selectedPending < 1 then STATE.selectedPending = #STATE.pendingOrder end
    if STATE.selectedPending > #STATE.pendingOrder then STATE.selectedPending = 1 end
end

local function selectedPending()
    normalizeSelectedPending()
    local key = STATE.pendingOrder[STATE.selectedPending]
    if key then return key, STATE.pending[key] end
    return nil, nil
end

local function approveSelected(always)
    local key, pending = selectedPending()
    if not pending then addAction("No pending request to approve"); return end
    STATE.approvedOnce[key] = true
    if always then
        WHITELIST[pending.parsed.itemName] = true
        BLACKLIST[pending.parsed.itemName] = nil
        saveSet(CONFIG.whitelistFile, WHITELIST)
        saveSet(CONFIG.blacklistFile, BLACKLIST)
        addAction("Approved always: " .. pending.parsed.itemName)
    else
        addAction("Approved once: " .. pending.parsed.itemName)
    end
end

local function denySelected(blacklist)
    local key, pending = selectedPending()
    if not pending then addAction("No pending request to deny"); return end
    STATE.deniedUntil[key] = nowSeconds() + CONFIG.denyCooldownSeconds
    if blacklist then
        BLACKLIST[pending.parsed.itemName] = true
        WHITELIST[pending.parsed.itemName] = nil
        saveSet(CONFIG.blacklistFile, BLACKLIST)
        saveSet(CONFIG.whitelistFile, WHITELIST)
        addAction("Blacklisted: " .. pending.parsed.itemName)
    else
        addAction("Denied once: " .. pending.parsed.itemName)
    end
end

local function nextPending(delta)
    if #STATE.pendingOrder <= 0 then return end
    STATE.selectedPending = STATE.selectedPending + delta
    normalizeSelectedPending()
    saveModeAndPage()
end

-------------------------
-- DRAWING
-------------------------

local function drawHeader(countdown)
    local w, h = term.getSize()
    local flash = STATE.status.underAttack and (nowSeconds() % 2 == 0)
    local lineColor = flash and colors.red or colors.gray
    fillAt(1, 1, w, "=", lineColor)
    if STATE.status.underAttack then centerAt(1, " !!! COLONY UNDER ATTACK !!! ", colors.red) else centerAt(1, " HackThePlanet Colony Supply ", colors.lime) end
    local pausedText = STATE.paused and " | PAUSED" or ""
    centerAt(2, "AE2 -> MineColonies Auto-Supply" .. pausedText .. " | Next Scan: " .. tostring(countdown) .. "s", STATE.paused and colors.orange or colors.cyan)
    fillAt(1, 3, w, "=", lineColor)
end

local function drawRequestRows(x, y, width, height, rows)
    if #rows == 0 then
        centerAt(y + 2, "No open colony requests right now.", colors.lime)
        centerAt(y + 3, "System idle. Waiting for MineColonies.", colors.gray)
        return
    end
    for i, row in ipairs(rows) do
        if i > height then break end
        writeAt(x, y + i - 1, trimText(row.text, width), row.color)
    end
end

local function drawSmallDashboard(countdown)
    clearScreen()
    drawHeader(countdown)
    local s = STATE.status
    writeAt(1, 4, "Colony: " .. STATE.colonyName, colors.yellow)
    writeAt(1, 5, "Status: " .. (s.underAttack and "UNDER ATTACK" or "Safe"), s.underAttack and colors.red or colors.lime)
    writeAt(1, 6, "Mode: " .. STATE.mode .. (STATE.paused and " PAUSED" or ""), STATE.paused and colors.orange or colors.yellow)
    writeAt(1, 7, "Citizens: " .. tostring(s.citizens) .. " / " .. tostring(s.maxCitizens), colors.white)
    writeAt(1, 8, "Happiness: " .. formatNumber(s.happiness, 2), colors.white)
    writeAt(1, 9, "Output: ME Bridge/" .. CONFIG.outputTarget, colors.gray)
    writeAt(1, 10, "Page: " .. STATE.page, colors.gray)
    drawRequestRows(1, 12, select(1, term.getSize()), select(2, term.getSize()) - 16, STATE.requestRows)
    local h = select(2, term.getSize())
    writeAt(1, h - 3, "Req: " .. STATE.stats.total .. " Pending: " .. STATE.stats.pending, colors.white)
    writeAt(1, h - 2, "Sent: " .. STATE.stats.sent .. " Craft: " .. STATE.stats.crafting, colors.green)
    writeAt(1, h - 1, "Missing: " .. STATE.stats.missing .. " Bad: " .. STATE.stats.bad, colors.red)
end

local function drawDashboardPage(countdown)
    local w, h = term.getSize()
    local leftW = math.max(28, math.floor(w * 0.52))
    local rightW = w - leftW - 1
    if rightW < 24 or h < 20 then drawSmallDashboard(countdown); return end

    clearScreen()
    drawHeader(countdown)
    local boxColor = STATE.status.underAttack and colors.red or colors.gray
    drawBox(1, 5, leftW, 9, " Colony Status ", boxColor)
    drawBox(leftW + 2, 5, rightW, 9, " System Status ", boxColor)

    local s = STATE.status
    writeAt(3, 6, "Colony:", colors.yellow); writeAt(12, 6, trimText(STATE.colonyName, leftW - 13), colors.white)
    writeAt(3, 7, "Status:", colors.yellow); writeAt(12, 7, s.underAttack and "UNDER ATTACK" or "Safe", s.underAttack and colors.red or colors.lime)
    writeAt(3, 8, "Citizens:", colors.yellow); writeAt(13, 8, tostring(s.citizens) .. " / " .. tostring(s.maxCitizens), colors.white)
    writeAt(3, 9, "Happy:", colors.yellow); writeAt(11, 9, formatNumber(s.happiness, 2), colors.white)
    writeAt(3, 10, "Active:", colors.yellow); writeAt(11, 10, s.active == nil and "Unknown" or (s.active and "Yes" or "No"), s.active == true and colors.lime or colors.gray)
    writeAt(3, 11, "Builds:", colors.yellow); writeAt(11, 11, tostring(s.constructionSites), colors.white)
    writeAt(3, 12, "Graves:", colors.yellow); writeAt(11, 12, tostring(s.graves), tonumber(s.graves) and tonumber(s.graves) > 0 and colors.red or colors.white)

    local rx = leftW + 4
    writeAt(rx, 6, "Mode:", colors.yellow); writeAt(rx + 7, 6, STATE.mode .. (STATE.paused and " PAUSED" or ""), STATE.paused and colors.orange or (STATE.mode == "AUTO" and colors.lime or colors.yellow))
    writeAt(rx, 7, "Output:", colors.yellow); writeAt(rx + 9, 7, "ME Bridge/" .. CONFIG.outputTarget, colors.white)
    writeAt(rx, 8, "Uptime:", colors.yellow); writeAt(rx + 9, 8, formatTime(nowSeconds() - STATE.started), colors.white)
    writeAt(rx, 9, "Scans:", colors.yellow); writeAt(rx + 9, 9, tostring(STATE.scans), colors.white)
    writeAt(rx, 10, "Pending:", colors.yellow); writeAt(rx + 10, 10, tostring(#STATE.pendingOrder), #STATE.pendingOrder > 0 and colors.yellow or colors.gray)
    writeAt(rx, 11, "Session Sent:", colors.yellow); writeAt(rx + 14, 11, tostring(STATE.sent), colors.green)
    writeAt(rx, 12, "Last:", colors.yellow); writeAt(rx + 7, 12, trimText(STATE.lastAction, rightW - 10), colors.white)

    local reqY = 15
    local reqH = math.max(8, h - reqY - 6)
    drawBox(1, reqY, w, reqH, " Current Requests ", boxColor)
    drawRequestRows(3, reqY + 1, w - 4, reqH - 2, STATE.requestRows)

    local footerY = reqY + reqH + 1
    if footerY + 4 <= h then
        drawBox(1, footerY, leftW, 5, " Scan Summary ", colors.gray)
        drawBox(leftW + 2, footerY, rightW, 5, " Recent Actions ", colors.gray)
        writeAt(3, footerY + 1, "Requests: " .. tostring(STATE.stats.total) .. "  Pending: " .. tostring(STATE.stats.pending), colors.white)
        writeAt(3, footerY + 2, "Sent: " .. tostring(STATE.stats.sent) .. "  Craft: " .. tostring(STATE.stats.crafting), colors.green)
        writeAt(3, footerY + 3, "Wait: " .. tostring(STATE.stats.waiting) .. "  Manual: " .. tostring(STATE.stats.skipped), colors.gray)
        writeAt(3, footerY + 4, "Missing: " .. tostring(STATE.stats.missing) .. "  Bad: " .. tostring(STATE.stats.bad), colors.red)
        for i = 1, math.min(3, #STATE.actions) do writeAt(leftW + 4, footerY + i, trimText(STATE.actions[i], rightW - 4), colors.white) end
    end
end

local function drawRequestsPage(countdown)
    clearScreen(); drawHeader(countdown)
    local w, h = term.getSize()
    drawBox(1, 5, w, h - 5, " Request Details ", colors.gray)
    writeAt(3, 6, "Mode: " .. STATE.mode .. " | Pending: " .. tostring(#STATE.pendingOrder) .. " | Safe requests are the build-material automation", colors.yellow)
    drawRequestRows(3, 8, w - 4, h - 9, STATE.requestRows)
end

local function drawBuildPage(countdown)
    clearScreen(); drawHeader(countdown)
    local w, h = term.getSize()
    local half = math.floor((w - 3) / 2)
    drawBox(1, 5, half, h - 5, " Build Material Totals ", colors.gray)
    drawBox(half + 2, 5, w - half - 1, h - 5, " Work Orders / Sites ", colors.gray)

    if #STATE.buildRows == 0 then
        writeAt(3, 7, "No material requests found.", colors.lime)
    else
        local y = 6
        for _, row in ipairs(STATE.buildRows) do
            y = y + 1
            if y > h - 2 then break end
            writeAt(3, y, trimText(row, half - 4), colors.white)
        end
    end

    if #STATE.workOrderRows == 0 then
        writeAt(half + 4, 7, "Construction Sites: " .. tostring(STATE.status.constructionSites), colors.white)
        writeAt(half + 4, 8, "No detailed work-order method found.", colors.gray)
        writeAt(half + 4, 10, "MineColonies requests are used as", colors.gray)
        writeAt(half + 4, 11, "the build material source.", colors.gray)
    else
        local y = 6
        for _, row in ipairs(STATE.workOrderRows) do
            y = y + 1
            if y > h - 2 then break end
            writeAt(half + 4, y, trimText(row, w - half - 5), colors.white)
        end
    end
end

local function drawPendingPage(countdown)
    clearScreen(); drawHeader(countdown)
    local w, h = term.getSize()
    drawBox(1, 5, w, h - 5, " Pending Approval ", colors.gray)
    if #STATE.pendingOrder == 0 then centerAt(8, "No pending approvals.", colors.lime); return end
    local y = 7
    for i, key in ipairs(STATE.pendingOrder) do
        local p = STATE.pending[key]
        if p then
            local prefix = i == STATE.selectedPending and "> " or "  "
            local msg = prefix .. tostring(i) .. "/" .. tostring(#STATE.pendingOrder) .. " " .. tostring(p.parsed.amount) .. "x " .. p.parsed.itemName .. " (" .. tostring(p.reason) .. ")"
            writeAt(3, y, trimText(msg, w - 6), i == STATE.selectedPending and colors.yellow or colors.white)
            y = y + 1
            if y > h - 2 then break end
        end
    end
end

local function drawHistoryPage(countdown)
    clearScreen(); drawHeader(countdown)
    local w, h = term.getSize()
    drawBox(1, 5, w, h - 5, " History ", colors.gray)
    local lines = readLines(CONFIG.historyFile, CONFIG.maxHistoryLines)
    local y = 6
    local maxVisible = h - 7
    local start = math.max(1, #lines - maxVisible + 1)
    for i = start, #lines do
        if lines[i] then writeAt(3, y, trimText(lines[i], w - 4), colors.white); y = y + 1 end
    end
    if #lines == 0 then centerAt(8, "No history yet.", colors.gray) end
end

local function drawSettingsPage(countdown)
    clearScreen(); drawHeader(countdown)
    local w, h = term.getSize()
    drawBox(1, 5, w, h - 5, " Settings / Rules ", colors.gray)
    local whitelistCount, blacklistCount, protectedCount = 0, 0, 0
    for _ in pairs(WHITELIST) do whitelistCount = whitelistCount + 1 end
    for _ in pairs(BLACKLIST) do blacklistCount = blacklistCount + 1 end
    for _ in pairs(PROTECTED) do protectedCount = protectedCount + 1 end
    writeAt(3, 7, "Mode: " .. STATE.mode, colors.yellow)
    writeAt(3, 8, "Paused: " .. tostring(STATE.paused), STATE.paused and colors.orange or colors.white)
    writeAt(3, 9, "Output Target: " .. CONFIG.outputTarget, colors.white)
    writeAt(3, 10, "Whitelist Items: " .. tostring(whitelistCount), colors.lime)
    writeAt(3, 11, "Blacklist Items: " .. tostring(blacklistCount), colors.red)
    writeAt(3, 12, "Protected Items: " .. tostring(protectedCount), colors.yellow)
    writeAt(3, 14, "AUTO      = safe requests send unless blacklisted/protected", colors.white)
    writeAt(3, 15, "APPROVAL  = requests wait for approval", colors.white)
    writeAt(3, 16, "WHITELIST = only ALWAYS-approved items send", colors.white)
    writeAt(3, 18, "Protected items always require approval unless ALWAYS-approved.", colors.gray)
end

local function drawMain(countdown)
    withScreen(MAIN, function()
        if STATE.page == "REQUESTS" then drawRequestsPage(countdown)
        elseif STATE.page == "BUILD" then drawBuildPage(countdown)
        elseif STATE.page == "PENDING" then drawPendingPage(countdown)
        elseif STATE.page == "HISTORY" then drawHistoryPage(countdown)
        elseif STATE.page == "SETTINGS" then drawSettingsPage(countdown)
        else drawDashboardPage(countdown) end
    end)
end

local function controlButton(x, y, w, label, action, active)
    addButton(CONTROL.name, x, y, w, 2, label, action, active and colors.lime or colors.gray)
end

local function drawControl(countdown)
    if not CONTROL then return end
    withScreen(CONTROL, function()
        clearScreen()
        local w, h = term.getSize()
        centerAt(1, "HTP CONTROL PANEL", colors.lime)
        centerAt(2, "Next Scan: " .. tostring(countdown) .. "s", colors.cyan)
        fillAt(1, 3, w, "=", STATE.status.underAttack and colors.red or colors.gray)

        local colW = math.max(6, math.floor((w - 4) / 3))
        controlButton(2, 4, colW, "AUTO", function() setMode("AUTO") end, STATE.mode == "AUTO")
        controlButton(3 + colW, 4, colW, "APPROVAL", function() setMode("APPROVAL") end, STATE.mode == "APPROVAL")
        controlButton(4 + colW * 2, 4, colW, "WHITE", function() setMode("WHITELIST") end, STATE.mode == "WHITELIST")

        controlButton(2, 7, colW, "DASH", function() setPage("DASHBOARD") end, STATE.page == "DASHBOARD")
        controlButton(3 + colW, 7, colW, "REQ", function() setPage("REQUESTS") end, STATE.page == "REQUESTS")
        controlButton(4 + colW * 2, 7, colW, "BUILD", function() setPage("BUILD") end, STATE.page == "BUILD")

        controlButton(2, 10, colW, "PENDING", function() setPage("PENDING") end, STATE.page == "PENDING")
        controlButton(3 + colW, 10, colW, "HISTORY", function() setPage("HISTORY") end, STATE.page == "HISTORY")
        controlButton(4 + colW * 2, 10, colW, "SETTINGS", function() setPage("SETTINGS") end, STATE.page == "SETTINGS")

        controlButton(2, 13, colW, STATE.paused and "RESUME" or "PAUSE", function() setPaused(not STATE.paused) end, STATE.paused)
        controlButton(3 + colW, 13, colW, "SCAN NOW", function() STATE.nextScanNow = true; addAction("Manual scan queued") end, false)
        controlButton(4 + colW * 2, 13, colW, "CLR HIST", function() clearHistory() end, false)

        local y = 16
        local key, pending = selectedPending()
        if pending then
            writeAt(2, y, "Pending " .. tostring(STATE.selectedPending) .. "/" .. tostring(#STATE.pendingOrder) .. ": " .. trimText(pending.parsed.amount .. "x " .. pending.parsed.itemName, w - 18), colors.yellow)
            writeAt(2, y + 1, "Reason: " .. trimText(pending.reason, w - 10), colors.gray)

            local half = math.max(8, math.floor((w - 5) / 2))
            addButton(CONTROL.name, 2, y + 3, half, 2, "PREV", function() nextPending(-1) end, colors.gray)
            addButton(CONTROL.name, 3 + half, y + 3, half, 2, "NEXT", function() nextPending(1) end, colors.gray)
            addButton(CONTROL.name, 2, y + 6, half, 2, "APPROVE", function() approveSelected(false); STATE.nextScanNow = true end, colors.lime)
            addButton(CONTROL.name, 3 + half, y + 6, half, 2, "ALWAYS", function() approveSelected(true); STATE.nextScanNow = true end, colors.green)
            addButton(CONTROL.name, 2, y + 9, half, 2, "DENY", function() denySelected(false); STATE.nextScanNow = true end, colors.orange)
            addButton(CONTROL.name, 3 + half, y + 9, half, 2, "BLACKLIST", function() denySelected(true); STATE.nextScanNow = true end, colors.red)
        else
            centerAt(y + 2, "No pending approvals", colors.gray)
            centerAt(y + 4, "Switch to APPROVAL mode to review all requests.", colors.gray)
        end

        if STATE.status.underAttack then centerAt(h - 1, "!!! COLONY UNDER ATTACK !!!", colors.red) else centerAt(h - 1, "AE2 LINKED | COLONY LINKED", colors.gray) end
    end)
end

local function renderAll(countdown)
    BUTTONS = {}
    local ok, err = pcall(function()
        drawMain(countdown)
        drawControl(countdown)
    end)
    if not ok then
        term.redirect(nativeTerm)
        clearScreen()
        print("Render error:")
        print(err)
        logError("Render error: " .. tostring(err))
    end
end

-------------------------
-- SCAN
-------------------------

local function addRequestRow(rows, text, color)
    if #rows < CONFIG.maxShownRequests then table.insert(rows, { text = text, color = color }) end
end

local function buildMaterialRows(parsedList)
    local totals = {}
    for _, parsed in ipairs(parsedList) do
        totals[parsed.itemName] = (totals[parsed.itemName] or 0) + (tonumber(parsed.amount) or 1)
    end
    local rows = {}
    for item, amount in pairs(totals) do table.insert(rows, tostring(amount) .. "x " .. item) end
    table.sort(rows)
    while #rows > CONFIG.maxBuildRows do table.remove(rows) end
    return rows
end

local function shouldProcessRequest(key, parsed, newPending, newOrder, skipReason)
    if BLACKLIST[parsed.itemName] then return false, "BLACKLISTED" end
    if STATE.deniedUntil[key] and STATE.deniedUntil[key] > nowSeconds() then return false, "DENIED" end
    if STATE.paused then addPending(newPending, newOrder, key, parsed, "paused"); return false, "PENDING" end
    if STATE.approvedOnce[key] then return true, "APPROVED" end
    if WHITELIST[parsed.itemName] then return true, "WHITELIST" end
    if skipReason then addPending(newPending, newOrder, key, parsed, skipReason); return false, "PENDING" end
    if PROTECTED[parsed.itemName] then addPending(newPending, newOrder, key, parsed, "protected item"); return false, "PENDING" end
    if STATE.mode == "AUTO" then return true, "AUTO" end
    if STATE.mode == "WHITELIST" then addPending(newPending, newOrder, key, parsed, "not whitelisted"); return false, "PENDING" end
    addPending(newPending, newOrder, key, parsed, "approval mode")
    return false, "PENDING"
end

local function processParsedRequest(parsed, rows, stats)
    local key = requestKey(parsed)
    if exportOnCooldown(key) then
        stats.waiting = stats.waiting + 1
        addRequestRow(rows, "[WAIT] " .. tostring(parsed.amount) .. "x " .. trimText(parsed.itemName, 50), colors.gray)
        return
    end

    local available = getAECount(parsed.itemName)
    if available > 0 then
        local moved, exportErr = exportAEItem(parsed.itemName, parsed.amount)
        if moved > 0 then
            stats.sent = stats.sent + 1
            STATE.sent = STATE.sent + moved
            STATE.approvedOnce[key] = nil
            markExported(key)
            addRequestRow(rows, "[SENT] " .. tostring(moved) .. "/" .. tostring(parsed.amount) .. "x " .. trimText(parsed.itemName, 44), colors.lime)
            addAction("Sent " .. tostring(moved) .. "x " .. parsed.itemName)
            logInfo("SENT " .. tostring(moved) .. "/" .. tostring(parsed.amount) .. " " .. parsed.itemName .. " -> " .. tostring(parsed.target))
            return
        end
        local craftOk, craftMsg = requestAECraft(parsed.itemName, parsed.amount)
        if craftOk then
            stats.crafting = stats.crafting + 1
            STATE.crafting = STATE.crafting + 1
            STATE.approvedOnce[key] = nil
            addRequestRow(rows, "[CRAFT] " .. tostring(parsed.amount) .. "x " .. trimText(parsed.itemName, 47), colors.yellow)
            addAction("Crafting " .. tostring(parsed.amount) .. "x " .. parsed.itemName)
            logInfo("CRAFT " .. tostring(parsed.amount) .. " " .. parsed.itemName .. " - " .. tostring(craftMsg))
        else
            stats.missing = stats.missing + 1
            STATE.missing = STATE.missing + 1
            addRequestRow(rows, "[MISS] " .. tostring(parsed.amount) .. "x " .. trimText(parsed.itemName, 48), colors.red)
            addAction("Missing " .. parsed.itemName)
            logInfo("MISS " .. tostring(parsed.amount) .. " " .. parsed.itemName .. " - " .. tostring(exportErr or craftMsg))
        end
    else
        local craftOk, craftMsg = requestAECraft(parsed.itemName, parsed.amount)
        if craftOk then
            stats.crafting = stats.crafting + 1
            STATE.crafting = STATE.crafting + 1
            STATE.approvedOnce[key] = nil
            addRequestRow(rows, "[CRAFT] " .. tostring(parsed.amount) .. "x " .. trimText(parsed.itemName, 47), colors.yellow)
            addAction("Crafting " .. tostring(parsed.amount) .. "x " .. parsed.itemName)
            logInfo("CRAFT " .. tostring(parsed.amount) .. " " .. parsed.itemName .. " - " .. tostring(craftMsg))
        else
            stats.missing = stats.missing + 1
            STATE.missing = STATE.missing + 1
            addRequestRow(rows, "[MISS] " .. tostring(parsed.amount) .. "x " .. trimText(parsed.itemName, 48), colors.red)
            addAction("Missing " .. parsed.itemName)
            logInfo("MISS " .. tostring(parsed.amount) .. " " .. parsed.itemName .. " - " .. tostring(craftMsg))
        end
    end
end

local function performScan()
    STATE.scans = STATE.scans + 1
    STATE.colonyName = getColonyName()
    STATE.status = getColonyStatus()

    local stats = { total = 0, sent = 0, crafting = 0, skipped = 0, waiting = 0, missing = 0, bad = 0, pending = 0 }
    local rows = {}
    local newPending = {}
    local newOrder = {}
    local parsedList = {}

    local requests, err = getRequests()
    if not requests then
        stats.bad = 1
        addRequestRow(rows, "[ERROR] Could not read MineColonies requests.", colors.red)
        addRequestRow(rows, trimText(tostring(err), 60), colors.red)
        logError("getRequests failed: " .. tostring(err))
        addAction("getRequests failed")
        STATE.stats = stats
        STATE.requestRows = rows
        return
    end

    for _, req in pairs(requests) do
        stats.total = stats.total + 1
        local parsed, parseErr = parseRequest(req)
        if not parsed then
            stats.bad = stats.bad + 1
            logError("Bad request: " .. tostring(parseErr))
        else
            table.insert(parsedList, parsed)
            local skip, skipReason = shouldSkipRequest(req, parsed)
            local key = requestKey(parsed)
            local allowed, reason = shouldProcessRequest(key, parsed, newPending, newOrder, skip and skipReason or nil)
            if allowed then
                processParsedRequest(parsed, rows, stats)
            elseif reason == "PENDING" then
                stats.pending = stats.pending + 1
                stats.waiting = stats.waiting + 1
                local pendingReason = newPending[key] and newPending[key].reason or "pending"
                addRequestRow(rows, "[PENDING] " .. tostring(parsed.amount) .. "x " .. trimText(parsed.itemName, 39) .. " (" .. trimText(pendingReason, 14) .. ")", colors.yellow)
            elseif reason == "BLACKLISTED" then
                stats.skipped = stats.skipped + 1
                addRequestRow(rows, "[BLOCKED] " .. tostring(parsed.amount) .. "x " .. trimText(parsed.itemName, 45), colors.red)
            else
                stats.waiting = stats.waiting + 1
                addRequestRow(rows, "[DENIED] " .. tostring(parsed.amount) .. "x " .. trimText(parsed.itemName, 45), colors.orange)
            end
        end
    end

    STATE.pending = newPending
    STATE.pendingOrder = newOrder
    normalizeSelectedPending()
    STATE.stats = stats
    STATE.requestRows = rows
    STATE.buildRows = buildMaterialRows(parsedList)
    STATE.workOrderRows = getWorkOrderRows()
    STATE.manual = STATE.manual + stats.skipped
    STATE.waiting = STATE.waiting + stats.waiting
    STATE.bad = STATE.bad + stats.bad

    if stats.total == 0 then addAction("No colony requests") end
end

-------------------------
-- TOUCH
-------------------------

local function handleTouch(screenName, x, y)
    for _, button in ipairs(BUTTONS) do
        if button.screen == screenName and x >= button.x1 and x <= button.x2 and y >= button.y1 and y <= button.y2 then
            local ok, err = pcall(button.action)
            if not ok then logError("Button error: " .. tostring(err)); addAction("Button error") end
            return true
        end
    end
    return false
end

-------------------------
-- START
-------------------------

initMonitors()
bootSplash()

term.redirect(nativeTerm)
clearScreen()
print("HTP Colony Supply running.")
print("Main: " .. tostring(MAIN.name) .. " " .. tostring(MAIN.w) .. "x" .. tostring(MAIN.h))
print("Control: " .. tostring(CONTROL and CONTROL.name or "none"))

logInfo("HackThePlanet Colony Supply started.")
logInfo("Output target: " .. tostring(CONFIG.outputTarget))
logInfo("Main monitor: " .. tostring(MAIN.name) .. " Control monitor: " .. tostring(CONTROL and CONTROL.name or "none"))
addAction("Program started")

local ok, err = pcall(performScan)
if not ok then logError("Initial scan error: " .. tostring(err)); addAction("Initial scan error") end

local nextScanAt = nowSeconds() + CONFIG.scanSeconds
renderAll(CONFIG.scanSeconds)

while true do
    local countdown = math.max(0, nextScanAt - nowSeconds())
    renderAll(countdown)

    local timer = os.startTimer(1)
    local event = { os.pullEvent() }

    if event[1] == "monitor_touch" then
        handleTouch(event[2], event[3], event[4])
        renderAll(math.max(0, nextScanAt - nowSeconds()))
    end

    if STATE.nextScanNow or nowSeconds() >= nextScanAt then
        STATE.nextScanNow = false
        local scanOk, scanErr = pcall(performScan)
        if not scanOk then
            logError("Main loop scan error: " .. tostring(scanErr))
            addAction("Scan error")
        end
        nextScanAt = nowSeconds() + CONFIG.scanSeconds
    end
end
