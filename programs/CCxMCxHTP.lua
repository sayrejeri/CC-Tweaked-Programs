-- startup
-- HackThePlanet Colony Supply v3 installer

local VERSION = "3.0.0"
local MODULE_REF = "ac0f196c71baccb1d60ce1ecf8e1f28ad9423af9"
local BASE_URL = "https://raw.githubusercontent.com/sayrejeri/CC-Tweaked-Programs/" .. MODULE_REF .. "/"
local STAGE = "/htp3.install"
local ROOT = "/htp3"

local FILES = {
    { source = "programs/htp3/util.lua", destination = "/htp3/util.lua", size = 12533, checksum = 1702331388, syntax = true },
    { source = "programs/htp3/config.lua", destination = "/htp3/config.lua", size = 7514, checksum = 3425244947, syntax = true },
    { source = "programs/htp3/state.lua", destination = "/htp3/state.lua", size = 11816, checksum = 691473520, syntax = true },
    { source = "programs/htp3/integrations.lua", destination = "/htp3/integrations.lua", size = 23214, checksum = 2798095192, syntax = true },
    { source = "programs/htp3/backup.lua", destination = "/htp3/backup.lua", size = 11551, checksum = 427700641, syntax = true },
    { source = "programs/htp3/engine.lua", destination = "/htp3/engine.lua", size = 553, checksum = 3468406505, syntax = true },
    { source = "programs/htp3/engine_parts/01.lua.part", destination = "/htp3/engine_parts/01.lua.part", size = 11189, checksum = 719022897 },
    { source = "programs/htp3/engine_parts/02.lua.part", destination = "/htp3/engine_parts/02.lua.part", size = 10350, checksum = 2593817041 },
    { source = "programs/htp3/engine_parts/03.lua.part", destination = "/htp3/engine_parts/03.lua.part", size = 11272, checksum = 1658635265 },
    { source = "programs/htp3/engine_parts/04.lua.part", destination = "/htp3/engine_parts/04.lua.part", size = 8751, checksum = 2882029278 },
    { source = "programs/htp3/ui.lua", destination = "/htp3/ui.lua", size = 537, checksum = 2399905801, syntax = true },
    { source = "programs/htp3/ui_parts/01.lua.part", destination = "/htp3/ui_parts/01.lua.part", size = 7614, checksum = 3467963436 },
    { source = "programs/htp3/ui_parts/02.lua.part", destination = "/htp3/ui_parts/02.lua.part", size = 11125, checksum = 3582148991 },
    { source = "programs/htp3/ui_parts/03.lua.part", destination = "/htp3/ui_parts/03.lua.part", size = 11271, checksum = 3628483508 },
    { source = "programs/htp3/ui_parts/04.lua.part", destination = "/htp3/ui_parts/04.lua.part", size = 9971, checksum = 1207652895 },
    { source = "programs/htp3/main.lua", destination = "/htp3/main.lua", size = 8961, checksum = 2233783055, syntax = true }
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
    print("Your current startup was not replaced.")
    print("Run startup again after fixing the error.")
    error(message, 0)
end

local function ensureDir(path)
    if path == "" or fs.exists(path) then return end
    local parent = fs.getDir(path)
    if parent ~= "" and not fs.exists(parent) then ensureDir(parent) end
    fs.makeDir(path)
end

local function writeAll(path, data)
    local parent = fs.getDir(path)
    if parent ~= "" then ensureDir(parent) end
    if fs.exists(path) then fs.delete(path) end
    local handle = fs.open(path, "wb") or fs.open(path, "w")
    if not handle then return false, "could not open " .. path end
    local ok, err = pcall(function() handle.write(data) end)
    handle.close()
    if not ok then
        if fs.exists(path) then fs.delete(path) end
        return false, err
    end
    return true
end

local function readAll(path)
    local handle = fs.open(path, "rb") or fs.open(path, "r")
    if not handle then return nil end
    local data = handle.readAll()
    handle.close()
    return data
end

local function adler32(data)
    local a, b = 1, 0
    for index = 1, #data do
        a = (a + data:byte(index)) % 65521
        b = (b + a) % 65521
    end
    return b * 65536 + a
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
    return fs.combine(STAGE, destination:gsub("^/", ""))
end

local function verifyBundle(folder, parts, label)
    local source = {}
    for _, name in ipairs(parts) do
        local data = readAll(fs.combine(folder, name))
        if not data then fail("missing staged " .. label .. " part " .. name) end
        source[#source + 1] = data
    end
    local compiled, err = load(table.concat(source, "\n"), "@" .. label .. ".bundle")
    if not compiled then fail(label .. " bundle syntax error: " .. tostring(err)) end
end

local function cleanupOldTemporaryFiles()
    for _, path in ipairs({
        "startup.new", "startup.update", "startup.bak", "startup.loader.bak",
        "startup.v2-backup", "startup.v21-backup", "fix223", "fix224"
    }) do
        if fs.exists(path) then pcall(function() fs.delete(path) end) end
    end
    if fs.exists(STAGE) then fs.delete(STAGE) end
end

term.setBackgroundColor(colors.black)
setColor(colors.white)
term.clear()
term.setCursorPos(1, 1)
print("HackThePlanet Colony Supply")
print("Installing Full Automation Suite v" .. VERSION)
print("")

cleanupOldTemporaryFiles()
ensureDir(STAGE)

for index, entry in ipairs(FILES) do
    write("[" .. index .. "/" .. #FILES .. "] " .. fs.getName(entry.destination) .. "... ")
    local cache = os.epoch and os.epoch("utc") or math.floor(os.clock() * 1000)
    local body, err = download(BASE_URL .. entry.source .. "?cache=" .. tostring(cache) .. "-" .. index)
    if not body then
        print("FAILED")
        fail(entry.source .. ": " .. tostring(err))
    end
    if #body ~= entry.size then
        print("FAILED")
        fail(entry.source .. " size mismatch: expected " .. entry.size .. ", got " .. #body)
    end
    local checksum = adler32(body)
    if checksum ~= entry.checksum then
        print("FAILED")
        fail(entry.source .. " checksum mismatch: expected " .. entry.checksum .. ", got " .. checksum)
    end
    if entry.syntax then
        local compiled, syntaxError = load(body, "@" .. entry.destination)
        if not compiled then
            print("FAILED")
            fail(entry.source .. " syntax error: " .. tostring(syntaxError))
        end
    end
    local ok, writeError = writeAll(stagedPath(entry.destination), body)
    if not ok then
        print("FAILED")
        fail(entry.destination .. ": " .. tostring(writeError))
    end
    setColor(colors.lime)
    print("OK")
    setColor(colors.white)
end

print("Checking assembled automation engine...")
verifyBundle(fs.combine(STAGE, "htp3/engine_parts"), { "01.lua.part", "02.lua.part", "03.lua.part", "04.lua.part" }, "engine")
print("Checking assembled monitor interface...")
verifyBundle(fs.combine(STAGE, "htp3/ui_parts"), { "01.lua.part", "02.lua.part", "03.lua.part", "04.lua.part" }, "ui")

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

if fs.exists(STAGE) then fs.delete(STAGE) end
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

local loaderCheck, loaderError = load(startupLoader, "@startup")
if not loaderCheck then fail("startup loader syntax error: " .. tostring(loaderError)) end
local okLoader, loaderWriteError = writeAll("startup.v3-new", startupLoader)
if not okLoader then fail(loaderWriteError) end

if fs.exists("startup.pre-v3") then fs.delete("startup.pre-v3") end
if fs.exists("startup") then fs.move("startup", "startup.pre-v3") end
fs.move("startup.v3-new", "startup")

setColor(colors.lime)
print("")
print("HTP Colony Supply v" .. VERSION .. " installed successfully.")
print("All automation, warehouse, request, crafting, backup, and remote systems are enabled.")
setColor(colors.gray)
print("External speaker/redstone/chat/Discord alerts remain held.")
setColor(colors.white)
print("Rebooting into v" .. VERSION .. "...")
sleep(2)
os.reboot()
