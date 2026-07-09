-- test_citizens.lua
-- Quick test for MineColonies citizen/villager data exposed to CC:Tweaked.

local colony = peripheral.find("colony_integrator") or peripheral.find("colonyIntegrator")

if not colony then
    print("No Colony Integrator found.")
    return
end

local methods = {
    "getCitizens",
    "getAllCitizens",
    "getCitizen",
    "amountOfCitizens",
    "maxOfCitizens",
    "getHappiness"
}

local function dump(value, indent)
    indent = indent or ""
    if type(value) ~= "table" then
        print(indent .. tostring(value))
        return
    end

    local count = 0
    for k, v in pairs(value) do
        count = count + 1
        if count > 12 then
            print(indent .. "...")
            break
        end

        if type(v) == "table" then
            print(indent .. tostring(k) .. " = {")
            dump(v, indent .. "  ")
            print(indent .. "}")
        else
            print(indent .. tostring(k) .. " = " .. tostring(v))
        end
    end
end

for _, method in ipairs(methods) do
    print("--- " .. method .. " ---")
    if type(colony[method]) == "function" then
        local ok, result = pcall(function()
            if method == "getCitizen" then
                return colony[method](1)
            end
            return colony[method]()
        end)

        if ok then
            dump(result)
        else
            print("ERROR: " .. tostring(result))
        end
    else
        print("not exposed")
    end
end
