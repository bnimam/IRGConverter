--[[
    IRGConverter — Lightroom Classic plugin.

    One job: send the photos selected in Lightroom to IRGConverter.app. The app
    reads the original files, so the conversion starts from the sensor data rather
    than from a Lightroom rendering, and nothing in the catalogue is touched.

    Appears as "Open in IRGConverter" under both Library > Plug-in Extras and
    File > Plug-in Extras — Lightroom lists the two menu tables separately and
    people look in either.

    Lightroom Classic only. Lightroom (the cloud one) has no plugin SDK of this
    kind, and there is nothing that can be done about that from here.
--]]

return {
    LrSdkVersion = 10.0,
    LrSdkMinimumVersion = 6.0,

    LrToolkitIdentifier = "io.geospace.irgconverter",
    LrPluginName = "IRGConverter",

    LrLibraryMenuItems = {
        {
            title = "Open in IRGConverter",
            file = "OpenInIRGConverter.lua",
        },
    },

    LrExportMenuItems = {
        {
            title = "Open in IRGConverter",
            file = "OpenInIRGConverter.lua",
        },
    },

    LrPluginInfoProvider = "PluginInfoProvider.lua",

    VERSION = { major = 2, minor = 0, revision = 0, build = 0 },
}
