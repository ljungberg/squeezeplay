--[[
=head1 NAME

applets.InputDetector.InputDetectorApplet - An applet to configure a squeezplay network proxy

=head1 DESCRIPTION

An applet to configure a squeezplay network proxy

=head1 FUNCTIONS

Applet related methods are described in L<jive.Applet>. 
InputDetectorApplet overrides the following methods:

=cut
--]]


-- stuff we use
local ipairs, pairs, tostring ,select, tonumber, type, assert = ipairs, pairs, tostring, select, tonumber, type, assert

local table           = require("table")
local string          = require("string")
local debug          = require("jive.utils.debug")

local oo              = require("loop.simple")
local io              = require("io")
local os              = require("os")
local socket	      = require("socket")
local lfs             = require("lfs")

local Applet          = require("jive.Applet")
local Event           = require("jive.ui.Event")
local Framework       = require("jive.ui.Framework")
local SimpleMenu      = require("jive.ui.SimpleMenu")
local Window          = require("jive.ui.Window")
local Icon            = require("jive.ui.Icon")
local Group           = require("jive.ui.Group")
local Label           = require("jive.ui.Label")
local Choice          = require("jive.ui.Choice")
local Textarea        = require("jive.ui.Textarea")
local Textinput       = require("jive.ui.Textinput")
local Keyboard        = require("jive.ui.Keyboard")
local Button          = require("jive.ui.Button")
local Popup           = require("jive.ui.Popup")
local Task            = require("jive.ui.Task")

local jnt           = jnt
local appletManager = appletManager


-- contants
local mappings = { "UNMAPPED","LOCAL","REMOTE","IGNORE" }
local readsize = 2 -- Could lead to blocking... > 1

-- runtime
local mapping = nil
local task = nil
local device = nil
local readfds = {}


module(..., Framework.constants)
oo.class(_M, Applet)


function menu(self, menuItem)
        log:info(":menu")

	local settings = self:getSettings()
        local window = Window("text_list", self:string('APPLET_NAME'))

	local fn = function(str) return self:string(str) end
	local choices = map(fn,mappings)
	settings.devicelist = self:getDeviceList(settings.devicelist)
	table.remove(choices,1)

        -- Menu for Settings...
        local menu = SimpleMenu("menu", { 
		-- Globals
		{
			id = 'AppletDesc',
			text = self:string('APPLET_DESC'),
			style = 'item_text',
			sound = "WINDOWSHOW",
		},
		{
			id = 'AppletState',
			text = tostring(self:string('APPLET_STATE')).." "..tostring(self:string(self:getInputDetectorMapping())).."("..self:getInputDetectorDevice()..")",
			style = 'item_text',
			sound = "WINDOWSHOW",
		},
		{ 
			id = 'Default',
			text = self:string('DEFAULT'),
			style = 'item_choice',
			sound = "WINDOWSHOW",
			check = Choice("choice",choices, function(obj, selectedIndex)
					-- pop default from choice list and 
                                               log:info(
                                                        "Choice updated: ",
                                                        tostring(selectedIndex),
                                                        " - ",
                                                        tostring(obj:getSelected())
                                               )
                                               settings.default_mapping = selectedIndex + 1
					       readfds,_ = self:readfdsetup(srttings.devicelist)
                                end,
                        	settings.default_mapping - 1 ), -- Index into choice
		}
	})

	choices = map(fn,mappings)

	for i,j in ipairs(settings.devicelist) do
		menu:addItem({ 
				id = 'dev'..tostring(i),
				text = j.name.." ("..j.handler..(j.mi and j.mi or j.ei )..")",
				style = 'item_choice',
				sound = "WINDOWSHOW",
				check = Choice("choice",choices, function(obj, selectedIndex)
                                               log:info(
                                                        "Choice updated: ",
                                                        tostring(selectedIndex),
                                                        " - ",
                                                        tostring(obj:getSelected())
                                               )
                                               j.mapping = selectedIndex 
					       readfds,_ = self:readfdsetup(settings.devicelist)
                                end,
                        	j.mapping and j.mapping or 1 ), -- Index into choice
		})
	end

        window:addWidget(menu)
        self:tieWindow(window)
        return window
end

--task dsiabled 
--service method
function getInputDetectorMapping(self)
	if task then
		if not task:running() then
			task:resume()
			log:warn(self,":getInputDetectorMapping task resumed")
		end	
	else
		-- ignored devices are not monitored and should return the last code...
		self:monitordevices()
	end
	
	log:debug(self,":getInputDetectorMapping ",mappings[mapping])
        return mappings[mapping] 
end

function getInputDetectorDevice(self)
	return device and device.name.."("..device.handler..(device.mi and device.mi or device.ei ) or tostring(self:string('UNINIT'))..")"
end


