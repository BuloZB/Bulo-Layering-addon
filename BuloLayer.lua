BuloLayer = LibStub("AceAddon-3.0"):NewAddon("BuloLayer", "AceConsole-3.0", "AceEvent-3.0", "AceComm-3.0", "AceTimer-3.0")
BuloLayer.Dialog = LibStub("AceConfigDialog-3.0")
BuloLayer:RegisterChatCommand("lh", "ChatCommand")
BuloLayer.VERSION = 141

function GetVersionString(ver)
	if ver >= 10 then
		return GetVersionString(floor(ver/10)) .. "." .. tostring(ver % 10)
	else
		return "v" .. tostring(ver)
	end
end

BuloLayer.options = {
	name = "|TInterface\\AddOns\\BuloLayer\\Media\\swap:24:24:0:5|t BuloLayer " .. GetVersionString(BuloLayer.VERSION),
	handler = BuloLayer,
	type = 'group',
	args = {
		desc = {
			type = "description",
			name = "|CffDEDE42Layer Hopper Config (You can type /lh config to open this).\n"
					.. "Auto inviting will be disabled automatically if inside an instance or battleground and when in a battleground queue.\n",
			fontSize = "medium",
			order = 1,
		},
		autoinvite = {
			type = "toggle",
			name = "Auto Invite",
			desc = "Enable auto invites for layer switch requests in the guild.",
			order = 2,
			get = "getAutoInvite",
			set = "setAutoInvite",
		},
	},
}

BuloLayer.optionDefaults = {
	global = {
		autoinvite = true,
	},
}

function BuloLayer:setAutoInvite(info, value)
	self.db.global.autoinvite = value;
end

function BuloLayer:getAutoInvite(info)
	return self.db.global.autoinvite;
end

BuloLayer.RequestLayerSwitchPrefix = "LH_rls"
BuloLayer.RequestLayerMinMaxPrefix = "LH_rlmm"
BuloLayer.RequestAllPlayersLayersPrefix = "LH_rapl"
BuloLayer.SendLayerMinMaxPrefix = "LH_slmm"
BuloLayer.SendLayerMinMaxWhisperPrefix = "LH_slmmw"
BuloLayer.SendResetLayerDataPrefix = "LH_srld"
BuloLayer.DEFAULT_PREFIX = "BuloLayer"
BuloLayer.CHAT_PREFIX = "|cFFFF69B4[BuloLayer]|r "
BuloLayer.minLayerId = -1
BuloLayer.maxLayerId = -1
BuloLayer.currentLayerId = -1
BuloLayer.foundOldVersion = false
BuloLayer.SendCurrentMinMaxTimer = nil
BuloLayer.paused = false

