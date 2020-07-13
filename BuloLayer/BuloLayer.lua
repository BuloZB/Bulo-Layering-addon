BuloLayer = LibStub("AceAddon-3.0"):NewAddon("BuloLayer", "AceConsole-3.0", "AceEvent-3.0", "AceComm-3.0", "AceTimer-3.0")
BuloLayer.Dialog = LibStub("AceConfigDialog-3.0")
BuloLayer:RegisterChatCommand("lh", "ChatCommand")
BuloLayer.VERSION = 156

local L = LibStub("AceLocale-3.0"):GetLocale("BuloLayer")

function GetVersionString(ver)
	if ver >= 10 then
		return GetVersionString(floor(ver/10)) .. "." .. tostring(ver % 10)
	else
		return "v" .. tostring(ver)
	end
end

BuloLayer.options = {
	name = "|TInterface\\AddOns\\BuloLayer\\Media\\swap:24:24:0:5|t " .. L["Layer Hopper"] .. " " .. GetVersionString(BuloLayer.VERSION),
	handler = BuloLayer,
	type = 'group',
	args = {
		desc = {
			type = "description",
			name = "|CffDEDE42" .. L["optionsDesc"],
			fontSize = "medium",
			order = 1,
		},
		autoinvite = {
			type = "toggle",
			name = L["Auto Invite"],
			desc = L["autoInviteDesc"],
			order = 2,
			get = "getAutoInvite",
			set = "setAutoInvite",
		},
		minimap = {
			type = "toggle",
			name = L["Minimap Button"],
			desc = L["minimapDesc"],
			order = 3,
			get = "getMinimap",
			set = "setMinimap",
		},
	},
}

BuloLayer.optionDefaults = {
	global = {
		autoinvite = true,
		hide = false,
	},
}

function BuloLayer:setAutoInvite(info, value)
	self.db.global.autoinvite = value;
end

function BuloLayer:getAutoInvite(info)
	return self.db.global.autoinvite;
end

function BuloLayer:setMinimap(info, value)
	self.db.global.hide = not value;
	if self.db.global.hide then
		self.icon:Hide("BuloLayer")
	else
		self.icon:Show("BuloLayer")
	end
end

function BuloLayer:getMinimap(info)
	return not self.db.global.hide;
end

BuloLayer.RequestLayerSwitchPrefix = "LH_rls"
BuloLayer.RequestLayerMinMaxPrefix = "LH_rlmm"
BuloLayer.RequestAllPlayersLayersPrefix = "LH_rapl"
BuloLayer.SendLayerMinMaxPrefix = "LH_slmm"
BuloLayer.SendLayerMinMaxWhisperPrefix = "LH_slmmw"
BuloLayer.SendResetLayerDataPrefix = "LH_srld"
BuloLayer.DEFAULT_PREFIX = "BuloLayer"
BuloLayer.CHAT_PREFIX = format("|cFFFF69B4[%s]|r ", L["BuloLayer"])
BuloLayer.minLayerId = -1
BuloLayer.maxLayerId = -1
BuloLayer.currentLayerId = -1
BuloLayer.foundOldVersion = false
BuloLayer.SendCurrentMinMaxTimer = nil
BuloLayer.paused = false
BuloLayer.layerIdRange = 100 -- this is a guess based on anecdotal data of max layer id spread for a single layer

function BuloLayer:OnInitialize()
	self.BuloLayerLauncher = LibStub("LibDataBroker-1.1"):NewDataObject("BuloLayer", {
		type = "launcher",
		text = L["Layer Hopper"],
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
				layerText = L["paused"]
			elseif BuloLayer.currentLayerId < 0 then
				layerText = format(L["unknownLayer"],
						BuloLayer.currentLayerId, BuloLayer.minLayerId, BuloLayer.maxLayerId)
			elseif not BuloLayer:MinMaxValid(BuloLayer.minLayerId, BuloLayer.maxLayerId) then
				if BuloLayer.minLayerId < 0 or BuloLayer.maxLayerId < 0 then
					layerText = L["minMaxUnknown"]
				else
					layerText = L["rangeTooSmall"]
				end
				layerText = layerText .. "\n" ..
						format(L["needMoreData"], BuloLayer.currentLayerId, BuloLayer.minLayerId, BuloLayer.maxLayerId)
			else
				layerText = format(L["currentLayer"],
						BuloLayer:GetLayerGuess(BuloLayer.currentLayerId, BuloLayer.minLayerId, BuloLayer.maxLayerId),
						BuloLayer.currentLayerId, BuloLayer.minLayerId, BuloLayer.maxLayerId)
			end
			GameTooltip:SetOwner(self, "ANCHOR_LEFT")
			GameTooltip:AddLine(format("|cFFFFFFFF%s|r %s", L["Layer Hopper"], GetVersionString(BuloLayer.VERSION)))
			GameTooltip:AddLine(layerText)
			GameTooltip:AddLine(L["minimapLeftClickAction"])
			GameTooltip:AddLine(L["minimapRightClickAction"])
			GameTooltip:AddLine(L["minimapOtherOptions"])
			GameTooltip:Show()
		end,
		OnLeave = function(self)
			GameTooltip:Hide()
		end
	})

	self.db = LibStub("AceDB-3.0"):New("BuloLayerOptions", BuloLayer.optionDefaults, "Default");
	LibStub("AceConfig-3.0"):RegisterOptionsTable("BuloLayer", BuloLayer.options);
	self.BuloLayerOptions = LibStub("AceConfigDialog-3.0"):AddToBlizOptions("BuloLayer", L["Layer Hopper"]);

	self.icon = LibStub("LibDBIcon-1.0")
	self.icon:Register("BuloLayer", self.BuloLayerLauncher, self.db.global)
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
		self:SendMessage(BuloLayer.RequestLayerMinMaxPrefix .. "," .. self.VERSION .. "," .. self.currentLayerId .. "," .. self.minLayerId .. "," .. self.maxLayerId, "GUILD")
	end
