-- HackThePlanet Colony Supply v3.0.3 button layout patch

local VERSION = "3.0.3"
local UI_PART = "/htp3/ui_parts/04.lua.part"
local CONFIG_FILE = "/htp3/config.lua"
local DATA_CONFIG = "/htp3/data/config.tbl"

local function fail(message)
    term.setTextColor(colors.red)
    print("HTP v" .. VERSION .. " button patch failed:")
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

local function patchOrConfirm(source, oldText, newText, label)
    local updated, count = replaceAllPlain(source, oldText, newText)
    if count > 0 then return updated, count end
    if source:find(newText, 1, true) then return source, 0 end
    fail("Patch point missing: " .. label)
end

local function backupOnce(path, suffix)
    local backup = path .. suffix
    if not fs.exists(backup) and fs.exists(path) then fs.copy(path, backup) end
end

term.setBackgroundColor(colors.black)
term.setTextColor(colors.white)
term.clear()
term.setCursorPos(1, 1)
print("HackThePlanet Colony Supply")
print("Applying larger button layout v" .. VERSION .. "...")
print("")

local ui = readAll(UI_PART)
if not ui then fail("Missing " .. UI_PART) end
backupOnce(UI_PART, ".v302.bak")

local replacements = {
    {
        old = "buttonHeight = buttonHeight or 2",
        new = "buttonHeight = buttonHeight or 3",
        label = "default action button height"
    },
    {
        old = "actionGrid(pageButtons, contentY + 2, 4, 2)",
        new = "actionGrid(pageButtons, contentY + 3, 4, 3)",
        label = "four-column page buttons"
    },
    {
        old = "actionGrid(pageButtons, contentY + 2, 3, 2)",
        new = "actionGrid(pageButtons, contentY + 3, 3, 3)",
        label = "three-column page buttons"
    },
    {
        old = "actionGrid(pageButtons, contentY + 2, 5, 2)",
        new = "actionGrid(pageButtons, contentY + 3, 5, 3)",
        label = "five-column page buttons"
    },
    {
        old = "actionGrid(quickButtons, quickY, 5, 2)",
        new = "actionGrid(quickButtons, quickY, 5, 3)",
        label = "quick action buttons"
    }
}

local changed = 0
for _, replacement in ipairs(replacements) do
    local count
    ui, count = patchOrConfirm(ui, replacement.old, replacement.new, replacement.label)
    changed = changed + count
end

-- Verify the complete assembled UI before replacing the live file.
local bundle = {}
for index = 1, 4 do
    local path = "/htp3/ui_parts/0" .. index .. ".lua.part"
    local part = index == 4 and ui or readAll(path)
    if not part then fail("Missing UI bundle part " .. path) end
    bundle[#bundle + 1] = part
end
local compiled, compileError = load(table.concat(bundle, "\n"), "@htp3/ui.bundle")
if not compiled then fail("Patched UI syntax error: " .. tostring(compileError)) end

local okUi, uiError = writeAll(UI_PART, ui)
if not okUi then fail(uiError) end
print("Control buttons enlarged and spaced away from labels.")

local config = readAll(CONFIG_FILE)
if config then
    backupOnce(CONFIG_FILE, ".v302.bak")
    local versionFound = false
    for _, oldVersion in ipairs({ "3.0.0", "3.0.1", "3.0.2" }) do
        local updated, count = replaceAllPlain(config, 'version = "' .. oldVersion .. '"', 'version = "' .. VERSION .. '"')
        if count > 0 then config = updated; versionFound = true; break end
    end
    if not versionFound and not config:find('version = "' .. VERSION .. '"', 1, true) then
        fail("Configuration version marker missing")
    end

    local mergeLine = "            for key, value in pairs(merged) do C[key] = value end"
    local forcedLine = mergeLine .. "\n            C.version = \"" .. VERSION .. "\""
    if not config:find(forcedLine, 1, true) then
        local updated, count = replaceAllPlain(config, mergeLine, forcedLine)
        if count == 0 then fail("Configuration merge patch point missing") end
        config = updated
    end

    local configCompiled, configError = load(config, "@htp3/config.lua")
    if not configCompiled then fail("Patched config syntax error: " .. tostring(configError)) end
    local okConfig, configWriteError = writeAll(CONFIG_FILE, config)
    if not okConfig then fail(configWriteError) end
end

if fs.exists(DATA_CONFIG) then
    local data = readAll(DATA_CONFIG)
    local ok, stored = pcall(textutils.unserialize, data or "")
    if ok and type(stored) == "table" then
        stored.version = VERSION
        local okData, dataError = writeAll(DATA_CONFIG, textutils.serialize(stored, { compact = true }))
        if not okData then fail(dataError) end
    end
end

term.setTextColor(colors.lime)
print("")
print("HTP Colony Supply v" .. VERSION .. " button patch complete.")
term.setTextColor(colors.white)
print("Reboot the computer to load the new layout.")
