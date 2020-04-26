BuloLayer = LibStub("AceAddon-3.0"):NewAddon("BuloLayer", "AceConsole-3.0", "AceEvent-3.0", "AceComm-3.0", "AceTimer-3.0")
BuloLayer.Dialog = LibStub("AceConfigDialog-3.0")
BuloLayer:RegisterChatCommand("lh", "ChatCommand")

BuloLayer.options = {
	name = "|TInterface\\AddOns\\BuloLayer\\Media\\swap:24:24:0:5|t BuloLayer v" .. GetAddOnMetadata("BuloLayer", "Version"),
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
BuloLayer.DEFAULT_PREFIX = "BuloLayer"
BuloLayer.CHAT_PREFIX = "|cFFFF69B4[BuloLayer]|r "
BuloLayer.COMM_VER = 124
BuloLayer.minLayerId = -1
BuloLayer.maxLayerId = -1
BuloLayer.currentLayerId = -1
BuloLayer.foundOldVersion = false
BuloLayer.SendCurrentMinMaxTimer = nil

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
			if BuloLayer.currentLayerId < 0 then
				layerText = "Unknown Layer. Target any NPC or mob to get current layer.\n(layer id: " .. BuloLayer.currentLayerId .. ", min: " .. BuloLayer.minLayerId .. ", max: " .. BuloLayer.maxLayerId .. " )"
			elseif not MinMaxValid(BuloLayer.minLayerId, BuloLayer.maxLayerId) then
				layerText = "Min/max layer IDs are unknown. Need more data from guild to determine current layer\n(but you can still request a layer switch). (layer id: " .. BuloLayer.currentLayerId .. ", min: " .. BuloLayer.minLayerId .. ", max: " .. BuloLayer.maxLayerId .. " )"
			else
				layerText = "Current Layer: " .. GetLayerGuess(BuloLayer.currentLayerId, BuloLayer.minLayerId, BuloLayer.maxLayerId) .. "\n(layer id: " .. BuloLayer.currentLayerId .. ", min: " .. BuloLayer.minLayerId .. ", max: " .. BuloLayer.maxLayerId .. " )"
			end
			GameTooltip:SetOwner(self, "ANCHOR_LEFT")
			GameTooltip:AddLine("|cFFFFFFFFLayer Hopper|r v"..GetAddOnMetadata("BuloLayer", "Version"))
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
	if self.minLayerId < 0 or self.maxLayerId < 0 then
		self:SendCommMessage(self.DEFAULT_PREFIX, BuloLayer.RequestLayerMinMaxPrefix .. "," .. self.COMM_VER .. "," .. self.currentLayerId .. "," .. self.minLayerId .. "," .. self.maxLayerId, "GUILD")
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
	end
	self:SendCommMessage(self.DEFAULT_PREFIX, BuloLayer.RequestLayerSwitchPrefix .. "," .. self.COMM_VER .. "," .. self.currentLayerId .. "," .. self.minLayerId .. "," .. self.maxLayerId, "GUILD")
	print(self.CHAT_PREFIX .. "Requesting layer hop from layer " .. GetLayerGuess(self.currentLayerId, self.minLayerId, self.maxLayerId) .. " to another layer.")
end

function BuloLayer:RequestAllPlayersLayers()
	self:SendCommMessage(self.DEFAULT_PREFIX, BuloLayer.RequestAllPlayersLayersPrefix .. "," .. self.COMM_VER .. "," .. self.currentLayerId .. "," .. self.minLayerId .. "," .. self.maxLayerId, "GUILD")
end

function BuloLayer:OnCommReceived(prefix, msg, distribution, sender)
	if sender ~= UnitName("player") and strlower(prefix) == strlower(self.DEFAULT_PREFIX) then
		local command, ver, layerId, minLayerId, maxLayerId = strsplit(",", msg)
		ver = tonumber(ver)
		layerId = tonumber(layerId)
		minLayerId = tonumber(minLayerId)
		maxLayerId = tonumber(maxLayerId)
		if ver ~= self.COMM_VER then
			if ver > self.COMM_VER and not self.foundOldVersion then
				print(self.CHAT_PREFIX .. "You are running an old version of Layer Hopper, please update from curseforge!")
				self.foundOldVersion = true
			end
			if floor(ver / 10) ~= floor(self.COMM_VER / 10) then
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
				self:SendCommMessage(self.DEFAULT_PREFIX, BuloLayer.SendLayerMinMaxWhisperPrefix .. "," .. self.COMM_VER .. "," .. self.currentLayerId .. "," .. self.minLayerId .. "," .. self.maxLayerId, "WHISPER", sender)
				if minOrMaxUpdated then
					self:UpdateIcon()
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
	if ver < self.COMM_VER then
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
	print(self.CHAT_PREFIX .. sender .. ": " .. layerString .. " - " .. versionString)
end

function BuloLayer:SendCurrentMinMax()
	self:SendCommMessage(self.DEFAULT_PREFIX, BuloLayer.SendLayerMinMaxPrefix .. "," .. self.COMM_VER .. "," .. self.currentLayerId .. "," .. self.minLayerId .. "," .. self.maxLayerId, "GUILD")
	if self.SendCurrentMinMaxTimer then
		self:CancelTimer(self.SendCurrentMinMaxTimer)
		self.SendCurrentMinMaxTimer = nil
	end
end

function BuloLayer:ChatCommand(input)
	input = strtrim(input);
	if input == "config" then
		self:ToggleConfigWindow()
	elseif input == "hop" then
		self:RequestLayerHop()
	elseif input == "list" then
		self:RequestAllPlayersLayers()
	else
		print("/lh config - Open/close configuration window\n" ..
			"/lh hop - Request a layer hop\n" ..
			"/lh list - List layers and versions for all guildies")
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
	if IsInInstance() then
		return
	end
	self.currentZoneId = C_Map.GetBestMapForUnit("player")
	local guid = UnitGUID(unit)
	if guid ~= nil then
		local unittype, zero, server_id, instance_id, zone_uid, npc_id, spawn_uid = strsplit("-", guid);
		if UnitExists(unit) and not UnitIsPlayer(unit) and unittype ~= "Pet" and not IsGuidOwned(guid) then
			local layerId = -1
			local _,_,_,_,i = strsplit("-", guid)
			if i then
				layerId = tonumber(i)
			end
			if layerId >= 0 then
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
	if min >= 0 and (self.minLayerId < 0 or min < self.minLayerId) then
		self.minLayerId = min
		return true
	end
	return false
end

function BuloLayer:UpdateMax(max)
	if max >= 0 and (self.maxLayerId < 0 or max > self.maxLayerId) then
		self.maxLayerId = max
		return true
	end
	return false
end

local tip = CreateFrame('GameTooltip', 'GuardianOwnerTooltip', nil, 'GameTooltipTemplate')

function IsGuidOwned(guid)
	tip:SetOwner(WorldFrame, 'ANCHOR_NONE')
	tip:SetHyperlink('unit:' .. guid or '')
	local text = GuardianOwnerTooltipTextLeft2
	local subtitle = text and text:GetText() or ''
	return strfind(subtitle, "'s Companion")
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

function GetVersionString(ver)
	if ver >= 10 then
		return GetVersionString(floor(ver/10)) .. "." .. tostring(ver % 10)
	else
		return "v" .. tostring(ver)
	end
end

BuloLayer:RegisterEvent("PLAYER_TARGET_CHANGED")
BuloLayer:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
BuloLayer:RegisterEvent("NAME_PLATE_UNIT_ADDED")
BuloLayer:RegisterEvent("GROUP_JOINED")
BuloLayer:RegisterEvent("PLAYER_ENTERING_WORLD")
BuloLayer:RegisterComm(BuloLayer.DEFAULT_PREFIX)