end

function BuloLayer:SendMessage(message, distribution, target)
	if distribution == "GUILD" and not IsInGuild() then
		return
	end
	self:SendCommMessage(self.DEFAULT_PREFIX, message, distribution, target)
end

function BuloLayer:RequestLayerHop()
	if not IsInGuild() then
		print(self.CHAT_PREFIX .. L["noGuildErr"])
		return
	elseif IsInGroup() then
		print(self.CHAT_PREFIX .. L["inGroupErr"])
		return
	elseif self.currentLayerId < 0 then
		print(self.CHAT_PREFIX .. L["unknownLayerErr"])
		return
	elseif IsInInstance() then
		print(self.CHAT_PREFIX .. L["inInstanceErr"])
		return
	elseif self.paused then
		print(self.CHAT_PREFIX .. L["paused"])
		return
	end
	self:SendMessage(BuloLayer.RequestLayerSwitchPrefix .. "," .. self.VERSION .. "," .. self.currentLayerId .. "," .. self.minLayerId .. "," .. self.maxLayerId, "GUILD")
	print(self.CHAT_PREFIX .. format(L["requestingHop"], self:GetLayerGuess(self.currentLayerId, self.minLayerId, self.maxLayerId)))
end

function BuloLayer:RequestAllPlayersLayers()
	self:SendMessage(BuloLayer.RequestAllPlayersLayersPrefix .. "," .. self.VERSION .. "," .. self.currentLayerId .. "," .. self.minLayerId .. "," .. self.maxLayerId, "GUILD")
end

function BuloLayer:ResetLayerData()
	if not IsInGuild() then
		return
	end
	local _, _, guildRankIndex = GetGuildInfo("player");
	if guildRankIndex <= 3 then
		self.currentLayerId = -1
		self.minLayerId = -1
		self.maxLayerId = -1
		self.paused = true
		print(self.CHAT_PREFIX .. L["resettingLayerData"])
		self:SendMessage(BuloLayer.SendResetLayerDataPrefix .. "," .. self.VERSION .. ",-1,-1,-1", "GUILD")
		self:ScheduleTimer("UnPause", 3 + random() * 3)
		self:UpdateIcon()
	else
		print(self.CHAT_PREFIX .. L["rankTooLow"])
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
				print(self.CHAT_PREFIX .. L["oldVersionErr"])
				self.foundOldVersion = true
			end
			if floor(ver / 10) ~= floor(self.VERSION / 10) then
				return
			end
		end
		if distribution == "GUILD" then
			if command == BuloLayer.RequestLayerSwitchPrefix then
				local minOrMaxUpdated = self:UpdateMinMax(minLayerId, maxLayerId)
				local layerGuess = self:GetLayerGuess(layerId, self.minLayerId, self.maxLayerId)
				local myLayerGuess = self:GetLayerGuess(self.currentLayerId, self.minLayerId, self.maxLayerId)
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
				self:SendMessage(BuloLayer.SendLayerMinMaxWhisperPrefix .. "," .. self.VERSION .. "," .. self.currentLayerId .. "," .. self.minLayerId .. "," .. self.maxLayerId, "WHISPER", sender)
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
						print(self.CHAT_PREFIX .. format(L["playerRequestedLayerReset"], sender))
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
	local layerGuess = self:GetLayerGuess(layerId, self.minLayerId, self.maxLayerId)
	local myLayerGuess = self:GetLayerGuess(self.currentLayerId, self.minLayerId, self.maxLayerId)
	local versionString = ""
	if ver < self.VERSION then
		versionString = "|cFFC21807" .. GetVersionString(ver) .. "|r"
	else
		versionString = GetVersionString(ver)
	end
	local layerString = ""
	if layerGuess < 0 then
		layerString = L["layer unknown"]
	elseif myLayerGuess > 0 and layerGuess > 0 and myLayerGuess ~= layerGuess then
		layerString = "|cFF00A86B" .. format(L["layer %s"], tostring(layerGuess)) .. "|r"
	else
		layerString = format(L["layer %s"], tostring(layerGuess))
	end
	print(self.CHAT_PREFIX .. format(L["printPlayerLayer"], sender, layerString, versionString, layerId))
