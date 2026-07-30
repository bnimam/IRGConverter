--[[
    Finding IRGConverter.app and handing it a list of files.

    Kept apart from the menu action so the search order, the file collection and
    the shell quoting are in one place and can be tested without Lightroom — see
    `test_plugin.lua`.
--]]

local LrPathUtils = import "LrPathUtils"
local LrFileUtils = import "LrFileUtils"
local LrTasks = import "LrTasks"
local LrPrefs = import "LrPrefs"

local IRGApp = {}

IRGApp.bundleIdentifier = "com.irg.IRGConverter"

--- Searched in order. A path set in the Plug-in Manager wins, then the usual
--- install locations, then the folders around the plugin itself — which is where
--- the app sits when it has been built from the repository rather than installed.
function IRGApp.candidatePaths()
    local prefs = LrPrefs.prefsForPlugin()
    local paths = {}

    if prefs.appPath and prefs.appPath ~= "" then
        table.insert(paths, prefs.appPath)
    end
    table.insert(paths, "/Applications/IRGConverter.app")

    local home = LrPathUtils.getStandardFilePath("home")
    if home then
        table.insert(paths, LrPathUtils.child(LrPathUtils.child(home, "Applications"),
                                              "IRGConverter.app"))
    end

    -- …/LightroomPlugin/irgconverter.lrplugin → …/LightroomPlugin → repository root.
    local pluginParent = LrPathUtils.parent(_PLUGIN.path)
    if pluginParent then
        table.insert(paths, LrPathUtils.child(pluginParent, "IRGConverter.app"))
        local repository = LrPathUtils.parent(pluginParent)
        if repository then
            table.insert(paths, LrPathUtils.child(repository, "IRGConverter.app"))
        end
    end
    return paths
end

--- Ask Spotlight where the bundle is, by identifier.
---
--- Last resort, and only reached when none of the fixed paths exist: it costs a
--- subprocess, and it is the only way to find an app the user has put somewhere
--- unusual without making them type a path.
function IRGApp.spotlightPath()
    local temp = LrPathUtils.getStandardFilePath("temp")
    if not temp then return nil end
    local logPath = LrPathUtils.child(temp, "irgconverter-mdfind-" .. tostring(os.time()) .. ".txt")
    local query = "kMDItemCFBundleIdentifier == '" .. IRGApp.bundleIdentifier .. "'"
    local command = "/usr/bin/mdfind " .. IRGApp.quote(query)
        .. " > " .. IRGApp.quote(logPath) .. " 2>/dev/null"

    local found = nil
    if LrTasks.execute(command) == 0 and LrFileUtils.exists(logPath) then
        local output = LrFileUtils.readFile(logPath) or ""
        -- First line only: several copies of a bundle is a normal state of
        -- affairs (a build folder plus /Applications) and either will do.
        found = output:match("^([^\n]+)")
        if found == "" then found = nil end
    end
    if logPath and LrFileUtils.exists(logPath) then LrFileUtils.delete(logPath) end
    return found
end

--- Absolute path to the app bundle, or nil with a message explaining what to do.
function IRGApp.locate()
    for _, path in ipairs(IRGApp.candidatePaths()) do
        if LrFileUtils.exists(path) then
            return path
        end
    end

    local viaSpotlight = IRGApp.spotlightPath()
    if viaSpotlight and LrFileUtils.exists(viaSpotlight) then
        return viaSpotlight
    end

    return nil, "Could not find IRGConverter.app. Move it into /Applications, or "
        .. "set its path in File > Plug-in Manager > IRGConverter."
end

--- POSIX single-quoting. A filename may legitimately contain a quote, a space or
--- a dollar sign, and none of those may reach the shell unwrapped.
function IRGApp.quote(text)
    return "'" .. tostring(text):gsub("'", "'\\''") .. "'"
end

--- The files behind a list of photos, in selection order.
---
--- Returns the paths, then how many were skipped because the file is not on this
--- machine — offline masters and missing files are ordinary in a catalogue, and
--- worth reporting rather than failing over. Virtual copies of one master share a
--- path, so duplicates are dropped: opening the same file five times would just be
--- five identical entries in the filmstrip.
---
--- `exists` is injectable for the test harness.
function IRGApp.collect(photos, exists)
    exists = exists or LrFileUtils.exists
    local paths, seen, missing = {}, {}, 0

    for _, photo in ipairs(photos) do
        local path = photo:getRawMetadata("path")
        if path and path ~= "" and not seen[path] then
            seen[path] = true
            -- `open` reads everything after the app as a file, but a path that
            -- does not start with / would still be ambiguous, and Lightroom has
            -- no reason to hand one over.
            if path:sub(1, 1) ~= "/" then
                missing = missing + 1
            elseif exists(path) then
                table.insert(paths, path)
            else
                missing = missing + 1
            end
        end
    end
    return paths, missing
end

--- The shell command that opens `paths` in the app at `appPath`.
function IRGApp.command(appPath, paths)
    local parts = { "/usr/bin/open", "-a", IRGApp.quote(appPath) }
    for _, path in ipairs(paths) do
        table.insert(parts, IRGApp.quote(path))
    end
    return table.concat(parts, " ")
end

--- Hand the files to the app. Returns true, or false plus a message.
function IRGApp.run(paths)
    if #paths == 0 then
        return false, "No files to open."
    end

    local appPath, locateError = IRGApp.locate()
    if not appPath then
        return false, locateError
    end

    local temp = LrPathUtils.getStandardFilePath("temp")
    local logPath = temp and LrPathUtils.child(
        temp, "irgconverter-open-" .. tostring(os.time()) .. ".log")

    local command = IRGApp.command(appPath, paths)
    if logPath then
        -- Captured so a failure can be reported in `open`'s own words rather than
        -- as a bare exit status.
        command = command .. " > " .. IRGApp.quote(logPath) .. " 2>&1"
    end

    local status = LrTasks.execute(command)

    local output = ""
    if logPath and LrFileUtils.exists(logPath) then
        output = LrFileUtils.readFile(logPath) or ""
        LrFileUtils.delete(logPath)
    end

    if status ~= 0 then
        local message = output:gsub("^%s*(.-)%s*$", "%1")
        if message == "" then
            message = "open exited with status " .. tostring(status)
        end
        return false, message
    end
    return true, appPath
end

return IRGApp
