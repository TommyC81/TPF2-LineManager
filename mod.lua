local log = require 'cartok/logging'
local helper = require 'cartok/helper'

function data()
    return {
        info = {
            name = _("Name"),
            description = _("Description"),

            params = {
                {
                    key = "messageLevel",
                    name = _("Button doesn't do shit yet"),
                    values = {
                        "INFO", "DEBUG",
                    },
                    defaultIndex = 0,
                },
                {
                    key = "RuleAggressive",
                    name = _("Button doesn't do shit yet either"),
                    values = {
                        "Money is King", "Demand is King",
                    },
                    defaultIndex = 0,
                },
                {
                    key = "RuleVerbose",
                    name = _("Button doesn't do shit yet neither"),
                    values = {
                        "less", "Normal",
                    },
                    defaultIndex = 1,
                },
            },

            minorVersion = 10,
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

        runFn = function(settings, modParams)
            local params = modParams[getCurrentModId()]
            --[[            --Button one (Can't get it to work...
                        if (log) then
                            if (params["messageLevel"] == 1) then
                                log.setLevel("DEBUG")
                            else
                                log.setLevel("INFO")
                            end
                        end
            ]]
            --Button two
            helper.ruleInvert = (params["RuleAggressive"] == 1)
            log.setVerboseDebugging(params["RuleVerbose"] == 1)
        end,

    }
end
