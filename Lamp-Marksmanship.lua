local function MyRoutine()
	local Author = 'Lamp - Marksmanship Hunter'
	local SpecID = 254

	-- Addon
	local Lib = LibStub("AceAddon-3.0"):GetAddon(Z_AddonName)
	local MainAddon = MainAddon
	-- HeroDBC
	local DBC = HeroDBC.DBC
	-- HeroLib
	local HL = HeroLibEx
	local Cache = HeroCache
	---@type Unit
	local Unit = HL.Unit
	---@type Unit
	local Player = Unit.Player
	---@type Unit
	local Target = Unit.Target
	---@type Pet
	local Pet = Unit.Pet
	---@type Spell
	local Spell = HL.Spell
	local Item = HL.Item
	local Cast = MainAddon.Cast
	local CastTargetIf = MainAddon.CastTargetIf
	local SmartAoE = MainAddon.SmartAoE
	local AoEON = MainAddon.AoEON
	local CDsON = MainAddon.CDsON

	-- Spells and Items (Marksmanship)
	local S = Spell.Hunter.Marksmanship
	local I = Item.Hunter.Marksmanship

	-- Exclude list for on-use items (safe default)
	local OnUseExcludes = {}

	-- Basic GUI config placeholder (keep minimal)
	local color = '65b346'
	local Config = {
		key = 'Lamp_MS_Config',
		title = 'Hunter - Marksmanship',
		subtitle = 'Lamp Custom',
		width = 400,
		height = 300,
		profiles = true,
		config = {
			{ type = 'header', text = 'Defensives', color = color },
			{ type = 'checkspin', text = ' Exhilaration', key = 'exhilaration', icon = S.Exhilaration:ID(), min = 1, max = 100, default_spin = 45, default_check = true },
			{ type = 'checkspin', text = ' Aspect of the Turtle', key = 'turtle', icon = Spell.Hunter.Commons.AspectoftheTurtle:ID(), min = 1, max = 100, default_spin = 20, default_check = true },
		}
	}
	MainAddon.SetCustomConfig(Author, SpecID, Config)

	-- State
	local BossFightRemains = 11111
	local FightRemains = 11111
	local Enemies10y = {}
	local ActiveEnemies10 = 1
	local TargetInRange = false

	-- GUI reads/writes Auratimers core toggles
	local function IsOnEnabled()
		return MainAddon.MasterON()
	end
	local function AoEEnabled()
		return AoEON()
	end
	local function CDsEnabled()
		return CDsON()
	end

	-- Trackers (Pshots/Tshots)
	local Pshots = false
	local Tshots = false
	local PshotsLastChange = 0
	local TshotsLastChange = 0
	local function SetPshots(value)
		if Pshots ~= value then
			Pshots = value
			PshotsLastChange = GetTime()
			local scheduledAt = PshotsLastChange
			C_Timer.After(15, function()
				if PshotsLastChange == scheduledAt and Pshots then
					Pshots = false
				end
			end)
		end
	end
	local function SetTshots(value)
		if Tshots ~= value then
			Tshots = value
			TshotsLastChange = GetTime()
			local scheduledAt = TshotsLastChange
			C_Timer.After(20, function()
				if TshotsLastChange == scheduledAt and Tshots then
					Tshots = false
				end
			end)
		end
	end

	-- Event registrations (Aimed Shot + Rapid Fire + Black Arrow/Arcane/Multi Shot)
	local AimedShotCastTracker = { lastEvent = nil, lastTime = 0, castGUID = nil, prevPshotsValue = nil, prevTshotsValue = nil }
	HL:RegisterForEvent(function(_, unitTarget, castGUID, spellID)
		if unitTarget ~= "player" or spellID ~= S.AimedShot:ID() then return end
		AimedShotCastTracker.lastEvent = "start"
		AimedShotCastTracker.lastTime = GetTime()
		AimedShotCastTracker.castGUID = castGUID
		AimedShotCastTracker.prevPshotsValue = Pshots
		AimedShotCastTracker.prevTshotsValue = Tshots
		SetPshots(true)
		SetTshots(false)
	end, "UNIT_SPELLCAST_START")
	HL:RegisterForEvent(function(_, unitTarget, castGUID, spellID)
		if unitTarget ~= "player" or spellID ~= S.AimedShot:ID() then return end
		AimedShotCastTracker.lastEvent = "succeeded"
		AimedShotCastTracker.lastTime = GetTime()
		AimedShotCastTracker.castGUID = castGUID
		SetPshots(true)
		SetTshots(false)
		AimedShotCastTracker.prevTshotsValue = nil
	end, "UNIT_SPELLCAST_SUCCEEDED")
	HL:RegisterForEvent(function(_, unitTarget, castGUID, spellID)
		if unitTarget ~= "player" or spellID ~= S.AimedShot:ID() then return end
		AimedShotCastTracker.lastEvent = "interrupted"
		AimedShotCastTracker.lastTime = GetTime()
		AimedShotCastTracker.castGUID = castGUID
		SetPshots(AimedShotCastTracker.prevPshotsValue or false)
		AimedShotCastTracker.prevPshotsValue = nil
		SetTshots((AimedShotCastTracker.prevTshotsValue ~= nil) and AimedShotCastTracker.prevTshotsValue or Tshots)
		AimedShotCastTracker.prevTshotsValue = nil
	end, "UNIT_SPELLCAST_INTERRUPTED")
	HL:RegisterForEvent(function(_, unitTarget, castGUID, spellID)
		if unitTarget ~= "player" or spellID ~= S.AimedShot:ID() then return end
		if AimedShotCastTracker.castGUID == castGUID and (AimedShotCastTracker.lastEvent == "succeeded" or AimedShotCastTracker.lastEvent == "interrupted") then return end
		AimedShotCastTracker.lastEvent = "canceled"
		AimedShotCastTracker.lastTime = GetTime()
		AimedShotCastTracker.castGUID = castGUID
		SetPshots(AimedShotCastTracker.prevPshotsValue or false)
		AimedShotCastTracker.prevPshotsValue = nil
		SetTshots((AimedShotCastTracker.prevTshotsValue ~= nil) and AimedShotCastTracker.prevTshotsValue or Tshots)
		AimedShotCastTracker.prevTshotsValue = nil
	end, "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_FAILED_QUIET")

	local RapidFireCastTracker = { lastEvent = nil, lastTime = 0, castGUID = nil, prevPshotsValue = nil }
	HL:RegisterForEvent(function(_, unitTarget, castGUID, spellID)
		if unitTarget ~= "player" or spellID ~= S.RapidFire:ID() or not S.NoScope:IsAvailable() then return end
		RapidFireCastTracker.lastEvent = "channel_start"
		RapidFireCastTracker.lastTime = GetTime()
		RapidFireCastTracker.castGUID = castGUID
		RapidFireCastTracker.prevPshotsValue = Pshots
		SetPshots(true)
		SetTshots(false)
	end, "UNIT_SPELLCAST_CHANNEL_START")
	HL:RegisterForEvent(function(_, unitTarget, castGUID, spellID)
		if unitTarget ~= "player" or spellID ~= S.RapidFire:ID() or not S.NoScope:IsAvailable() then return end
		RapidFireCastTracker.lastEvent = "interrupted"
		RapidFireCastTracker.lastTime = GetTime()
		RapidFireCastTracker.castGUID = castGUID
		SetPshots(RapidFireCastTracker.prevPshotsValue or false)
		RapidFireCastTracker.prevPshotsValue = nil
	end, "UNIT_SPELLCAST_INTERRUPTED")
	HL:RegisterForEvent(function(_, unitTarget, castGUID, spellID)
		if unitTarget ~= "player" or spellID ~= S.RapidFire:ID() or not S.NoScope:IsAvailable() then return end
		RapidFireCastTracker.lastEvent = "channel_stop"
		RapidFireCastTracker.lastTime = GetTime()
		RapidFireCastTracker.castGUID = castGUID
	end, "UNIT_SPELLCAST_CHANNEL_STOP")
	HL:RegisterForEvent(function(_, unitTarget, castGUID, spellID)
		if unitTarget ~= "player" then return end
		if spellID == S.BlackArrow:ID() or spellID == S.ArcaneShot:ID() or spellID == S.MultiShot:ID() then
			SetPshots(false)
			if spellID == S.BlackArrow:ID() or spellID == S.MultiShot:ID() then
				SetTshots(true)
			end
		end
	end, "UNIT_SPELLCAST_SUCCEEDED")

	-- Init
	local function Init()
		S.AimedShot:RegisterInFlight()
		MainAddon:Print('LAMP Marksmanship loaded')

		-- Lightweight GUI similar to requested layout
		if not _G.LAMP_MS_Frame then
			local frame = CreateFrame("Frame", "LAMP_MS_Frame", UIParent, "BackdropTemplate")
			frame:SetSize(160, 210)
			frame:SetPoint("CENTER")
			frame:SetMovable(true)
			frame:EnableMouse(true)
			frame:RegisterForDrag("LeftButton")
			frame:SetScript("OnDragStart", frame.StartMoving)
			frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
			frame:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8X8", edgeFile = "Interface/Tooltips/UI-Tooltip-Border", edgeSize = 6 })
			frame:SetBackdropColor(0.06, 0.06, 0.06, 0.92)
			frame:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
			-- Title
			frame._title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
			frame._title:SetPoint("TOP", frame, "TOP", 0, -6)
			frame._title:SetText("LAMP - Marksmanship")
			-- Divider under title
			local divider = frame:CreateTexture(nil, "ARTWORK")
			divider:SetColorTexture(1, 1, 1, 0.10)
			divider:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -22)
			divider:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -22)
			divider:SetHeight(1)

			local function makeButton(key, label, yOffset, onClick)
				local btn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
				btn:SetSize(130, 30)
				btn:SetPoint("TOP", frame, "TOP", 0, yOffset)
				btn:SetText(label)
				-- hide default borders for a flatter style
				if btn.Left then btn.Left:Hide() end
				if btn.Middle then btn.Middle:Hide() end
				if btn.Right then btn.Right:Hide() end
				local fs = btn:GetFontString() if fs then fs:SetTextColor(1,1,1,1) end
				-- background texture for state coloring
				btn._bg = btn:CreateTexture(nil, "BACKGROUND")
				btn._bg:SetAllPoints(btn)
				btn._bg:SetColorTexture(0.15, 0.15, 0.15, 0.6)
				-- hover overlay
				btn._hover = btn:CreateTexture(nil, "HIGHLIGHT")
				btn._hover:SetAllPoints(btn)
				btn._hover:SetColorTexture(1, 1, 1, 0.08)
				btn._hover:Hide()
				btn:SetScript("OnEnter", function(self) if self._hover then self._hover:Show() end end)
				btn:SetScript("OnLeave", function(self) if self._hover then self._hover:Hide() end end)
				btn:SetScript("OnClick", onClick)
				return btn
			end

			local function setBtnColor(btn, enabled)
				if not btn or not btn._bg then return end
				if enabled then
					btn._bg:SetColorTexture(0.00, 0.60, 0.00, 0.70)
				else
					btn._bg:SetColorTexture(0.60, 0.00, 0.00, 0.70)
				end
			end

			local function updateLabels()
				if frame._onBtn then
					local on = MainAddon.MasterON()
					frame._onBtn:SetText(on and "ON" or "OFF")
					setBtnColor(frame._onBtn, on)
				end
				if frame._aoeBtn then
					local aoe = (MainAddon.db and MainAddon.db.global and MainAddon.db.global.aoe) and true or false
					frame._aoeBtn:SetText(aoe and "AOE" or "AOE OFF")
					setBtnColor(frame._aoeBtn, aoe)
				end
				if frame._cdsBtn then
					local cds = (MainAddon.db and MainAddon.db.global and MainAddon.db.global.cds) and true or false
					frame._cdsBtn:SetText(cds and "CDS" or "CDS OFF")
					setBtnColor(frame._cdsBtn, cds)
				end
			end

			frame._onBtn = makeButton("on", "ON", -15, function()
				MainAddon.MasterToggle()
				updateLabels()
			end)
			frame._aoeBtn = makeButton("aoe", "AOE", -60, function()
				MainAddon:AoEToggle()
				updateLabels()
			end)
			frame._cdsBtn = makeButton("cds", "CDS", -105, function()
				MainAddon.CDsToggle()
				updateLabels()
			end)
			frame._extraBtn = makeButton("extra", "", -150, function() end)

			updateLabels()
			frame:Hide()
			frame:SetScript("OnShow", function(self)
				updateLabels()
				if not self._ticker then
					self._ticker = C_Timer.NewTicker(0.25, updateLabels)
				end
			end)
			frame:SetScript("OnHide", function(self)
				if self._ticker then
					self._ticker:Cancel()
					self._ticker = nil
				end
			end)
			SLASH_LAMPMS1 = "/lampms"
			SlashCmdList["LAMPMS"] = function()
				if frame:IsShown() then frame:Hide() else frame:Show() end
			end
		end
	end

	HL:RegisterForEvent(function()
		BossFightRemains = 11111
		FightRemains = 11111
	end, "PLAYER_REGEN_ENABLED")

	-- Keep Aimed Shot in-flight registration updated when talents/spells change
	HL:RegisterForEvent(function()
		S.AimedShot:RegisterInFlight()
	end, "SPELLS_CHANGED", "LEARNED_SPELL_IN_TAB")

	-- Helpers
	local function Precombat()
		if S.HuntersMark:IsReady() and Target:DebuffDown(S.HuntersMarkDebuff, true) then
			if Cast(S.HuntersMark) then return "hunters_mark precombat LAMP" end
		end
		if S.AimedShot:IsReady() and not Player:IsCasting(S.AimedShot) then
			if Cast(S.AimedShot) then return "aimed_shot precombat LAMP" end
		end
		if S.SteadyShot:IsReady() and not Player:IsCasting(S.AimedShot) then
			if Cast(S.SteadyShot) then return "steady_shot precombat LAMP" end
		end
	end

	local function CDs()
		if S.Berserking and S.Berserking:IsReady() and (Player:BuffUp(S.TrueshotBuff) or (Player:InBossEncounter() and BossFightRemains < 13)) then
			if Cast(S.Berserking) then return "berserking cds" end
		end
		if S.BloodFury and S.BloodFury:IsReady() and (Player:BuffUp(S.TrueshotBuff) or S.Trueshot:CooldownRemains() > 30 or (Player:InBossEncounter() and BossFightRemains < 16)) then
			if Cast(S.BloodFury) then return "blood_fury cds" end
		end
		if S.AncestralCall and S.AncestralCall:IsReady() and (Player:BuffUp(S.TrueshotBuff) or S.Trueshot:CooldownRemains() > 30 or (Player:InBossEncounter() and BossFightRemains < 16)) then
			if Cast(S.AncestralCall) then return "ancestral_call cds" end
		end
		if S.Fireblood and S.Fireblood:IsReady() and (Player:BuffUp(S.TrueshotBuff) or S.Trueshot:CooldownRemains() > 30 or (Player:InBossEncounter() and BossFightRemains < 9)) then
			if Cast(S.Fireblood) then return "fireblood cds" end
		end
		if S.LightsJudgment and S.LightsJudgment:IsReady() and Player:BuffDown(S.TrueshotBuff) then
			if Cast(S.LightsJudgment) then return "lights_judgment cds" end
		end
		-- Potions omitted (handled by core if enabled)
	end

	local function Trinkets()
		local TrinketToUse = Player:GetUseableItems(OnUseExcludes, 13)
		local TrinketToUse2 = Player:GetUseableItems(OnUseExcludes, 14)
		if TrinketToUse and TrinketToUse:IsReady() then
			if (TrinketToUse:HasUseBuff() and Player:BuffUp(S.TrueshotBuff)) or not TrinketToUse:HasUseBuff() or BossFightRemains < 20 then
				if Cast(TrinketToUse) then return "trinket1 cds" end
			end
		end
		if TrinketToUse2 and TrinketToUse2:IsReady() then
			if (TrinketToUse2:HasUseBuff() and Player:BuffUp(S.TrueshotBuff)) or not TrinketToUse2:HasUseBuff() or BossFightRemains < 20 then
				if Cast(TrinketToUse2) then return "trinket2 cds" end
			end
		end
	end

	-- Action lists inspired by HR structure
	local function Cleave()
		if S.ExplosiveShot:IsReady() and (S.PrecisionDetonation:IsAvailable() and Player:PrevGCDP(1, S.AimedShot) and (Player:BuffDown(S.TrueshotBuff) or not S.WindrunnerQuiver:IsAvailable())) then
			if Cast(S.ExplosiveShot) then return "explosive_shot cleave 1 LAMP" end
		end
		if S.BlackArrow:IsReady() and Player:BuffUp(S.PreciseShotsBuff) and Player:BuffDown(S.MovingTargetBuff) and Tshots then
			if Cast(S.BlackArrow) then return "black_arrow cleave 2 LAMP" end
		end
		if S.Volley:IsReady() and (((S.DoubleTap:IsAvailable() and Player:BuffDown(S.DoubleTapBuff)) or not S.AspectoftheHydra:IsAvailable()) and (Player:BuffDown(S.PreciseShotsBuff) or Player:BuffUp(S.MovingTargetBuff))) then
			if Cast(S.Volley) then return "volley cleave 3 LAMP" end
		end
		if S.RapidFire:IsReady() and (S.Bulletstorm:IsAvailable() and Player:BuffDown(S.BulletstormBuff) and (not S.DoubleTap:IsAvailable() or Player:BuffUp(S.DoubleTapBuff) or (not S.AspectoftheHydra:IsAvailable() and Player:BuffRemains(S.TrickShotsBuff) > S.RapidFire:ExecuteTime())) and (Player:BuffDown(S.PreciseShotsBuff) or Player:BuffUp(S.MovingTargetBuff) or not S.Volley:IsAvailable())) then
			if Cast(S.RapidFire) then return "rapid_fire cleave 4 LAMP" end
		end
		if S.Volley:IsReady() and (not S.DoubleTap:IsAvailable() and (Player:BuffDown(S.PreciseShotsBuff) or Player:BuffUp(S.MovingTargetBuff))) then
			if Cast(S.Volley) then return "volley cleave 5 LAMP" end
		end
		if S.Trueshot:IsReady() and (Tshots and (Player:BuffDown(S.DoubleTapBuff) or not S.Volley:IsAvailable()) and (Player:BuffUp(S.LunarStormCDBuff) or not S.DoubleTap:IsAvailable() or not S.Volley:IsAvailable()) and (Player:BuffDown(S.PreciseShotsBuff) or Player:BuffUp(S.MovingTargetBuff) or not S.Volley:IsAvailable())) then
			if Cast(S.Trueshot) then return "trueshot cleave 6 LAMP" end
		end
		if S.SteadyShot:IsReady() and (S.BlackArrow:IsAvailable() and Player:FocusP() + Player:FocusCastRegen(S.SteadyShot:CastTime()) < Player:FocusMax() - 10 and Player:PrevGCDP(1, S.AimedShot) and Player:BuffDown(S.DeathblowBuff) and Player:BuffDown(S.TrueshotBuff) and S.Trueshot:CooldownDown()) then
			if Cast(S.SteadyShot) then return "steady_shot cleave 7 LAMP" end
		end
		if S.RapidFire:IsReady() and (S.LunarStorm:IsAvailable() and Player:BuffDown(S.LunarStormCDBuff) and (Player:BuffDown(S.PreciseShotsBuff) or Player:BuffUp(S.MovingTargetBuff) or (S.Volley:CooldownDown() and S.Trueshot:CooldownDown()) or not S.Volley:IsAvailable())) then
			if Cast(S.RapidFire) then return "rapid_fire cleave 8 LAMP" end
		end
		if S.KillShot:IsReady() and ((S.Headshot:IsAvailable() and Player:BuffUp(S.PreciseShotsBuff) and (Target:DebuffDown(S.SpottersMarkDebuff) or Player:BuffDown(S.MovingTargetBuff))) or (not S.Headshot:IsAvailable() and Player:BuffUp(S.RazorFragmentsBuff))) then
			if Cast(S.KillShot) then return "kill_shot cleave 9 LAMP" end
		end
		if S.BlackArrow:IsReady() and ((S.Headshot:IsAvailable() and Player:BuffUp(S.PreciseShotsBuff) and (Target:DebuffDown(S.SpottersMarkDebuff) or Player:BuffDown(S.MovingTargetBuff))) or (not S.Headshot:IsAvailable() and Player:BuffUp(S.RazorFragmentsBuff))) then
			if Cast(S.BlackArrow) then return "black_arrow cleave 10 LAMP" end
		end
		if S.MultiShot:IsReady() and (Player:BuffUp(S.PreciseShotsBuff) and (Target:DebuffDown(S.SpottersMarkDebuff) or Player:BuffDown(S.MovingTargetBuff)) and not S.AspectoftheHydra:IsAvailable() and (S.SymphonicArsenal:IsAvailable() or S.SmallGameHunter:IsAvailable())) then
			if Cast(S.MultiShot) then return "multishot cleave 11 LAMP" end
		end
		if S.ArcaneShot:IsReady() and (Player:BuffUp(S.PreciseShotsBuff) and (Target:DebuffDown(S.SpottersMarkDebuff) or Player:BuffDown(S.MovingTargetBuff))) then
			if Cast(S.ArcaneShot) then return "arcane_shot cleave 12 LAMP" end
		end
		if S.AimedShot:IsReady() and ((Player:BuffDown(S.PreciseShotsBuff) or (Target:DebuffUp(S.SpottersMarkDebuff) and Player:BuffUp(S.MovingTargetBuff))) and S.AimedShot:FullRechargeTime() < S.RapidFire:ExecuteTime() + S.AimedShot:CastTime() and (not S.Bulletstorm:IsAvailable() or Player:BuffUp(S.BulletstormBuff)) and S.WindrunnerQuiver:IsAvailable()) then
			if Cast(S.AimedShot) then return "aimed_shot cleave 13 LAMP" end
		end
		if S.RapidFire:IsReady() and (not S.Bulletstorm:IsAvailable() or Player:BuffStack(S.BulletstormBuff) <= 10 or S.AspectoftheHydra:IsAvailable()) then
			if Cast(S.RapidFire) then return "rapid_fire cleave 14 LAMP" end
		end
		if S.AimedShot:IsReady() and (Player:BuffDown(S.PreciseShotsBuff) or (Target:DebuffUp(S.SpottersMarkDebuff) and Player:BuffUp(S.MovingTargetBuff))) then
			if Cast(S.AimedShot) then return "aimed_shot cleave 15 LAMP" end
		end
		if S.RapidFire:IsReady() then
			if Cast(S.RapidFire) then return "rapid_fire cleave 16 LAMP" end
		end
		if S.ExplosiveShot:IsReady() and (S.PrecisionDetonation:IsAvailable() or Player:BuffDown(S.TrueshotBuff)) then
			if Cast(S.ExplosiveShot) then return "explosive_shot cleave 17 LAMP" end
		end
		if S.BlackArrow:IsReady() and not S.Headshot:IsAvailable() then
			if Cast(S.BlackArrow) then return "black_arrow cleave 18 LAMP" end
		end
		if S.SteadyShot:IsReady() then
			if Cast(S.SteadyShot) then return "steady_shot cleave 19 LAMP" end
		end
	end

	local function DarkRangerST()
		-- if S.ExplosiveShot:IsReady() and S.PrecisionDetonation:IsAvailable() and Player:PrevGCDP(1, S.AimedShot) and Player:BuffDown(S.TrueshotBuff) and Player:BuffDown(S.LockandLoadBuff) then
		-- 	if Cast(S.ExplosiveShot) then return "explosive_shot drst 1 LAMP" end
		-- end
		if S.Trueshot:IsReady() and Tshots and Player:BuffDown(S.DoubleTapBuff) and not S.BlackArrow:IsReady() then
			if Cast(S.Trueshot) then return "trueshot drst 7 LAMP" end
		end
		if S.Volley:IsReady() and Player:BuffDown(S.DoubleTapBuff) then
			if Cast(S.Volley) then return "volley drst 2 LAMP" end
		end
		-- if S.SteadyShot:IsReady() and Player:FocusP() + Player:FocusCastRegen(S.SteadyShot:CastTime()) < Player:FocusMax() - 10 and Player:PrevGCDP(1, S.AimedShot) and not S.BlackArrow:IsReady() and Player:BuffDown(S.TrueshotBuff) and S.Trueshot:CooldownDown() then
		-- 	if Cast(S.SteadyShot) then return "steady_shot drst 3 LAMP" end
		-- end
		if S.BlackArrow:IsReady() and (not S.Headshot:IsAvailable() or (S.Headshot:IsAvailable() and Pshots and (Target:DebuffDown(S.SpottersMarkDebuff) or Player:BuffDown(S.MovingTargetBuff)))) then
			if Cast(S.BlackArrow) then return "black_arrow drst 4 LAMP" end
		end
		if S.AimedShot:IsReady() and ((Player:BuffUp(S.TrueshotBuff) and not Pshots) or (Player:BuffUp(S.LockandLoadBuff) and not Pshots and Player:BuffUp(S.MovingTargetBuff))) then
			if Cast(S.AimedShot) then return "aimed_shot drst 5 LAMP" end
		end
		if S.RapidFire:IsReady() and Player:BuffDown(S.DeathblowBuff) then
			if Cast(S.RapidFire) then return "rapid_fire drst 6 LAMP" end
		end
		if S.Trueshot:IsReady() and Tshots and Player:BuffDown(S.DoubleTapBuff) and Player:BuffDown(S.DeathblowBuff) then
			if Cast(S.Trueshot) then return "trueshot drst 7b LAMP" end
		end
		if S.ArcaneShot:IsReady() and Pshots and (Target:DebuffDown(S.SpottersMarkDebuff) or Player:BuffDown(S.MovingTargetBuff)) then
			if Cast(S.ArcaneShot) then return "arcane_shot drst 8 LAMP" end
		end
		if S.AimedShot:IsReady() and ((not Pshots) or (Target:DebuffUp(S.SpottersMarkDebuff) and Player:BuffUp(S.MovingTargetBuff))) then
			if Cast(S.AimedShot) then return "aimed_shot drst 9 LAMP" end
		end
		-- if S.ExplosiveShot:IsReady() and S.ShrapnelShot:IsAvailable() and Player:BuffDown(S.LockandLoadBuff) then
		-- 	if Cast(S.ExplosiveShot) then return "explosive_shot drst 10 LAMP" end
		-- end
		if S.SteadyShot:IsReady() then
			if Cast(S.SteadyShot) then return "steady_shot drst 11 LAMP" end
		end
	end

	local function SentinelST()
		if S.ExplosiveShot:IsReady() and S.PrecisionDetonation:IsAvailable() and S.AimedShot:InFlight() and Player:BuffDown(S.TrueshotBuff) then
			if Cast(S.ExplosiveShot) then return "explosive_shot sentst 1 LAMP" end
		end
		if S.Volley:IsReady() and Player:BuffDown(S.DoubleTapBuff) then
			if Cast(S.Volley) then return "volley sentst 2 LAMP" end
		end
		if S.Trueshot:IsReady() and Tshots and Player:BuffDown(S.DoubleTapBuff) then
			if Cast(S.Trueshot) then return "trueshot sentst 3 LAMP" end
		end
		if S.RapidFire:IsReady() and S.LunarStorm:IsAvailable() and Player:BuffDown(S.LunarStormCDBuff) then
			if Cast(S.RapidFire) then return "rapid_fire sentst 4 LAMP" end
		end
		if S.KillShot:IsReady() and ((S.Headshot:IsAvailable() and Player:BuffUp(S.PreciseShotsBuff) and (Target:DebuffDown(S.SpottersMarkDebuff) or Player:BuffDown(S.MovingTargetBuff))) or (not S.Headshot:IsAvailable() and Player:BuffUp(S.RazorFragmentsBuff))) then
			if Cast(S.KillShot) then return "kill_shot sentst 5 LAMP" end
		end
		if S.ArcaneShot:IsReady() and Player:BuffUp(S.PreciseShotsBuff) and (Target:DebuffDown(S.SpottersMarkDebuff) or Player:BuffDown(S.MovingTargetBuff)) then
			if Cast(S.ArcaneShot) then return "arcane_shot sentst 6 LAMP" end
		end
		if S.AimedShot:IsReady() and (Player:BuffDown(S.PreciseShotsBuff) or (Target:DebuffUp(S.SpottersMarkDebuff) and Player:BuffUp(S.MovingTargetBuff))) and S.AimedShot:FullRechargeTime() < S.RapidFire:ExecuteTime() + S.AimedShot:CastTime() and (not S.Bulletstorm:IsAvailable() or Player:BuffUp(S.BulletstormBuff)) and S.WindrunnerQuiver:IsAvailable() then
			if Cast(S.AimedShot) then return "aimed_shot sentst 7 LAMP" end
		end
		if S.RapidFire:IsReady() then
			if Cast(S.RapidFire) then return "rapid_fire sentst 8 LAMP" end
		end
		if S.AimedShot:IsReady() and (Player:BuffDown(S.PreciseShotsBuff) or (Target:DebuffUp(S.SpottersMarkDebuff) and Player:BuffUp(S.MovingTargetBuff))) then
			if Cast(S.AimedShot) then return "aimed_shot sentst 9 LAMP" end
		end
		if S.ExplosiveShot:IsReady() and (S.PrecisionDetonation:IsAvailable() or Player:BuffDown(S.TrueshotBuff)) then
			if Cast(S.ExplosiveShot) then return "explosive_shot sentst 10 LAMP" end
		end
		if S.SteadyShot:IsReady() then
			if Cast(S.SteadyShot) then return "steady_shot sentst 11 LAMP" end
		end
	end

	local function Trickshots()
		-- if S.ExplosiveShot:IsReady() and S.PrecisionDetonation:IsAvailable() and Player:PrevGCDP(1, S.AimedShot) and Player:BuffDown(S.TrueshotBuff) and (not S.ShrapnelShot:IsAvailable() or Player:BuffDown(S.LockandLoadBuff)) then
		-- 	if Cast(S.ExplosiveShot) then return "explosive_shot trickshots 1 LAMP" end
		-- end
		if S.Trueshot:IsReady() and Tshots and Player:BuffDown(S.DoubleTapBuff) and Player:BuffDown(S.DeathblowBuff) and not S.BlackArrow:IsReady() then
			if Cast(S.Trueshot) then return "trueshot trickshots 8 LAMP" end
		end
		if S.Volley:IsReady() and Player:BuffDown(S.DoubleTapBuff) and (not S.ShrapnelShot:IsAvailable() or Player:BuffDown(S.LockandLoadBuff)) then
			if Cast(S.Volley) then return "volley trickshots 2 LAMP" end
		end
		if S.RapidFire:IsReady() and S.Bulletstorm:IsAvailable() and Player:BuffDown(S.BulletstormBuff) and Tshots then
			if Cast(S.RapidFire) then return "rapid_fire trickshots 3 LAMP" end
		end
		-- if S.SteadyShot:IsReady() and S.BlackArrow:IsAvailable() and Player:FocusP() + Player:FocusCastRegen(S.SteadyShot:CastTime()) < Player:FocusMax() - 30 and Player:PrevGCDP(1, S.AimedShot) and Player:BuffDown(S.DeathblowBuff) and Player:BuffDown(S.TrueshotBuff) and S.Trueshot:CooldownDown() then
		-- 	if Cast(S.SteadyShot) then return "steady_shot trickshots 5 LAMP" end
		-- end
		if S.BlackArrow:IsReady() and (not S.Headshot:IsAvailable() or Pshots or not Tshots) then
			if Cast(S.BlackArrow) then return "black_arrow trickshots 6 LAMP" end
		end
		if S.MultiShot:IsReady() and (Pshots and Player:BuffDown(S.MovingTargetBuff) or not Tshots) then
			if Cast(S.MultiShot) then return "multishot trickshots 7 LAMP" end
		end
		if S.Trueshot:IsReady() and Tshots and Player:BuffDown(S.DoubleTapBuff) then
			if Cast(S.Trueshot) then return "trueshot trickshots 8b LAMP" end
		end
		if S.Volley:IsReady() and Player:BuffDown(S.DoubleTapBuff) and (not S.Salvo:IsAvailable() or not S.PrecisionDetonation:IsAvailable() or (Player:BuffDown(S.PreciseShotsBuff) or (Target:DebuffUp(S.SpottersMarkDebuff) and Player:BuffUp(S.MovingTargetBuff)))) then
			if Cast(S.Volley) then return "volley trickshots 9 LAMP" end
		end
		if S.AimedShot:IsReady() and ((not Pshots) or (Target:DebuffUp(S.SpottersMarkDebuff) and Player:BuffUp(S.MovingTargetBuff))) and Tshots and Player:BuffUp(S.BulletstormBuff) and S.AimedShot:FullRechargeTime() < Player:GCD() then
			if Cast(S.AimedShot) then return "aimed_shot trickshots 10 LAMP" end
		end
		if S.RapidFire:IsReady() and Tshots and (not S.BlackArrow:IsAvailable() or Player:BuffDown(S.DeathblowBuff)) and (not S.NoScope:IsAvailable() or Target:DebuffDown(S.SpottersMarkDebuff)) and (S.NoScope:IsAvailable() or Player:BuffDown(S.BulletstormBuff)) then
			if Cast(S.RapidFire) then return "rapid_fire trickshots 11 LAMP" end
		end
		-- if S.ExplosiveShot:IsReady() and S.PrecisionDetonation:IsAvailable() and S.ShrapnelShot:IsAvailable() and Player:BuffDown(S.LockandLoadBuff) and ((not Pshots) or (Target:DebuffUp(S.SpottersMarkDebuff) and Player:BuffUp(S.MovingTargetBuff))) then
		-- 	if Cast(S.ExplosiveShot) then return "explosive_shot trickshots 12 LAMP" end
		-- end
		if S.AimedShot:IsReady() and ((not Pshots) or (Target:DebuffUp(S.SpottersMarkDebuff) and Player:BuffUp(S.MovingTargetBuff))) and Tshots then
			if Cast(S.AimedShot) then return "aimed_shot trickshots 13 LAMP" end
		end
		if S.ExplosiveShot:IsReady() and not S.ShrapnelShot:IsAvailable() then
			if Cast(S.ExplosiveShot) then return "explosive_shot trickshots 14 LAMP" end
		end
		if S.SteadyShot:IsReady() and Player:FocusP() + Player:FocusCastRegen(S.SteadyShot:CastTime()) < Player:FocusMax() then
			if Cast(S.SteadyShot) then return "steady_shot trickshots 15 LAMP" end
		end
		if S.MultiShot:IsReady() then
			if Cast(S.MultiShot) then return "multishot trickshots 16 LAMP" end
		end
	end

	-- Overrides to match HR behaviors
	local OldIsCastable
	OldIsCastable = HL.AddCoreOverride("Spell.IsCastable", function(self, BypassRecovery, Range, AoESpell, ThisUnit, Offset)
		if self == S.SteadyShot then
			Range = true
		end
		local ok, reason = OldIsCastable(self, BypassRecovery, Range, AoESpell, ThisUnit, Offset)
		return ok, reason
	end, 254)

	local OldIsReady
	OldIsReady = HL.AddCoreOverride("Spell.IsReady", function(self, Range, AoESpell, ThisUnit, BypassRecovery, Offset)
		local ready = OldIsReady(self, Range, AoESpell, ThisUnit, BypassRecovery, Offset) and Player:FocusP() >= self:Cost()
		if self == S.AimedShot then
			if Player:IsCasting(self) then return false end
			return ready and S.AimedShot:Charges() >= 1
		elseif self == S.WailingArrow then
			return ready and not Player:IsCasting(self)
		else
			return ready
		end
	end, 254)

	local OldBuffUp
	OldBuffUp = HL.AddCoreOverride("Player.BuffUp", function(self, buff, anyCaster, offset)
		if buff == S.LunarStormReadyBuff then
			return Player:BuffDown(S.LunarStormCDBuff)
		else
			return OldBuffUp(self, buff, anyCaster, offset)
		end
	end, 254)

	local OldBuffDown
	OldBuffDown = HL.AddCoreOverride("Player.BuffDown", function(self, buff, anyCaster, offset)
		if buff == S.MovingTargetBuff and Player:IsCasting(S.AimedShot) then
			return true
		else
			return OldBuffDown(self, buff, anyCaster, offset)
		end
	end, 254)

	local OldDebuffDown
	OldDebuffDown = HL.AddCoreOverride("Target.DebuffDown", function(self, debuff, anyCaster, offset)
		if debuff == S.SpottersMarkDebuff and Player:IsCasting(S.AimedShot) then
			return true
		else
			return OldDebuffDown(self, debuff, anyCaster, offset)
		end
	end, 254)

	HL.AddCoreOverride("Player.FocusP", function()
		local base = Player:Focus() + Player:FocusRemainingCastRegen()
		if not Player:IsCasting() then
			return base
		else
			if Player:IsCasting(S.SteadyShot) then
				return base + 10
			elseif Player:IsChanneling(S.RapidFire) then
				return base + 7
			elseif Player:IsCasting(S.WailingArrow) then
				return Player:BuffUp(S.TrueshotBuff) and base - 8 or base - 15
			elseif Player:IsCasting(S.AimedShot) then
				return Player:BuffUp(S.TrueshotBuff) and base - 18 or base - 35
			else
				return base
			end
		end
	end, 254)

	local function MainAPL()
		-- Enemies and ranges
		local splash = Target:GetEnemiesInSplashRange(10)
		if AoEEnabled() then
			ActiveEnemies10 = Target:EnemiesAround(10)
			Enemies10y = splash
		else
			ActiveEnemies10 = 1
			Enemies10y = splash
		end
		MainAddon.InfoText = ActiveEnemies10
		if not IsOnEnabled() then return end
		if MainAddon.TargetIsValid() or Player:AffectingCombat() then
			BossFightRemains = HL.BossFightRemains()
			FightRemains = BossFightRemains
			if FightRemains == 11111 then
				FightRemains = HL.FightRemains(Enemies10y, false)
			end
		end

		-- Defensives (basic)
		if Player:AffectingCombat() then
			if Spell.Hunter.Commons.Exhilaration:IsCastable() and Player:HealthPercentage() <= (MainAddon.Config.GetClassSetting('exhilaration_spin') or 45) then
				if Cast(Spell.Hunter.Commons.Exhilaration) then return "Exhilaration LAMP" end
			end
			if Spell.Hunter.Commons.AspectoftheTurtle:IsCastable() and Player:HealthPercentage() <= (MainAddon.Config.GetClassSetting('turtle_spin') or 20) then
				if Cast(Spell.Hunter.Commons.AspectoftheTurtle) then return "Turtle LAMP" end
			end
		end

		-- Out of combat precombat
		if MainAddon.TargetIsValid() and not Player:AffectingCombat() then
			local r = Precombat(); if r then return r end
		end

		-- CDs and Trinkets
		if CDsEnabled() then
			local cr = CDs(); if cr then return cr end
			local tr = Trinkets(); if tr then return tr end
		end

		if S.ExplosiveShot:CooldownUp() and S.PrecisionDetonation:IsAvailable() and Player:IsCasting(S.AimedShot) and Player:BuffDown(S.TrueshotBuff) and (not S.ShrapnelShot:IsAvailable() or Player:BuffDown(S.LockandLoadBuff)) then
			if Cast(S.ExplosiveShot) then return "explosive_shot trickshots 1 LAMP" end
		end
		-- Force Black Arrow suggestion while casting Aimed Shot (for UI visibility)
		if Player:IsCasting(S.AimedShot) then
			if Cast(S.BlackArrow) then return "black_arrow forced while_aimed_cast LAMP" end
		end

		-- Hunter's Mark on bosses
		if S.HuntersMark:IsReady() and Target:IsBoss() and Target:DebuffDown(S.HuntersMarkDebuff, true) and Target:TimeToX(80) > 20 then
			if Cast(S.HuntersMark) then return "Hunter's Mark LAMP" end
		end

		-- Action list selection (match HR target thresholds)
		if ActiveEnemies10 > 2 and S.TrickShots:IsAvailable() and S.BlackArrow:IsAvailable() then
			local r = Trickshots(); if r then return r end
		end
		if (ActiveEnemies10 < 3 or not S.TrickShots:IsAvailable()) and S.BlackArrow:IsAvailable() then
			local r = DarkRangerST(); if r then return r end
		end
	end

	MainAddon.SetCustomAPL(Author, SpecID, MainAPL, Init)
end

local function TryLoading ()
	C_Timer.After(1, function()
		if MainAddon then
			MyRoutine()
		else
			TryLoading()
		end
	end)
end
TryLoading()


