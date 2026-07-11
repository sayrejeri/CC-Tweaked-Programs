local U = {}

function U.now()
    if os.epoch then return math.floor(os.epoch("utc") / 1000) end
    return math.floor(os.clock())
end

function U.millis()
    if os.epoch then return os.epoch("utc") end
    return math.floor(os.clock() * 1000)
end

function U.safe(fn, ...)
    local args = { ... }
    return pcall(function() return fn(table.unpack(args)) end)
end

function U.call(object, method, ...)
    if not object or type(object[method]) ~= "function" then return false, "missing method " .. tostring(method) end
    local args = { ... }
    return pcall(function() return object[method](table.unpack(args)) end)
end

function U.text(value)
    if value == nil then return "" end
    return tostring(value)
end

function U.lower(value)
    return string.lower(U.text(value))
end

function U.trim(value, maxLength)
    local output = U.text(value):gsub("^%s+", ""):gsub("%s+$", "")
    if maxLength and #output > maxLength then
        if maxLength <= 3 then return output:sub(1, maxLength) end
        return output:sub(1, maxLength - 3) .. "..."
    end
    return output
end

function U.clamp(value, low, high)
    value = tonumber(value) or low
    if value < low then return low end
    if value > high then return high end
    return value
end

function U.round(value, places)
    local power = 10 ^ (places or 0)
    return math.floor((tonumber(value) or 0) * power + 0.5) / power
end

function U.formatNumber(value)
    local number = tonumber(value) or 0
    if math.abs(number) >= 1000000000 then return string.format("%.2fB", number / 1000000000) end
    if math.abs(number) >= 1000000 then return string.format("%.2fM", number / 1000000) end
    if math.abs(number) >= 1000 then return string.format("%.1fK", number / 1000) end
    if math.floor(number) == number then return tostring(number) end
    return string.format("%.2f", number)
end

function U.formatDuration(seconds)
    local total = math.max(0, math.floor(tonumber(seconds) or 0))
    local days = math.floor(total / 86400)
    local hours = math.floor((total % 86400) / 3600)
    local minutes = math.floor((total % 3600) / 60)
    local secs = total % 60
    if days > 0 then return days .. "d " .. hours .. "h" end
    if hours > 0 then return hours .. "h " .. minutes .. "m" end
    if minutes > 0 then return minutes .. "m " .. secs .. "s" end
    return secs .. "s"
end

function U.title(value)
    local text = U.text(value):gsub("_", " "):gsub("%-", " ")
    return (text:gsub("(%a)([%w']*)", function(first, rest)
        return first:upper() .. rest:lower()
    end))
end

function U.itemDisplay(item)
    if type(item) ~= "table" then return U.title(U.text(item):gsub("^.*:", "")) end
    return U.text(item.displayName or item.label or item.name or item.item or item.id or "Unknown Item"):gsub("^.*:", "")
end

function U.cleanBuilding(value)
    local raw
    if type(value) == "table" then
        raw = value.name or value.displayName or value.buildingName or value.type or value.id
    else
        raw = value
    end
    raw = U.text(raw)
    if raw == "" then return "Unknown" end
    raw = raw:gsub("^.*:", ""):gsub("^.*%.", "")
    raw = raw:gsub("building", ""):gsub("workorder", "")
    raw = raw:gsub("[%[%]{}()]", " ")
    return U.title(U.trim(raw))
end

function U.contains(value, needle)
    return U.lower(value):find(U.lower(needle), 1, true) ~= nil
end

function U.containsAny(value, words)
    local lowerValue = U.lower(value)
    for _, word in ipairs(words or {}) do
        if lowerValue:find(U.lower(word), 1, true) then return true, word end
    end
    return false, nil
end

function U.deepcopy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local copy = {}
    seen[value] = copy
    for key, child in pairs(value) do copy[U.deepcopy(key, seen)] = U.deepcopy(child, seen) end
    return setmetatable(copy, getmetatable(value))
end

