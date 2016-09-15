if SERVER then AddCSLuaFile() end
print("loading pfoolproof by thelastpenguin")

-- INITIALIZATION
local RECENT_ERRORS_TO_KEEP = 10
local LOG_FILES_TO_KEEP = 8
local ANALYTICS_ENDPOINT = 'http://analytics.lastpengu.in/api/'

pfoolproof = {}

local datadir = 'pfoolproof'..(SERVER and '_sv' or '_cl')
file.CreateDir(datadir)

pfoolproof.addons = {}

pfoolproof.versionStringToNumber = function(version)
	local versionNumber = 0
	for k, v in ipairs(string.Explode('.', version, false)) do
		versionNumber = versionNumber * 100 + tonumber(v)
	end
	return versionNumber
end

-- HELPER FUNCTIONS
local function formattedDate()
	return os.date("%Y-%m-%d - h%Hm%Ms%S")
end

local function formattedTime()
	return os.date("h%Hm%Ms%S")
end

local function game_GetIP()
	local hostip = GetConVarString( "hostip" ) -- GetConVarNumber is inaccurate
	hostip = tonumber( hostip )
	if not hostip then return 'single player' end

	local ip = {}
	ip[ 1 ] = bit.rshift( bit.band( hostip, 0xFF000000 ), 24 )
	ip[ 2 ] = bit.rshift( bit.band( hostip, 0x00FF0000 ), 16 )
	ip[ 3 ] = bit.rshift( bit.band( hostip, 0x0000FF00 ), 8 )
	ip[ 4 ] = bit.band( hostip, 0x000000FF )

	return table.concat( ip, "." )
end

local src_name_cache = {}
local function printPrefix(depth)
	-- finds the file name and line number of the function 3 calls above in the stack
	local src = debug.getinfo(depth or 3, 'S')
	if not src_name_cache[src.short_src] then
		src_name_cache[src.short_src] = string.GetFileFromFilename(src.short_src)
	end
	return src_name_cache[src.short_src] .. ':' .. src.linedefined .. ' '
end

local function cleanupOldFiles(path, number)
	local files = file.Find(path..'/*', 'DATA')
	local file_to_age = {}
	for k,v in ipairs(files) do
		file_to_age[path .. '/' .. v] = file.Time(path .. '/' .. v, 'DATA')
	end

	local count = 0
	local deleted = 0
	for k,v in SortedPairsByValue(file_to_age, true) do
		count = count + 1
		if count > number then
			file.Delete(k)
			deleted = deleted + 1
		end
	end
	return deleted
end

-- ADDON META TABLE
local addon_mt = {}
addon_mt.__index = addon_mt

function addon_mt:addDiagnostic(desc, func)
	table.insert(self.diagnosticTests, {
		desc = desc,
		howToFix = howToFix,
		func = func
	})

	local function reportError(error)
		local path = string.GetFileFromFilename(debug.getinfo(func, 'S').short_src)
		self:_recordError("TEST FATAL ERROR in " .. tostring(error))
		self.fatalErrors = self.fatalErrors + 1
		self:addRecentError(error)
	end

	timer.Simple(0.01, function()
		local succ, error = pcall(func, function(succ)
			if not succ then
				reportError(tostring(error))
			end
		end)
		if not succ then
			reportError(tostring(error))
		end
	end)
end

function addon_mt:setAnalytics(_bool)
	self.analytics = _bool
end

function addon_mt:pcall(func, ...)
	local status, error = pcall(func, ...)
	if not status then
		self:_recordError('PCALL ERROR: '..tostring(error))
		ErrorNoHalt(error)
	end
end

function addon_mt:assert(boolean, message)
	if not boolean then
		self:_recordError('FATAL ERROR ASSERT FAILURE in ' .. printPrefix() .. ': ' .. tostring(message))
	end
end

