-- Luacheck config for the Backlog KOReader plugin.
-- Mirrors KOReader's own .luacheckrc so `luacheck .` here matches upstream CI.
unused_args = false
std = "luajit"
self = false

globals = {
    "G_reader_settings",
    "G_defaults",
    "table.pack",
    "table.unpack",
}

read_globals = {
    "_ENV",
}

exclude_files = {
    "spec/run.lua", -- LuaJIT runner; defines busted-style globals on purpose
}

-- Specs use the busted framework's globals.
files["spec/unit/*"].std = "+busted"

ignore = {
    "631", -- line is too long (matches KOReader)
}
