-- HackThePlanet Colony Supply v3.0.6 recovery

local VERSION = "3.0.6"
local BACKUP_COMMIT = "b77d47ac0feb58104d37808bdaab4cf48e8d054b"
local BACKUP_URL = "https://raw.githubusercontent.com/sayrejeri/CC-Tweaked-Programs/" .. BACKUP_COMMIT .. "/programs/htp3/backup.lua"
local UI_CORE = "/htp3/ui_parts/01.lua.part"
local UI_LAYOUT = "/htp3/ui_parts/04.lua.part"
local CONFIG_FILE = "/htp3/config.lua"
local DATA_CONFIG = "/htp3/data/config.tbl"

local function fail(message)
    term.setTextColor(colors.red)
    print("")
    print("HTP v" .. VERSION .. " recovery failed:")
    print(tostring(message))
    term.setTextColor(colors.white)
    error(message, 0)
end

local function readAll(path)
    if not fs.exists(path) or fs.isDir(path) then return nil end
    local handle = fs.open(path, "r")
    if not handle then return nil end
    local data = handle.readAll()
    handle.close()
    return data
end

local function writeAll(path, data)
    local parent = fs.getDir(path)
    if parent ~= "" and not fs.exists(parent) then fs.makeDir(parent) end
    local temporary = path .. ".tmp"
    if fs.exists(temporary) then fs.delete(temporary) end
    local handle = fs.open(temporary, "w")
    if not handle then return false, "could not open " .. temporary end
    local ok, err = pcall(function() handle.write(data) end)
    handle.close()
    if not ok then
        if fs.exists(temporary) then fs.delete(temporary) end
        return false, err
    end
    if fs.exists(path) then fs.delete(path) end
    fs.move(temporary, path)
    return true
end

local function download(url)
    local cache = os.epoch and os.epoch("utc") or math.floor(os.clock() * 1000)
    local response, err = http.get(url .. "?cache=" .. tostring(cache), nil, true)
    if not response then return nil, err or "HTTP request failed" end
    local body = response.readAll()
    response.close()
    if not body or body == "" then return nil, "empty response" end
    return body
end

local function replacePlain(source, oldText, newText)
    local first, last = source:find(oldText, 1, true)
    if not first then return source, false end
    return source:sub(1, first - 1) .. newText .. source:sub(last + 1), true
end

