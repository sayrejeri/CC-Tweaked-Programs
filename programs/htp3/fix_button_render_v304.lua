-- HackThePlanet Colony Supply v3.0.4 button rendering fix

local VERSION = "3.0.4"
local UI_CORE = "/htp3/ui_parts/01.lua.part"
local UI_LAYOUT = "/htp3/ui_parts/04.lua.part"
local CONFIG_FILE = "/htp3/config.lua"
local DATA_CONFIG = "/htp3/data/config.tbl"

local function fail(message)
    term.setTextColor(colors.red)
    print("HTP v" .. VERSION .. " button fix failed:")
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

local function replacePlain(source, oldText, newText)
    local first, last = source:find(oldText, 1, true)
    if not first then return source, false end
    return source:sub(1, first - 1) .. newText .. source:sub(last + 1), true
end

local function replaceAllPlain(source, oldText, newText)
    local output = {}
    local position = 1
    local count = 0
    while true do
        local first, last = source:find(oldText, position, true)
        if not first then
            output[#output + 1] = source:sub(position)
            break
        end
        output[#output + 1] = source:sub(position, first - 1)
        output[#output + 1] = newText
        position = last + 1
        count = count + 1
    end
    return table.concat(output), count
end

local function backupOnce(path, suffix)
    local backup = path .. suffix
    if fs.exists(path) and not fs.exists(backup) then fs.copy(path, backup) end
end

term.setBackgroundColor(colors.black)
term.setTextColor(colors.white)
term.clear()
term.setCursorPos(1, 1)
print("HackThePlanet Colony Supply")
print("Fixing button rendering v" .. VERSION .. "...")
print("")

local uiCore = readAll(UI_CORE)
if not uiCore then fail("Missing " .. UI_CORE) end
backupOnce(UI_CORE, ".v303.bak")

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

local changed
uiCore, changed = replacePlain(uiCore, oldFill, newFill)
if not changed and not uiCore:find("local screenWidth, screenHeight = dimensions()", 1, true) then
    fail("Button background render patch point missing")
end

local okCore, coreError = writeAll(UI_CORE, uiCore)
if not okCore then fail(coreError) end
print("Button backgrounds now preserve spaces instead of trimming them.")

local uiLayout = readAll(UI_LAYOUT)
if not uiLayout then fail("Missing " .. UI_LAYOUT) end
backupOnce(UI_LAYOUT, ".v303.bak")

-- Keep the taller v3.0.3 layout even if this patch is run directly on v3.0.2.
local layoutPatches = {
    { "buttonHeight = buttonHeight or 2", "buttonHeight = buttonHeight or 3" },
    { "actionGrid(pageButtons, contentY + 2, 4, 2)", "actionGrid(pageButtons, contentY + 3, 4, 3)" },
    { "actionGrid(pageButtons, contentY + 2, 3, 2)", "actionGrid(pageButtons, contentY + 3, 3, 3)" },
    { "actionGrid(pageButtons, contentY + 2, 5, 2)", "actionGrid(pageButtons, contentY + 3, 5, 3)" },
    { "actionGrid(quickButtons, quickY, 5, 2)", "actionGrid(quickButtons, quickY, 5, 3)" }
}
for _, patch in ipairs(layoutPatches) do
    uiLayout = select(1, replaceAllPlain(uiLayout, patch[1], patch[2]))
end
local okLayout, layoutError = writeAll(UI_LAYOUT, uiLayout)
if not okLayout then fail(layoutError) end

local bundle = {}
for index = 1, 4 do
    local path = "/htp3/ui_parts/0" .. index .. ".lua.part"
    local part = readAll(path)
    if not part then fail("Missing UI bundle part " .. path) end
    bundle[#bundle + 1] = part
end
local compiled, compileError = load(table.concat(bundle, "\n"), "@htp3/ui.bundle")
if not compiled then fail("Patched UI syntax error: " .. tostring(compileError)) end
print("Complete UI bundle passed syntax verification.")

local config = readAll(CONFIG_FILE)
if config then
    backupOnce(CONFIG_FILE, ".v303.bak")
    for _, oldVersion in ipairs({ "3.0.0", "3.0.1", "3.0.2", "3.0.3" }) do
        config = select(1, replaceAllPlain(config, 'version = "' .. oldVersion .. '"', 'version = "' .. VERSION .. '"'))
        config = select(1, replaceAllPlain(config, 'C.version = "' .. oldVersion .. '"', 'C.version = "' .. VERSION .. '"'))
    end
    local configCompiled, configError = load(config, "@htp3/config.lua")
    if not configCompiled then fail("Patched config syntax error: " .. tostring(configError)) end
    local okConfig, configWriteError = writeAll(CONFIG_FILE, config)
    if not okConfig then fail(configWriteError) end
end

if fs.exists(DATA_CONFIG) then
    local storedText = readAll(DATA_CONFIG)
    local ok, stored = pcall(textutils.unserialize, storedText or "")
    if ok and type(stored) == "table" then
        stored.version = VERSION
        local okData, dataError = writeAll(DATA_CONFIG, textutils.serialize(stored, { compact = true }))
        if not okData then fail(dataError) end
    end
end

term.setTextColor(colors.lime)
print("")
print("HTP Colony Supply v" .. VERSION .. " button rendering fixed.")
term.setTextColor(colors.white)
print("Reboot the computer to reload the UI.")
