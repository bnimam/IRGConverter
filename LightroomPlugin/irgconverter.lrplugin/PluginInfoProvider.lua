--[[
    The Plug-in Manager panel: shows whether the app was found, and lets its path
    be set by hand when it lives somewhere unusual.
--]]

local LrView = import "LrView"
local LrPrefs = import "LrPrefs"
local LrDialogs = import "LrDialogs"
local IRGApp = require "IRGApp"

local provider = {}

function provider.sectionsForTopOfDialog(f, _)
    local prefs = LrPrefs.prefsForPlugin()
    local appPath, locateError = IRGApp.locate()

    return {
        {
            title = "IRGConverter",

            f:row {
                f:static_text {
                    title = appPath and ("Found the app at: " .. appPath)
                        or (locateError or "IRGConverter.app not found."),
                    fill_horizontal = 1,
                    height_in_lines = 2,
                },
            },

            f:row {
                f:static_text { title = "App path" },
                f:edit_field {
                    value = LrView.bind { key = "appPath", bind_to_object = prefs },
                    width_in_chars = 40,
                    placeholder_string = "/Applications/IRGConverter.app",
                },
                f:push_button {
                    title = "Test",
                    action = function()
                        local path, err = IRGApp.locate()
                        if path then
                            LrDialogs.message("IRGConverter found", path, "info")
                        else
                            LrDialogs.message("Not found", err, "critical")
                        end
                    end,
                },
            },

            f:row {
                f:static_text {
                    title = "Select photos in Lightroom, then choose Library > "
                        .. "Plug-in Extras > Open in IRGConverter. The app opens the "
                        .. "original files, so it starts from the sensor data rather "
                        .. "than a Lightroom rendering. Nothing in your catalogue is "
                        .. "modified, and results are saved from the app itself.",
                    fill_horizontal = 1,
                    height_in_lines = 5,
                },
            },
        },
    }
end

return provider
