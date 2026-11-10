-- Optional self-updater for manual installations.
--
-- Storefront-managed installations should normally use Storefront's Update All
-- flow. This module gives sideloaded copies the same release-based OTA path.

local M = {}

local USER_AGENT = "KOReader-Mac1984"

local function lfs_module()
    local ok, module = pcall(require, "libs/libkoreader-lfs")
    if ok and module then return module end
    ok, module = pcall(require, "lfs")
    if ok then return module end
    error("Mac1984 OTA: lfs is unavailable")
end

local function path_join(parent, child)
    if parent:sub(-1) == "/" then return parent .. child end
    return parent .. "/" .. child
end

local function parent_dir(path)
    return path:match("^(.*)/[^/]+$") or "."
end

local function file_exists(path)
    return lfs_module().attributes(path, "mode") == "file"
end

local function dir_exists(path)
    return lfs_module().attributes(path, "mode") == "directory"
end

local function make_path(path)
    local ok, util = pcall(require, "util")
    if ok and util and type(util.makePath) == "function" then
        util.makePath(path)
        return true
    end

    local lfs = lfs_module()
    local current = path:sub(1, 1) == "/" and "" or "."
    for part in path:gmatch("[^/]+") do
        current = current .. "/" .. part
        local mode = lfs.attributes(current, "mode")
        if mode ~= "directory" then
            if mode or not lfs.mkdir(current) then return false end
        end
    end
    return true
end

local function remove_file(path)
    if file_exists(path) then os.remove(path) end
end

local function remove_tree(path)
    if not dir_exists(path) then
        remove_file(path)
        return
    end
    local lfs = lfs_module()
    for name in lfs.dir(path) do
        if name ~= "." and name ~= ".." then
            local child = path_join(path, name)
            if dir_exists(child) then
                remove_tree(child)
            else
                remove_file(child)
            end
        end
    end
    lfs.rmdir(path)
end

local function shell_quote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function tracked_file_handle(file)
    local closed = false
    local handle = {}

    function handle:write(chunk)
        if closed then return nil, "closed" end
        return file:write(chunk)
    end

    function handle:close()
        if closed then return true end
        closed = true
        return file:close()
    end

    return handle
end

function M.download(url, destination)
    local ok_http, http = pcall(require, "socket.http")
    local ok_socket, socket = pcall(require, "socket")
    local ok_socketutil, socketutil = pcall(require, "socketutil")
    if ok_http and ok_socket and ok_socketutil then
        local file = io.open(destination, "wb")
        if file then
            -- socketutil.file_sink closes its handle at end-of-stream. Track the
            -- state so our cleanup cannot close the same file a second time.
            local handle = tracked_file_handle(file)
            socketutil:set_timeout(socketutil.FILE_BLOCK_TIMEOUT, 180)
            local ok, code = pcall(function()
                return socket.skip(1, http.request{
                    url = url,
                    method = "GET",
                    headers = { ["User-Agent"] = USER_AGENT },
                    sink = socketutil.file_sink(handle),
                    redirect = true,
                })
            end)
            socketutil:reset_timeout()
            handle:close()
            if ok and code == 200 then return true end
        end
    end

    local status = os.execute(string.format(
        "curl -sfL --connect-timeout 10 --max-time 180 -A %s -o %s %s",
        shell_quote(USER_AGENT), shell_quote(destination), shell_quote(url)
    ))
    return status == 0 or status == true
end