end

function BuloLayer:SendCurrentMinMax()
	self:SendMessage(BuloLayer.SendLayerMinMaxPrefix .. "," .. self.VERSION .. "," .. self.currentLayerId .. "," .. self.minLayerId .. "," .. self.maxLayerId, "GUILD")
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
	elseif input == "mmb" then
		local minimap = not self:getMinimap()
		self:setMinimap(nil, minimap)
		if minimap then
			print(self.CHAT_PREFIX .. L["minimapShown"])
		else
			print(self.CHAT_PREFIX .. L["minimapHidden"])
		end
	else
		print(format("/lh config - %s\n" ..
				"/lh hop - %s\n" ..
				"/lh list - %s\n" ..
				"/lh reset - %s\n" ..
				"/lh mmb - %s",
				L["configConsole"],
				L["layerHopConsole"],
				L["listLayersConsole"],
				L["resetLayersConsole"],
				L["toggleMinimapConsole"]))
	end
end

function BuloLayer:ToggleConfigWindow()
	if BuloLayer.Dialog.OpenFrames["BuloLayer"] then
		BuloLayer.Dialog:Close("BuloLayer")
	else
		BuloLayer.Dialog:Open("BuloLayer")
	end
end

local blacklistedNpcIds = {
	"2671",  -- Mechanical Squirrel
	"14444", -- Orcish Orphan
	"14878", -- Jubling
	"15429", -- Disgusting Oozeling
	"15706", -- Winter Reindeer
}

function BuloLayer:IsBlacklistedNpcId(npc_id)
	for _, blacklistedId in pairs(blacklistedNpcIds) do
		if npc_id == blacklistedId then
			return true
		end
	end
	return false
end

function BuloLayer:UpdateLayerFromUnit(unit)
	if IsInInstance() or self.paused then
		return
	end
	local guid = UnitGUID(unit)
	local unitName, _ = UnitName(unit)
	if guid ~= nil then
		local unittype, zero, server_id, instance_id, zone_uid, npc_id, spawn_uid = strsplit("-", guid);
		if UnitExists(unit) and not UnitIsPlayer(unit) and unittype ~= "Pet" and UnitLevel(unit) ~= 1 and not self:IsBlacklistedNpcId(npc_id) then
			local layerId = -1
			if zone_uid then
				layerId = tonumber(zone_uid)
			end
			if layerId >= 0 and not self:IsLayerIdValid(layerId) then
				local errColorMsg = "|cFFC21807%s|r"
				print(self.CHAT_PREFIX .. format(errColorMsg, L["mobErrTitle"]))
				print(self.CHAT_PREFIX .. format(errColorMsg, format(L["mobErrName"], tostring(unitName))))
				print(self.CHAT_PREFIX .. format(errColorMsg, format(L["mobErrGUID"], tostring(guid))))
				print(self.CHAT_PREFIX .. format(errColorMsg, format(L["mobErrZone"], tostring(GetSubZoneText()) .. ", " .. tostring(GetZoneText()))))
				print(self.CHAT_PREFIX .. format(errColorMsg, L["mobErrGithub"]))
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
	local layer = self:GetLayerGuess(self.currentLayerId, self.minLayerId, self.maxLayerId)
	if layer < 0 then
		self.BuloLayerLauncher.icon = "Interface/AddOns/BuloLayer/Media/swap"
	else
		self.BuloLayerLauncher.icon = "Interface/AddOns/BuloLayer/Media/layer" .. layer
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
	if self.minLayerId >= 0 and self.maxLayerId >= 0 and self.maxLayerId - self.minLayerId > self.layerIdRange and layerId >= 0 and ((layerId < self.minLayerId and self.minLayerId - layerId > self.layerIdRange * 2) or (layerId > self.maxLayerId and layerId - self.maxLayerId > self.layerIdRange * 2)) then
		return false
	end
	return layerId >= 0
end

function BuloLayer:GetLayerGuess(layerId, minLayerId, maxLayerId)
	if layerId < 0 or not self:MinMaxValid(minLayerId, maxLayerId) then
		return -1
	end
	local layerGuess = 1
	local midLayerId = (minLayerId + maxLayerId) / 2
	if layerId > midLayerId then
		layerGuess = 2
	end
	return layerGuess
end

function BuloLayer:MinMaxValid(minLayerId, maxLayerId)
	return minLayerId >= 0 and maxLayerId >= 0 and maxLayerId - minLayerId > self.layerIdRange
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
