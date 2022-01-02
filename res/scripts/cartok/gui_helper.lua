---@author CARTOK
-- Contains code and inspiration from 'Departure Board' created by kryfield, available here: https://steamcommunity.com/workshop/filedetails/?id=2692112427
-- General Transport Fever 2 API documentation can be found here: https://transportfever2.com/wiki/api/index.html
-- GUI specific API documentation can be found here: https://transportfever2.com/wiki/api/modules/api.gui.html
-- Further information of GUI states and functions can be found here: https://www.transportfever2.com/wiki/doku.php?id=modding:userinterface
local gui = require "gui"

local gui_helper = {}

gui_helper.settingsWindow = nil

function gui_helper.initGui()
    -- Create button
    local buttonLabel = gui.textView_create("gameInfo.linemanager.label", "BUTTONLABEL")
    local button = gui.button_create("gameInfo.linemanager.button", buttonLabel)

    game.gui.boxLayout_addItem("gameInfo.layout", button.id)

    -- Create settings window
    -- TODO: This needs to be fleshed out with actual contents and callbacks etc.
    local textView = api.gui.comp.TextView.new("")
    gui_helper.settingsWindow = api.gui.comp.Window.new("TITLE", textView)
    gui_helper.settingsWindow:setTitle("TITLE")
    gui_helper.settingsWindow:addHideOnCloseHandler()
    gui_helper.settingsWindow:setMovable(true)
    gui_helper.settingsWindow:setPinButtonVisible(true)
    gui_helper.settingsWindow:setResizable(false)
    gui_helper.settingsWindow:setSize(api.gui.util.Size.new(450, 76)) -- 2 lines
    gui_helper.settingsWindow:setPosition(0, 0)
    gui_helper.settingsWindow:setPinned(true)
    gui_helper.settingsWindow:setResizable(true)
    gui_helper.settingsWindow:setVisible(false, false)
end

return gui_helper