function BuloLayer:OnInitialize()
	self.BuloLayerLauncher = LibStub("LibDataBroker-1.1"):NewDataObject("BuloLayer", {
		type = "launcher",
		text = "BuloLayer",
		icon = "Interface/AddOns/BuloLayer/Media/swap",
		OnClick = function(self, button)
			if button == "LeftButton" then
				BuloLayer:RequestLayerHop()
			elseif button == "RightButton" then
				BuloLayer:ToggleConfigWindow()
			end
		end,
		OnEnter = function(self)
			local layerText = ""
			if BuloLayer.paused then
				layerText = "Resetting layer data for the guild. Should only take a few more seconds..."
			elseif BuloLayer.currentLayerId < 0 then
				layerText = "Unknown Layer. Target any NPC or mob to get current layer.\n(layer id: " .. BuloLayer.currentLayerId .. ", min: " .. BuloLayer.minLayerId .. ", max: " .. BuloLayer.maxLayerId .. " )"
			elseif not MinMaxValid(BuloLayer.minLayerId, BuloLayer.maxLayerId) then
				layerText = "Min/max layer IDs are unknown. Need more data from guild to determine current layer\n(but you can still request a layer switch). (layer id: " .. BuloLayer.currentLayerId .. ", min: " .. BuloLayer.minLayerId .. ", max: " .. BuloLayer.maxLayerId .. " )"
			else
				layerText = "Current Layer: " .. GetLayerGuess(BuloLayer.currentLayerId, BuloLayer.minLayerId, BuloLayer.maxLayerId) .. "\n(layer id: " .. BuloLayer.currentLayerId .. ", min: " .. BuloLayer.minLayerId .. ", max: " .. BuloLayer.maxLayerId .. " )"
			end
			GameTooltip:SetOwner(self, "ANCHOR_LEFT")
			GameTooltip:AddLine("|cFFFFFFFFLayer Hopper|r " .. GetVersionString(BuloLayer.VERSION))
			GameTooltip:AddLine(layerText)
			GameTooltip:AddLine("Left click to request a layer hop.")
			GameTooltip:AddLine("Right click to access Layer Hopper settings.")
			GameTooltip:AddLine("/lh to see other options")
			GameTooltip:Show()
		end,
		OnLeave = function(self)
			GameTooltip:Hide()
		end
	})
	LibStub("LibDBIcon-1.0"):Register("BuloLayer", self.BuloLayerLauncher, BuloLayerOptions)

	self.db = LibStub("AceDB-3.0"):New("BuloLayerOptions", BuloLayer.optionDefaults, "Default");
	LibStub("AceConfig-3.0"):RegisterOptionsTable("BuloLayer", BuloLayer.options);
	self.BuloLayerOptions = LibStub("AceConfigDialog-3.0"):AddToBlizOptions("BuloLayer", "BuloLayer");
end

function BuloLayer:PLAYER_TARGET_CHANGED()
	self:UpdateLayerFromUnit("target")
end

function BuloLayer:UPDATE_MOUSEOVER_UNIT()
	self:UpdateLayerFromUnit("mouseover")
end

function BuloLayer:NAME_PLATE_UNIT_ADDED(unit)
	self:UpdateLayerFromUnit(unit)
end

function BuloLayer:GROUP_JOINED()
	if not UnitIsGroupLeader("player") then
		self.currentLayerId = -1
		self:UpdateIcon()
	end
end

function BuloLayer:PLAYER_ENTERING_WORLD()
	self.currentLayerId = -1
	self:UpdateIcon()
	if not self.paused and (self.minLayerId < 0 or self.maxLayerId < 0) then
		self:SendCommMessage(self.DEFAULT_PREFIX, BuloLayer.RequestLayerMinMaxPrefix .. "," .. self.VERSION .. "," .. self.currentLayerId .. "," .. self.minLayerId .. "," .. self.maxLayerId, "GUILD")
	end
end

function BuloLayer:RequestLayerHop()
	if IsInGroup() then
		print(self.CHAT_PREFIX .. "Can't request layer hop while in a group.")
		return
	elseif self.currentLayerId < 0 then
		print(self.CHAT_PREFIX .. "Can't request layer hop until your layer is known. Target any NPC or mob to get current layer.")
		return
	elseif IsInInstance() then
		print(self.CHAT_PREFIX .. "Can't request layer hop while in an instance or battleground.")
		return
	elseif self.paused then
		print(self.CHAT_PREFIX .. "Resetting layer data for the guild. Should only take a few more seconds...")
		return
	end
	self:SendCommMessage(self.DEFAULT_PREFIX, BuloLayer.RequestLayerSwitchPrefix .. "," .. self.VERSION .. "," .. self.currentLayerId .. "," .. self.minLayerId .. "," .. self.maxLayerId, "GUILD")
	print(self.CHAT_PREFIX .. "Requesting layer hop from layer " .. GetLayerGuess(self.currentLayerId, self.minLayerId, self.maxLayerId) .. " to another layer.")
end

function BuloLayer:RequestAllPlayersLayers()
	self:SendCommMessage(self.DEFAULT_PREFIX, BuloLayer.RequestAllPlayersLayersPrefix .. "," .. self.VERSION .. "," .. self.currentLayerId .. "," .. self.minLayerId .. "," .. self.maxLayerId, "GUILD")
