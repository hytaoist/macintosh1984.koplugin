local data_dir = assert(arg[1], "data directory")
local expected_source = assert(arg[2], "expected runtime source")
local plugin_paths = {}
for index = 3, #arg do
    if arg[index] and arg[index] ~= "" then
        table.insert(plugin_paths, arg[index])
    end
end

package.preload["logger"] = function()
    return { warn = function() end }
end

package.preload["libs/libkoreader-lfs"] = function()
    return {
        attributes = function(path, attribute)
            local file = io.open(path, "rb")
            if file then
                file:close()
                if attribute then return "file" end
                return { mode = "file" }
            end
        end,
    }
end

package.preload["datastorage"] = function()
    return {
        getDataDir = function() return data_dir end,
    }
end

for _, plugin_path in ipairs(plugin_paths) do
    package.path = plugin_path .. "/?.lua;" .. package.path
end
dofile("patches/2-mac1984.lua")

assert(_G.mac1984_loader_test_loaded, "loader did not load the plugin runtime")
assert(_G.mac1984_loader_test_loaded == expected_source,
    string.format("loader selected %s, expected %s",
        tostring(_G.mac1984_loader_test_loaded), tostring(expected_source)))
print("loader test OK")