local function replaceAll(source, oldText, newText)
    local output, position = {}, 1
    while true do
        local first, last = source:find(oldText, position, true)
        if not first then
            output[#output + 1] = source:sub(position)
            break
        end
        output[#output + 1] = source:sub(position, first - 1)
        output[#output + 1] = newText
        position = last + 1
    end
    return table.concat(output)
end

local function backupOnce(path, suffix)
    local destination = path .. suffix
    if fs.exists(path) and not fs.exists(destination) then fs.copy(path, destination) end
end

term.setBackgroundColor(colors.black)
term.setTextColor(colors.white)
term.clear()
term.setCursorPos(1, 1)
print("HackThePlanet Colony Supply")
print("Recovering v" .. VERSION .. "...")
print("")

if not fs.exists("/htp3/main.lua") then fail("/htp3/main.lua is missing") end

print("[1/5] Replacing broken backup module...")
local backupBody, backupError = download(BACKUP_URL)
if not backupBody then fail(backupError) end
local backupCompiled, backupSyntax = load(backupBody, "@htp3/backup.lua")
if not backupCompiled then fail("clean backup module syntax error: " .. tostring(backupSyntax)) end
backupOnce("/htp3/backup.lua", ".broken-v305")
local backupOk, backupWriteError = writeAll("/htp3/backup.lua", backupBody)
if not backupOk then fail(backupWriteError) end
print("      Backup module restored.")

print("[2/5] Verifying button rendering...")
local core = readAll(UI_CORE)
if not core then fail("Missing " .. UI_CORE) end
local oldFill = [[    local function fillAt(x, y, width, character, foreground, background)
        writeAt(x, y, string.rep(character or " ", math.max(0, width)), foreground, background)
    end]]
local newFill = [[    local function fillAt(x, y, width, character, foreground, background)
        local screenWidth, screenHeight = dimensions()
        if y < 1 or y > screenHeight or x > screenWidth then return end
        x = math.max(1, math.floor(x))
        local available = math.max(0, math.min(math.floor(width or 0), screenWidth - x + 1))
        if available <= 0 then return end
        term.setCursorPos(x, y)
        term.setTextColor(foreground or colors.white)
        term.setBackgroundColor(background or colors.black)
        term.write(string.rep(character or " ", available))
        term.setBackgroundColor(colors.black)
    end]]
core = select(1, replacePlain(core, oldFill, newFill))
backupOnce(UI_CORE, ".pre-v306")
local coreOk, coreWriteError = writeAll(UI_CORE, core)
if not coreOk then fail(coreWriteError) end

print("[3/5] Centering navigation and sizing buttons...")
local layout = readAll(UI_LAYOUT)
if not layout then fail("Missing " .. UI_LAYOUT) end
layout = replaceAll(layout, "buttonHeight = buttonHeight or 2", "buttonHeight = buttonHeight or 3")
layout = replaceAll(layout, "actionGrid(pageButtons, contentY + 2, 4, 2)", "actionGrid(pageButtons, contentY + 3, 4, 3)")
layout = replaceAll(layout, "actionGrid(pageButtons, contentY + 2, 3, 2)", "actionGrid(pageButtons, contentY + 3, 3, 3)")
layout = replaceAll(layout, "actionGrid(pageButtons, contentY + 2, 5, 2)", "actionGrid(pageButtons, contentY + 3, 5, 3)")
layout = replaceAll(layout, "actionGrid(quickButtons, quickY, 5, 2)", "actionGrid(quickButtons, quickY, 5, 3)")

local oldNav = [[            local navColumns = 5
            local navGap = 1
            local navButtonHeight = height >= 38 and 3 or 2
            local navButtonWidth = math.floor((width - 2 - ((navColumns - 1) * navGap)) / navColumns)
            local navY = cardY + cardHeight + 1]]
local newNav = [[            local navColumns = 5
            local navGap = 1
            local navButtonHeight = height >= 38 and 3 or 2
            local navSidePadding = math.max(3, math.floor(width * 0.03))
            local navAvailableWidth = width - (navSidePadding * 2)
            local navButtonWidth = math.floor((navAvailableWidth - ((navColumns - 1) * navGap)) / navColumns)
            local navTotalWidth = (navButtonWidth * navColumns) + ((navColumns - 1) * navGap)
            local navStartX = math.floor((width - navTotalWidth) / 2) + 1
            local navY = cardY + cardHeight + 1]]
layout = select(1, replacePlain(layout, oldNav, newNav))
layout = replaceAll(layout, "                local x = 1 + column * (navButtonWidth + navGap)", "                local x = navStartX + column * (navButtonWidth + navGap)")
backupOnce(UI_LAYOUT, ".pre-v306")
local layoutOk, layoutWriteError = writeAll(UI_LAYOUT, layout)
if not layoutOk then fail(layoutWriteError) end

local uiSource = {}
for index = 1, 4 do
    local part = readAll("/htp3/ui_parts/0" .. index .. ".lua.part")
    if not part then fail("Missing UI part " .. index) end
    uiSource[#uiSource + 1] = part
end
local uiCompiled, uiSyntax = load(table.concat(uiSource, "\n"), "@htp3/ui.bundle")
if not uiCompiled then fail("UI bundle syntax error: " .. tostring(uiSyntax)) end
print("      UI bundle verified.")

print("[4/5] Updating version data...")
local config = readAll(CONFIG_FILE)
if config then
    for _, oldVersion in ipairs({ "3.0.0", "3.0.1", "3.0.2", "3.0.3", "3.0.4", "3.0.5" }) do
        config = replaceAll(config, 'version = "' .. oldVersion .. '"', 'version = "' .. VERSION .. '"')
        config = replaceAll(config, 'C.version = "' .. oldVersion .. '"', 'C.version = "' .. VERSION .. '"')
    end
    local configCompiled, configSyntax = load(config, "@htp3/config.lua")
    if not configCompiled then fail("config syntax error: " .. tostring(configSyntax)) end
    local configOk, configWriteError = writeAll(CONFIG_FILE, config)
    if not configOk then fail(configWriteError) end
end
if fs.exists(DATA_CONFIG) then
    local okStored, stored = pcall(textutils.unserialize, readAll(DATA_CONFIG) or "")
    if okStored and type(stored) == "table" then
        stored.version = VERSION
        local storedOk, storedError = writeAll(DATA_CONFIG, textutils.serialize(stored, { compact = true }))
        if not storedOk then fail(storedError) end
    end
end
writeAll("/htp3/installed_version.txt", VERSION .. "\nbackup_commit=" .. BACKUP_COMMIT .. "\n")

print("[5/5] Restoring permanent startup loader...")
local loader = [[-- HackThePlanet Colony Supply loader
local ok, err = pcall(dofile, "/htp3/main.lua")
if not ok then
    term.redirect(term.native())
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.red)
    term.clear()
    term.setCursorPos(1, 1)
    print("HTP Colony Supply failed to start:")
    print(tostring(err))
    term.setTextColor(colors.white)
end
]]
local loaderCompiled, loaderSyntax = load(loader, "@startup")
if not loaderCompiled then fail(loaderSyntax) end
backupOnce("startup", ".broken-v305")
local loaderOk, loaderWriteError = writeAll("startup", loader)
if not loaderOk then fail(loaderWriteError) end

for _, path in ipairs({ "fix305", "fixbuttons", "fixbuttons304", "startup.update", "startup.new" }) do
    if fs.exists(path) then pcall(function() fs.delete(path) end) end
end

term.setTextColor(colors.lime)
print("")
print("HTP Colony Supply v" .. VERSION .. " recovered successfully.")
term.setTextColor(colors.white)
print("Rebooting into the normal program...")
sleep(2)
os.reboot()