end

function BuloLayer:ResetLayerData()
	local _, _, guildRankIndex = GetGuildInfo("player");
	if guildRankIndex <= 3 then
		self.currentLayerId = -1
		self.minLayerId = -1
		self.maxLayerId = -1
		self.paused = true
		print(self.CHAT_PREFIX .. "Resetting layer data in the guild...")
		self:SendCommMessage(self.DEFAULT_PREFIX, BuloLayer.SendResetLayerDataPrefix .. "," .. self.VERSION .. ",-1,-1,-1", "GUILD")
		self:ScheduleTimer("UnPause", 3 + random() * 3)
		self:UpdateIcon()
	else
		print(self.CHAT_PREFIX .. "Can't request layer data reset unless you are class lead or higher rank.")
	end
end

function BuloLayer:OnCommReceived(prefix, msg, distribution, sender)
	if sender ~= UnitName("player") and strlower(prefix) == strlower(self.DEFAULT_PREFIX) and not self.paused then
		local command, ver, layerId, minLayerId, maxLayerId = strsplit(",", msg)
		ver = tonumber(ver)
		layerId = tonumber(layerId)
		minLayerId = tonumber(minLayerId)
		maxLayerId = tonumber(maxLayerId)
		if ver ~= self.VERSION then
			if ver > self.VERSION and not self.foundOldVersion then
				print(self.CHAT_PREFIX .. "You are running an old version of Layer Hopper, please update from curseforge!")
				self.foundOldVersion = true
			end
			if floor(ver / 10) ~= floor(self.VERSION / 10) then
				return
			end
		end
		if distribution == "GUILD" then
			if command == BuloLayer.RequestLayerSwitchPrefix then
				local minOrMaxUpdated = self:UpdateMinMax(minLayerId, maxLayerId)
				local layerGuess = GetLayerGuess(layerId, self.minLayerId, self.maxLayerId)
				local myLayerGuess = GetLayerGuess(self.currentLayerId, self.minLayerId, self.maxLayerId)
				if layerGuess > 0 and myLayerGuess > 0 and layerGuess ~= myLayerGuess and self.db.global.autoinvite and not IsInBgQueue() and not IsInInstance() and CanInvite() then
					InviteUnit(sender)
				end
				if minOrMaxUpdated then
					self:UpdateIcon()
				end
			elseif command == BuloLayer.RequestLayerMinMaxPrefix then
				local minOrMaxUpdated = self:UpdateMinMax(minLayerId, maxLayerId)
				if not self.SendCurrentMinMaxTimer and not (self.minLayerId == minLayerId and self.maxLayerId == maxLayerId) and self.minLayerId >= 0 and self.maxLayerId >= 0 then
					self.SendCurrentMinMaxTimer = self:ScheduleTimer("SendCurrentMinMax", random() * 5)
				end
				if minOrMaxUpdated then
					self:UpdateIcon()
				end
			elseif command == BuloLayer.SendLayerMinMaxPrefix then
				local minUpdated = self:UpdateMin(minLayerId)
				local maxUpdated = self:UpdateMax(maxLayerId)
				local minAndMaxUpdated = minUpdated and maxUpdated
				local minOrMaxUpdated = minUpdated or maxUpdated
				if self.SendCurrentMinMaxTimer and (minAndMaxUpdated or (minUpdated and self.maxLayerId == maxLayerId) or (maxUpdated and self.minLayerId == minLayerId) or (self.minLayerId == minLayerId and self.maxLayerId == maxLayerId)) then
					self:CancelTimer(self.SendCurrentMinMaxTimer)
					self.SendCurrentMinMaxTimer = nil
				end
				if minOrMaxUpdated then
					self:UpdateIcon()
				end
			elseif command == BuloLayer.RequestAllPlayersLayersPrefix then
				local minOrMaxUpdated = self:UpdateMinMax(minLayerId, maxLayerId)
				self:SendCommMessage(self.DEFAULT_PREFIX, BuloLayer.SendLayerMinMaxWhisperPrefix .. "," .. self.VERSION .. "," .. self.currentLayerId .. "," .. self.minLayerId .. "," .. self.maxLayerId, "WHISPER", sender)
				if minOrMaxUpdated then
					self:UpdateIcon()
				end
			elseif command == BuloLayer.SendResetLayerDataPrefix then
				for i=1,GetNumGuildMembers() do
					local nameWithRealm, rank, rankIndex = GetGuildRosterInfo(i)
					local name, realm = strsplit("-", nameWithRealm)
					if name == sender and rankIndex <= 3 then
						self.currentLayerId = -1
						self.minLayerId = -1
						self.maxLayerId = -1
						self.paused = true
						print(self.CHAT_PREFIX .. sender .. " requested a reset of layer data for the guild.")
						self:ScheduleTimer("UnPause", 3 + random() * 3)
						self:UpdateIcon()
						return
					end
				end
			end
		elseif distribution == "WHISPER" then
			if command == BuloLayer.SendLayerMinMaxWhisperPrefix then
				local minOrMaxUpdated = self:UpdateMinMax(minLayerId, maxLayerId)
				self:PrintPlayerLayerWithVersion(layerId, ver, sender)
			end
		end
	end