function addon_mt:print(...)
	local prefix = printPrefix()
	if self.debug then
		MsgC(Color(220, 220, 220), '[')
		MsgC(color_white, self.addonName)
		MsgC(Color(220, 220, 220), ']')
		print(...)
	end
	local line = table.concat({prefix .. ' ', ...}, ' ')
	file.Append(self.logfile, formattedDate() .. ' - ' .. line..'\n\n')
end

function addon_mt:_recordError(line, isFatal)
	file.Append(self.logfile, formattedDate() .. ' - ' .. line..'\n\n')

	self:_addRecentError(line)

	if SERVER and self.analytics then
		http.Post(ANALYTICS_ENDPOINT .. 'error', {
			addon = self.addonName,
			version = self.version,
			ServerIP = game_GetIP(),
			error = line,
		}, function() end, function(errorMessage)
			self:print("analytics failed to report fatal error. code: " .. errorMessage)
		end)
	end
end

function addon_mt:_addRecentError(error)
	table.insert(self.recentErrors, 1, line)
	if #self.recentErrors > RECENT_ERRORS_TO_KEEP then
		if not self.recentErrors[RECENT_ERRORS_TO_KEEP + 1]:find('FATAL ERROR') then
			self.recentErrors[RECENT_ERRORS_TO_KEEP + 1] = nil
		end
	end
end

function addon_mt:error(...)
	local prefix = printPrefix()
	local line = table.concat({'ERROR in ' .. prefix .. ': ', ...}, ' ')

	self.errors = self.errors + 1
	self:_recordError(line, false)

	error(...)
end

function addon_mt:fatalError(...)
	local prefix = printPrefix()
	local line = table.concat({'FATAL ERROR in ' .. prefix .. ': ', ...}, ' ')

	self.fatalErrors = self.fatalErrors + 1
	self:_recordError(line, true)

	error(...)
end

function pfoolproof.registerAddon(addonName, version)
	if type(addonName) ~= 'string' then error 'expected argument1 addonName got nil' end

	local addonDataDir = datadir..'/'..addonName
	local addonLogsDir = addonDataDir .. '/logs'
	local addonLogsFile = addonLogsDir .. '/' .. os.date("%Y-%m-%d - h%Hm%Ms%S") .. '.txt'

	if not file.IsDir(addonDataDir, 'DATA') then file.CreateDir(addonDataDir) end
	if not file.IsDir(addonLogsDir, 'DATA') then file.CreateDir(addonLogsDir) end

	local addon = setmetatable({
		addonName = addonName,
		version = verson or '0.0.0',
		diagnosticTests = {},
		datadir = addonDataDir,
		logdir = addonLogsDir,
		logfile = addonLogsFile,
		errors = 0,
		fatalErrors = 0,
		recentErrors = {},
		analytics = false,
	}, addon_mt)

	-- logs the last 5 sessions
	local deleted = cleanupOldFiles(addon.logdir, LOG_FILES_TO_KEEP) -- 5 is the number of logs files to retain
	if deleted > 0 then
		addon:print("cleaned ".. deleted .. " old log files.")
	end

	table.insert(pfoolproof.addons, addon)

	if version then
		addon:print("ADDON VERSION: " .. version)
	end

	timer.Simple(10, function()
		if SERVER and addon.analytics then
			http.Post(ANALYTICS_ENDPOINT .. 'server', {
				addon = addon.addonName,
				version = addon.version,
				serverIp = game_GetIP(),
				hostname = GetHostName()
			}, function() end, function(error)
				addon:print("analytics failed to report hostname and ipaddress " .. error)
			end)
		end
	end)

	return addon
end

local COMMANDID_SHOW_MENU = 1
local COMMANDID_FETCH_INFO = 2
local COMMANDID_SHOW_ADDON = 3
local COMMANDID_FETCH_LOGFILE = 4
local COMMANDID_SHOW_LOGFILE = 5
local COMMANDID_FETCH_LOGFILE = 6
local COMMANDID_RUN_TEST = 7
local COMMANDID_TEST_RESULT = 8

