-- startup
-- HackThePlanet CC & MineColonies Program
-- CC:Tweaked + Advanced Peripherals + AE2 + MineColonies
-- AE2 auto-supply dashboard with approvals, request-type rules, citizens, and alerts.

local CONFIG = {
    outputTarget = "bottom",
    scanSeconds = 30,
    splashSeconds = 15,
    monitorScale = 0.5,
    maxExportPerRequest = 512,
    maxCraftPerRequest = 512,
    requestCooldownSeconds = 120,
    craftCooldownSeconds = 300,
    denyCooldownSeconds = 300,
    errorRepeatSeconds = 300,
    autoCraft = true,
    defaultMode = "AUTO",
    settingsFile = "htp_settings.cfg",
    whitelistFile = "htp_whitelist.txt",
    blockedFile = "htp_blacklist.txt",
    historyFile = "htp_history.log",
    errorFile = "htp_colony_errors.log",
    maxRows = 14,
    maxHistoryLines = 120,
    sentHistoryLimit = 50,
    errorHistoryLimit = 50
}

local TYPE_ORDER = { "BUILD", "TOOL", "ARMOR", "FOOD", "FUEL", "SPECIAL", "OTHER" }
local TYPE_LABELS = {
    BUILD = "Build Materials",
    TOOL = "Tools",
    ARMOR = "Armor",
    FOOD = "Food",
    FUEL = "Fuel",
    SPECIAL = "Special/NBT",
    OTHER = "Other"
}
local TYPE_DEFAULTS = {
    BUILD = "AUTO",
    TOOL = "APPROVAL",
    ARMOR = "APPROVAL",
    FOOD = "APPROVAL",
    FUEL = "AUTO",
    SPECIAL = "OFF",
    OTHER = "APPROVAL"
}

local BUILDING_NAMES = {
    townhall = "Town Hall",
    builder = "Builder's Hut",
    residence = "Residence",
    guardtower = "Guard Tower",
    cook = "Restaurant",
    restaurant = "Restaurant",
    farmer = "Farm",
    warehouse = "Warehouse",
    deliveryman = "Courier's Hut",
    courier = "Courier's Hut",
    miner = "Mine",
    lumberjack = "Forester's Hut",
    forester = "Forester's Hut",
    fisherman = "Fisher's Hut",
    fisher = "Fisher's Hut",
    bakery = "Bakery",
    baker = "Bakery",
    blacksmith = "Blacksmith",
    sawmill = "Sawmill",
    crusher = "Crusher",
    stonemason = "Stonemason",
    stone = "Stonemason",
    composter = "Composter",
    sifter = "Sifter",
    enchanter = "Enchanter",
    school = "School",
    university = "University",
    hospital = "Hospital",
    graveyard = "Graveyard",
    barracks = "Barracks",
    barrackstower = "Barracks Tower",
    combatacademy = "Combat Academy",
    archery = "Archery",
    library = "Library",
    tavern = "Tavern",
    apiary = "Apiary",
    florist = "Florist",
    plantation = "Plantation",
    mechanic = "Mechanic",
    glassblower = "Glassblower",
    dyer = "Dyer",
    concrete = "Concrete Mixer",
    rabbit = "Rabbit Hutch",
    chicken = "Chicken Farmer",
    cow = "Cowhand's Hut",
    swine = "Swineherd's Hut",
    shepherd = "Shepherd's Hut",
    workorderbuilding = "Building Work Order"
}

local nativeTerm = term.current()
local bridge = peripheral.find("me_bridge") or peripheral.find("meBridge")
local colony = peripheral.find("colony_integrator") or peripheral.find("colonyIntegrator")

if not bridge then error("No ME Bridge found. Connect an Advanced Peripherals ME Bridge.") end
if not colony then error("No Colony Integrator found. Connect a Colony Integrator inside your colony.") end

-------------------------
-- BASIC HELPERS
-------------------------

local function epoch()
    if os.epoch then return math.floor(os.epoch("utc") / 1000) end
    return math.floor(os.clock())
end

local function attempt(fn)
    local ok, a, b, c = pcall(fn)
    if ok then return true, a, b, c end
    return false, a, nil, nil
end

local function has(obj, method)
    return obj and type(obj[method]) == "function"
end

local function text(value)
    return tostring(value == nil and "" or value)
end

local function lower(value)
    return string.lower(text(value))
end

local function trim(value, maxLength)
    local s = text(value)
    local limit = tonumber(maxLength) or 20
    if limit <= 0 then return "" end
    if #s <= limit then return s end
    if limit <= 3 then return string.sub(s, 1, limit) end
    return string.sub(s, 1, limit - 3) .. "..."
end

local function fmtNumber(value, decimals)
    local n = tonumber(value)
    if not n then return text(value ~= nil and value or "?") end
    if decimals and decimals > 0 then
        return string.format("%." .. tostring(decimals) .. "f", n)
    end
    return tostring(math.floor(n + 0.5))
end

local function fmtStat(value)
    local n = tonumber(value)
    if not n then return text(value ~= nil and value or "?") end
    if math.abs(n - math.floor(n + 0.00001)) < 0.005 then
        return tostring(math.floor(n + 0.00001))
    end
    return string.format("%.2f", n)
end

local function fmtDuration(seconds)
    local total = math.max(0, tonumber(seconds) or 0)
    local hours = math.floor(total / 3600)
    local minutes = math.floor((total % 3600) / 60)
    local secs = math.floor(total % 60)
    if hours > 0 then return hours .. "h " .. minutes .. "m" end
    if minutes > 0 then return minutes .. "m " .. secs .. "s" end
    return secs .. "s"
end

local function titleCase(value)
    local s = text(value):gsub("_", " "):gsub("%-", " ")
    return (s:gsub("(%a)([%w_']*)", function(first, rest)
        return string.upper(first) .. string.lower(rest)
    end))
end

local function appendLine(path, message)
    local file = fs.open(path, "a")
    if file then
        file.writeLine("[" .. epoch() .. "] " .. text(message))
        file.close()
    end
end