end

function BuloLayer:PrintPlayerLayerWithVersion(layerId, ver, sender)
	local layerGuess = GetLayerGuess(layerId, self.minLayerId, self.maxLayerId)
	local myLayerGuess = GetLayerGuess(self.currentLayerId, self.minLayerId, self.maxLayerId)
	local versionString = ""
	if ver < self.VERSION then
		versionString = "|cFFC21807" .. GetVersionString(ver) .. "|r"
	else
		versionString = GetVersionString(ver)
	end
	local layerString = ""
	if layerGuess < 0 then
		layerString = "layer unknown"
	elseif myLayerGuess > 0 and layerGuess > 0 and myLayerGuess ~= layerGuess then
		layerString = "|cFF00A86Blayer " .. tostring(layerGuess) .. "|r"
	else
		layerString = "layer " .. tostring(layerGuess)
	end
	print(self.CHAT_PREFIX .. sender .. ": " .. layerString .. " - " .. versionString .. " layer id: " .. layerId)
end

function BuloLayer:SendCurrentMinMax()
	self:SendCommMessage(self.DEFAULT_PREFIX, BuloLayer.SendLayerMinMaxPrefix .. "," .. self.VERSION .. "," .. self.currentLayerId .. "," .. self.minLayerId .. "," .. self.maxLayerId, "GUILD")
	if self.SendCurrentMinMaxTimer then
		self:CancelTimer(self.SendCurrentMinMaxTimer)
		self.SendCurrentMinMaxTimer = nil
	end
end

function BuloLayer:UnPause()
	self.paused = false
end

function BuloLayer:ChatCommand(input)
	input = strtrim(input);
	if input == "config" then
		self:ToggleConfigWindow()
	elseif input == "hop" then
		self:RequestLayerHop()
	elseif input == "list" then
		self:RequestAllPlayersLayers()
	elseif input == "reset" then
		self:ResetLayerData()
	else
		print("/lh config - Open/close configuration window\n" ..
			"/lh hop - Request a layer hop\n" ..
			"/lh list - List layers and versions for all guildies\n" ..
			"/lh reset - Reset layer data for all guildies. (can only be done by class lead rank or above)")
	end
end

function BuloLayer:ToggleConfigWindow()
	if BuloLayer.Dialog.OpenFrames["BuloLayer"] then
		BuloLayer.Dialog:Close("BuloLayer")
	else
		BuloLayer.Dialog:Open("BuloLayer")
	end
end

