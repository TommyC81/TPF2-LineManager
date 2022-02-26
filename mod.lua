function data()
    return {
        info = {
            name = _("Name"),
            description = _("Description"),
            minorVersion = 24,
            severityAdd = "NONE",
            severityRemove = "NONE",
            tags = { "Script Mod" },
            authors = {
                {
                    name = "CARTOK", -- Author of LineManager
                    role = "CREATOR", -- OPTIONAL "CREATOR", "CO_CREATOR", "TESTER" or "BASED_ON" or "OTHER"
                },
                {
                    name = "RusteyBucket", -- Contributor to LineManager
                    role = "CO_CREATOR", -- OPTIONAL "CREATOR", "CO_CREATOR", "TESTER" or "BASED_ON" or "OTHER"
                },
                {
                    name = "Celmi", -- Author of TPF2-Timetables mod. LineManager uses code and inspiration from this mod.
                    role = "OTHER", -- OPTIONAL "CREATOR", "CO_CREATOR", "TESTER" or "BASED_ON" or "OTHER"
                },
                {
                    name = "kryfield", -- Author of Departure Board mod. LineManager uses code and inspiration from this mod.
                    role = "OTHER", -- OPTIONAL "CREATOR", "CO_CREATOR", "TESTER" or "BASED_ON" or "OTHER"
                },
            },
        },
    }
end
