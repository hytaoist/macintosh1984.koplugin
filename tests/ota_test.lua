-- Regression tests for the self-updater's network and release parsing paths.

local source_path = assert(arg[1], "OTA module path")
local available = {}

package.preload["logger"] = function()
    return {
        info = function() end,
        warn = function() end,
    }
end

package.preload["socket.http"] = function()
    return {
        request = function(request)
            request.sink('{"ok":true}')
            request.sink(nil)
            return 1, 200
        end,
    }
end

package.preload["socket"] = function()
    return {
        skip = function(count, ...)
            return select(count + 1, ...)
        end,
    }
end

package.preload["socketutil"] = function()
    local socketutil = {
        FILE_BLOCK_TIMEOUT = 15,
    }

    function socketutil:set_timeout()
        self.timeout_set = true
    end

    function socketutil:reset_timeout()
        self.timeout_reset = true
    end

    -- Match KOReader's file sink: it closes the handle on end-of-stream.
    function socketutil.file_sink(handle)
        return function(chunk)
            if chunk then return handle:write(chunk) end
            handle:close()
            return 1
        end
    end

    return socketutil
end

package.preload["datastorage"] = function()
    return {
        getSettingsDir = function() return available.settings_dir end,
    }
end

package.preload["libs/libkoreader-lfs"] = function()
    return {
        attributes = function(_, attribute)
            if attribute == "mode" then return "file" end
            return { mode = "file" }
        end,
    }
end

package.preload["json"] = function()
    return {
        decode = function(raw)
            if raw:find('"tag_name"', 1, true) then
                return {
                    tag_name = "v1.2.2",
                    assets = {
                        {
                            name = "macintosh1984-v1.2.2.koplugin.zip",
                            browser_download_url = "https://example.test/plugin.zip",
                            size = 1234,
                        },
                        {
                            name = "SHA256SUMS",
                            browser_download_url = "https://example.test/SHA256SUMS",
                        },
                    },
                }
            end
            return { ok = true }
        end,
    }
end

local SHA256_DIGEST =
    "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

package.preload["ffi/sha2"] = function()
    return {
        sha256 = function()
            local update = function(chunk)
                if chunk then return update end
                return SHA256_DIGEST
            end
            return update
        end,
    }
end

local OTA = assert(loadfile(source_path))()
available.settings_dir = os.getenv("TMPDIR") or "/tmp"
local destination = available.settings_dir .. "/mac1984-ota-test.json"

assert(OTA.download("https://example.test/release.json", destination),
    "download failed when socketutil closed the file")
local downloaded = assert(io.open(destination, "rb"))
assert(downloaded:read("*a") == '{"ok":true}', "downloaded content is wrong")
downloaded:close()
os.remove(destination)

OTA.download = function(_, path)
    local file = assert(io.open(path, "wb"))
    if path:find("sha256sums", 1, true) then
        file:write(SHA256_DIGEST .. "  macintosh1984-v1.2.2.koplugin.zip\n")
    else
        file:write('{"tag_name":"v1.2.2"}')
    end
    file:close()
    return true
end
local release = assert(OTA.fetch_latest("hytaoist/macintosh1984.koplugin"))
assert(release.version == "1.2.2", "release version parsing failed")
assert(release.asset_name == "macintosh1984-v1.2.2.koplugin.zip",
    "Storefront asset selection failed")
assert(release.url == "https://example.test/plugin.zip", "release URL selection failed")
assert(release.checksum == SHA256_DIGEST, "release checksum was not picked up")
assert(OTA.is_newer("1.2.2", "1.2.1"), "version comparison failed")
assert(not OTA.is_newer("v1.2.1", "1.2.1"), "equal versions should not be newer")

-- A download is only installed when it matches the published digest.
local package_path = available.settings_dir .. "/mac1984-ota-test.zip"
local package_file = assert(io.open(package_path, "wb"))
package_file:write("PK\003\004fake archive")
package_file:close()
assert(OTA.verify_checksum(package_path, SHA256_DIGEST),
    "a matching checksum was rejected")
assert(OTA.verify_checksum(package_path, nil),
    "a release without a checksum should still be installable")
local ok_verify, verify_error = OTA.verify_checksum(package_path, string.rep("f", 64))
assert(not ok_verify, "a mismatched checksum was accepted")
assert(type(verify_error) == "string", "a checksum mismatch has no error message")

-- A build without hashing support must not block the update.
local saved_preload = package.preload["ffi/sha2"]
package.preload["ffi/sha2"] = nil
package.loaded["ffi/sha2"] = nil
assert(OTA.verify_checksum(package_path, SHA256_DIGEST),
    "an unverifiable update was blocked")
package.preload["ffi/sha2"] = saved_preload
package.loaded["ffi/sha2"] = nil
os.remove(package_path)

print("OTA test OK")
