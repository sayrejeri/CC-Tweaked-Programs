-- startup
-- HackThePlanet CC & MineColonies Program installer
-- Installs v2.2.2 by patching the verified v2.2.0 installer.

local VERSION = "2.2.2"
local SOURCE_URL = "https://raw.githubusercontent.com/sayrejeri/CC-Tweaked-Programs/5ef48867ea72b1f857cd61c47375042b5dc90b59/programs/CCxMCxHTP.lua"

local function fail(message)
    term.setTextColor(colors.red)
    print("")
    print("HTP v" .. VERSION .. " install failed:")
    print(tostring(message))
    term.setTextColor(colors.white)
    error(message, 0)
end

local function replaceFirst(source, oldText, newText, label)
    local first, last = source:find(oldText, 1, true)
    if not first then fail("Patch point missing: " .. label) end
    return source:sub(1, first - 1) .. newText .. source:sub(last + 1)
end

term.setBackgroundColor(colors.black)
term.setTextColor(colors.white)
term.clear()
term.setCursorPos(1, 1)
print("HackThePlanet Colony Supply")
print("Preparing verified v" .. VERSION .. " installer...")

local response, requestError = http.get(SOURCE_URL, nil, true)
if not response then fail(requestError or "Unable to download verified v2.2.0 installer") end
local installer = response.readAll()
response.close()
if not installer or installer == "" then fail("Downloaded installer was empty") end

installer = replaceFirst(
    installer,
    "-- Installs verified version 2.2.0 from the verified v2.1.0 source bundle.",
    "-- Installs verified version 2.2.2 from the verified v2.1.0 source bundle.",
    "installer comment"
)

installer = replaceFirst(
    installer,
    'local VERSION = "2.2.0"\nlocal SOURCE_VERSION = "2.1.0"',
    'local VERSION = "2.2.2"\nlocal SOURCE_VERSION = "2.1.0"',
    "installer version"
)

installer = replaceFirst(
    installer,
    'decoded = replaceLiteral(decoded, "-- Version: 2.1.0", "-- Version: 2.2.0", "version comment")',
    'decoded = replaceLiteral(decoded, "-- Version: 2.1.0", "-- Version: 2.2.2", "version comment")',
    "runtime version comment"
)

installer = replaceFirst(
    installer,
    [[decoded = replaceLiteral(decoded, 'local VERSION = "2.1.0"', 'local VERSION = "2.2.0"', "runtime version")]],
    [[decoded = replaceLiteral(decoded, 'local VERSION = "2.1.0"', 'local VERSION = "2.2.2"', "runtime version")]],
    "runtime version"
)

local insertionPoint = [[decoded = replaceLiteral(decoded,
    '    craftJobsFile = "htp_craft_jobs.cfg",\n',]]

local rackPatch = [[decoded = replaceLiteral(decoded,
    '        "^entangledtile_",\n',
    '        "^entangledtile_",\n' ..
    '        "^entangled:tile_",\n',
    "colon Entangled Block peripheral names"
)

]]

installer = replaceFirst(
    installer,
    insertionPoint,
    rackPatch .. insertionPoint,
    "warehouse rack name matcher"
)

local compiled, compileError = load(installer, "@htp_v222_installer")
if not compiled then fail("Patched installer syntax error: " .. tostring(compileError)) end

term.setTextColor(colors.lime)
print("Updater collision fixed.")
print("Rack detection patch loaded.")
term.setTextColor(colors.white)
compiled()
