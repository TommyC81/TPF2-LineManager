---@author CARTOK
-- Contains code and inspiration from 'Departure Board' created by kryfield, available here: https://steamcommunity.com/workshop/filedetails/?id=2692112427
-- General Transport Fever 2 API documentation can be found here: https://transportfever2.com/wiki/api/index.html
-- GUI specific API documentation can be found here: https://transportfever2.com/wiki/api/modules/api.gui.html
-- Further information of GUI states and functions can be found here: https://www.transportfever2.com/wiki/doku.php?id=modding:userinterface
local gui = require "gui"

local gui_helper = {}

local settingsWindow = nil

local debugging = false
local verboseDebugging = true

function gui_helper.initGui()
    -- Create LineManager button in the main GUI
    local buttonLabel = gui.textView_create("gameInfo.linemanager.label", "[LM]")
    local button = gui.button_create("gameInfo.linemanager.button", buttonLabel)
    button:onClick(gui_helper.buttonClick)
    -- TODO: Should add a divider in the bar before this button. How?
    game.gui.boxLayout_addItem("gameInfo.layout", button.id)

    -- SETTINGS WINDOW
    -- Create a BoxLayout for the options
    local settingsBox = api.gui.layout.BoxLayout.new("VERTICAL")

    -- Create the SETTINGS window
    settingsWindow = api.gui.comp.Window.new("", settingsBox)
    settingsWindow:setTitle("LineManager Settings")
    settingsWindow:addHideOnCloseHandler()
    settingsWindow:setMovable(true)
    settingsWindow:setPinButtonVisible(true)
    settingsWindow:setResizable(false)
    settingsWindow:setSize(api.gui.util.Size.new(300, 200))
    settingsWindow:setPosition(0, 0)
    settingsWindow:setPinned(true)
    settingsWindow:setVisible(false, false)

    -- Add a header for the Debugging options
    local header_Debugging = api.gui.comp.TextView.new("Debugging options")
    settingsBox:addItem(header_Debugging)

    -- Create a toggle for debugging mode and add it to the SettingsBox (BoxLayout)
    local checkBox_debugging = api.gui.comp.CheckBox.new("Debugging")
    checkBox_debugging:setSelected(debugging, false)
    checkBox_debugging:onToggle(function(selected)
        -- Send a script event to say that the debugging setting has been changed.
        api.cmd.sendCommand(api.cmd.make.sendScriptEvent("LineManager", "settingsGui", "debuggingUpdate", selected))
    end)
    settingsBox:addItem(checkBox_debugging)

    -- Create a toggle for verboseDebugging mode
    local checkBox_verboseDebugging = api.gui.comp.CheckBox.new("Verbose Debugging")
    checkBox_verboseDebugging:setSelected(verboseDebugging, false)
    checkBox_verboseDebugging:onToggle(function(selected)
        -- Send a script event to say that the verboseDebugging setting has been changed.
        api.cmd.sendCommand(api.cmd.make.sendScriptEvent("LineManager", "settingsGui", "verboseDebuggingUpdate", selected))
    end)
    settingsBox:addItem(checkBox_verboseDebugging)
end

function gui_helper.buttonClick()
    if not settingsWindow:isVisible() then
        settingsWindow:setVisible(true, false)
    else
        settingsWindow:setVisible(false, false)
    end
end

return gui_helper
