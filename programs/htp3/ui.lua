local ROOT = "/htp3/ui_parts"
local PARTS = { "01.lua.part", "02.lua.part", "03.lua.part", "04.lua.part" }
local source = {}
for _, name in ipairs(PARTS) do
    local path = fs.combine(ROOT, name)
    local file = fs.open(path, "r")
    if not file then error("Missing HTP UI part: " .. path, 0) end
    source[#source + 1] = file.readAll()
    file.close()
end
local compiled, err = load(table.concat(source, "\n"), "@htp3/ui.bundle")
if not compiled then error("HTP UI bundle syntax error: " .. tostring(err), 0) end
return compiled()