function startInputDetector(self)
	local settings = self:getSettings()
	local ec
	if log:isDebug() then
		for k,v in pairs(settings) do log:debug(self,":startInputDetector settings [",k,"]=",v) end
		for k,v in pairs(settings.devicelist) do log:debug(self,":startInputDetector devlist [",k,"]=",debug.view(v)) end
	end
	mapping = 4 -- IGNORE --FIXME config?
	readfds,ec = self:readfdsetup(settings.devicelist)
	if ec then
		log:warn("Errors while setting up device monitoring rematching devices & retrying")
		settings.devicelist = self:getDeviceList(settings.devicelist)
		readfds,ec = self:readfdsetup(settings.devicelist)
	end
end

function map(f, t)
  local t2 = {}
  for k,v in pairs(t) do t2[k] = f(v) end
  return t2
end


function free(self)
	log:debug(self,":free()")
	local set = self:getSettings()
	self:storeSettings() -- Applet Mananger should do this...
	log:debug(self,":free() end")
	return false -- We are a stay resident applet
end


function getDeviceList(self,oldlist)
--[[
#!/usr/bin/lua
-- egrep "^N:|^H:|^$" /proc/bus/input/devices

-- loads the socket module 
local socket = require("socket")

N: Name="e2i Technology, Inc. USB Touchpanel"
H: Handlers=mouse3 event9

N: Name="libcec-daemon"
H: Handlers=kbd event0

--]]
	local new = {}
	local devices =  io.open("/proc/bus/input/devices", "r")

	local name
	for line in devices:lines() do
		local tag, s = string.match(line, "^(.*): (.*)")

		log:debug(line,"-",tag,"::::",s)
		if tag and s then
			if tag == "N" then
				name = string.match(s, "Name=(.*)")
			elseif tag == "H" then
				local hander = "other"
				local kbd = string.match(s, "(kbd)")
				local event,eindex = string.match(s, "(event)([0-9]+)")
				local mouse,mindex = string.match(s, "(mouse)([0-9]+)")
			
				if mouse and kbd then 
					handler = "combind"
				elseif mouse then
					handler = mouse
				elseif kbd then
					handler = kbd
				end

				if event and name then
					new[#new+1] = { name = name, event = event, handler = handler, ei = eindex, mi = mindex }
				end
			end
		else
		    name = nil
		end
	end

	if oldlist then
		for n,r in pairs(new) do
			for i,j in pairs(oldlist) do
				if r.name == j.name and r.handler == j.handler and j.mapping then
					if not r.mapping then
						r.mapping = j.mapping
						for k,v in pairs(j) do
							log:debug(self,":devicelist old [",k,"]=",v)
						end
						table.remove(oldlist,i)
					end
				end
				if r.mapping then
					for k,v in pairs(r) do
						log:debug(self,":devicelist new [",k,"]=",v)
					end
					break
				end
			end
		end
	end

	return new
end


function readfdsetup(self,t)
	local readfds = {}
	local ec = nil
	for n,r in pairs(t) do 
		local device = "/dev/input/"..t[n].event..t[n].ei
		log:debug(self,":readfdsetup ",n," ",mappings[r.mapping]," ",device," ",debug.view(r))
		if not (r.mapping and r.mapping == 4) then -- IGNORE
			local dev, err = io.open(device,"rb")
			if err then
				ec=1
				log:warn(device, " open ", err)
			else
				readfds[#readfds+1] = { getfd = function() return dev.fileno and dev:fileno() or lfs.fileno(dev) end, dev = dev, detail = t[n] , file = device }
			end
		else
			log:debug(self,":readfdsetup (ignored) ",n," ",r.name," ",device)
		end
	end

	log:debug(":readfdsetup ",#readfds, " =",ec)
	return readfds, ec
end

function monitordevices(self)
		local r,w,err = socket.select(readfds,nil,0) -- non blocking
		local settings = self:getSettings()

		if err and err ~= "timeout" then
			log:error(self,":monitordevices select error", err)
			settings.devicelist = self:getDeviceList(settings.devicelist)
			readfds,_ = self:readfdsetup(settings.devicelist)
		elseif err ~= "timeout" then
			for n,fd in ipairs(r) do
				log:debug("monitordevices fd consume data ",fd.detail.name," ",fd.file)
				--fd.dev:seek("end") -- char dev seems not to be seekable
				-- consume data on fd
				local data = 'x'
				local lr, err = {fd} , nil
				while(#lr > 0 and data and not err) do
					data = fd.dev:read(readsize) -- blocking
					lr,_,err = socket.select(lr,nil,0)
				end
				log:debug("monitordevices consumed data")
				if not data or err and err ~= "timeout" then
					log:error("select data read errror ",fd.detail.name," ",fd.file,",",err)
					settings.devicelist = self:getDeviceList(settings.devicelist)
					readfds,_ = self:readfdsetup(settings.devicelist)
				else
					mapping = fd.detail.mapping and fd.detail.mapping or settings.default_mapping
					device = fd.detail

					log:debug(self,":monitordevices mapping=",mapping)
				end
			end
		end
end
