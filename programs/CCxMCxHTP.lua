-- startup
-- HackThePlanet CC & MineColonies Program
-- CC:Tweaked + Advanced Peripherals + AE2 + MineColonies
-- Dual-monitor AE2 supply dashboard with approvals, build page, and citizens page.

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
    autoCraft = true,
    defaultMode = "AUTO", -- AUTO / APPROVAL / WHITELIST
    settingsFile = "htp_settings.cfg",
    whitelistFile = "htp_whitelist.txt",
    blockedFile = "htp_blacklist.txt",
    historyFile = "htp_history.log",
    errorFile = "htp_colony_errors.log",
    maxRows = 12,
    maxHistoryLines = 80
}

local nativeTerm = term.current()
local bridge = peripheral.find("me_bridge") or peripheral.find("meBridge")
local colony = peripheral.find("colony_integrator") or peripheral.find("colonyIntegrator")
if not bridge then error("No ME Bridge found. Connect an Advanced Peripherals ME Bridge.") end
if not colony then error("No Colony Integrator found. Connect a Colony Integrator inside your colony.") end

local function safe(fn, fallback)
    local ok, result = pcall(fn)
    if ok then return result end
    return fallback, result
end

local function now()
    if os.epoch then return math.floor(os.epoch("utc") / 1000) end
    return math.floor(os.clock())
end

local function has(obj, method) return type(obj[method]) == "function" end
local function text(v) return tostring(v or "") end
local function lower(v) return string.lower(text(v)) end
local function trim(v, max)
    v = text(v)
    max = tonumber(max) or 20
    if max <= 0 then return "" end
    if #v <= max then return v end
    if max <= 3 then return string.sub(v, 1, max) end
    return string.sub(v, 1, max - 3) .. "..."
end

local function fmtNum(v, places)
    local n = tonumber(v)
    if not n then return text(v or "?") end
    if places and places > 0 then return string.format("%." .. tostring(places) .. "f", n) end
    return tostring(math.floor(n + 0.5))
end

local function fmtStat(v)
    local n = tonumber(v)
    if not n then return text(v or "?") end
    if math.abs(n - math.floor(n + 0.00001)) < 0.005 then return tostring(math.floor(n + 0.00001)) end
    return string.format("%.2f", n)
end

local function titleCase(v)
    v = text(v)
    v = v:gsub("_", " "):gsub("%-", " ")
    return (v:gsub("(%a)([%w_']*)", function(a, b) return string.upper(a) .. string.lower(b) end))
end

local function labelValue(v)
    if type(v) ~= "table" then return text(v) end
    return text(v.name or v.displayName or v.type or v.buildingName or v.id or "Assigned")
end

local function cleanJobName(v)
    local raw = labelValue(v)
    local l = lower(raw)
    local known = {
        { "builder", "Builder" },
        { "miner", "Miner" },
        { "farmer", "Farmer" },
        { "guard", "Guard" },
        { "courier", "Courier" },
        { "cook", "Cook" },
        { "restaurant", "Cook" },
        { "lumberjack", "Lumberjack" },
        { "forester", "Forester" },
        { "fisher", "Fisher" },
        { "rancher", "Rancher" },
        { "shepherd", "Shepherd" },
        { "chicken", "Chicken Herder" },
        { "cowboy", "Cowhand" },
        { "swine", "Swineherd" },
        { "composter", "Composter" },
        { "sifter", "Sifter" },
        { "baker", "Baker" },
        { "sawmill", "Sawmill" },
        { "crusher", "Crusher" },
        { "stonemason", "Stonemason" },
        { "blacksmith", "Blacksmith" },
        { "mechanic", "Mechanic" },
        { "enchanter", "Enchanter" },
        { "florist", "Florist" },
        { "student", "Student" },
        { "teacher", "Teacher" },
        { "visitor", "Visitor" },
        { "citizen", "Citizen" }
    }
    for _, pair in ipairs(known) do
        if string.find(l, pair[1], 1, true) then return pair[2] end
    end
    raw = raw:gsub("^.*%.", "")
    raw = raw:gsub("^.*:", "")
    raw = raw:gsub("^Building", "")
    raw = raw:gsub("^building", "")
    if raw == "" then return "Worker" end
    return titleCase(raw)
end

local function fmtTime(seconds)
    seconds = math.max(0, tonumber(seconds) or 0)
    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    local s = math.floor(seconds % 60)
    if h > 0 then return h .. "h " .. m .. "m" end
    if m > 0 then return m .. "m " .. s .. "s" end
    return s .. "s"
end

local function append(path, line)
    local f = fs.open(path, "a")
    if f then f.writeLine("[" .. now() .. "] " .. text(line)); f.close() end
end

