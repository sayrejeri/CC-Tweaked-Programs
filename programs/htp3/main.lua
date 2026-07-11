local ROOT = "/htp3"
local U = dofile(ROOT .. "/util.lua")
local createConfig = dofile(ROOT .. "/config.lua")
local C = createConfig(U).load()
local createState = dofile(ROOT .. "/state.lua")
local S = createState(U, C)
local createIntegrations = dofile(ROOT .. "/integrations.lua")
local I = createIntegrations(U, C, S)
local createBackup = dofile(ROOT .. "/backup.lua")
local B = createBackup(U, C, S, I)
local createEngine = dofile(ROOT .. "/engine.lua")
local E = createEngine(U, C, S, I, B)
local createUI = dofile(ROOT .. "/ui.lua")
local UI = createUI(U, C, S, I, B, E)

local INSTALLER_URL = "https://raw.githubusercontent.com/sayrejeri/CC-Tweaked-Programs/main/programs/CCxMCxHTP.lua"

local function ensureComputerLabel()
    if os.getComputerLabel and not os.getComputerLabel() then
        pcall(os.setComputerLabel, "HTP Colony Supply")
    end
end

local function seedStockTargets()
    if U.tableCount(S.stockTargets) > 0 then return end
    S.stockTargets = {
        ["minecraft:cobblestone"] = { item = { name = "minecraft:cobblestone" }, displayName = "Cobblestone", target = 2048 },
        ["minecraft:oak_planks"] = { item = { name = "minecraft:oak_planks" }, displayName = "Oak Planks", target = 1024 },
        ["minecraft:torch"] = { item = { name = "minecraft:torch" }, displayName = "Torches", target = 256 },
        ["minecraft:bread"] = { item = { name = "minecraft:bread" }, displayName = "Bread", target = 256 }
    }
    U.writeTable(C.files.stockTargets, S.stockTargets)
end