function BuloLayer:UpdateLayerFromUnit(unit)
	if IsInInstance() or self.paused then
		return
	end
	local guid = UnitGUID(unit)
	if guid ~= nil then
		local unittype, zero, server_id, instance_id, zone_uid, npc_id, spawn_uid = strsplit("-", guid);
		if UnitExists(unit) and not UnitIsPlayer(unit) and unittype ~= "Pet" and UnitLevel(unit) ~= 1 then
			local layerId = -1
			local _,_,_,_,i = strsplit("-", guid)
			if i then
				layerId = tonumber(i)
			end
			if self:IsLayerIdValid(layerId) then
				self.currentLayerId = layerId
				local minOrMaxUpdated = self:UpdateMinMax(self.currentLayerId, self.currentLayerId)
				self:UpdateIcon()
				if minOrMaxUpdated and self.minLayerId >= 0 and self.maxLayerId >= 0 then
					self:SendCurrentMinMax()
				end
			end
		end
	end
end

function BuloLayer:UpdateIcon()
	local layer = GetLayerGuess(self.currentLayerId, self.minLayerId, self.maxLayerId)
	if layer < 0 then
		BuloLayer.BuloLayerLauncher.icon = "Interface/AddOns/BuloLayer/Media/swap"
	else
		BuloLayer.BuloLayerLauncher.icon = "Interface/AddOns/BuloLayer/Media/layer" .. layer
	end
end

function BuloLayer:UpdateMinMax(min, max)
	return self:UpdateMin(min) or self:UpdateMax(max)
end

function BuloLayer:UpdateMin(min)
	if self:IsLayerIdValid(min) and (self.minLayerId < 0 or min < self.minLayerId) then
		self.minLayerId = min
		return true
	end
	return false
end

function BuloLayer:UpdateMax(max)
	if self:IsLayerIdValid(max) and (self.maxLayerId < 0 or max > self.maxLayerId) then
		self.maxLayerId = max
		return true
	end
	return false
end

function BuloLayer:IsLayerIdValid(layerId)
	--Will turn this back on if needed
	--if self.minLayerId >= 0 and self.maxLayerId >= 0 and self.maxLayerId - self.minLayerId > 100 and ((layerId >= 0 and layerId < self.minLayerId and self.minLayerId - layerId > 200) or (layerId >= 0 and layerId > self.maxLayerId and layerId - self.maxLayerId > 200)) then
	--	return false
	--end
	return layerId >= 0
end

function GetLayerGuess(layerId, minLayerId, maxLayerId)
	if layerId < 0 or not MinMaxValid(minLayerId, maxLayerId) then
		return -1
	end
	local layerGuess = 1
	local midLayerId = (minLayerId + maxLayerId) / 2
	if layerId > midLayerId then
		layerGuess = 2
	end
	return layerGuess
end

function MinMaxValid(minLayerId, maxLayerId)
	return minLayerId >= 0 and maxLayerId >= 0 and maxLayerId - minLayerId > 50 -- this is a guess based on number of zones in classic https://wow.gamepedia.com/UiMapID/Classic
end

function IsInBgQueue()
	local status, mapName, instanceID, minlevel, maxlevel;
	for i = 1, MAX_BATTLEFIELD_QUEUES do
		status, mapName, instanceID, minlevel, maxlevel, teamSize = GetBattlefieldStatus(i);
		if status == "queued" or status == "confirm" then
			return true
		end
	end
	return false
end

function CanInvite()
	return not IsInGroup() or (IsInGroup() and (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")))
end

BuloLayer:RegisterEvent("PLAYER_TARGET_CHANGED")
BuloLayer:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
BuloLayer:RegisterEvent("NAME_PLATE_UNIT_ADDED")
BuloLayer:RegisterEvent("GROUP_JOINED")
BuloLayer:RegisterEvent("PLAYER_ENTERING_WORLD")
BuloLayer:RegisterComm(BuloLayer.DEFAULT_PREFIX)
