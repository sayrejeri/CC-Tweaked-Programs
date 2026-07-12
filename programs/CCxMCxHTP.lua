-- startup
-- HackThePlanet Colony Supply v3.0.2 installer

local VERSION = "3.0.2"
local MODULE_REF = "1024504ffbd148fcd938548e61384d782ffa0318"
local BASE_URL = "https://raw.githubusercontent.com/sayrejeri/CC-Tweaked-Programs/" .. MODULE_REF .. "/"
local STAGE = "/htp3.install"
local ROOT = "/htp3"

local FILES = {
    { source = "programs/htp3/util.lua", destination = "/htp3/util.lua", syntax = true },
    { source = "programs/htp3/config.lua", destination = "/htp3/config.lua", syntax = true },
    { source = "programs/htp3/state.lua", destination = "/htp3/state.lua", syntax = true },
    { source = "programs/htp3/integrations.lua", destination = "/htp3/integrations.lua", syntax = true },
    { source = "programs/htp3/backup.lua", destination = "/htp3/backup.lua", syntax = true },
    { source = "programs/htp3/engine.lua", destination = "/htp3/engine.lua", syntax = true },
    { source = "programs/htp3/engine_parts/01.lua.part", destination = "/htp3/engine_parts/01.lua.part" },
    { source = "programs/htp3/engine_parts/02.lua.part", destination = "/htp3/engine_parts/02.lua.part" },
    { source = "programs/htp3/engine_parts/03.lua.part", destination = "/htp3/engine_parts/03.lua.part" },
    { source = "programs/htp3/engine_parts/04.lua.part", destination = "/htp3/engine_parts/04.lua.part" },
    { source = "programs/htp3/ui.lua", destination = "/htp3/ui.lua", syntax = true },
    { source = "programs/htp3/ui_parts/01.lua.part", destination = "/htp3/ui_parts/01.lua.part" },
    { source = "programs/htp3/ui_parts/02.lua.part", destination = "/htp3/ui_parts/02.lua.part" },
    { source = "programs/htp3/ui_parts/03.lua.part", destination = "/htp3/ui_parts/03.lua.part" },
    { source = "programs/htp3/ui_parts/04.lua.part", destination = "/htp3/ui_parts/04.lua.part" },
    { source = "programs/htp3/main.lua", destination = "/htp3/main.lua", syntax = true }
}

local function setColor(color)
    if term.isColor and term.isColor() then term.setTextColor(color) end
end

local function fail(message)
    setColor(colors.red)
    print("")
    print("HTP v" .. VERSION .. " install failed:")
    print(tostring(message))
    setColor(colors.white)
    print("")
    print("The existing v3 program and data were not replaced.")
    print("Run startup again after correcting the error.")
    error(message, 0)
end

local function ensureDir(path)
    if not path or path == "" or fs.exists(path) then return end
    local parent = fs.getDir(path)
    if parent ~= "" and not fs.exists(parent) then ensureDir(parent) end
    fs.makeDir(path)
end

local function readAll(path)
    if not path or not fs.exists(path) or fs.isDir(path) then return nil end
    local handle = fs.open(path, "rb") or fs.open(path, "r")
    if not handle then return nil end
    local data = handle.readAll()
    handle.close()
    return data
end

local function writeAll(path, data)
    local parent = fs.getDir(path)
    if parent ~= "" then ensureDir(parent) end
    local temporary = path .. ".tmp"
    if fs.exists(temporary) then fs.delete(temporary) end
    local handle = fs.open(temporary, "wb") or fs.open(temporary, "w")
    if not handle then return false, "could not open " .. temporary end
    local ok, err = pcall(function() handle.write(data or "") end)
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
    local response, err = http.get(url, nil, true)
    if not response then return nil, err or "HTTP request failed" end
    local body = response.readAll()
    response.close()
    if not body or body == "" then return nil, "empty response" end
    return body
end

local function stagedPath(destination)
    local cleaned = destination:gsub("^/", "")
    return fs.combine(STAGE, cleaned)
end