function M.fetch_latest(repo)
    if not repo or repo == "" then return nil, "GitHub repository is not configured" end
    local settings_dir = require("datastorage"):getSettingsDir()
    local response_path = path_join(settings_dir, "mac1984-release.json")
    local ok_download = M.download(
        "https://api.github.com/repos/" .. repo .. "/releases/latest",
        response_path
    )
    if not ok_download then
        remove_file(response_path)
        return nil, "Could not download release information"
    end

    local file = io.open(response_path, "rb")
    local raw = file and file:read("*a")
    if file then file:close() end
    remove_file(response_path)

    local ok_json, json_module = pcall(require, "json")
    local release
    if ok_json and type(json_module) == "table"
        and type(json_module.decode) == "function" then
        ok_json, release = pcall(json_module.decode, raw or "")
    end
    if not ok_json or type(release) ~= "table" or type(release.tag_name) ~= "string" then
        return nil, "GitHub returned an invalid release"
    end

    local version = release.tag_name:gsub("^v", "")
    local selected
    for _index, asset in ipairs(release.assets or {}) do
        if type(asset.name) == "string"
            and asset.name:lower():match("%.koplugin%.zip$")
            and type(asset.browser_download_url) == "string" then
            selected = asset
            break
        end
    end
    if not selected then
        for _index, asset in ipairs(release.assets or {}) do
            if type(asset.name) == "string"
                and asset.name:lower():find("koplugin", 1, true)
                and asset.name:lower():match("%.zip$")
                and type(asset.browser_download_url) == "string" then
                selected = asset
                break
            end
        end
    end
    if not selected then return nil, "Release has no .koplugin.zip asset" end

    return {
        version = version,
        tag = release.tag_name,
        url = selected.browser_download_url,
        asset_name = selected.name,
        size = selected.size,
    }
end

function M.is_newer(latest, current)
    local latest_parts = {}
    local current_parts = {}
    for number in tostring(latest):gmatch("%d+") do
        table.insert(latest_parts, tonumber(number))
    end
    for number in tostring(current):gmatch("%d+") do
        table.insert(current_parts, tonumber(number))
    end
    for index = 1, math.max(#latest_parts, #current_parts) do
        local latest_part = latest_parts[index] or 0
        local current_part = current_parts[index] or 0
        if latest_part ~= current_part then return latest_part > current_part end
    end
    return false
end

function M.extract_plugin(zip_path, destination)
    local ok_archiver, Archiver = pcall(require, "ffi/archiver")
    if not ok_archiver or not Archiver then return false, "Archive support is unavailable" end

    local reader = Archiver.Reader:new()
    if not reader:open(zip_path) then return false, "Could not open the update archive" end

    local prefix
    for entry in reader:iterate() do
        if entry.path and entry.path:match("_meta%.lua$") then
            prefix = entry.path:gsub("_meta%.lua$", "")
            break
        end
    end
    if not prefix or prefix == "" then
        reader:close()
        return false, "The update archive has no plugin metadata"
    end

    remove_tree(destination)
    if not make_path(destination) then
        reader:close()
        return false, "Could not create the update directory"
    end

    local ok = true
    for entry in reader:iterate() do
        if entry.path and entry.path:sub(1, #prefix) == prefix and entry.mode == "file" then
            local relative = entry.path:sub(#prefix + 1)
            if relative ~= "" then
                local destination_path = path_join(destination, relative)
                if not make_path(parent_dir(destination_path))
                    or not reader:extractToPath(entry.path, destination_path) then
                    ok = false
                    break
                end
            end
        end
    end
    reader:close()

    if not ok or not file_exists(path_join(destination, "_meta.lua"))
        or not file_exists(path_join(destination, "main.lua")) then
        remove_tree(destination)
        return false, "The update archive is incomplete"
    end
    return true
end

function M.install(plugin_path, url, version)
    local zip_path = plugin_path .. ".update.zip"
    local new_path = plugin_path .. ".new"
    local old_path = plugin_path .. ".old"

    remove_file(zip_path)
    remove_tree(new_path)
    remove_tree(old_path)
    if not M.download(url, zip_path) then
        remove_file(zip_path)
        return false, "Download failed"
    end

    local ok_extract, extract_error = M.extract_plugin(zip_path, new_path)
    remove_file(zip_path)
    if not ok_extract then return false, extract_error end

    if not os.rename(plugin_path, old_path) then
        remove_tree(new_path)
        return false, "Could not move the current plugin"
    end
    if not os.rename(new_path, plugin_path) then
        os.rename(old_path, plugin_path)
        remove_tree(new_path)
        return false, "Could not activate the downloaded plugin"
    end

    remove_tree(old_path)
    return true, version
end

return M
