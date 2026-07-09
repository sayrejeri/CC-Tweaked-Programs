-- patch_no_protected.lua
-- Run this once on the CC:Tweaked computer to remove protected-item approval checks
-- from the local startup file. It keeps blacklist/whitelist/approval mode.

local target = "startup"

if not fs.exists(target) then
    print("No startup file found on this computer.")
    print("Download CCxMCxHTP.lua as startup first.")
    return
end

local f = fs.open(target, "r")
local data = f.readAll()
f.close()

local before = data

data = data:gsub('local PROTECTED = mergeSets%(%s*DEFAULT_PROTECTED,%s*loadSet%(%s*CONFIG%.protectedFile%s*%)%s*%)', 'local PROTECTED = {}')
data = data:gsub('if PROTECTED%[parsed%.itemName%] then addPending%(newPending, newOrder, key, parsed, "protected item"%); return false, "PENDING" end\n%s*', '')
data = data:gsub('local whitelistCount, blacklistCount, protectedCount = 0, 0, 0', 'local whitelistCount, blacklistCount, protectedCount = 0, 0, 0')
data = data:gsub('for _ in pairs%(PROTECTED%) do protectedCount = protectedCount %+ 1 end\n%s*', '')
data = data:gsub('writeAt%(3, 12, "Protected Items: " %.%. tostring%(protectedCount%), colors%.yellow%)\n%s*', '')
data = data:gsub('writeAt%(3, 14, "AUTO      = safe requests send unless blacklisted/protected", colors%.white%)', 'writeAt(3, 14, "AUTO      = safe requests send unless blacklisted", colors.white)')
data = data:gsub('writeAt%(3, 18, "Protected items always require approval unless ALWAYS%-approved%.", colors%.gray%)\n%s*', '')
data = data:gsub('Loading whitelist / blacklist / protected rules%.%.%.', 'Loading whitelist / blacklist rules...')

if data == before then
    print("No protected-rule lines found to patch.")
    print("Your file may already be patched or has changed.")
    return
end

local out = fs.open(target, "w")
out.write(data)
out.close()

print("Patched startup: protected item approval disabled.")
print("Run: reboot")
