
--[[
=head1 NAME

applets.SelectPlayer.SelectPlayerApplet - Applet to select currently active player

=head1 DESCRIPTION

Gets list of all available players and displays for selection. Selection should cause main menu to update (i.e., so things like "now playing" are for the selected player)

=head1 FUNCTIONS

Applet related methods are described in L<jive.Applet>. 

=cut
--]]


-- stuff we use
local oo                 = require("loop.simple")
local pairs, ipairs, tostring      = pairs, ipairs, tostring

local Applet             = require("jive.Applet")
local SimpleMenu         = require("jive.ui.SimpleMenu")
local RadioGroup         = require("jive.ui.RadioGroup")
local RadioButton        = require("jive.ui.RadioButton")
local Window             = require("jive.ui.Window")
local appletManager      = appletManager

local log                = require("jive.utils.log").logger("applets.browser")

local EVENT_KEY_PRESS  = jive.ui.EVENT_KEY_PRESS
local EVENT_SCROLL     = jive.ui.EVENT_SCROLL
local EVENT_CONSUME    = jive.ui.EVENT_CONSUME
local EVENT_ACTION     = jive.ui.EVENT_ACTION
local EVENT_WINDOW_POP = jive.ui.EVENT_WINDOW_POP
local KEY_PLAY         = jive.ui.KEY_PLAY

module(...)
oo.class(_M, Applet)


function getPlayers(self)
	-- get list of slimservers
	-- local slimServers = appletManager:getApplet("SlimDiscovery"):getSlimservers():servers()
	local window = Window("window", self:string("SELECT_PLAYER"))
        local menu = SimpleMenu("menu")
        local group = RadioGroup()
	local currentPlayer = self:getSettings()["selectedPlayer"]
	for _, s in appletManager:getApplet("SlimDiscovery"):getSlimServers():servers() do
		self.server = s
		-- get list of players within each slimserver
		for playerMac,playerName in pairs(self.server.players) do
			log:debug('player:|', playerMac,'|',playerName)
			local matchedTuple = self:selectedPlayerCheck(playerMac, self.server.name)
			-- display as radio selections
	                local button = RadioButton(
	                        "radio", 
	                        group, 
	                        function() self:selectPlayer(playerMac, self.server.name) end,
				matchedTuple == true
	                )
	                menu:addItem({
	                        text = playerName:getName(),
	                        icon = button,
	                })
		end
	end
	window:addWidget(menu)
	-- Store the selected player when the menu is exited
	window:addListener(EVENT_WINDOW_POP,
		function()
			self:storeSettings()
		end
	)
	self:tieAndShowWindow(window)
	return window
end

function selectedPlayerCheck(self, playerMac, serverName)
	local currentlySelectedMac = self:getSettings()["selectedPlayer"]
	local currentlySelectedSlim = self:getSettings()["selectedServer"]
	if (playerMac == currentlySelectedMac and serverName == currentlySelectedSlim) then
		return true
	else
		return false
	end
end

function selectPlayer(self, playerMac, serverName)
	log:warn(playerMac)
	self:getSettings()["selectedPlayer"] = playerMac
	self:getSettings()["selectedServer"] = serverName
	return true
end

--[[

=head1 LICENSE

Copyright 2007 Logitech. All Rights Reserved.

This file is subject to the Logitech Public Source License Version 1.0. Please see the LICENCE file for details.

=cut
--]]