if SERVER then
	util.AddNetworkString('pfoolproof.command')

	-- COMMAND LAYER
	local function sendOpenMenu(pl)
		print(pl:Name() .. ' opened the pfoolproof diagnostic menu.')
		net.Start('pfoolproof.command')
		net.WriteUInt(COMMANDID_SHOW_MENU, 32)

		net.WriteUInt(#pfoolproof.addons, 32)
		for k,v in ipairs(pfoolproof.addons) do
			net.WriteString(v.addonName)
			net.WriteString(v.version)
			net.WriteUInt(v.errors, 32)
			net.WriteUInt(v.fatalErrors, 32)
		end

		net.Send(pl)
	end

	concommand.Add('pfoolproof', function(pl, cmd, args)
		if not pl:IsSuperAdmin() then pl:ChatPrint("insufficient permissions.") return end
		if args[1] == 'check' then
			for k,v in ipairs(pfoolproof.addons) do
				if v.fatalErrors > 0 then
					sendOpenMenu(pl)
					return
				end
			end
		else
			sendOpenMenu(pl)
		end
	end)

	local commands = {}

	commands[COMMANDID_FETCH_INFO] = function(pl)
		local addonIndex = net.ReadUInt(32)

		local addon = pfoolproof.addons[addonIndex]
		if not addon then
			pl:ChatPrint("[pfoolproof] bad addon index " .. addonIndex)
			return
		end

		local logFiles = file.Find(addon.logdir .. '/*', 'DATA')

		net.Start('pfoolproof.command')
			net.WriteUInt(COMMANDID_SHOW_ADDON, 32)
			net.WriteUInt(addonIndex, 32)

			-- send the unit test names
			net.WriteUInt(#addon.diagnosticTests, 32)
			for k,v in pairs(addon.diagnosticTests) do
				net.WriteString(v.desc)
			end

			-- send the recent error messages
			net.WriteUInt(#addon.recentErrors, 32)
			for k,v in ipairs(addon.recentErrors) do
				net.WriteString(v)
			end

			-- send the log file names
			net.WriteUInt(#logFiles, 32)
			for k,v in ipairs(logFiles) do
				net.WriteString(v)
				net.WriteUInt(file.Size(addon.logdir .. '/' .. v, 'DATA'), 32)
			end
		net.Send(pl)
	end

	commands[COMMANDID_FETCH_LOGFILE] = function(pl)
		local addonIndex = net.ReadUInt(32)
		local addon = pfoolproof.addons[addonIndex]
		if not addon then
			pl:ChatPrint("[pfoolproof] bad addon index" .. addonIndex)
			return
		end
		local logFile = file.Read(addon.logdir .. '/' .. net.ReadString(), 'DATA')
		if not logFile then
			pl:ChatPrint("[pfoolproof] failed to read the logfile")
			return
		end

		net.Start('pfoolproof.command')
		net.WriteUInt(COMMANDID_SHOW_LOGFILE, 32)
		net.WriteString(addon.logfile)
		net.WriteString(string.sub(logFile, math.max(1, string.len(logFile) - 40000)))
		net.Send(pl)
	end

	commands[COMMANDID_RUN_TEST] = function(pl)
		local addonIndex = net.ReadUInt(32)
		local addon = pfoolproof.addons[addonIndex]
		if not addon then
			pl:ChatPrint("[pfoolproof] bad addon index" .. addonIndex)
			return
		end
		local testIndex = net.ReadUInt(32)
		local test = addon.diagnosticTests[testIndex]
		if not test then
			pl:ChatPrint("[pfoolproof] bad test index " .. testIndex)
			return
		end
		local status, error = pcall(test.func, function(result)
			net.Start('pfoolproof.command')
				net.WriteUInt(COMMANDID_TEST_RESULT, 32)
				net.WriteUInt(testIndex, 32)
				net.WriteUInt(result and 1 or 0, 8)
			net.Send(pl)
		end)
		if not status then
			net.Start('pfoolproof.command')
				net.WriteUInt(COMMANDID_TEST_RESULT, 32)
				net.WriteUInt(testIndex, 32)
				net.WriteUInt(0, 8)
			net.Send(pl)
		end
	end

	net.Receive('pfoolproof.command', function(_, pl)
		if not pl:IsSuperAdmin() then return end

		local command = net.ReadUInt(32)
		if not commands[command] then pl:ChatPrint("[pfoolproof] bad command index "..command) return end
		commands[command](pl)
	end)
elseif CLIENT then

	local menu
	local addons = {}
	local testPanels = nil

	local function commandCloseMenu()
		if IsValid(menu) then menu:Remove() end
		menu = nil
		addons = nil
	end

	local function commandFetchAddon(addon)
		net.Start('pfoolproof.command')
		net.WriteUInt(COMMANDID_FETCH_INFO, 32)
		net.WriteUInt(addon.index, 32)
		net.SendToServer()
	end

	local function commandFetchLogFile(addon, logfile)
		net.Start('pfoolproof.command')
		net.WriteUInt(COMMANDID_FETCH_LOGFILE, 32)
		net.WriteUInt(addon.index, 32)
		net.WriteString(logfile.file)
		net.SendToServer()
	end

	commands = {}
	commands[COMMANDID_SHOW_MENU] = function()
		if menu then
			commandCloseMenu()
		end

		menu = vgui.Create('pfpmenu')

		local panel = menu:NewContent() -- the base page
		addons = {}
		for i = 1, net.ReadUInt(32) do
			table.insert(addons, {
				index = i,
				addonName = net.ReadString(),
				version = net.ReadString(),
				errors = net.ReadUInt(32),
				fatalErrors = net.ReadUInt(32)
			})
		end

		for k, addon in ipairs(addons) do
			local addonRow = vgui.Create('pfpmenu_row', panel)
			addonRow:SetTall(30)
			local addonName = addonRow:SetText(addon.addonName)
			addonName:SetFont('foolproof_20px')
			addonName:SizeToContents()
			addonName:CenterVertical()
			local errorText = addonRow:AddText('errors: ' .. addon.errors .. '  fatal errors: ' .. addon.fatalErrors, 'right')
			errorText:SetPos(addonRow:GetWide() - 200, 0)
			errorText:CenterVertical()

			if addon.fatalErrors > 0 then
				addonRow:SetTint(Color(255, 0, 0))
			elseif addon.errors > 0 then
				addonRow:SetTint(Color(255, 255, 0))
			else
				addonRow:SetTint(Color(0, 255, 0))
			end
			local versionText = addonRow:AddText('v' .. addon.version, 'right')

			addonRow.DoClick = function(self)
				print("fetching addon " .. addon.addonName)
				commandFetchAddon(addon)
				self:FlashMessage("Fetching Information")
			end
		end
	end

	-- received info
	commands[COMMANDID_SHOW_ADDON] = function()
		local addonIndex = net.ReadUInt(32)
		if not addons or not addons[addonIndex] then return end
		local addon = addons[addonIndex]

		local diagnosticTests = {}
		for i = 1, net.ReadUInt(32) do
			table.insert(diagnosticTests, {
				desc = net.ReadString(),
				status = 'pending',
			})
		end

		local errorMessages = {}
		for i = 1, net.ReadUInt(32) do
			table.insert(errorMessages, net.ReadString())
		end

		local logFiles = {}
		for i = 1, net.ReadUInt(32) do
			table.insert(logFiles, {
				file = net.ReadString(),
				size = net.ReadUInt(32)
			})
		end

		local panel = menu:NewContent()

		-- recent error messages
		local infoRow = vgui.Create('pfpmenu_row', panel)
		infoRow:SetText('Recent Errors (click to copy all)')
		infoRow:SetTint(Color(60, 60, 60))
		infoRow.DoClick = function(self)
			SetClipboardText('```'..table.concat(errorMessages, '\n')..'```')
			self:FlashMessage("Copied errors as markdown")
		end

		for k, message in ipairs(errorMessages) do
			local messageRow = vgui.Create('pfpmenu_row', panel)
			local label = messageRow:SetText(message, 'left')
			label:SetWrap(true)
			label:SetSize(messageRow:GetWide(), 40)
			messageRow:SetTall(label:GetTall())
			label:CenterVertical()
			messageRow:SetTint(string.find(message, 'FATAL ERROR') and Color(255, 0, 0) or Color(255, 255, 0))
			messageRow.DoClick = function(self)
				SetClipboardText(message)
				self:FlashMessage("Copied to clipboard")
			end
		end

		local p = vgui.Create('DPanel', panel)
		p:SetAlpha(0)
		p:SetTall(20)

		-- show diagnostic tests
		testPanels = {}
		local infoRow = vgui.Create('pfpmenu_row', panel)
		infoRow:SetText('Diagnostic Tests (Click to run all)')
		infoRow:SetTint(Color(60, 60, 60))
		infoRow.DoClick = function(self)
			for k, panel in ipairs(testPanels) do
				panel:SetStatus('pending', Color(200, 200, 200))
				panel:DoClick()
			end
		end

		for k, test in ipairs(diagnosticTests) do
			local messageRow = vgui.Create('pfpmenu_row', panel)
			messageRow:SetText(test.desc)
			local status
			messageRow.SetStatus = function(self, text, color)
				if IsValid(status) then status:Remove() end
				status = messageRow:AddText(text, 'right')
				status:SetColor(color)
				self:SetTint(color)
			end
			messageRow.DoClick = function()
				messageRow:SetStatus('pending', Color(200, 200, 200))
				net.Start('pfoolproof.command')
					net.WriteUInt(COMMANDID_RUN_TEST, 32)
					net.WriteUInt(addon.index, 32)
					net.WriteUInt(k, 32)
				net.SendToServer()
			end
			table.insert(testPanels, messageRow)
		end
		infoRow:DoClick()

		local p = vgui.Create('DPanel', panel)
		p:SetAlpha(0)
		p:SetTall(20)

		-- log files
		local infoRow = vgui.Create('pfpmenu_row', panel)
		infoRow:SetText('Log Files')
		infoRow:SetTint(Color(60, 60, 60))
		infoRow:SetMouseInputEnabled(false)

		for i = #logFiles, 1, -1 do
			local logFile = logFiles[i]
			local messageRow = vgui.Create('pfpmenu_row', panel)
			messageRow:SetText(logFile.file)
			messageRow:AddText(string.NiceSize(logFile.size), 'right')
			messageRow.DoClick = function(self)
				commandFetchLogFile(addon, logFile)
				self:FlashMessage("Fetching log file...")
			end
		end
	end

	commands[COMMANDID_TEST_RESULT] = function()
		local testIndex = net.ReadUInt(32)
		local result = net.ReadUInt(8)
		if IsValid(testPanels[testIndex]) then
			if result == 1 then
				testPanels[testIndex]:SetStatus('Ok', Color(0, 255, 0))
			else
				testPanels[testIndex]:SetStatus('Failed', Color(255, 0, 0))
			end
		end
	end

	-- show logfile
	commands[COMMANDID_SHOW_LOGFILE] = function()
		if not menu then return end
		local panel = menu:NewContent()
		local html = vgui.Create('DHTML', panel)
		local title = net.ReadString()
		local log = net.ReadString()
		html:SetHTML(string.format([[
			<html>
			<style>
			* {
				color: white;
				font-family: "HelveticaNeue-Light", "Helvetica Neue Light", "Helvetica Neue", Helvetica, Arial, "Lucida Grande", sans-serif
				font-weight: 300;
			}
			</style>
			<body>
			<h4>%s</h4>
			<code><pre>%s</pre></code>
			</body>
			</html>
		]], title, log))
		html:SetSize(menu:GetContentSize())
	end

	net.Receive('pfoolproof.command', function()
		local command = net.ReadUInt(32)
		commands[command]()
	end)


	-- VGUI
	surface.CreateFont('foolproof_20px', {
		size = 20,
		weight = 200,
		font = 'Roboto',
	})

	surface.CreateFont('foolproof_16px', {
		size = 16,
		weight = 200,
		font = 'Roboto',
	})

	vgui.Register('pfpmenu', {
		Init = function(self)
			self:SetSize(ScrW() * 0.5, ScrH() * 0.8)
			self:Center()
			self:MakePopup()

			local header = vgui.Create('DPanel', self)
			header.Paint = function(self, w, h)
				surface.SetDrawColor(60, 60, 60, 255)
				surface.DrawRect(0, 0, w, h)
				surface.SetDrawColor(80, 80, 80, 255)
				surface.DrawOutlinedRect(0, 0, w, h)
			end
			header:SetSize(self:GetWide(), 25)

			local headerLabel = Label('KragleStudio\'s Diagnostics by thelastpenguin', header)
			headerLabel:SetFont('foolproof_20px')
			headerLabel:SizeToContents()
			headerLabel:SetPos(10, 0)
			headerLabel:Center()

			local closeButton = vgui.Create('DButton', header)
			closeButton:SetSize(100, header:GetTall())
			closeButton:SetText('Close')
			closeButton:SetFont('foolproof_20px')
			closeButton:Dock(RIGHT)
			closeButton.Paint = function() end
			closeButton.DoClick = function()
				commandCloseMenu()
			end

			local backButton = vgui.Create('DButton', header)
			backButton:SetSize(100, header:GetTall())
			backButton:SetText('Back')
			backButton:SetFont('foolproof_20px')
			backButton:Dock(LEFT)
			backButton.Paint = function() end
			backButton.DoClick = function()
				self:PopPanel()
			end

			self.panelStack = {}
		end,

		GetContent = function(self)
			return self.panelStack[#self.panelStack]
		end,

		GetContentSize = function(self)
			return self:GetWide() - 20, self:GetTall() - 25 - 20
		end,

		GetContentPos = function(self)
			return 10, 25 + 10
		end,

		PushPanel = function(self, panel)
			table.insert(self.panelStack, panel)
			panel:SetSize(self:GetContentSize())

			if #self.panelStack == 1 then
				panel:SetPos(self:GetContentPos())
			else
				local targetx, targety = self:GetContentPos()
				local panelBelow = self.panelStack[#self.panelStack - 1]
				panelBelow:SetPos(targetx, targety)
				panelBelow:MoveTo(-panelBelow:GetWide(), targety, 0.2, 0)
				panelBelow:SetAlpha(255)
				panelBelow:AlphaTo(0, 0.2)
				panelBelow:SetMouseInputEnabled(false)
				panel:SetPos(self:GetWide(), targety)
				panel:MoveTo(targetx, targety, 0.2, 0)
				panel:SetAlpha(0)
				panel:AlphaTo(255, 0.2)
				panel:SetMouseInputEnabled(true)
			end

		end,

		PopPanel = function(self)
			if #self.panelStack == 1 then
				commandCloseMenu()
			else
				local targetx, targety = self:GetContentPos()
				local panel = self.panelStack[#self.panelStack]
				local panelBelow = self.panelStack[#self.panelStack - 1]
				self.panelStack[#self.panelStack] = nil

				panelBelow:SetPos(-panelBelow:GetWide(), targety)
				panelBelow:MoveTo(targetx, targety, 0.2, 0)
				panelBelow:SetAlpha(0)
				panelBelow:AlphaTo(255, 0.2)
				panelBelow:SetMouseInputEnabled(true)
				panel:SetPos(targetx, targety)
				panel:MoveTo(self:GetWide(), targety, 0.2, 0)
				panel:SetAlpha(255)
				panel:AlphaTo(0, 0.2, 0, function()
					panel:Remove()
				end)
				panel:SetMouseInputEnabled(false)
			end
		end,

		NewContent = function(self)
			local wrapper = vgui.Create('DScrollPanel', self)
			wrapper:SetPos(self:GetContentPos())
			wrapper:SetSize(self:GetContentSize())

			local p = vgui.Create('pfpmenu_content', wrapper)
			p:SetWide(wrapper:GetWide())

			self:PushPanel(wrapper)

			return p
		end,

		Paint = function(self, w, h)
			surface.SetDrawColor(40, 40, 40, 255)
			surface.DrawRect(0, 0, w, h)
			surface.SetDrawColor(200, 200, 200, 50)
			surface.DrawOutlinedRect(0, 0, w, h)
		end,
	}, 'EditablePanel')

	vgui.Register('pfpmenu_content', {
		Init = function(self)
			self:SetPadding(10)
		end,
		SetPadding = function(self, num)
			self._padding = num
		end,
		PerformLayout = function(self)
			local w, y = self:GetWide(), 0
			for k,v in ipairs(self:GetChildren()) do
				v:SetPos(0, y)
				v:SetWide(w)
				y = y + v:GetTall() + self._padding
			end
			y = y - self._padding
			self:SetTall(y)
		end,
		Paint = function() end,
		OnChildAdded = function(self, panel)
			panel:SetWide(self:GetWide())
		end,
	})

	vgui.Register('pfpmenu_row', {
		Init = function(self)
			self:SetTall(20)
			self.lerp = 0
			self.tint = Color(220,220,220)
		end,

		SetText = function(self, text)
			return self:AddText(text, 'left')
		end,

		AddText = function(self, text, align)
			local label = Label(text, self)
			label:SetFont('foolproof_16px')
			label:SizeToContents()
			if not align or align == 'center' then
				label:Center()
			elseif align == 'left' then
				label:SetPos(10, 0)
				label:CenterVertical()
			elseif align == 'right' then
				label:SetPos(self:GetWide() - label:GetWide() - 10, 0)
				label:CenterVertical()
			end
			self.label = label
			return label
		end,

		FlashMessage = function(self, text)
			local panel = vgui.Create('DPanel', self)
			panel:SetSize(self:GetSize())
			panel.Paint = function(self, w, h)
				surface.SetDrawColor(0, 0, 0, 220)
				surface.DrawRect(0, 0, w, h)
			end

			local label = Label(text, panel)
			label:SetFont('foolproof_16px')
			label:SizeToContents()
			label:Center()

			panel:AlphaTo(0, 2, 0, function()
				panel:Remove()
			end)
		end,

		SetTint = function(self, tint)
			self.tint = tint
		end,

		OnMouseReleased = function(self)
			if self.DoClick then
				self:DoClick()
			end
		end,

		Paint = function(self, w, h)
			surface.SetDrawColor(self.tint.r, self.tint.g, self.tint.b, 40)
			surface.DrawRect(0, 0, w, h)
			surface.DrawOutlinedRect(0, 0, w, h)
			self.lerp = Lerp(FrameTime() * 40, self.lerp, self:IsHovered() and 1 or 0)

			if self.lerp > 0.01 then
				surface.SetDrawColor(255,255,255, 20 * self.lerp)
				surface.DrawRect(0, 0, w, h)
				surface.SetDrawColor(self.tint.r, self.tint.g, self.tint.b, 200)
				surface.DrawRect(0, 0, 5 * self.lerp, h)
			end
		end,
	})

	-- BOOTSTRAP
	timer.Simple(30, function()
		if not IsValid(LocalPlayer()) or not LocalPlayer().IsSuperAdmin then return end
		if LocalPlayer():IsSuperAdmin() then
			LocalPlayer():ConCommand('pfoolproof check\n')
		end
	end)
end