local function verifyBundle(folder, names, label)
    local pieces = {}
    for _, name in ipairs(names) do
        local path = fs.combine(folder, name)
        local data = readAll(path)
        if not data then fail("Missing staged " .. label .. " part: " .. name) end
        pieces[#pieces + 1] = data
    end
    local compiled, err = load(table.concat(pieces, "\n"), "@" .. label .. ".bundle")
    if not compiled then fail(label .. " bundle syntax error: " .. tostring(err)) end
end

local function cleanupStage()
    if fs.exists(STAGE) then fs.delete(STAGE) end
end

term.setBackgroundColor(colors.black)
setColor(colors.white)
term.clear()
term.setCursorPos(1, 1)
print("HackThePlanet Colony Supply")
print("Installing Responsive Command Center v" .. VERSION)
print("")

cleanupStage()
ensureDir(STAGE)

for index, entry in ipairs(FILES) do
    write("[" .. index .. "/" .. #FILES .. "] " .. fs.getName(entry.destination) .. "... ")
    local body, err = download(BASE_URL .. entry.source)
    if not body then
        print("FAILED")
        cleanupStage()
        fail(entry.source .. ": " .. tostring(err))
    end

    if entry.syntax then
        local compiled, syntaxError = load(body, "@" .. entry.destination)
        if not compiled then
            print("FAILED")
            cleanupStage()
            fail(entry.source .. " syntax error: " .. tostring(syntaxError))
        end
    end

    local ok, writeError = writeAll(stagedPath(entry.destination), body)
    if not ok then
        print("FAILED")
        cleanupStage()
        fail(entry.destination .. ": " .. tostring(writeError))
    end

    setColor(colors.lime)
    print("OK")
    setColor(colors.white)
end

local stagedConfig = readAll(stagedPath("/htp3/config.lua")) or ""
if not stagedConfig:find('version = "3.0.2"', 1, true) then
    cleanupStage()
    fail("Downloaded configuration does not identify v3.0.2")
end

print("Checking complete automation engine...")
verifyBundle(fs.combine(STAGE, "htp3/engine_parts"), {
    "01.lua.part", "02.lua.part", "03.lua.part", "04.lua.part"
}, "engine")

print("Checking responsive monitor interface...")
verifyBundle(fs.combine(STAGE, "htp3/ui_parts"), {
    "01.lua.part", "02.lua.part", "03.lua.part", "04.lua.part"
}, "ui")

print("Installing modules while preserving data and logs...")
ensureDir(ROOT)
ensureDir(fs.combine(ROOT, "data"))
ensureDir(fs.combine(ROOT, "logs"))

if fs.exists(fs.combine(ROOT, "engine_parts")) then fs.delete(fs.combine(ROOT, "engine_parts")) end
if fs.exists(fs.combine(ROOT, "ui_parts")) then fs.delete(fs.combine(ROOT, "ui_parts")) end

for _, entry in ipairs(FILES) do
    local source = stagedPath(entry.destination)
    local destination = entry.destination
    local parent = fs.getDir(destination)
    if parent ~= "" then ensureDir(parent) end
    if fs.exists(destination) then fs.delete(destination) end
    fs.move(source, destination)
end

cleanupStage()
writeAll(fs.combine(ROOT, "installed_version.txt"), VERSION .. "\nmodule_ref=" .. MODULE_REF .. "\n")

local startupLoader = [[
-- HackThePlanet Colony Supply v3 loader
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
    print("")
    print("Run startup again after correcting the error.")
end
]]

local loaderCompiled, loaderError = load(startupLoader, "@startup")
if not loaderCompiled then fail("Startup loader syntax error: " .. tostring(loaderError)) end

local loaderOk, loaderWriteError = writeAll("startup.v3-new", startupLoader)
if not loaderOk then fail(loaderWriteError) end
if fs.exists("startup.pre-v302") then fs.delete("startup.pre-v302") end
if fs.exists("startup") then fs.move("startup", "startup.pre-v302") end
fs.move("startup.v3-new", "startup")

setColor(colors.lime)
print("")
print("HTP Colony Supply v" .. VERSION .. " installed successfully.")
print("Large control monitors now use the full responsive command center.")
setColor(colors.white)
print("Rebooting...")
sleep(2)
os.reboot()
