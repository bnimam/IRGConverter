--[[
    Harness for the plugin's non-UI logic.

    Lightroom's Lua has no standalone interpreter, but the pieces worth testing —
    finding the app, collecting the files behind a selection, and shell quoting —
    only need a handful of SDK functions stubbed.

        lua LightroomPlugin/test_plugin.lua /Applications/IRGConverter.app
        lua LightroomPlugin/test_plugin.lua <app> <image> --launch

    With a third argument of --launch it really runs `open`, which brings the app
    up with that image loaded. Without it, nothing outside this process happens.
--]]

local appArg, imageArg, launchArg = arg[1], arg[2], arg[3]
assert(appArg, "usage: test_plugin.lua <IRGConverter.app> [image] [--launch]")

local failures = 0
local function check(condition, message)
    if condition then
        print("  ok   " .. message)
    else
        print("  FAIL " .. message)
        failures = failures + 1
    end
end

local home = os.getenv("HOME") or "/Users/nobody"
local prefs = { appPath = nil }
local executed = {}

-- Minimal stand-ins for the SDK modules IRGApp.lua imports.
local stubs = {
    LrPathUtils = {
        child = function(dir, name) return dir .. "/" .. name end,
        parent = function(path)
            local parent = path:match("^(.*)/[^/]+$")
            return parent ~= "" and parent or "/"
        end,
        getStandardFilePath = function(which)
            if which == "home" then return home end
            return os.getenv("TMPDIR") or "/tmp"
        end,
    },
    LrFileUtils = {
        exists = function(path)
            -- Directories (an .app bundle) and files both count, as in the SDK.
            local f = io.open(path, "r")
            if f then f:close() return "file" end
            local ok = os.execute("test -e " .. ("'" .. path:gsub("'", "'\\''") .. "'"))
            return (ok == true or ok == 0) and "directory" or false
        end,
        readFile = function(path)
            local f = io.open(path, "r")
            if not f then return nil end
            local body = f:read("*a")
            f:close()
            return body
        end,
        delete = function(path) os.remove(path) end,
    },
    LrTasks = {
        execute = function(command)
            table.insert(executed, command)
            local ok, _, code = os.execute(command)
            if type(ok) == "number" then return ok end
            return ok and 0 or (code or 1)
        end,
    },
    LrPrefs = {
        prefsForPlugin = function() return prefs end,
    },
}

_G.import = function(name)
    return assert(stubs[name], "harness does not stub " .. name)
end
_PLUGIN = { path = "/tmp/lrplugins/irgconverter.lrplugin" }

package.path = "LightroomPlugin/irgconverter.lrplugin/?.lua;" .. package.path
local IRGApp = require "IRGApp"

print("locating the app")
prefs.appPath = appArg
local found, err = IRGApp.locate()
check(found == appArg, "prefers the path set in preferences (" .. tostring(found or err) .. ")")

prefs.appPath = nil
local candidates = IRGApp.candidatePaths()
local joinedCandidates = table.concat(candidates, "\n")
check(joinedCandidates:find("/Applications/IRGConverter.app", 1, true),
      "looks in /Applications")
check(joinedCandidates:find(home .. "/Applications/IRGConverter.app", 1, true),
      "looks in ~/Applications")
check(joinedCandidates:find("/tmp/lrplugins/IRGConverter.app", 1, true),
      "looks next to the plugin folder")
check(joinedCandidates:find("/tmp/IRGConverter.app", 1, true),
      "looks one level further up, where a repository build sits")

prefs.appPath = "/nowhere/IRGConverter.app"
local missingApp, missingError = IRGApp.locate()
if missingApp then
    -- A real install elsewhere on this machine is a legitimate outcome: the
    -- fallbacks are doing their job. Only the message matters when nothing exists.
    check(missingApp:find("IRGConverter.app", 1, true) ~= nil,
          "a bad preference falls through to a real install (" .. missingApp .. ")")
else
    check(type(missingError) == "string" and missingError:find("Plug%-in Manager") ~= nil,
          "with nothing installed, the message says where to set the path")
end
prefs.appPath = appArg

print("\ncollecting the files behind a selection")
local function photo(path)
    return { getRawMetadata = function() return path end }
end
local function existsAll() return "file" end

local paths, missing = IRGApp.collect(
    { photo("/a/one.ORF"), photo("/a/two.ORF") }, existsAll)
check(#paths == 2 and paths[1] == "/a/one.ORF" and paths[2] == "/a/two.ORF",
      "keeps selection order")
check(missing == 0, "nothing reported missing")

paths = IRGApp.collect({ photo("/a/one.ORF"), photo("/a/one.ORF") }, existsAll)
check(#paths == 1, "virtual copies of one master collapse to a single file")

paths, missing = IRGApp.collect(
    { photo("/a/here.ORF"), photo("/gone/offline.ORF") },
    function(p) return p == "/a/here.ORF" and "file" or false end)
check(#paths == 1 and paths[1] == "/a/here.ORF" and missing == 1,
      "an offline master is skipped and counted")

paths, missing = IRGApp.collect({ photo(nil), photo("") }, existsAll)
check(#paths == 0 and missing == 0, "photos with no path at all are ignored")

paths, missing = IRGApp.collect({ photo("-nasty.ORF") }, existsAll)
check(#paths == 0 and missing == 1,
      "a relative path is refused rather than handed to open as a flag")

print("\nbuilding the command")
local command = IRGApp.command("/Applications/IRGConverter.app",
                               { "/a/in put.tif", "/a/it's here.ORF" })
check(command:find("^/usr/bin/open %-a '/Applications/IRGConverter%.app'"),
      "opens with the app bundle")
check(command:find("'/a/in put.tif'", 1, true), "quotes a path containing a space")
check(command:find("'/a/it'\\''s here.ORF'", 1, true),
      "escapes a single quote in a filename")

local ok, message = IRGApp.run({})
check(not ok and message == "No files to open.", "an empty list is refused")

if launchArg == "--launch" and imageArg then
    print("\nlaunching the app for real")
    local launched, detail = IRGApp.run({ imageArg })
    check(launched, "open reported success" .. (launched and "" or ": " .. tostring(detail)))
    check(#executed > 0 and executed[#executed]:find(imageArg, 1, true) ~= nil,
          "the command carried the image path")
else
    print("\n(skipping the real launch — pass an image and --launch to include it)")
end

print(failures == 0 and "\nAll plugin checks passed." or ("\n" .. failures .. " failed."))
os.exit(failures == 0 and 0 or 1)