local function readLines(path, limit)
    local out = {}
    if not fs.exists(path) then return out end
    local f = fs.open(path, "r")
    if not f then return out end
    while true do
        local line = f.readLine()
        if not line then break end
        table.insert(out, line)
    end
    f.close()
    if limit and #out > limit then
        local trimmed = {}
        for i = math.max(1, #out - limit + 1), #out do table.insert(trimmed, out[i]) end
        return trimmed
    end
    return out
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
    local keys = {}
    for key, value in pairs(set) do if value then table.insert(keys, key) end end
    table.sort(keys)
    for _, key in ipairs(keys) do f.writeLine(key) end
    f.close()
end

local function loadSettings()
    local settings = {}
    for _, line in ipairs(readLines(CONFIG.settingsFile)) do
        local k, v = string.match(line, "^([%w_]+)%s*=%s*(.-)%s*$")
        if k and v then settings[k] = v end
    end
    return settings
end

local function saveSettings(settings)
    local f = fs.open(CONFIG.settingsFile, "w")
    if not f then return end
    for key, value in pairs(settings) do f.writeLine(key .. "=" .. text(value)) end
    f.close()
end

local MAIN = { name = "terminal", object = nativeTerm, w = 51, h = 19, area = 0 }
local CONTROL = nil
local BUTTONS = {}

local function detectMonitors()
    local monitors = {}
    for _, name in ipairs(peripheral.getNames()) do
        if peripheral.getType(name) == "monitor" then
            local mon = peripheral.wrap(name)
            pcall(function() mon.setTextScale(CONFIG.monitorScale) end)
            local okSize, w, h = pcall(function() return mon.getSize() end)
            if okSize and type(w) == "number" and type(h) == "number" then
                table.insert(monitors, { name = name, object = mon, w = w, h = h, area = w * h })
            end
        end
    end
    table.sort(monitors, function(a, b) return a.area > b.area end)
    if #monitors >= 1 then MAIN = monitors[1] end
    if #monitors >= 2 then CONTROL = monitors[2] end
    if MAIN.object == nativeTerm then
        local w, h = term.getSize()
        MAIN.w, MAIN.h, MAIN.area = w, h, w * h
    end
end

local function withScreen(screen, fn)
    local old = term.current()
    term.redirect(screen.object)
    local okRun, err = pcall(fn)
    term.redirect(old or nativeTerm)
    if not okRun then error(err) end
end

local function clear()
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(1, 1)
end

local function writeAt(x, y, value, color, background)
    local w, h = term.getSize()
    if y < 1 or y > h or x > w then return end
    if x < 1 then x = 1 end
    term.setCursorPos(x, y)
    term.setBackgroundColor(background or colors.black)
    term.setTextColor(color or colors.white)
    term.write(trim(value, w - x + 1))
    term.setBackgroundColor(colors.black)
end

local function fillAt(x, y, width, ch, color, background)
    width = math.max(0, tonumber(width) or 0)
    if width > 0 then writeAt(x, y, string.rep(ch or " ", width), color, background) end
end

local function center(y, value, color)
    local w = term.getSize()
    value = text(value)
    writeAt(math.max(1, math.floor((w - #value) / 2) + 1), y, value, color)
end

local function box(x, y, w, h, title, color)
    color = color or colors.gray
    w = math.max(4, w)
    h = math.max(3, h)
    writeAt(x, y, "+" .. string.rep("-", w - 2) .. "+", color)
    for row = 1, h - 2 do
        writeAt(x, y + row, "|", color)
        fillAt(x + 1, y + row, w - 2, " ", colors.white, colors.black)
        writeAt(x + w - 1, y + row, "|", color)
    end
    writeAt(x, y + h - 1, "+" .. string.rep("-", w - 2) .. "+", color)
    if title then writeAt(x + 2, y, " " .. trim(title, w - 6) .. " ", colors.yellow) end
end

local function button(screenName, x, y, w, h, label, action, color)
    table.insert(BUTTONS, { screen = screenName, x1 = x, y1 = y, x2 = x + w - 1, y2 = y + h - 1, action = action })
    color = color or colors.gray
    for row = 0, h - 1 do writeAt(x, y + row, string.rep(" ", w), colors.black, color) end
    writeAt(x + math.max(0, math.floor((w - #label) / 2)), y + math.floor(h / 2), label, colors.black, color)
end

local settings = loadSettings()
local WHITELIST = loadSet(CONFIG.whitelistFile)
local BLOCKED = loadSet(CONFIG.blockedFile)

local STATE = {
    mode = settings.mode or CONFIG.defaultMode,
    page = settings.page or "DASHBOARD",
    paused = settings.paused == "true",
    selected = tonumber(settings.selected or "1") or 1,
    started = now(),
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
    actions = {},
    lastAction = "Program started",
    colonyName = "Unknown Colony",
    status = {},
    stats = { total = 0, sent = 0, crafting = 0, skipped = 0, waiting = 0, missing = 0, bad = 0, pending = 0 },
    scanNow = false
}

local function saveState()
    settings.mode = STATE.mode
    settings.page = STATE.page
    settings.paused = tostring(STATE.paused)
    settings.selected = tostring(STATE.selected)
    saveSettings(settings)
end

local function action(message)
    STATE.lastAction = message
    table.insert(STATE.actions, 1, message)
    while #STATE.actions > 6 do table.remove(STATE.actions) end
    append(CONFIG.historyFile, message)
end

local function setMode(mode)
    STATE.mode = mode
    saveState()
    action("Mode set to " .. mode)
end

local function setPage(page)
    STATE.page = page
    saveState()
    action("Page: " .. page)
end

local function setPaused(value)
    STATE.paused = value == true
    saveState()
    action(STATE.paused and "Auto supply paused" or "Auto supply resumed")
end

local function clearHistory()
    local f = fs.open(CONFIG.historyFile, "w")
    if f then f.close() end
    STATE.actions = {}
    STATE.lastAction = "History cleared"
    append(CONFIG.historyFile, "History cleared")
end

local function bootSplash()
    local steps = {
        "Booting HackThePlanet systems...",
        "Loading CC:Tweaked services...",
        "Connecting to AE2 network...",
        "Checking MineColonies Integrator...",
        "Detecting dual monitors...",
        "Loading approval rules...",
        "Loading build and citizen pages...",
        "System ready."
    }
    local ticks = math.max(20, CONFIG.splashSeconds * 10)
    for tick = 1, ticks do
        local percent = math.floor((tick / ticks) * 100)
        local step = steps[math.min(#steps, math.max(1, math.ceil((percent / 100) * #steps)))]
        local function draw()
            clear()
            local w, h = term.getSize()
            local y = math.max(2, math.floor(h / 2) - 6)
            center(y, "========================================", colors.gray)
            center(y + 1, "HackThePlanet", colors.lime)
            center(y + 2, "CC & MineColonies Program", colors.cyan)
            center(y + 3, "AE2 Auto-Supply Command Center", colors.yellow)
            center(y + 5, step, colors.white)
            local bw = math.min(42, math.max(18, w - 12))
            local bx = math.max(1, math.floor((w - bw - 2) / 2) + 1)
            writeAt(bx, y + 7, "[", colors.gray)
            local filled = math.floor((percent / 100) * bw)
            for i = 1, bw do writeAt(bx + i, y + 7, i <= filled and "=" or "-", i <= filled and colors.lime or colors.gray) end
            writeAt(bx + bw + 1, y + 7, "]", colors.gray)
            center(y + 9, percent .. "%", colors.white)
        end
        withScreen(MAIN, draw)
        if CONTROL then withScreen(CONTROL, draw) end
        sleep(0.1)
    end
end

local function aeCount(itemName)
    local item = safe(function() return bridge.getItem({ name = itemName }) end, nil)
    if type(item) == "table" then return tonumber(item.amount or item.count or 0) or 0 end
    return 0
end

local function exportItem(itemName, amount)
    amount = math.max(1, math.min(tonumber(amount) or 1, CONFIG.maxExportPerRequest))
    local before = aeCount(itemName)
    if before <= 0 then return 0, "none in AE2" end
    amount = math.min(amount, before)
    local result, err
    if has(bridge, "exportItem") then
        result, err = safe(function() return bridge.exportItem({ name = itemName, count = amount }, CONFIG.outputTarget) end, nil)
    elseif has(bridge, "exportItemToPeripheral") then
        result, err = safe(function() return bridge.exportItemToPeripheral({ name = itemName, count = amount }, CONFIG.outputTarget) end, nil)
    else
        return 0, "no export method"
    end
    if type(result) == "number" then return result, nil end
    if type(result) == "table" then
        local moved = tonumber(result.amount or result.count or result.transferred or result.exported or 0) or 0
        if moved > 0 then return moved, nil end
    end
    sleep(0.15)
    local movedByCount = math.max(0, before - aeCount(itemName))
    if movedByCount > 0 then return movedByCount, nil end
    return 0, text(err or result or "export failed")
end

local craftCooldown = {}
local function craftItem(itemName, amount)
    if not CONFIG.autoCraft then return false, "craft disabled" end
    amount = math.max(1, math.min(tonumber(amount) or 1, CONFIG.maxCraftPerRequest))
    local key = itemName .. "|" .. amount
    if craftCooldown[key] and now() - craftCooldown[key] < CONFIG.craftCooldownSeconds then return true, "craft cooldown" end
    if has(bridge, "isCrafting") and safe(function() return bridge.isCrafting({ name = itemName }) end, false) == true then
        craftCooldown[key] = now()
        return true, "already crafting"
    end
    if not has(bridge, "craftItem") then return false, "no craftItem method" end
    local result, err = safe(function() return bridge.craftItem({ name = itemName, count = amount }) end, nil)
    if result == true or type(result) == "table" or (result == nil and err == nil) then
        craftCooldown[key] = now()
        return true, "craft scheduled"
    end
    return false, text(err or result or "craft failed")
end

local manualWords = { "tool of class", "of class", "minimum level", "maximum level", "armor", "equipment", "repair", "food", "fuel", "compostable", "fertilizer", "flowers", "smeltable ore", "stack list", "rallying banner", "guard tool", "crafter" }
local toolWords = { "sword", "pickaxe", "axe", "shovel", "hoe", "helmet", "chestplate", "leggings", "boots", "shield", "bow", "crossbow", "trident" }

local function requestText(req)
    local parts = { req.name, req.desc, req.description, req.target, req.state, req.id }
    local out = ""
    for _, part in ipairs(parts) do out = out .. " " .. text(part) end
    return lower(out)
end

local function firstItemTable(req)
    local candidates = {}
    if type(req.items) == "table" then
        if #req.items > 0 then for _, item in ipairs(req.items) do table.insert(candidates, item) end else table.insert(candidates, req.items) end
    end
    if type(req.item) == "table" then table.insert(candidates, req.item) end
    if type(req.stack) == "table" then table.insert(candidates, req.stack) end
    if type(req.requestedItem) == "table" then table.insert(candidates, req.requestedItem) end
    for _, item in ipairs(candidates) do
        local name = item.name or item.item or item.id or item.itemName
        if type(name) == "string" and name ~= "" and name ~= "minecraft:air" then return item end
    end
    return nil
end

local function requestAmount(req, item)
    local values = { req.count, req.amount, req.quantity, req.qty, req.minCount, req.missing, req.needed, item and item.count, item and item.amount, item and item.quantity, item and item.qty, item and item.minCount }
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
    local name = item.name or item.item or item.id or item.itemName
    if type(name) ~= "string" or name == "" then return nil, "bad item" end
    return {
        item = item,
        itemName = name,
        amount = requestAmount(req, item),
        display = req.name or req.desc or req.description or item.displayName or name,
        target = req.target or req.building or req.resolver or "Unknown",
        id = req.id or req.token or req.name or req.desc or name
    }, nil
end

local function manualReason(req, parsed)
    if parsed.item.nbt or parsed.item.tag or parsed.item.fingerprint then return "NBT/special item" end
    local full = requestText(req)
    for _, word in ipairs(manualWords) do if string.find(full, word, 1, true) then return "manual: " .. word end end
    local itemName = lower(parsed.itemName)
    for _, word in ipairs(toolWords) do if string.find(itemName, word, 1, true) then return "tool/armor item" end end
    return nil
end

local function colonyName()
    return text(safe(function() return colony.getColonyName() end, "Unknown Colony"))
end

local function colonyStatus()
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
    local result, err = safe(function() return colony.getRequests() end, nil)
    if type(result) ~= "table" then return nil, text(err or "getRequests failed") end
    return result, nil
end

local function workOrderRows()
    local rows = {}
    for _, method in ipairs({ "getWorkOrders", "getWorkorders", "getConstructionSites", "getBuildings" }) do
        if has(colony, method) then
            local result = safe(function() return colony[method]() end, nil)
            if type(result) == "table" then
                for _, entry in pairs(result) do
                    if type(entry) == "table" then
                        local title = entry.name or entry.displayName or entry.type or entry.workOrderType or entry.buildingName or entry.id or "Work Order"
                        local level = entry.level or entry.targetLevel or entry.buildLevel or entry.currentLevel
                        local state = entry.state or entry.status or entry.priority or entry.claimedBy
                        table.insert(rows, "[" .. method .. "] " .. labelValue(title) .. (level and (" L" .. fmtStat(level)) or "") .. (state and (" - " .. labelValue(state)) or ""))
                    else
                        table.insert(rows, "[" .. method .. "] " .. text(entry))
                    end
                    if #rows >= 16 then return rows end
                end
                if #rows > 0 then return rows end
            end
        end
    end
    return rows
end

local function citizenColor(hp, maxHp, food, happy, state)
    local flash = now() % 2 == 0
    local stateText = lower(state)
    local nHp = tonumber(hp)
    local nMax = tonumber(maxHp)
    local nFood = tonumber(food)
    local nHappy = tonumber(happy)
    if nHp and ((nMax and nMax > 0 and nHp / nMax <= 0.35) or nHp <= 7) then return flash and colors.red or colors.orange end
    if nFood and nFood < 5 then return flash and colors.red or colors.orange end
    if nHappy and nHappy < 1 then return flash and colors.red or colors.orange end
    if nFood and nFood < 10 then return colors.orange end
    if nHappy and nHappy < 1.5 then return colors.orange end
    if string.find(stateText, "sleep", 1, true) then return colors.lightBlue end
    return colors.white
end

local function citizenRows()
    local rows = {}
    for _, method in ipairs({ "getCitizens", "getAllCitizens" }) do
        if has(colony, method) then
            local result = safe(function() return colony[method]() end, nil)
            if type(result) == "table" then
                for _, citizen in pairs(result) do
                    if type(citizen) == "table" then
                        local name = citizen.name or citizen.citizenName or citizen.firstName or citizen.firstname or citizen.id or "Citizen"
                        if citizen.lastName then name = text(name) .. " " .. text(citizen.lastName) end
                        local job = citizen.job or citizen.work or citizen.profession or citizen.workBuilding or citizen.workplace or citizen.jobName
                        local hp = citizen.health or citizen.hp
                        local maxHp = citizen.maxHealth or citizen.maxHp
                        local food = citizen.saturation or citizen.food or citizen.hunger
                        local happy = citizen.happiness or citizen.happy
                        local state = citizen.state or citizen.status
                        local warnings = {}
                        if tonumber(hp) and ((tonumber(maxHp) and tonumber(maxHp) > 0 and tonumber(hp) / tonumber(maxHp) <= 0.35) or tonumber(hp) <= 7) then table.insert(warnings, "LOW HP") end
                        if tonumber(food) and tonumber(food) < 10 then table.insert(warnings, "LOW FOOD") end
                        if tonumber(happy) and tonumber(happy) < 1.5 then table.insert(warnings, "LOW HAPPY") end
                        local line = text(name)
                        if job then line = line .. " | Job: " .. cleanJobName(job) end
                        if hp then line = line .. " | HP: " .. fmtStat(hp) .. (maxHp and ("/" .. fmtStat(maxHp)) or "") end
                        if food then line = line .. " | Food: " .. fmtStat(food) end
                        if happy then line = line .. " | Happy: " .. fmtStat(happy) end
                        if state then line = line .. " | " .. labelValue(state) end
                        if #warnings > 0 then line = line .. " | ! " .. table.concat(warnings, ", ") end
                        table.insert(rows, { text = line, color = citizenColor(hp, maxHp, food, happy, state) })
                    else
                        table.insert(rows, { text = text(citizen), color = colors.white })
                    end
                    if #rows >= 48 then return rows end
                end
                if #rows > 0 then return rows end
            end
        end
    end
    return rows
end

local function requestKey(parsed) return text(parsed.id) .. "|" .. parsed.itemName .. "|" .. parsed.amount end
local recentExports = {}
local function onCooldown(key) return recentExports[key] and now() - recentExports[key] < CONFIG.requestCooldownSeconds end

local function addPending(nextPending, nextOrder, key, parsed, reason)
    nextPending[key] = { parsed = parsed, reason = reason or "approval", time = now() }
    table.insert(nextOrder, key)
end

local function normalizeSelected()
    if #STATE.pendingOrder <= 0 then STATE.selected = 1; return end
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
    if not pending then action("No pending request"); return end
    STATE.approvedOnce[key] = true
    if always then
        WHITELIST[pending.parsed.itemName] = true
        BLOCKED[pending.parsed.itemName] = nil
        saveSet(CONFIG.whitelistFile, WHITELIST)
        saveSet(CONFIG.blockedFile, BLOCKED)
        action("Approved always: " .. pending.parsed.itemName)
    else
        action("Approved once: " .. pending.parsed.itemName)
    end
    STATE.scanNow = true
end

local function denySelected(block)
    local key, pending = selectedPending()
    if not pending then action("No pending request"); return end
    STATE.deniedUntil[key] = now() + CONFIG.denyCooldownSeconds
    if block then
        BLOCKED[pending.parsed.itemName] = true
        WHITELIST[pending.parsed.itemName] = nil
        saveSet(CONFIG.blockedFile, BLOCKED)
        saveSet(CONFIG.whitelistFile, WHITELIST)
        action("Blocked: " .. pending.parsed.itemName)
    else
        action("Denied once: " .. pending.parsed.itemName)
    end
    STATE.scanNow = true
end

local function shouldProcess(key, parsed, nextPending, nextOrder, reason)
    if BLOCKED[parsed.itemName] then return false, "BLOCKED" end
    if STATE.deniedUntil[key] and STATE.deniedUntil[key] > now() then return false, "DENIED" end
    if STATE.paused then addPending(nextPending, nextOrder, key, parsed, "paused"); return false, "PENDING" end
    if STATE.approvedOnce[key] then return true, "APPROVED" end
    if WHITELIST[parsed.itemName] then return true, "WHITELIST" end
    if reason then addPending(nextPending, nextOrder, key, parsed, reason); return false, "PENDING" end
    if STATE.mode == "AUTO" then return true, "AUTO" end
    if STATE.mode == "WHITELIST" then addPending(nextPending, nextOrder, key, parsed, "not whitelisted"); return false, "PENDING" end
    addPending(nextPending, nextOrder, key, parsed, "approval mode")
    return false, "PENDING"
end

local function addRow(rows, message, color)
    if #rows < CONFIG.maxRows then table.insert(rows, { text = message, color = color }) end
end

local function sendRequest(parsed, rows, stats)
    local key = requestKey(parsed)
    if onCooldown(key) then
        stats.waiting = stats.waiting + 1
        addRow(rows, "[WAIT] " .. parsed.amount .. "x " .. trim(parsed.itemName, 50), colors.gray)
        return
    end
    if aeCount(parsed.itemName) > 0 then
        local moved, err = exportItem(parsed.itemName, parsed.amount)
        if moved > 0 then
            recentExports[key] = now()
            STATE.approvedOnce[key] = nil
            stats.sent = stats.sent + 1
            STATE.sent = STATE.sent + moved
            addRow(rows, "[SENT] " .. moved .. "/" .. parsed.amount .. "x " .. trim(parsed.itemName, 44), colors.lime)
            action("Sent " .. moved .. "x " .. parsed.itemName)
            return
        end
    end
    local crafted, msg = craftItem(parsed.itemName, parsed.amount)
    if crafted then
        STATE.approvedOnce[key] = nil
        stats.crafting = stats.crafting + 1
        STATE.craft = STATE.craft + 1
        addRow(rows, "[CRAFT] " .. parsed.amount .. "x " .. trim(parsed.itemName, 47), colors.yellow)
        action("Crafting " .. parsed.amount .. "x " .. parsed.itemName)
    else
        stats.missing = stats.missing + 1
        STATE.missing = STATE.missing + 1
        addRow(rows, "[MISS] " .. parsed.amount .. "x " .. trim(parsed.itemName, 48), colors.red)
        action("Missing " .. parsed.itemName .. " - " .. trim(msg, 30))
    end
end

local function buildRows(parsedRequests)
    local totals = {}
    for _, parsed in ipairs(parsedRequests) do totals[parsed.itemName] = (totals[parsed.itemName] or 0) + (tonumber(parsed.amount) or 1) end
    local rows = {}
    for item, amount in pairs(totals) do table.insert(rows, amount .. "x " .. item) end
    table.sort(rows)
    return rows
end

local function scan()
    STATE.scans = STATE.scans + 1
    STATE.colonyName = colonyName()
    STATE.status = colonyStatus()
    STATE.workRows = workOrderRows()
    STATE.citizenRows = citizenRows()
    local stats = { total = 0, sent = 0, crafting = 0, skipped = 0, waiting = 0, missing = 0, bad = 0, pending = 0 }
    local rows, parsedList, nextPending, nextOrder = {}, {}, {}, {}
    local reqs, err = getRequests()
    if not reqs then
        stats.bad = 1
        addRow(rows, "[ERROR] " .. err, colors.red)
        append(CONFIG.errorFile, err)
        STATE.stats = stats
        STATE.rows = rows
        return
    end
    for _, req in pairs(reqs) do
        stats.total = stats.total + 1
        local parsed, parseErr = parseRequest(req)
        if not parsed then
            stats.bad = stats.bad + 1
            append(CONFIG.errorFile, "Bad request: " .. text(parseErr))
        else
            table.insert(parsedList, parsed)
            local reason = manualReason(req, parsed)
            local key = requestKey(parsed)
            local allowed, status = shouldProcess(key, parsed, nextPending, nextOrder, reason)
            if allowed then
                sendRequest(parsed, rows, stats)
            elseif status == "PENDING" then
                stats.pending = stats.pending + 1
                stats.waiting = stats.waiting + 1
                local why = nextPending[key] and nextPending[key].reason or "pending"
                addRow(rows, "[PENDING] " .. parsed.amount .. "x " .. trim(parsed.itemName, 39) .. " (" .. trim(why, 14) .. ")", colors.yellow)
            elseif status == "BLOCKED" then
                stats.skipped = stats.skipped + 1
                addRow(rows, "[BLOCKED] " .. parsed.amount .. "x " .. trim(parsed.itemName, 45), colors.red)
            else
                stats.waiting = stats.waiting + 1
                addRow(rows, "[DENIED] " .. parsed.amount .. "x " .. trim(parsed.itemName, 45), colors.orange)
            end
        end
    end
    STATE.pending = nextPending
    STATE.pendingOrder = nextOrder
    normalizeSelected()
    STATE.stats = stats
    STATE.rows = rows
    STATE.buildRows = buildRows(parsedList)
    if stats.total == 0 then action("No colony requests") end
end

local function header(countdown)
    local w = term.getSize()
    local lineColor = STATE.status.underAttack and (now() % 2 == 0 and colors.red or colors.gray) or colors.gray
    fillAt(1, 1, w, "=", lineColor)
    center(1, STATE.status.underAttack and " !!! COLONY UNDER ATTACK !!! " or " HackThePlanet Colony Supply ", STATE.status.underAttack and colors.red or colors.lime)
    center(2, "AE2 -> MineColonies Auto-Supply" .. (STATE.paused and " | PAUSED" or "") .. " | Next Scan: " .. countdown .. "s", STATE.paused and colors.orange or colors.cyan)
    fillAt(1, 3, w, "=", lineColor)
end

local function rowsAt(x, y, w, h, rows, empty)
    if #rows == 0 then
        writeAt(x, y, empty or "Nothing to show.", colors.gray)
        return
    end
    for i, row in ipairs(rows) do
        if i > h then break end
        writeAt(x, y + i - 1, trim(row.text or row, w), row.color or colors.white)
    end
end

local function dashboard(countdown)
    local w, h = term.getSize()
    clear()
    header(countdown)
    if w < 70 or h < 20 then
        writeAt(1, 4, "Colony: " .. STATE.colonyName, colors.yellow)
        writeAt(1, 5, "Mode: " .. STATE.mode .. (STATE.paused and " PAUSED" or ""), STATE.paused and colors.orange or colors.yellow)
        writeAt(1, 6, "Citizens: " .. text(STATE.status.citizens) .. " / " .. text(STATE.status.maxCitizens), colors.white)
        writeAt(1, 7, "Happiness: " .. fmtNum(STATE.status.happiness, 2), colors.white)
        rowsAt(1, 9, w, h - 12, STATE.rows, "No requests.")
        return
    end
    local left = math.floor(w * 0.52)
    local right = w - left - 1
    box(1, 5, left, 9, " Colony Status ", STATE.status.underAttack and colors.red or colors.gray)
    box(left + 2, 5, right, 9, " System Status ", STATE.status.underAttack and colors.red or colors.gray)
    writeAt(3, 6, "Colony:", colors.yellow); writeAt(12, 6, trim(STATE.colonyName, left - 13))
    writeAt(3, 7, "Status:", colors.yellow); writeAt(12, 7, STATE.status.underAttack and "UNDER ATTACK" or "Safe", STATE.status.underAttack and colors.red or colors.lime)
    writeAt(3, 8, "Citizens:", colors.yellow); writeAt(13, 8, text(STATE.status.citizens) .. " / " .. text(STATE.status.maxCitizens))
    writeAt(3, 9, "Happy:", colors.yellow); writeAt(11, 9, fmtNum(STATE.status.happiness, 2))
    writeAt(3, 10, "Builds:", colors.yellow); writeAt(11, 10, text(STATE.status.constructionSites))
    writeAt(3, 11, "Graves:", colors.yellow); writeAt(11, 11, text(STATE.status.graves), tonumber(STATE.status.graves) and tonumber(STATE.status.graves) > 0 and colors.red or colors.white)
    local rx = left + 4
    writeAt(rx, 6, "Mode:", colors.yellow); writeAt(rx + 7, 6, STATE.mode .. (STATE.paused and " PAUSED" or ""), STATE.paused and colors.orange or colors.lime)
    writeAt(rx, 7, "Output:", colors.yellow); writeAt(rx + 9, 7, "ME Bridge/" .. CONFIG.outputTarget)
    writeAt(rx, 8, "Uptime:", colors.yellow); writeAt(rx + 9, 8, fmtTime(now() - STATE.started))
    writeAt(rx, 9, "Scans:", colors.yellow); writeAt(rx + 9, 9, text(STATE.scans))
    writeAt(rx, 10, "Pending:", colors.yellow); writeAt(rx + 10, 10, text(#STATE.pendingOrder), #STATE.pendingOrder > 0 and colors.yellow or colors.gray)
    writeAt(rx, 11, "Last:", colors.yellow); writeAt(rx + 7, 11, trim(STATE.lastAction, right - 10))
    local reqY = 15
    local reqH = math.max(8, h - reqY - 6)
    box(1, reqY, w, reqH, " Current Requests ", colors.gray)
    rowsAt(3, reqY + 1, w - 4, reqH - 2, STATE.rows, "No open colony requests.")
    local foot = reqY + reqH + 1
    if foot + 4 <= h then
        box(1, foot, left, 5, " Scan Summary ", colors.gray)
        box(left + 2, foot, right, 5, " Recent Actions ", colors.gray)
        writeAt(3, foot + 1, "Requests: " .. STATE.stats.total .. "  Pending: " .. STATE.stats.pending)
        writeAt(3, foot + 2, "Sent: " .. STATE.stats.sent .. "  Craft: " .. STATE.stats.crafting, colors.green)
        writeAt(3, foot + 3, "Wait: " .. STATE.stats.waiting .. "  Manual: " .. STATE.stats.skipped, colors.gray)
        writeAt(3, foot + 4, "Missing: " .. STATE.stats.missing .. "  Bad: " .. STATE.stats.bad, colors.red)
        rowsAt(left + 4, foot + 1, right - 4, 3, STATE.actions, "")
    end
end

local function simplePage(countdown, title, rows, empty)
    local w, h = term.getSize()
    clear(); header(countdown); box(1, 5, w, h - 5, title, colors.gray)
    rowsAt(3, 7, w - 4, h - 8, rows, empty)
end

local function buildPage(countdown)
    local w, h = term.getSize()
    clear(); header(countdown)
    local half = math.floor((w - 3) / 2)
    box(1, 5, half, h - 5, " Build Material Totals ", colors.gray)
    box(half + 2, 5, w - half - 1, h - 5, " Work Orders / Sites ", colors.gray)
    if #STATE.buildRows == 0 then
        writeAt(3, 7, "No material requests found.", colors.lime)
        if #STATE.workRows > 0 or (tonumber(STATE.status.constructionSites) and tonumber(STATE.status.constructionSites) > 0) then
            writeAt(3, 9, "Work order found. Waiting for", colors.yellow)
            writeAt(3, 10, "MineColonies to ask for materials.", colors.yellow)
        end
    else
        rowsAt(3, 7, half - 4, h - 8, STATE.buildRows, "")
    end
    rowsAt(half + 4, 7, w - half - 5, h - 8, STATE.workRows, "Construction Sites: " .. text(STATE.status.constructionSites))
end

local function citizensPage(countdown)
    local rows = {}
    table.insert(rows, { text = "Citizens: " .. text(STATE.status.citizens) .. " / " .. text(STATE.status.maxCitizens) .. " | Colony Happiness: " .. fmtNum(STATE.status.happiness, 2), color = colors.yellow })
    table.insert(rows, { text = "Red flashing = danger | Orange = low | Blue = sleeping", color = colors.gray })
    table.insert(rows, { text = "", color = colors.white })
    if #STATE.citizenRows == 0 then
        table.insert(rows, { text = "No detailed citizen list exposed by this Colony Integrator.", color = colors.gray })
        table.insert(rows, { text = "Counts/happiness still work on the dashboard.", color = colors.gray })
    else
        for _, row in ipairs(STATE.citizenRows) do table.insert(rows, row) end
    end
    simplePage(countdown, " Citizens / Villagers ", rows, "No citizen data.")
end

local function pendingPage(countdown)
    local rows = {}
    for i, key in ipairs(STATE.pendingOrder) do
        local pending = STATE.pending[key]
        if pending then
            table.insert(rows, { text = (i == STATE.selected and "> " or "  ") .. i .. "/" .. #STATE.pendingOrder .. " " .. pending.parsed.amount .. "x " .. pending.parsed.itemName .. " (" .. pending.reason .. ")", color = i == STATE.selected and colors.yellow or colors.white })
        end
    end
    simplePage(countdown, " Pending Approval ", rows, "No pending approvals.")
end

local function settingsPage(countdown)
    local wc, bc = 0, 0
    for _ in pairs(WHITELIST) do wc = wc + 1 end
    for _ in pairs(BLOCKED) do bc = bc + 1 end
    simplePage(countdown, " Settings / Rules ", {
        { text = "Mode: " .. STATE.mode, color = colors.yellow },
        { text = "Paused: " .. text(STATE.paused), color = STATE.paused and colors.orange or colors.white },
        { text = "Output Target: " .. CONFIG.outputTarget, color = colors.white },
        { text = "Whitelist Items: " .. wc, color = colors.lime },
        { text = "Blocked Items: " .. bc, color = colors.red },
        { text = "", color = colors.white },
        { text = "AUTO      = safe requests send unless blocked", color = colors.white },
        { text = "APPROVAL  = requests wait for approval", color = colors.white },
        { text = "WHITELIST = only ALWAYS-approved items send", color = colors.white }
    }, "No settings.")
end

local function historyPage(countdown)
    simplePage(countdown, " History ", readLines(CONFIG.historyFile, CONFIG.maxHistoryLines), "No history yet.")
end

local function drawMain(countdown)
    withScreen(MAIN, function()
        if STATE.page == "REQUESTS" then simplePage(countdown, " Request Details ", STATE.rows, "No requests.")
        elseif STATE.page == "BUILD" then buildPage(countdown)
        elseif STATE.page == "CITIZENS" then citizensPage(countdown)
        elseif STATE.page == "PENDING" then pendingPage(countdown)
        elseif STATE.page == "HISTORY" then historyPage(countdown)
        elseif STATE.page == "SETTINGS" then settingsPage(countdown)
        else dashboard(countdown) end
    end)
end

local function drawControl(countdown)
    if not CONTROL then return end
    withScreen(CONTROL, function()
        clear()
        local w, h = term.getSize()
        center(1, "HTP CONTROL PANEL", colors.lime)
        center(2, "Next Scan: " .. countdown .. "s", colors.cyan)
        fillAt(1, 3, w, "=", STATE.status.underAttack and colors.red or colors.gray)
        local colW = math.max(6, math.floor((w - 4) / 3))
        local function cb(col, row, label, fn, active, color)
            button(CONTROL.name, 2 + ((col - 1) * (colW + 1)), row, colW, 2, label, fn, active and colors.lime or (color or colors.gray))
        end
        cb(1, 4, "AUTO", function() setMode("AUTO") end, STATE.mode == "AUTO")
        cb(2, 4, "APPROVAL", function() setMode("APPROVAL") end, STATE.mode == "APPROVAL")
        cb(3, 4, "WHITE", function() setMode("WHITELIST") end, STATE.mode == "WHITELIST")
        cb(1, 7, "DASH", function() setPage("DASHBOARD") end, STATE.page == "DASHBOARD")
        cb(2, 7, "REQ", function() setPage("REQUESTS") end, STATE.page == "REQUESTS")
        cb(3, 7, "BUILD", function() setPage("BUILD") end, STATE.page == "BUILD")
        cb(1, 10, "CITIZENS", function() setPage("CITIZENS") end, STATE.page == "CITIZENS")
        cb(2, 10, "PENDING", function() setPage("PENDING") end, STATE.page == "PENDING")
        cb(3, 10, "HISTORY", function() setPage("HISTORY") end, STATE.page == "HISTORY")
        cb(1, 13, "SETTINGS", function() setPage("SETTINGS") end, STATE.page == "SETTINGS")
        cb(2, 13, STATE.paused and "RESUME" or "PAUSE", function() setPaused(not STATE.paused) end, STATE.paused)
        cb(3, 13, "SCAN", function() STATE.scanNow = true; action("Manual scan queued") end, false)
        local y = 16
        local key, pending = selectedPending()
        if pending then
            writeAt(2, y, "Pending " .. STATE.selected .. "/" .. #STATE.pendingOrder .. ": " .. trim(pending.parsed.amount .. "x " .. pending.parsed.itemName, w - 18), colors.yellow)
            writeAt(2, y + 1, "Reason: " .. trim(pending.reason, w - 10), colors.gray)
            local half = math.max(8, math.floor((w - 5) / 2))
            button(CONTROL.name, 2, y + 3, half, 2, "PREV", function() STATE.selected = STATE.selected - 1; normalizeSelected(); saveState() end, colors.gray)
            button(CONTROL.name, 3 + half, y + 3, half, 2, "NEXT", function() STATE.selected = STATE.selected + 1; normalizeSelected(); saveState() end, colors.gray)
            button(CONTROL.name, 2, y + 6, half, 2, "APPROVE", function() approveSelected(false) end, colors.lime)
            button(CONTROL.name, 3 + half, y + 6, half, 2, "ALWAYS", function() approveSelected(true) end, colors.green)
            button(CONTROL.name, 2, y + 9, half, 2, "DENY", function() denySelected(false) end, colors.orange)
            button(CONTROL.name, 3 + half, y + 9, half, 2, "BLOCK", function() denySelected(true) end, colors.red)
        else
            center(y + 2, "No pending approvals", colors.gray)
        end
        if h >= 30 then button(CONTROL.name, 2, h - 3, math.max(10, w - 4), 2, "CLEAR HISTORY", function() clearHistory() end, colors.gray) end
        center(h - 1, STATE.status.underAttack and "!!! COLONY UNDER ATTACK !!!" or "AE2 LINKED | COLONY LINKED", STATE.status.underAttack and colors.red or colors.gray)
    end)
end

local function render(countdown)
    BUTTONS = {}
    local okRender, err = pcall(function() drawMain(countdown); drawControl(countdown) end)
    if not okRender then
        term.redirect(nativeTerm)
        clear()
        print("Render error:")
        print(err)
        append(CONFIG.errorFile, "Render error: " .. text(err))
    end
end

local function handleTouch(screenName, x, y)
    for _, b in ipairs(BUTTONS) do
        if b.screen == screenName and x >= b.x1 and x <= b.x2 and y >= b.y1 and y <= b.y2 then
            local okTouch, err = pcall(b.action)
            if not okTouch then append(CONFIG.errorFile, "Button error: " .. text(err)) end
            return true
        end
    end
    return false
end

detectMonitors()
bootSplash()
term.redirect(nativeTerm)
clear()
print("HTP Colony Supply running.")
print("Main: " .. text(MAIN.name) .. " " .. text(MAIN.w) .. "x" .. text(MAIN.h))
print("Control: " .. text(CONTROL and CONTROL.name or "none"))
action("Program started")
local okScan, scanErr = pcall(scan)
if not okScan then append(CONFIG.errorFile, "Initial scan error: " .. text(scanErr)); action("Initial scan error") end
local nextScan = now() + CONFIG.scanSeconds
render(CONFIG.scanSeconds)
while true do
    local countdown = math.max(0, nextScan - now())
    render(countdown)
    local timer = os.startTimer(1)
    local event = { os.pullEvent() }
    if event[1] == "monitor_touch" then handleTouch(event[2], event[3], event[4]); render(math.max(0, nextScan - now())) end
    if STATE.scanNow or now() >= nextScan then
        STATE.scanNow = false
        local scanOk, err = pcall(scan)
        if not scanOk then append(CONFIG.errorFile, "Scan error: " .. text(err)); action("Scan error") end
        nextScan = now() + CONFIG.scanSeconds
    end
end