function U.merge(base, override)
    local result = U.deepcopy(base or {})
    for key, value in pairs(override or {}) do
        if type(value) == "table" and type(result[key]) == "table" then
            result[key] = U.merge(result[key], value)
        else
            result[key] = U.deepcopy(value)
        end
    end
    return result
end

function U.tableCount(value)
    local count = 0
    for _ in pairs(value or {}) do count = count + 1 end
    return count
end

function U.keys(value)
    local result = {}
    for key in pairs(value or {}) do result[#result + 1] = key end
    table.sort(result, function(a, b) return tostring(a) < tostring(b) end)
    return result
end

function U.values(value)
    local result = {}
    for _, child in pairs(value or {}) do result[#result + 1] = child end
    return result
end

function U.indexBy(list, keyName)
    local result = {}
    for _, value in ipairs(list or {}) do
        if type(value) == "table" and value[keyName] ~= nil then result[value[keyName]] = value end
    end
    return result
end

function U.stableSerialize(value)
    if type(value) ~= "table" then return U.text(value) end
    local pieces = { "{" }
    local keys = U.keys(value)
    for _, key in ipairs(keys) do
        local child = value[key]
        pieces[#pieces + 1] = tostring(key) .. "="
        if type(child) == "table" then
            pieces[#pieces + 1] = U.stableSerialize(child)
        else
            pieces[#pieces + 1] = tostring(child)
        end
        pieces[#pieces + 1] = ";"
    end
    pieces[#pieces + 1] = "}"
    return table.concat(pieces)
end

function U.adler32(data)
    local a, b = 1, 0
    data = data or ""
    for index = 1, #data do
        a = (a + data:byte(index)) % 65521
        b = (b + a) % 65521
    end
    return b * 65536 + a
end

function U.ensureDir(path)
    if not path or path == "" then return true end
    if fs.exists(path) then return fs.isDir(path) end
    local ok = pcall(function() fs.makeDir(path) end)
    return ok and fs.exists(path)
end

function U.readAll(path)
    if not path or not fs.exists(path) or fs.isDir(path) then return nil end
    local handle = fs.open(path, "rb") or fs.open(path, "r")
    if not handle then return nil end
    local data = handle.readAll()
    handle.close()
    return data
end

function U.writeAll(path, data)
    local parent = fs.getDir(path)
    if parent ~= "" then U.ensureDir(parent) end
    local temporary = path .. ".tmp"
    if fs.exists(temporary) then fs.delete(temporary) end
    local handle = fs.open(temporary, "wb") or fs.open(temporary, "w")
    if not handle then return false, "unable to open " .. temporary end
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

function U.readTable(path, defaultValue)
    local data = U.readAll(path)
    if not data or data == "" then return U.deepcopy(defaultValue or {}) end
    local ok, result = pcall(textutils.unserialize, data)
    if not ok or type(result) ~= "table" then return U.deepcopy(defaultValue or {}) end
    return result
end

function U.writeTable(path, value)
    return U.writeAll(path, textutils.serialize(value or {}, { compact = true }))
end

function U.readLines(path, limit)
    local result = {}
    if not path or not fs.exists(path) or fs.isDir(path) then return result end
    local handle = fs.open(path, "r")
    if not handle then return result end
    while true do
        local line = handle.readLine()
        if not line then break end
        result[#result + 1] = line
    end
    handle.close()
    if limit and #result > limit then
        local trimmed = {}
        for index = #result - limit + 1, #result do trimmed[#trimmed + 1] = result[index] end
        return trimmed
    end
    return result
end

function U.appendLine(path, message, maxLines)
    local parent = fs.getDir(path)
    if parent ~= "" then U.ensureDir(parent) end
    local handle = fs.open(path, "a")
    if handle then
        handle.writeLine("[" .. U.now() .. "] " .. U.text(message))
        handle.close()
    end
    if maxLines then
        local lines = U.readLines(path)
        if #lines > maxLines then
            local kept = {}
            for index = #lines - maxLines + 1, #lines do kept[#kept + 1] = lines[index] end
            U.writeAll(path, table.concat(kept, "\n") .. "\n")
        end
    end
end

function U.parseKeyValues(path)
    local result = {}
    for _, line in ipairs(U.readLines(path)) do
        local key, value = line:match("^([^=]+)=(.*)$")
        if key then result[U.trim(key)] = U.trim(value) end
    end
    return result
end

function U.readSet(path)
    local result = {}
    for _, line in ipairs(U.readLines(path)) do
        local clean = U.trim(line)
        if clean ~= "" and clean:sub(1, 1) ~= "#" then result[clean] = true end
    end
    return result
end

function U.writeSet(path, set)
    local lines = {}
    for key, enabled in pairs(set or {}) do if enabled then lines[#lines + 1] = tostring(key) end end
    table.sort(lines)
    return U.writeAll(path, table.concat(lines, "\n") .. (#lines > 0 and "\n" or ""))
end

function U.readNumberMap(path)
    local result = {}
    for key, value in pairs(U.parseKeyValues(path)) do
        local number = tonumber(value)
        if number then result[key] = number end
    end
    return result
end

function U.writeNumberMap(path, map)
    local lines = {}
    for key, value in pairs(map or {}) do lines[#lines + 1] = tostring(key) .. "=" .. tostring(value) end
    table.sort(lines)
    return U.writeAll(path, table.concat(lines, "\n") .. (#lines > 0 and "\n" or ""))
end

function U.itemName(item)
    if type(item) == "string" then return item end
    if type(item) ~= "table" then return U.text(item) end
    return item.name or item.item or item.id or item.itemName or ""
end

function U.itemComponents(item)
    if type(item) ~= "table" then return nil end
    return item.components or item.component or item.dataComponents or item.nbt or item.tag
end

function U.itemFingerprint(item)
    if type(item) ~= "table" then return nil end
    return item.fingerprint or item.hash or item.itemFingerprint
end

function U.itemKey(item)
    local name = U.itemName(item)
    local fingerprint = U.itemFingerprint(item)
    if fingerprint and U.text(fingerprint) ~= "" then return name .. "#fp:" .. U.text(fingerprint) end
    local components = U.itemComponents(item)
    if components ~= nil then return name .. "#cmp:" .. tostring(U.adler32(U.stableSerialize(components))) end
    return name
end

function U.itemFilter(item, count)
    local filter = { name = U.itemName(item), count = math.max(1, math.floor(tonumber(count) or 1)) }
    local fingerprint = U.itemFingerprint(item)
    if fingerprint and U.text(fingerprint) ~= "" then filter.fingerprint = U.text(fingerprint) end
    local components = U.itemComponents(item)
    if components ~= nil and not filter.fingerprint then
        if type(components) == "table" then
            filter.components = components
        else
            filter.components = U.text(components)
        end
    end
    return filter
end

function U.sameItem(a, b)
    return U.itemKey(a) == U.itemKey(b)
end

function U.positionKey(position)
    if type(position) ~= "table" then return U.text(position) end
    return table.concat({ position.x or "?", position.y or "?", position.z or "?", position.dimension or "" }, ",")
end

function U.copyFile(source, destination, maxBytes)
    local data = U.readAll(source)
    if data == nil then return false, "missing source" end
    if maxBytes and #data > maxBytes then data = data:sub(#data - maxBytes + 1) end
    return U.writeAll(destination, data)
end

function U.safeDelete(path)
    if path and fs.exists(path) then return pcall(function() fs.delete(path) end) end
    return true
end

function U.progressBar(percent, width, filledCharacter, emptyCharacter)
    local value = U.clamp(percent or 0, 0, 1)
    local size = math.max(1, math.floor(width or 10))
    local filled = math.floor(value * size + 0.5)
    return string.rep(filledCharacter or "#", filled) .. string.rep(emptyCharacter or "-", size - filled)
end

function U.sorted(list, comparator)
    local result = {}
    for _, value in ipairs(list or {}) do result[#result + 1] = value end
    table.sort(result, comparator)
    return result
end

return U