local function screenList()
    local screens = { term.native() }
    for _, monitor in ipairs(I.monitors or {}) do screens[#screens + 1] = monitor.object end
    return screens
end

local function drawSplash(screen, percent, message)
    local previous = term.current()
    term.redirect(screen)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    local width, height = term.getSize()
    local y = math.max(2, math.floor(height / 2) - 5)
    local function center(row, text, color)
        term.setTextColor(color or colors.white)
        term.setCursorPos(math.max(1, math.floor((width - #text) / 2) + 1), row)
        term.write(text)
    end
    center(y, "=============================================", colors.gray)
    center(y + 1, "HackThePlanet", colors.lime)
    center(y + 2, "CC & MineColonies Program", colors.cyan)
    center(y + 3, "Full Automation Suite v" .. C.version, colors.yellow)
    center(y + 5, message, colors.white)
    local barWidth = math.min(42, math.max(12, width - 12))
    center(y + 7, "[" .. U.progressBar(percent / 100, barWidth, "=", "-") .. "]", colors.lime)
    center(y + 9, percent .. "%", colors.white)
    term.redirect(previous)
end

local function splash()
    local steps = {
        "Detecting peripherals...",
        "Connecting AE2 and MineColonies...",
        "Scanning warehouse inventories...",
        "Loading persistent request lifecycle...",
        "Loading crafting retries and priorities...",
        "Checking backup disk...",
        "Opening remote command channels...",
        "Starting colony command center..."
    }
    local ticks = math.max(#steps, C.ui.splashSeconds * 5)
    for tick = 1, ticks do
        local percent = math.floor((tick / ticks) * 100)
        local step = steps[math.min(#steps, math.max(1, math.ceil((percent / 100) * #steps)))]
        for _, screen in ipairs(screenList()) do pcall(drawSplash, screen, percent, step) end
        sleep(0.2)
    end
end

function E.updateProgram()
    local backupOk, backupMessage = B.backup(true, "pre-update")
    S.action("Pre-update backup: " .. backupMessage, backupOk and colors.lime or colors.orange, true)

    local url = INSTALLER_URL .. "?cache=" .. tostring(U.millis())
    local response, requestError = http.get(url, nil, true)
    if not response then
        S.error("Update download failed: " .. U.text(requestError))
        return
    end
    local body = response.readAll()
    response.close()
    if not body or body == "" then
        S.error("Update download returned an empty file")
        return
    end
    local compiled, syntaxError = load(body, "@startup.update")
    if not compiled then
        S.error("Downloaded updater syntax error: " .. U.text(syntaxError))
        return
    end
    local temporary = "startup.update"
    local ok, writeError = U.writeAll(temporary, body)
    if not ok then
        S.error("Unable to save updater: " .. U.text(writeError))
        return
    end
    if fs.exists("startup.loader.bak") then fs.delete("startup.loader.bak") end
    if fs.exists("startup") then fs.move("startup", "startup.loader.bak") end
    fs.move(temporary, "startup")
    S.action("Fresh updater downloaded. Rebooting.", colors.lime, true)
    S.saveAll()
    sleep(1)
    os.reboot()
end

local function initialSetup()
    ensureComputerLabel()
    seedStockTargets()
    I.detect()
    I.openRemoteChannels()
    B.detect()
    S.remoteMode = not I.bridge and not I.colony and #I.modems > 0
    splash()
    if not S.remoteMode then
        B.backup(false, "startup")
        E.safeScan()
    else
        S.action("Remote command center waiting for colony broadcast", colors.lightBlue, true)
        S.nextScanAt = U.now() + C.scan.deepIdle
    end
end

local function redraw()
    local countdown = math.max(0, S.nextScanAt - U.now())
    local ok, err = pcall(UI.render, countdown)
    if not ok then S.error("UI render failed: " .. U.text(err)) end
end

local function handlePeripheralChange()
    local wasRemote = S.remoteMode
    I.detect()
    I.openRemoteChannels()
    B.detect()
    S.remoteMode = not I.bridge and not I.colony and #I.modems > 0
    if wasRemote ~= S.remoteMode then
        S.action(S.remoteMode and "Switched to remote command-center mode" or "Switched to local colony mode", colors.lightBlue, true)
    end
    S.forceScan = not S.remoteMode
end

local function handleModemMessage(channel, replyChannel, payload)
    if channel == C.remote.channel then
        if S.remoteMode then
            if E.handleRemoteSnapshot(payload) then redraw() end
        else
            if E.handleRemoteCommand(payload) then
                I.broadcastSnapshot(E.snapshot())
                S.forceScan = true
            end
        end
    elseif channel == C.remote.replyChannel then
        if not S.remoteMode and E.handleRemoteCommand(payload) then
            I.broadcastSnapshot(E.snapshot())
            S.forceScan = true
        elseif S.remoteMode and E.handleRemoteSnapshot(payload) then
            redraw()
        end
    end
end

local function eventLoop()
    local renderTimer = os.startTimer(C.ui.refreshSeconds)
    local broadcastAt = U.now()
    redraw()

    while not S.stop do
        if not S.remoteMode and (S.forceScan or U.now() >= S.nextScanAt) then
            E.safeScan()
            I.broadcastSnapshot(E.snapshot())
            broadcastAt = U.now() + C.remote.broadcastSeconds
            redraw()
        elseif not S.remoteMode and C.remote.enabled and U.now() >= broadcastAt then
            I.broadcastSnapshot(E.snapshot())
            broadcastAt = U.now() + C.remote.broadcastSeconds
        end

        local event = { os.pullEventRaw() }
        local name = event[1]
        if name == "terminate" then
            S.action("Program stopped from terminal", colors.orange, true)
            S.saveAll()
            B.backup(false, "shutdown")
            S.stop = true
        elseif name == "timer" and event[2] == renderTimer then
            redraw()
            renderTimer = os.startTimer(C.ui.refreshSeconds)
        elseif name == "monitor_touch" then
            UI.handleTouch(event[2], event[3], event[4])
            redraw()
        elseif name == "key" then
            UI.handleKey(event[2])
            redraw()
        elseif name == "peripheral" or name == "peripheral_detach" or name == "disk" or name == "disk_eject" then
            handlePeripheralChange()
            redraw()
        elseif name == "modem_message" then
            handleModemMessage(event[3], event[4], event[5])
        elseif name == "ae_crafting" then
            E.handleCraftEvent(event[2], event[3], event[4])
            redraw()
        elseif name == "term_resize" or name == "monitor_resize" then
            I.detect()
            redraw()
        end
    end
end

local function fatal(err)
    term.redirect(term.native())
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.red)
    term.clear()
    term.setCursorPos(1, 1)
    print("HackThePlanet Colony Supply v" .. C.version .. " crashed:")
    print(U.text(err))
    term.setTextColor(colors.white)
    print("")
    print("A backup attempt was made. Run startup to restart.")
    pcall(function() S.error("Fatal: " .. U.text(err)); S.saveAll(); B.backup(true, "crash") end)
end

local ok, err = pcall(function()
    initialSetup()
    eventLoop()
end)
if not ok then fatal(err) end
