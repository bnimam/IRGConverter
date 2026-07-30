--[[
    Menu action: open the selected photos in IRGConverter.app.

    Runs in an async task because catalogue reads and `LrTasks.execute` both
    require one. Nothing is written: the app is handed the original file paths and
    the catalogue is left exactly as it was.
--]]

local LrApplication = import "LrApplication"
local LrDialogs = import "LrDialogs"
local LrTasks = import "LrTasks"
local IRGApp = require "IRGApp"

LrTasks.startAsyncTask(function()
    local catalog = LrApplication.activeCatalog()
    -- Target photos, not selected photos: with nothing selected this is the whole
    -- filmstrip, which matches what every other Lightroom command does.
    local photos = catalog:getTargetPhotos()

    if not photos or #photos == 0 then
        LrDialogs.message("Nothing selected",
                          "Select one or more photos, then choose Open in IRGConverter.",
                          "info")
        return
    end

    local paths, missing = IRGApp.collect(photos)

    if #paths == 0 then
        LrDialogs.message(
            "No files to open",
            missing > 0
                and ("None of the " .. missing .. " selected photo(s) could be found on "
                     .. "this machine. Reconnect the drive holding them and try again.")
                or "The selected photos have no files behind them.",
            "critical")
        return
    end

    local ok, message = IRGApp.run(paths)
    if not ok then
        LrDialogs.message("Could not open IRGConverter", message, "critical")
        return
    end

    -- Only speak up when something was left behind; the app coming to the front is
    -- confirmation enough for the normal case.
    if missing > 0 then
        LrDialogs.message(
            "Opened " .. #paths .. " of " .. (#paths + missing) .. " photos",
            missing .. " could not be found on this machine and were skipped.",
            "warning")
    end
end)