local function readLines(path, limit)
    local out = {}
    if not fs.exists(path) then return out end
    local file = fs.open(path, "r")
    if not file then return out end
    while true do
        local line = file.readLine()
        if not line then break end
        table.insert(out, line)
    end
    file.close()
    if limit and #out > limit then
        local reduced = {}
        for i = math.max(1, #out - limit + 1), #out do
            table.insert(reduced, out[i])
        end
        return reduced
    end
    return out
end

local function loadSet(path)
    local set = {}
    for _, line in ipairs(readLines(path)) do
        local cleaned = line:gsub("^%s+", ""):gsub("%s+$", "")
        if cleaned ~= "" and cleaned:sub(1, 1) ~= "#" then
            set[cleaned] = true
        end
    end
    return set
end

local function saveSet(path, set)
    local file = fs.open(path, "w")
    if not file then return end
    local keys = {}
    for key, enabled in pairs(set) do
        if enabled then table.insert(keys, key) end
    end
    table.sort(keys)
    for _, key in ipairs(keys) do file.writeLine(key) end
    file.close()
end

local function loadSettings()
    local result = {}
    for _, line in ipairs(readLines(CONFIG.settingsFile)) do
        local key, value = line:match("^([%w_]+)%s*=%s*(.-)%s*$")
        if key and value then result[key] = value end
    end
    return result
end

local function saveSettings(settings)
    local file = fs.open(CONFIG.settingsFile, "w")
    if not file then return end
    local keys = {}
    for key in pairs(settings) do table.insert(keys, key) end
    table.sort(keys)
    for _, key in ipairs(keys) do
        file.writeLine(key .. "=" .. text(settings[key]))
    end
    file.close()
end

local function labelValue(value)
    if type(value) ~= "table" then return text(value) end
    return text(value.name or value.displayName or value.type or value.buildingName or value.id or "Unknown")
end

local function cleanItemName(itemName)
    local raw = text(itemName)
    raw = raw:gsub("^.-:", "")
    return titleCase(raw)
end

local function cleanStateName(value)
    local raw = labelValue(value)
    raw = raw:gsub("^.*%.", ""):gsub("^.*:", "")
    return titleCase(raw)
end

local function cleanBuildingName(value)
    local raw = labelValue(value)
    local cleaned = lower(raw)
    cleaned = cleaned:gsub("^.*%.", ""):gsub("^.*:", "")
    cleaned = cleaned:gsub("[^%w_]", "")
    if BUILDING_NAMES[cleaned] then return BUILDING_NAMES[cleaned] end

    for key, display in pairs(BUILDING_NAMES) do
        if cleaned:find(key, 1, true) then return display end
    end

    if cleaned == "" then return "Unknown Building" end
    return titleCase(cleaned:gsub("building", ""))
end

local function cleanJobName(value)
    local cleaned = lower(labelValue(value))
    local matches = {
        { "builder", "Builder" }, { "miner", "Miner" }, { "farmer", "Farmer" },
        { "guard", "Guard" }, { "courier", "Courier" }, { "delivery", "Courier" },
        { "cook", "Cook" }, { "restaurant", "Cook" }, { "lumberjack", "Lumberjack" },
        { "forester", "Forester" }, { "fisher", "Fisher" }, { "rancher", "Rancher" },
        { "shepherd", "Shepherd" }, { "chicken", "Chicken Herder" },
        { "cowboy", "Cowhand" }, { "swine", "Swineherd" }, { "composter", "Composter" },
        { "sifter", "Sifter" }, { "baker", "Baker" }, { "blacksmith", "Blacksmith" },
        { "sawmill", "Sawmill Worker" }, { "crusher", "Crusher" },
        { "stonemason", "Stonemason" }, { "mechanic", "Mechanic" },
        { "enchanter", "Enchanter" }, { "florist", "Florist" },
        { "student", "Student" }, { "teacher", "Teacher" }, { "visitor", "Visitor" },
        { "citizen", "Citizen" }
    }
    for _, pair in ipairs(matches) do
        if cleaned:find(pair[1], 1, true) then return pair[2] end
    end
    return cleanBuildingName(value)
end

-------------------------
-- MONITORS AND DRAWING
-------------------------

local MAIN = { name = "terminal", object = nativeTerm, w = 51, h = 19, area = 969, aspect = 2.68 }
local CONTROL = nil
local ALERT = nil
local BUTTONS = {}

local function monitorSize(mon)
    local ok, w, h = pcall(function() return mon.getSize() end)
    if ok and type(w) == "number" and type(h) == "number" then return w, h end
    return nil, nil
end

local function detectMonitors()
    local monitors = {}
    for _, name in ipairs(peripheral.getNames()) do
        if peripheral.getType(name) == "monitor" then
            local mon = peripheral.wrap(name)
            pcall(function() mon.setTextScale(CONFIG.monitorScale) end)
            local w, h = monitorSize(mon)
            if w and h then
                table.insert(monitors, {
                    name = name,
                    object = mon,
                    w = w,
                    h = h,
                    area = w * h,
                    aspect = w / math.max(1, h)
                })
            end
        end
    end

    table.sort(monitors, function(a, b) return a.area > b.area end)
    if #monitors >= 1 then MAIN = monitors[1] end

    if #monitors == 2 then
        CONTROL = monitors[2]
    elseif #monitors >= 3 then
        local remaining = {}
        for i = 2, #monitors do table.insert(remaining, monitors[i]) end

        local alertIndex = 1
        for i = 2, #remaining do
            if remaining[i].aspect > remaining[alertIndex].aspect then alertIndex = i end
        end
        ALERT = table.remove(remaining, alertIndex)
        table.sort(remaining, function(a, b) return a.area > b.area end)
        CONTROL = remaining[1]
    end

    if MAIN.object == nativeTerm then
        local w, h = term.getSize()
        MAIN.w, MAIN.h, MAIN.area, MAIN.aspect = w, h, w * h, w / math.max(1, h)
    end
end

local function withScreen(screen, fn)
    if not screen or not screen.object then return false, "screen unavailable" end
    local previous = term.current()
    term.redirect(screen.object)
    local ok, err = pcall(fn)
    term.redirect(previous or nativeTerm)
    return ok, err
end

local function clear(background)
    term.setBackgroundColor(background or colors.black)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(1, 1)
end

local function writeAt(x, y, value, color, background)
    local screenW, screenH = term.getSize()
    local px = tonumber(x) or 1
    local py = tonumber(y) or 1
    if py < 1 or py > screenH or px > screenW then return end
    if px < 1 then px = 1 end
    term.setCursorPos(px, py)
    term.setBackgroundColor(background or colors.black)
    term.setTextColor(color or colors.white)
    term.write(trim(value, math.max(0, screenW - px + 1)))
    term.setBackgroundColor(colors.black)
end

local function fillAt(x, y, width, char, color, background)
    local amount = math.max(0, tonumber(width) or 0)
    if amount > 0 then writeAt(x, y, string.rep(char or " ", amount), color, background) end
end

local function center(y, value, color, background)
    local screenW = select(1, term.getSize())
    local stringValue = text(value)
    writeAt(math.max(1, math.floor((screenW - #stringValue) / 2) + 1), y, stringValue, color, background)
end

local function box(x, y, width, height, title, color)
    local px = tonumber(x) or 1
    local py = tonumber(y) or 1
    local w = math.max(4, tonumber(width) or 4)
    local h = math.max(3, tonumber(height) or 3)
    local c = color or colors.gray
    writeAt(px, py, "+" .. string.rep("-", w - 2) .. "+", c)
    for row = 1, h - 2 do
        writeAt(px, py + row, "|", c)
        fillAt(px + 1, py + row, w - 2, " ", colors.white, colors.black)
        writeAt(px + w - 1, py + row, "|", c)
    end
    writeAt(px, py + h - 1, "+" .. string.rep("-", w - 2) .. "+", c)
    if title then writeAt(px + 2, py, " " .. trim(title, w - 6) .. " ", colors.yellow) end
end

local function addButton(screenName, x, y, width, height, label, actionFn, color)
    local px = tonumber(x) or 1
    local py = tonumber(y) or 1
    local w = math.max(4, tonumber(width) or 4)
    local h = math.max(1, tonumber(height) or 1)
    local c = color or colors.gray
    table.insert(BUTTONS, {
        screen = screenName,
        x1 = px, y1 = py,
        x2 = px + w - 1, y2 = py + h - 1,
        action = actionFn
    })
    for row = 0, h - 1 do
        writeAt(px, py + row, string.rep(" ", w), colors.black, c)
    end
    writeAt(px + math.max(0, math.floor((w - #label) / 2)), py + math.floor(h / 2), label, colors.black, c)
end

-------------------------
-- STATE AND LOGGING
-------------------------

local settings = loadSettings()
local WHITELIST = loadSet(CONFIG.whitelistFile)
local BLOCKED = loadSet(CONFIG.blockedFile)
local TYPE_MODES = {}
for _, id in ipairs(TYPE_ORDER) do
    TYPE_MODES[id] = settings["type_" .. id] or TYPE_DEFAULTS[id]
end

local STATE = {
    mode = settings.mode or CONFIG.defaultMode,
    page = settings.page or "DASHBOARD",
    paused = settings.paused == "true",
    selected = tonumber(settings.selected or "1") or 1,
    typeIndex = tonumber(settings.typeIndex or "1") or 1,
    started = epoch(),
    scans = 0,
    sent = 0,
    craft = 0,
    missing = 0,
    pending = {},
    pendingOrder = {},
    approvedOnce = {},
    deniedUntil = {},
    rows = {},
    buildRows = {},
    workRows = {},
    citizenRows = {},
    citizenAlerts = {},
    alerts = {},
    actions = {},
    sentRows = {},
    errorRows = {},
    errorLastSeen = {},
    lastAction = "Program started",
    lastError = nil,
    lastErrorAt = 0,
    lastOutputTest = "Not tested",
    colonyName = "Unknown Colony",
    status = {},
    stats = { total = 0, sent = 0, crafting = 0, skipped = 0, waiting = 0, missing = 0, bad = 0, pending = 0, off = 0 },
    scanNow = false,
    idleActive = false,
    idleScans = 0,
    idleStarted = nil
}

local function saveState()
    settings.mode = STATE.mode
    settings.page = STATE.page
    settings.paused = tostring(STATE.paused)
    settings.selected = tostring(STATE.selected)
    settings.typeIndex = tostring(STATE.typeIndex)
    for _, id in ipairs(TYPE_ORDER) do settings["type_" .. id] = TYPE_MODES[id] end
    saveSettings(settings)
end

local function pushLimited(list, item, limit)
    table.insert(list, 1, item)
    while #list > limit do table.remove(list) end
end

local function action(message, color, logToHistory)
    STATE.lastAction = text(message)
    pushLimited(STATE.actions, { text = text(message), color = color or colors.white }, 8)
    if logToHistory ~= false then appendLine(CONFIG.historyFile, message) end
end

local function recordSent(message, color)
    pushLimited(STATE.sentRows, { text = text(message), color = color or colors.lime }, CONFIG.sentHistoryLimit)
    action(message, color or colors.lime, true)
end

local function recordError(message)
    local msg = text(message)
    local last = STATE.errorLastSeen[msg]
    if not last or epoch() - last >= CONFIG.errorRepeatSeconds then
        STATE.errorLastSeen[msg] = epoch()
        pushLimited(STATE.errorRows, { text = "[" .. epoch() .. "] " .. msg, color = colors.red }, CONFIG.errorHistoryLimit)
        appendLine(CONFIG.errorFile, msg)
    end
    STATE.lastError = msg
    STATE.lastErrorAt = epoch()
end

local function beginIdle()
    if not STATE.idleActive then
        STATE.idleActive = true
        STATE.idleScans = 1
        STATE.idleStarted = epoch()
        action("Colony idle: no open requests", colors.gray, true)
    else
        STATE.idleScans = STATE.idleScans + 1
        STATE.lastAction = "No requests for " .. STATE.idleScans .. " scans"
    end
end

local function endIdle()
    if not STATE.idleActive then return end
    local duration = epoch() - (STATE.idleStarted or epoch())
    action("Requests resumed after " .. STATE.idleScans .. " idle scans (" .. fmtDuration(duration) .. ")", colors.cyan, true)
    STATE.idleActive = false
    STATE.idleScans = 0
    STATE.idleStarted = nil
end

local function setMode(mode)
    STATE.mode = mode
    saveState()
    action("Global mode set to " .. mode, colors.yellow, true)
end

local function setPage(page)
    STATE.page = page
    saveState()
    STATE.lastAction = "Page: " .. page
end

local function setPaused(value)
    STATE.paused = value == true
    saveState()
    action(STATE.paused and "Auto supply paused" or "Auto supply resumed", STATE.paused and colors.orange or colors.lime, true)
end

local function clearHistory()
    local file = fs.open(CONFIG.historyFile, "w")
    if file then file.close() end
    STATE.actions = {}
    STATE.lastAction = "History cleared"
    appendLine(CONFIG.historyFile, "History cleared")
end

local function currentType()
    if STATE.typeIndex < 1 then STATE.typeIndex = #TYPE_ORDER end
    if STATE.typeIndex > #TYPE_ORDER then STATE.typeIndex = 1 end
    return TYPE_ORDER[STATE.typeIndex]
end

local function setTypeMode(typeId, mode)
    TYPE_MODES[typeId] = mode
    saveState()
    action(TYPE_LABELS[typeId] .. " -> " .. mode, mode == "AUTO" and colors.lime or (mode == "APPROVAL" and colors.yellow or colors.red), true)
end

-------------------------
-- BOOT SPLASH
-------------------------

local function drawBoot(percent, step)
    clear()
    local w, h = term.getSize()
    local y = math.max(2, math.floor(h / 2) - 6)
    center(y, "========================================", colors.gray)
    center(y + 1, "HackThePlanet", colors.lime)
    center(y + 2, "CC & MineColonies Program", colors.cyan)
    center(y + 3, "AE2 Auto-Supply Command Center", colors.yellow)
    center(y + 5, step, colors.white)
    local barWidth = math.min(42, math.max(18, w - 12))
    local barX = math.max(1, math.floor((w - barWidth - 2) / 2) + 1)
    local filled = math.floor((percent / 100) * barWidth)
    writeAt(barX, y + 7, "[", colors.gray)
    for i = 1, barWidth do
        writeAt(barX + i, y + 7, i <= filled and "=" or "-", i <= filled and colors.lime or colors.gray)
    end
    writeAt(barX + barWidth + 1, y + 7, "]", colors.gray)
    center(y + 9, percent .. "%", colors.white)
end

local function bootSplash()
    local steps = {
        "Booting HackThePlanet systems...",
        "Loading CC:Tweaked services...",
        "Connecting to AE2 network...",
        "Checking MineColonies Integrator...",
        "Detecting monitors...",
        "Loading request type rules...",
        "Cleaning building display names...",
        "Loading alert screen...",
        "System ready."
    }
    local ticks = math.max(20, CONFIG.splashSeconds * 10)
    for tick = 1, ticks do
        local percent = math.floor((tick / ticks) * 100)
        local step = steps[math.min(#steps, math.max(1, math.ceil((percent / 100) * #steps)))]
        withScreen(MAIN, function() drawBoot(percent, step) end)
        if CONTROL then withScreen(CONTROL, function() drawBoot(percent, step) end) end
        if ALERT then withScreen(ALERT, function() drawBoot(percent, step) end) end
        sleep(0.1)
    end
end

-------------------------
-- AE2
-------------------------

local function aeCount(itemName)
    local ok, item = attempt(function() return bridge.getItem({ name = itemName }) end)
    if ok and type(item) == "table" then return tonumber(item.amount or item.count or 0) or 0 end
    return 0
end

local function exportItem(itemName, amount)
    local wanted = math.max(1, math.min(tonumber(amount) or 1, CONFIG.maxExportPerRequest))
    local before = aeCount(itemName)
    if before <= 0 then return 0, "none in AE2" end
    wanted = math.min(wanted, before)

    local ok, result
    if has(bridge, "exportItem") then
        ok, result = attempt(function() return bridge.exportItem({ name = itemName, count = wanted }, CONFIG.outputTarget) end)
    elseif has(bridge, "exportItemToPeripheral") then
        ok, result = attempt(function() return bridge.exportItemToPeripheral({ name = itemName, count = wanted }, CONFIG.outputTarget) end)
    else
        return 0, "ME Bridge has no export method"
    end

    if not ok then return 0, text(result) end
    if type(result) == "number" then return result, nil end
    if type(result) == "table" then
        local moved = tonumber(result.amount or result.count or result.transferred or result.exported or 0) or 0
        if moved > 0 then return moved, nil end
    end

    sleep(0.15)
    local after = aeCount(itemName)
    local movedByCount = math.max(0, before - after)
    if movedByCount > 0 then return movedByCount, nil end
    return 0, "target did not accept item"
end

local craftCooldown = {}

local function isCraftable(itemName)
    local methods = { "isCraftable", "isItemCraftable" }
    for _, method in ipairs(methods) do
        if has(bridge, method) then
            local ok, result = attempt(function() return bridge[method]({ name = itemName }) end)
            if ok and type(result) == "boolean" then return result end
        end
    end
    return nil
end

local function craftItem(itemName, amount)
    if not CONFIG.autoCraft then return false, "autocraft disabled" end
    local wanted = math.max(1, math.min(tonumber(amount) or 1, CONFIG.maxCraftPerRequest))
    local key = itemName .. "|" .. wanted
    if craftCooldown[key] and epoch() - craftCooldown[key] < CONFIG.craftCooldownSeconds then
        return true, "craft cooldown"
    end

    local craftable = isCraftable(itemName)
    if craftable == false then return false, "no AE2 crafting pattern" end

    if has(bridge, "isCrafting") then
        local ok, active = attempt(function() return bridge.isCrafting({ name = itemName }) end)
        if ok and active == true then
            craftCooldown[key] = epoch()
            return true, "already crafting"
        end
    end

    if not has(bridge, "craftItem") then return false, "ME Bridge has no craftItem method" end
    local ok, result = attempt(function() return bridge.craftItem({ name = itemName, count = wanted }) end)
    if not ok then return false, text(result) end
    if result == false then return false, "AE2 rejected crafting request" end

    craftCooldown[key] = epoch()
    return true, "craft scheduled"
end

local function outputTest()
    local moved, err = exportItem("minecraft:dirt", 1)
    if moved > 0 then
        STATE.lastOutputTest = "PASS: moved 1 dirt"
        recordSent("Output test passed: moved 1 Dirt", colors.lime)
    else
        STATE.lastOutputTest = "FAIL: " .. trim(err, 38)
        recordError("Output test failed: " .. text(err))
    end
end

-------------------------
-- REQUEST PARSING
-------------------------

local TOOL_WORDS = { "sword", "pickaxe", "axe", "shovel", "hoe", "shield", "bow", "crossbow", "trident" }
local ARMOR_WORDS = { "helmet", "chestplate", "leggings", "boots", "armor" }
local FOOD_WORDS = { "bread", "apple", "carrot", "potato", "beef", "porkchop", "chicken", "mutton", "rabbit", "cod", "salmon", "stew", "soup", "berries", "cookie", "melon", "pumpkin_pie", "golden_carrot" }
local SPECIAL_WORDS = { "tool of class", "of class", "minimum level", "maximum level", "repair", "compostable", "fertilizer", "flowers", "smeltable ore", "stack list", "rallying banner", "guard tool", "crafter" }

local function containsAny(value, words)
    for _, word in ipairs(words) do
        if value:find(word, 1, true) then return true, word end
    end
    return false, nil
end

local function requestText(req)
    local parts = { req.name, req.desc, req.description, req.target, req.state, req.id, req.type }
    local out = ""
    for _, part in ipairs(parts) do out = out .. " " .. text(part) end
    return lower(out)
end

local function firstItemTable(req)
    local candidates = {}
    if type(req.items) == "table" then
        if #req.items > 0 then
            for _, item in ipairs(req.items) do table.insert(candidates, item) end
        else
            table.insert(candidates, req.items)
        end
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

local function requestAmount(req, item)
    local values = {
        req.count, req.amount, req.quantity, req.qty, req.minCount, req.missing, req.needed,
        item and item.count, item and item.amount, item and item.quantity, item and item.qty, item and item.minCount
    }
    for _, value in ipairs(values) do
        local n = tonumber(value)
        if n and n > 0 then return math.floor(n) end
    end
    return 1
end

local function parseRequest(req)
    if type(req) ~= "table" then return nil, "request not table" end
    local item = firstItemTable(req)
    if not item then return nil, "no item table" end
    local itemName = item.name or item.item or item.id or item.itemName
    if type(itemName) ~= "string" or itemName == "" then return nil, "bad item name" end
    return {
        item = item,
        itemName = itemName,
        displayName = cleanItemName(itemName),
        amount = requestAmount(req, item),
        target = req.target or req.building or req.resolver or "Unknown",
        id = req.id or req.token or req.name or req.desc or itemName,
        rawRequest = req
    }, nil
end

local function classifyRequest(req, parsed)
    local item = lower(parsed.itemName)
    local all = requestText(req) .. " " .. item

    if parsed.item.nbt or parsed.item.tag or parsed.item.fingerprint then return "SPECIAL", "NBT/special" end
    if containsAny(item, ARMOR_WORDS) then return "ARMOR", nil end
    if containsAny(item, TOOL_WORDS) then return "TOOL", nil end
    if containsAny(item, FOOD_WORDS) then return "FOOD", nil end
    if all:find("fuel", 1, true) then return "FUEL", nil end
    local special, word = containsAny(all, SPECIAL_WORDS)
    if special then return "SPECIAL", word end

    local target = lower(labelValue(parsed.target))
    if target:find("citizen", 1, true) or target:find("visitor", 1, true) then return "OTHER", nil end
    return "BUILD", nil
end

-------------------------
-- MINECOLONIES
-------------------------

local function colonyName()
    local ok, result = attempt(function() return colony.getColonyName() end)
    if ok then return text(result) end
    return "Unknown Colony"
end

local function colonyStatus()
    local function read(method, fallback)
        if not has(colony, method) then return fallback end
        local ok, result = attempt(function() return colony[method]() end)
        if ok then return result end
        return fallback
    end
    return {
        citizens = read("amountOfCitizens", "?"),
        maxCitizens = read("maxOfCitizens", "?"),
        happiness = read("getHappiness", "?"),
        underAttack = read("isUnderAttack", false) == true,
        active = read("isActive", nil),
        constructionSites = read("amountOfConstructionSites", "?"),
        graves = read("amountOfGraves", "?")
    }
end

local function getRequests()
    if not has(colony, "getRequests") then return nil, "Colony Integrator has no getRequests method" end
    local ok, result = attempt(function() return colony.getRequests() end)
    if not ok then return nil, text(result) end
    if type(result) ~= "table" then return nil, "getRequests returned " .. type(result) end
    return result, nil
end

local function workOrderRows()
    local rows = {}
    local seen = {}
    local methods = { "getWorkOrders", "getWorkorders", "getBuildings" }

    for _, method in ipairs(methods) do
        if has(colony, method) then
            local ok, result = attempt(function() return colony[method]() end)
            if ok and type(result) == "table" then
                for _, entry in pairs(result) do
                    local line
                    if type(entry) == "table" then
                        local rawName = entry.name or entry.displayName or entry.type or entry.workOrderType or entry.buildingName or entry.id or "Unknown Building"
                        local name = cleanBuildingName(rawName)
                        local level = entry.level or entry.targetLevel or entry.buildLevel or entry.currentLevel
                        local priority = entry.priority
                        if priority == nil then priority = entry.state or entry.status end
                        line = name
                        if level ~= nil then line = line .. " L" .. fmtStat(level) end
                        if priority ~= nil and text(priority) ~= "" then line = line .. " - " .. cleanStateName(priority) end
                    else
                        line = cleanBuildingName(entry)
                    end
                    if line and line ~= "" and not seen[line] then
                        seen[line] = true
                        table.insert(rows, line)
                    end
                end
            end
        end
    end

    table.sort(rows)
    return rows
end

local function citizenColor(hp, maxHp, food, happiness, state)
    local nHp = tonumber(hp)
    local nMaxHp = tonumber(maxHp)
    local nFood = tonumber(food)
    local nHappy = tonumber(happiness)
    local stateText = lower(labelValue(state))
    local flash = epoch() % 2 == 0

    if nHp and ((nMaxHp and nMaxHp > 0 and nHp / nMaxHp <= 0.35) or nHp <= 7) then
        return flash and colors.red or colors.orange, "LOW HP"
    end
    if nFood and nFood < 5 then return flash and colors.red or colors.orange, "LOW FOOD" end
    if nHappy and nHappy < 1 then return flash and colors.red or colors.orange, "LOW HAPPY" end
    if nFood and nFood < 10 then return colors.orange, "LOW FOOD" end
    if nHappy and nHappy < 1.5 then return colors.orange, "LOW HAPPY" end
    if stateText:find("sleep", 1, true) then return colors.lightBlue, nil end
    return colors.white, nil
end

local function citizenRows()
    local rows = {}
    local alerts = {}
    local methods = { "getCitizens", "getAllCitizens" }

    for _, method in ipairs(methods) do
        if has(colony, method) then
            local ok, result = attempt(function() return colony[method]() end)
            if ok and type(result) == "table" then
                for _, citizen in pairs(result) do
                    if type(citizen) == "table" then
                        local name = citizen.name or citizen.citizenName or citizen.firstName or citizen.firstname or citizen.id or "Citizen"
                        if citizen.lastName then name = text(name) .. " " .. text(citizen.lastName) end
                        local job = citizen.job or citizen.work or citizen.profession or citizen.workBuilding or citizen.workplace or citizen.jobName
                        local hp = citizen.health or citizen.hp
                        local maxHp = citizen.maxHealth or citizen.maxHp
                        local food = citizen.saturation or citizen.food or citizen.hunger
                        local happiness = citizen.happiness or citizen.happy
                        local state = citizen.state or citizen.status
                        local color, warning = citizenColor(hp, maxHp, food, happiness, state)
                        if warning then table.insert(alerts, warning .. ": " .. text(name)) end

                        local line = text(name)
                        if job then line = line .. " | Job: " .. cleanJobName(job) end
                        if hp then line = line .. " | HP: " .. fmtStat(hp) .. (maxHp and ("/" .. fmtStat(maxHp)) or "") end
                        if food then line = line .. " | Food: " .. fmtStat(food) end
                        if happiness then line = line .. " | Happy: " .. fmtStat(happiness) end
                        if state then line = line .. " | " .. cleanStateName(state) end
                        if warning then line = line .. " | ! " .. warning end
                        table.insert(rows, { text = line, color = color })
                    end
                    if #rows >= 60 then return rows, alerts end
                end
                if #rows > 0 then return rows, alerts end
            end
        end
    end
    return rows, alerts
end

-------------------------
-- APPROVAL AND PROCESSING
-------------------------

local recentExports = {}

local function requestKey(parsed)
    return text(parsed.id) .. "|" .. parsed.itemName .. "|" .. parsed.amount
end

local function onCooldown(key)
    return recentExports[key] and epoch() - recentExports[key] < CONFIG.requestCooldownSeconds
end

local function addPending(nextPending, nextOrder, key, parsed, reason)
    nextPending[key] = { parsed = parsed, reason = reason or "approval", time = epoch() }
    table.insert(nextOrder, key)
end

local function normalizeSelected()
    if #STATE.pendingOrder <= 0 then STATE.selected = 1 return end
    if STATE.selected < 1 then STATE.selected = #STATE.pendingOrder end
    if STATE.selected > #STATE.pendingOrder then STATE.selected = 1 end
end

local function selectedPending()
    normalizeSelected()
    local key = STATE.pendingOrder[STATE.selected]
    if key then return key, STATE.pending[key] end
    return nil, nil
end

local function approveSelected(always)
    local key, pending = selectedPending()
    if not pending then action("No pending request", colors.gray, false) return end
    STATE.approvedOnce[key] = true
    if always then
        WHITELIST[pending.parsed.itemName] = true
        BLOCKED[pending.parsed.itemName] = nil
        saveSet(CONFIG.whitelistFile, WHITELIST)
        saveSet(CONFIG.blockedFile, BLOCKED)
        action("Approved always: " .. pending.parsed.displayName, colors.lime, true)
    else
        action("Approved once: " .. pending.parsed.displayName, colors.lime, true)
    end
    STATE.scanNow = true
end

local function denySelected(block)
    local key, pending = selectedPending()
    if not pending then action("No pending request", colors.gray, false) return end
    STATE.deniedUntil[key] = epoch() + CONFIG.denyCooldownSeconds
    if block then
        BLOCKED[pending.parsed.itemName] = true
        WHITELIST[pending.parsed.itemName] = nil
        saveSet(CONFIG.blockedFile, BLOCKED)
        saveSet(CONFIG.whitelistFile, WHITELIST)
        action("Blocked: " .. pending.parsed.displayName, colors.red, true)
    else
        action("Denied once: " .. pending.parsed.displayName, colors.orange, true)
    end
    STATE.scanNow = true
end

local function shouldProcess(key, parsed, nextPending, nextOrder)
    if BLOCKED[parsed.itemName] then return false, "BLOCKED" end
    if STATE.deniedUntil[key] and STATE.deniedUntil[key] > epoch() then return false, "DENIED" end
    if STATE.paused then addPending(nextPending, nextOrder, key, parsed, "paused") return false, "PENDING" end
    if STATE.approvedOnce[key] then return true, "APPROVED" end
    if WHITELIST[parsed.itemName] then return true, "WHITELIST" end

    if STATE.mode == "APPROVAL" then
        addPending(nextPending, nextOrder, key, parsed, "global approval")
        return false, "PENDING"
    end
    if STATE.mode == "WHITELIST" then
        addPending(nextPending, nextOrder, key, parsed, "not whitelisted")
        return false, "PENDING"
    end

    local typeMode = TYPE_MODES[parsed.category] or "APPROVAL"
    if typeMode == "OFF" then return false, "OFF" end
    if typeMode == "APPROVAL" then
        addPending(nextPending, nextOrder, key, parsed, TYPE_LABELS[parsed.category] or parsed.category)
        return false, "PENDING"
    end
    return true, "AUTO"
end

local function addRequestRow(rows, message, color)
    if #rows < CONFIG.maxRows then table.insert(rows, { text = message, color = color }) end
end

local function sendRequest(parsed, rows, stats)
    local key = requestKey(parsed)
    if onCooldown(key) then
        stats.waiting = stats.waiting + 1
        addRequestRow(rows, "[WAIT " .. parsed.category .. "] " .. parsed.amount .. "x " .. trim(parsed.displayName, 45), colors.gray)
        return
    end

    if aeCount(parsed.itemName) > 0 then
        local moved, exportErr = exportItem(parsed.itemName, parsed.amount)
        if moved > 0 then
            recentExports[key] = epoch()
            STATE.approvedOnce[key] = nil
            stats.sent = stats.sent + 1
            STATE.sent = STATE.sent + moved
            addRequestRow(rows, "[SENT " .. parsed.category .. "] " .. moved .. "/" .. parsed.amount .. "x " .. trim(parsed.displayName, 39), colors.lime)
            recordSent("Sent " .. moved .. "x " .. parsed.displayName, colors.lime)
            return
        end
        recordError("Export failed for " .. parsed.displayName .. ": " .. text(exportErr))
    end

    local crafted, craftMessage = craftItem(parsed.itemName, parsed.amount)
    if crafted then
        recentExports[key] = epoch()
        STATE.approvedOnce[key] = nil
        stats.crafting = stats.crafting + 1
        STATE.craft = STATE.craft + 1
        addRequestRow(rows, "[CRAFTING " .. parsed.category .. "] " .. parsed.amount .. "x " .. trim(parsed.displayName, 36), colors.yellow)
        recordSent("Crafting " .. parsed.amount .. "x " .. parsed.displayName, colors.yellow)
    else
        STATE.approvedOnce[key] = nil
        stats.missing = stats.missing + 1
        STATE.missing = STATE.missing + 1
        addRequestRow(rows, "[NO CRAFT] " .. trim(parsed.displayName, 48), colors.red)
        recordError("No craft for " .. parsed.displayName .. ": " .. text(craftMessage))
    end
end

local function buildMaterialRows(parsedRequests)
    local totals = {}
    for _, parsed in ipairs(parsedRequests) do
        if parsed.category == "BUILD" then
            totals[parsed.itemName] = (totals[parsed.itemName] or 0) + (tonumber(parsed.amount) or 1)
        end
    end
    local rows = {}
    for itemName, amount in pairs(totals) do
        table.insert(rows, amount .. "x " .. cleanItemName(itemName))
    end
    table.sort(rows)
    return rows
end

local function makeAlerts()
    local alerts = {}
    if STATE.status.underAttack then
        table.insert(alerts, { text = "!!! UNDER ATTACK !!!", color = colors.white, bg = colors.red, priority = 100 })
    end
    if tonumber(STATE.status.graves) and tonumber(STATE.status.graves) > 0 then
        table.insert(alerts, { text = "GRAVES DETECTED: " .. STATE.status.graves, color = colors.white, bg = colors.red, priority = 95 })
    end
    if STATE.lastError and epoch() - STATE.lastErrorAt <= 300 then
        table.insert(alerts, { text = "ERROR: " .. trim(STATE.lastError, 50), color = colors.white, bg = colors.red, priority = 80 })
    end
    if #STATE.citizenAlerts > 0 then
        table.insert(alerts, { text = trim(STATE.citizenAlerts[1], 55), color = colors.black, bg = colors.orange, priority = 70 })
    end
    if #STATE.pendingOrder > 0 then
        table.insert(alerts, { text = "PENDING REQUESTS: " .. #STATE.pendingOrder, color = colors.black, bg = colors.yellow, priority = 50 })
    end
    if STATE.paused then
        table.insert(alerts, { text = "AUTO SUPPLY PAUSED", color = colors.black, bg = colors.orange, priority = 45 })
    end
    if #alerts == 0 then
        table.insert(alerts, { text = "COLONY SAFE | AE2 OK | 0 PENDING", color = colors.black, bg = colors.lime, priority = 1 })
    end
    table.sort(alerts, function(a, b) return a.priority > b.priority end)
    return alerts
end

local function scan()
    STATE.scans = STATE.scans + 1
    STATE.colonyName = colonyName()
    STATE.status = colonyStatus()
    STATE.workRows = workOrderRows()
    STATE.citizenRows, STATE.citizenAlerts = citizenRows()

    local stats = { total = 0, sent = 0, crafting = 0, skipped = 0, waiting = 0, missing = 0, bad = 0, pending = 0, off = 0 }
    local rows = {}
    local parsedList = {}
    local nextPending = {}
    local nextOrder = {}

    local requests, requestErr = getRequests()
    if not requests then
        stats.bad = 1
        addRequestRow(rows, "[ERROR] Unable to read colony requests", colors.red)
        recordError("getRequests failed: " .. text(requestErr))
        STATE.stats = stats
        STATE.rows = rows
        STATE.alerts = makeAlerts()
        return
    end

    for _, req in pairs(requests) do
        stats.total = stats.total + 1
        local parsed, parseErr = parseRequest(req)
        if not parsed then
            stats.bad = stats.bad + 1
            recordError("Bad request: " .. text(parseErr))
        else
            local category, categoryNote = classifyRequest(req, parsed)
            parsed.category = category
            parsed.categoryNote = categoryNote
            table.insert(parsedList, parsed)

            local key = requestKey(parsed)
            local allowed, status = shouldProcess(key, parsed, nextPending, nextOrder)
            if allowed then
                sendRequest(parsed, rows, stats)
            elseif status == "PENDING" then
                stats.pending = stats.pending + 1
                stats.waiting = stats.waiting + 1
                local reason = nextPending[key] and nextPending[key].reason or "pending"
                addRequestRow(rows, "[PENDING " .. category .. "] " .. parsed.amount .. "x " .. trim(parsed.displayName, 35) .. " (" .. trim(reason, 12) .. ")", colors.yellow)
            elseif status == "OFF" then
                stats.off = stats.off + 1
                addRequestRow(rows, "[OFF " .. category .. "] " .. parsed.amount .. "x " .. trim(parsed.displayName, 43), colors.gray)
            elseif status == "BLOCKED" then
                stats.skipped = stats.skipped + 1
                addRequestRow(rows, "[BLOCKED] " .. parsed.amount .. "x " .. trim(parsed.displayName, 45), colors.red)
            else
                stats.waiting = stats.waiting + 1
                addRequestRow(rows, "[DENIED] " .. parsed.amount .. "x " .. trim(parsed.displayName, 46), colors.orange)
            end
        end
    end

    STATE.pending = nextPending
    STATE.pendingOrder = nextOrder
    normalizeSelected()
    STATE.stats = stats
    STATE.rows = rows
    STATE.buildRows = buildMaterialRows(parsedList)

    if stats.total == 0 then beginIdle() else endIdle() end
    STATE.alerts = makeAlerts()
end

-------------------------
-- HISTORY COLLAPSING
-------------------------

local function historyRowColor(message)
    local lowered = lower(message)
    if lowered:find("output test passed", 1, true) then return colors.lime end
    if lowered:find("sent ", 1, true) or lowered:find("requests resumed", 1, true) then return colors.lime end
    if lowered:find("crafting ", 1, true) then return colors.yellow end
    if lowered:find("denied", 1, true) then return colors.orange end
    if lowered:find("failed", 1, true) or lowered:find("error", 1, true) or lowered:find("blocked", 1, true) then return colors.red end
    if lowered:find("idle", 1, true) or lowered:find("no colony requests", 1, true) then return colors.gray end
    return colors.white
end

local function collapsedHistoryRows()
    local raw = readLines(CONFIG.historyFile, CONFIG.maxHistoryLines * 4)
    local rows = {}
    local currentMessage = nil
    local firstStamp = nil
    local lastStamp = nil
    local repeatCount = 0

    local function normaliseMessage(message)
        if message == "No colony requests" or message == "Colony idle: no open requests" then
            return "Colony idle: no open requests"
        end
        return message
    end

    local function flushRepeated()
        if not currentMessage or repeatCount <= 0 then return end

        local display = currentMessage
        if repeatCount > 1 then
            display = display .. " x" .. repeatCount
            if firstStamp and lastStamp and firstStamp ~= lastStamp then
                display = firstStamp .. " - " .. lastStamp .. " " .. display
            elseif firstStamp then
                display = firstStamp .. " " .. display
            end
        elseif firstStamp then
            display = firstStamp .. " " .. display
        end

        table.insert(rows, {
            text = display,
            color = historyRowColor(currentMessage)
        })
    end

    for _, line in ipairs(raw) do
        local stamp, message = line:match("^(%b[])%s*(.*)$")
        message = normaliseMessage(message or line)

        if message == currentMessage then
            repeatCount = repeatCount + 1
            lastStamp = stamp or lastStamp
        else
            flushRepeated()
            currentMessage = message
            firstStamp = stamp
            lastStamp = stamp
            repeatCount = 1
        end
    end
    flushRepeated()

    if STATE.idleActive then
        table.insert(rows, {
            text = "Currently idle: " .. STATE.idleScans .. " scans (" .. fmtDuration(epoch() - (STATE.idleStarted or epoch())) .. ")",
            color = colors.gray
        })
    end

    if #rows > CONFIG.maxHistoryLines then
        local reduced = {}
        for i = #rows - CONFIG.maxHistoryLines + 1, #rows do
            table.insert(reduced, rows[i])
        end
        rows = reduced
    end
    return rows
end

-------------------------
-- UI PAGES
-------------------------

local function header(countdown)
    local w = select(1, term.getSize())
    local lineColor = STATE.status.underAttack and (epoch() % 2 == 0 and colors.red or colors.gray) or colors.gray
    fillAt(1, 1, w, "=", lineColor)
    center(1, STATE.status.underAttack and " !!! COLONY UNDER ATTACK !!! " or " HackThePlanet Colony Supply ", STATE.status.underAttack and colors.red or colors.lime)
    center(2, "AE2 -> MineColonies Auto-Supply" .. (STATE.paused and " | PAUSED" or "") .. " | Next Scan: " .. countdown .. "s", STATE.paused and colors.orange or colors.cyan)
    fillAt(1, 3, w, "=", lineColor)
end

local function rowsAt(x, y, width, height, rows, emptyMessage)
    local w = math.max(1, tonumber(width) or 1)
    local h = math.max(0, tonumber(height) or 0)
    if not rows or #rows == 0 then
        writeAt(x, y, emptyMessage or "Nothing to show.", colors.gray)
        return
    end
    for i, row in ipairs(rows) do
        if i > h then break end
        if type(row) == "table" then
            writeAt(x, y + i - 1, trim(row.text, w), row.color or colors.white)
        else
            writeAt(x, y + i - 1, trim(row, w), colors.white)
        end
    end
end

local function simplePage(countdown, title, rows, emptyMessage)
    local w, h = term.getSize()
    clear()
    header(countdown)
    box(1, 5, w, math.max(3, h - 5), title, colors.gray)
    rowsAt(3, 7, math.max(1, w - 4), math.max(0, h - 8), rows, emptyMessage)
end

local function dashboardPage(countdown)
    local w, h = term.getSize()
    clear()
    header(countdown)

    if w < 70 or h < 20 then
        writeAt(1, 4, "Colony: " .. STATE.colonyName, colors.yellow)
        writeAt(1, 5, "Mode: " .. STATE.mode .. (STATE.paused and " PAUSED" or ""), STATE.paused and colors.orange or colors.yellow)
        writeAt(1, 6, "Citizens: " .. text(STATE.status.citizens) .. " / " .. text(STATE.status.maxCitizens), colors.white)
        writeAt(1, 7, "Happiness: " .. fmtNumber(STATE.status.happiness, 2), colors.white)
        rowsAt(1, 9, w, math.max(0, h - 11), STATE.rows, "No requests.")
        return
    end

    local left = math.floor(w * 0.52)
    local right = w - left - 1
    box(1, 5, left, 9, " Colony Status ", STATE.status.underAttack and colors.red or colors.gray)
    box(left + 2, 5, right, 9, " System Status ", STATE.status.underAttack and colors.red or colors.gray)

    writeAt(3, 6, "Colony:", colors.yellow); writeAt(12, 6, trim(STATE.colonyName, left - 13), colors.white)
    writeAt(3, 7, "Status:", colors.yellow); writeAt(12, 7, STATE.status.underAttack and "UNDER ATTACK" or "Safe", STATE.status.underAttack and colors.red or colors.lime)
    writeAt(3, 8, "Citizens:", colors.yellow); writeAt(13, 8, text(STATE.status.citizens) .. " / " .. text(STATE.status.maxCitizens), colors.white)
    writeAt(3, 9, "Happy:", colors.yellow); writeAt(11, 9, fmtNumber(STATE.status.happiness, 2), colors.white)
    writeAt(3, 10, "Builds:", colors.yellow); writeAt(11, 10, text(STATE.status.constructionSites), colors.white)
    writeAt(3, 11, "Graves:", colors.yellow); writeAt(11, 11, text(STATE.status.graves), tonumber(STATE.status.graves) and tonumber(STATE.status.graves) > 0 and colors.red or colors.white)

    local rx = left + 4
    writeAt(rx, 6, "Mode:", colors.yellow); writeAt(rx + 7, 6, STATE.mode .. (STATE.paused and " PAUSED" or ""), STATE.paused and colors.orange or colors.lime)
    writeAt(rx, 7, "Output:", colors.yellow); writeAt(rx + 9, 7, "ME Bridge/" .. CONFIG.outputTarget, colors.white)
    writeAt(rx, 8, "Uptime:", colors.yellow); writeAt(rx + 9, 8, fmtDuration(epoch() - STATE.started), colors.white)
    writeAt(rx, 9, "Scans:", colors.yellow); writeAt(rx + 9, 9, text(STATE.scans), colors.white)
    writeAt(rx, 10, "Pending:", colors.yellow); writeAt(rx + 10, 10, text(#STATE.pendingOrder), #STATE.pendingOrder > 0 and colors.yellow or colors.gray)
    writeAt(rx, 11, "Output Test:", colors.yellow); writeAt(rx + 13, 11, trim(STATE.lastOutputTest, right - 16), STATE.lastOutputTest:find("PASS", 1, true) and colors.lime or colors.gray)

    if #STATE.citizenAlerts > 0 then
        writeAt(3, 13, "Citizen Alert: " .. trim(STATE.citizenAlerts[1], left - 18), colors.orange)
    end

    local requestY = 15
    local requestH = math.max(8, h - requestY - 6)
    box(1, requestY, w, requestH, " Current Requests ", colors.gray)
    rowsAt(3, requestY + 1, w - 4, requestH - 2, STATE.rows, "No open colony requests.")

    local footerY = requestY + requestH + 1
    if footerY + 4 <= h then
        box(1, footerY, left, 5, " Scan Summary ", colors.gray)
        box(left + 2, footerY, right, 5, " Recent Actions ", colors.gray)
        writeAt(3, footerY + 1, "Req: " .. STATE.stats.total .. " Pending: " .. STATE.stats.pending .. " Off: " .. STATE.stats.off, colors.white)
        writeAt(3, footerY + 2, "Sent: " .. STATE.stats.sent .. " Craft: " .. STATE.stats.crafting, colors.green)
        writeAt(3, footerY + 3, "Wait: " .. STATE.stats.waiting .. " Blocked: " .. STATE.stats.skipped, colors.gray)
        writeAt(3, footerY + 4, "Missing: " .. STATE.stats.missing .. " Bad: " .. STATE.stats.bad, colors.red)
        rowsAt(left + 4, footerY + 1, right - 4, 3, STATE.actions, "")
    end
end

local function buildPage(countdown)
    local w, h = term.getSize()
    clear()
    header(countdown)
    local half = math.floor((w - 3) / 2)
    box(1, 5, half, math.max(3, h - 5), " Build Material Totals ", colors.gray)
    box(half + 2, 5, w - half - 1, math.max(3, h - 5), " Buildings / Work Orders ", colors.gray)

    if #STATE.buildRows == 0 then
        writeAt(3, 7, "No build material requests found.", colors.lime)
        if #STATE.workRows > 0 or (tonumber(STATE.status.constructionSites) and tonumber(STATE.status.constructionSites) > 0) then
            writeAt(3, 9, "Buildings detected. Waiting for", colors.yellow)
            writeAt(3, 10, "MineColonies to request materials.", colors.yellow)
        end
    else
        rowsAt(3, 7, half - 4, h - 8, STATE.buildRows, "")
    end
    rowsAt(half + 4, 7, w - half - 5, h - 8, STATE.workRows, "No buildings/work orders found.")
end

local function citizensPage(countdown)
    local rows = {
        { text = "Citizens: " .. text(STATE.status.citizens) .. " / " .. text(STATE.status.maxCitizens) .. " | Colony Happiness: " .. fmtNumber(STATE.status.happiness, 2), color = colors.yellow },
        { text = "Red flashing = danger | Orange = low | Blue = sleeping", color = colors.gray },
        { text = "", color = colors.white }
    }
    if #STATE.citizenRows == 0 then
        table.insert(rows, { text = "No detailed citizen list exposed by this Colony Integrator.", color = colors.gray })
    else
        for _, row in ipairs(STATE.citizenRows) do table.insert(rows, row) end
    end
    simplePage(countdown, " Citizens / Villagers ", rows, "No citizen data.")
end

local function typesPage(countdown)
    local rows = {
        { text = "Request Type Rules", color = colors.yellow },
        { text = "AUTO = send/craft | APPROVAL = pending | OFF = ignore", color = colors.gray },
        { text = "", color = colors.white }
    }
    for i, id in ipairs(TYPE_ORDER) do
        local mode = TYPE_MODES[id] or "APPROVAL"
        local color = mode == "AUTO" and colors.lime or (mode == "APPROVAL" and colors.yellow or colors.red)
        table.insert(rows, { text = (i == STATE.typeIndex and "> " or "  ") .. TYPE_LABELS[id] .. ": " .. mode, color = color })
    end
    simplePage(countdown, " Request Type Modes ", rows, "No type rules.")
end

local function pendingPage(countdown)
    local rows = {}
    for i, key in ipairs(STATE.pendingOrder) do
        local pending = STATE.pending[key]
        if pending then
            table.insert(rows, {
                text = (i == STATE.selected and "> " or "  ") .. i .. "/" .. #STATE.pendingOrder .. " [" .. pending.parsed.category .. "] " .. pending.parsed.amount .. "x " .. pending.parsed.displayName .. " (" .. pending.reason .. ")",
                color = i == STATE.selected and colors.yellow or colors.white
            })
        end
    end
    simplePage(countdown, " Pending Approval ", rows, "No pending approvals.")
end

local function settingsPage(countdown)
    local whitelistCount, blockedCount = 0, 0
    for _ in pairs(WHITELIST) do whitelistCount = whitelistCount + 1 end
    for _ in pairs(BLOCKED) do blockedCount = blockedCount + 1 end
    simplePage(countdown, " Settings / Rules ", {
        { text = "Global Mode: " .. STATE.mode, color = colors.yellow },
        { text = "Paused: " .. text(STATE.paused), color = STATE.paused and colors.orange or colors.white },
        { text = "Output Target: " .. CONFIG.outputTarget, color = colors.white },
        { text = "Output Test: " .. STATE.lastOutputTest, color = STATE.lastOutputTest:find("PASS", 1, true) and colors.lime or colors.gray },
        { text = "Whitelist Items: " .. whitelistCount, color = colors.lime },
        { text = "Blocked Items: " .. blockedCount, color = colors.red },
        { text = "", color = colors.white },
        { text = "Global AUTO uses request type rules", color = colors.gray },
        { text = "Global APPROVAL forces pending", color = colors.gray },
        { text = "Global WHITELIST only sends ALWAYS-approved", color = colors.gray }
    }, "No settings.")
end

local function drawMain(countdown)
    if STATE.page == "REQUESTS" then
        simplePage(countdown, " Request Details ", STATE.rows, "No requests.")
    elseif STATE.page == "BUILD" then
        buildPage(countdown)
    elseif STATE.page == "CITIZENS" then
        citizensPage(countdown)
    elseif STATE.page == "TYPES" then
        typesPage(countdown)
    elseif STATE.page == "PENDING" then
        pendingPage(countdown)
    elseif STATE.page == "HISTORY" then
        simplePage(countdown, " History ", collapsedHistoryRows(), "No history yet.")
    elseif STATE.page == "ERRORS" then
        simplePage(countdown, " Errors ", STATE.errorRows, "No errors.")
    elseif STATE.page == "SENT" then
        simplePage(countdown, " Last Sent / Crafting ", STATE.sentRows, "Nothing sent yet.")
    elseif STATE.page == "SETTINGS" then
        settingsPage(countdown)
    else
        dashboardPage(countdown)
    end
end

local function drawAlert()
    if not ALERT then return end
    local alerts = STATE.alerts
    local index = 1
    if #alerts > 1 then index = (math.floor(epoch() / 4) % #alerts) + 1 end
    local alert = alerts[index] or { text = "COLONY SAFE", color = colors.black, bg = colors.lime }
    local bg = alert.bg or colors.black
    local fg = alert.color or colors.white
    if bg == colors.red and epoch() % 2 == 1 then bg, fg = colors.black, colors.red end

    clear(bg)
    local w, h = term.getSize()
    for y = 1, h do fillAt(1, y, w, " ", fg, bg) end
    center(math.max(1, math.floor((h + 1) / 2)), trim(alert.text, w), fg, bg)
end

local function drawControl(countdown)
    if not CONTROL then return end
    clear()
    local w, h = term.getSize()
    center(1, "HTP CONTROL PANEL", colors.lime)
    center(2, "Next Scan: " .. countdown .. "s", colors.cyan)
    fillAt(1, 3, w, "=", STATE.status.underAttack and colors.red or colors.gray)

    local colWidth = math.max(6, math.floor((w - 4) / 3))
    local function controlButton(column, row, label, fn, active, color)
        local x = 2 + ((column - 1) * (colWidth + 1))
        addButton(CONTROL.name, x, row, colWidth, 2, label, fn, active and colors.lime or (color or colors.gray))
    end

    controlButton(1, 4, "AUTO", function() setMode("AUTO") end, STATE.mode == "AUTO")
    controlButton(2, 4, "APPROVAL", function() setMode("APPROVAL") end, STATE.mode == "APPROVAL")
    controlButton(3, 4, "WHITE", function() setMode("WHITELIST") end, STATE.mode == "WHITELIST")

    controlButton(1, 7, "DASH", function() setPage("DASHBOARD") end, STATE.page == "DASHBOARD")
    controlButton(2, 7, "REQ", function() setPage("REQUESTS") end, STATE.page == "REQUESTS")
    controlButton(3, 7, "BUILD", function() setPage("BUILD") end, STATE.page == "BUILD")

    controlButton(1, 10, "CITIZENS", function() setPage("CITIZENS") end, STATE.page == "CITIZENS")
    controlButton(2, 10, "PENDING", function() setPage("PENDING") end, STATE.page == "PENDING")
    controlButton(3, 10, "TYPES", function() setPage("TYPES") end, STATE.page == "TYPES")

    controlButton(1, 13, "ERRORS", function() setPage("ERRORS") end, STATE.page == "ERRORS")
    controlButton(2, 13, "SENT", function() setPage("SENT") end, STATE.page == "SENT")
    controlButton(3, 13, "HISTORY", function() setPage("HISTORY") end, STATE.page == "HISTORY")

    controlButton(1, 16, "SETTINGS", function() setPage("SETTINGS") end, STATE.page == "SETTINGS")
    controlButton(2, 16, STATE.paused and "RESUME" or "PAUSE", function() setPaused(not STATE.paused) end, STATE.paused)
    controlButton(3, 16, "SCAN", function() STATE.scanNow = true action("Manual scan queued", colors.cyan, false) end, false)

    local y = 19
    if STATE.page == "TYPES" then
        local id = currentType()
        writeAt(2, y, "Type " .. STATE.typeIndex .. "/" .. #TYPE_ORDER .. ": " .. TYPE_LABELS[id], colors.yellow)
        writeAt(2, y + 1, "Mode: " .. TYPE_MODES[id], TYPE_MODES[id] == "AUTO" and colors.lime or (TYPE_MODES[id] == "APPROVAL" and colors.yellow or colors.red))
        local half = math.max(8, math.floor((w - 5) / 2))
        addButton(CONTROL.name, 2, y + 3, half, 2, "PREV", function() STATE.typeIndex = STATE.typeIndex - 1 currentType() saveState() end, colors.gray)
        addButton(CONTROL.name, 3 + half, y + 3, half, 2, "NEXT", function() STATE.typeIndex = STATE.typeIndex + 1 currentType() saveState() end, colors.gray)
        addButton(CONTROL.name, 2, y + 6, half, 2, "AUTO", function() setTypeMode(currentType(), "AUTO") end, colors.lime)
        addButton(CONTROL.name, 3 + half, y + 6, half, 2, "APPROVAL", function() setTypeMode(currentType(), "APPROVAL") end, colors.yellow)
        addButton(CONTROL.name, 2, y + 9, half, 2, "OFF", function() setTypeMode(currentType(), "OFF") end, colors.red)
        addButton(CONTROL.name, 3 + half, y + 9, half, 2, "CYCLE", function()
            local typeId = currentType()
            local current = TYPE_MODES[typeId]
            setTypeMode(typeId, current == "AUTO" and "APPROVAL" or (current == "APPROVAL" and "OFF" or "AUTO"))
        end, colors.gray)
    else
        local _, pending = selectedPending()
        if pending then
            writeAt(2, y, "Pending " .. STATE.selected .. "/" .. #STATE.pendingOrder .. ": " .. trim(pending.parsed.amount .. "x " .. pending.parsed.displayName, w - 18), colors.yellow)
            writeAt(2, y + 1, "Type: " .. pending.parsed.category .. " | " .. trim(pending.reason, w - 18), colors.gray)
            local half = math.max(8, math.floor((w - 5) / 2))
            addButton(CONTROL.name, 2, y + 3, half, 2, "PREV", function() STATE.selected = STATE.selected - 1 normalizeSelected() saveState() end, colors.gray)
            addButton(CONTROL.name, 3 + half, y + 3, half, 2, "NEXT", function() STATE.selected = STATE.selected + 1 normalizeSelected() saveState() end, colors.gray)
            addButton(CONTROL.name, 2, y + 6, half, 2, "APPROVE", function() approveSelected(false) end, colors.lime)
            addButton(CONTROL.name, 3 + half, y + 6, half, 2, "ALWAYS", function() approveSelected(true) end, colors.green)
            addButton(CONTROL.name, 2, y + 9, half, 2, "DENY", function() denySelected(false) end, colors.orange)
            addButton(CONTROL.name, 3 + half, y + 9, half, 2, "BLOCK", function() denySelected(true) end, colors.red)
        else
            center(y + 2, "No pending approvals", colors.gray)
        end
    end

    if h >= 34 then
        addButton(CONTROL.name, 2, h - 6, math.max(10, w - 4), 2, "TEST OUTPUT", outputTest, colors.lightBlue)
        addButton(CONTROL.name, 2, h - 3, math.max(10, w - 4), 2, "CLEAR HISTORY", clearHistory, colors.gray)
    end
    center(h - 1, STATE.status.underAttack and "!!! COLONY UNDER ATTACK !!!" or "AE2 LINKED | COLONY LINKED", STATE.status.underAttack and colors.red or colors.gray)
end

local function render(countdown)
    BUTTONS = {}

    local okMain, errMain = withScreen(MAIN, function() drawMain(countdown) end)
    if not okMain then recordError("Main render failed: " .. text(errMain)) end

    if CONTROL then
        local okControl, errControl = withScreen(CONTROL, function() drawControl(countdown) end)
        if not okControl then recordError("Control render failed: " .. text(errControl)) end
    end

    if ALERT then
        local okAlert, errAlert = withScreen(ALERT, drawAlert)
        if not okAlert then recordError("Alert render failed: " .. text(errAlert)) end
    end
end

local function handleTouch(screenName, x, y)
    for _, button in ipairs(BUTTONS) do
        if button.screen == screenName and x >= button.x1 and x <= button.x2 and y >= button.y1 and y <= button.y2 then
            local ok, err = pcall(button.action)
            if not ok then recordError("Button failed: " .. text(err)) end
            return true
        end
    end
    return false
end

-------------------------
-- START
-------------------------

detectMonitors()
bootSplash()

term.redirect(nativeTerm)
clear()
print("HTP Colony Supply running.")
print("Main: " .. text(MAIN.name) .. " " .. text(MAIN.w) .. "x" .. text(MAIN.h))
print("Control: " .. text(CONTROL and CONTROL.name or "none"))
print("Alert: " .. text(ALERT and ALERT.name or "none"))
action("Program started", colors.lime, true)

local okInitial, initialErr = pcall(scan)
if not okInitial then recordError("Initial scan failed: " .. text(initialErr)) end

local nextScan = epoch() + CONFIG.scanSeconds
render(CONFIG.scanSeconds)

while true do
    local countdown = math.max(0, nextScan - epoch())
    render(countdown)
    os.startTimer(1)
    local event = { os.pullEvent() }

    if event[1] == "monitor_touch" then
        handleTouch(event[2], event[3], event[4])
        render(math.max(0, nextScan - epoch()))
    end

    if STATE.scanNow or epoch() >= nextScan then
        STATE.scanNow = false
        local okScan, scanErr = pcall(scan)
        if not okScan then recordError("Scan failed: " .. text(scanErr)) end
        nextScan = epoch() + CONFIG.scanSeconds
    end
end
