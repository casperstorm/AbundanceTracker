local _, Addon = ...

local ABUNDANCE_SPELL_ID = 207383
local TRACKED_HOT_SPELL_IDS = {
    [774] = true,
    [155777] = true,
}
local MAX_STACKS = 12

local TRACKED_HOT_NAMES = {}
local TRACKED_HOT_SPELL_NAMES = {}
local ABUNDANCE_SPELL_NAME = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(ABUNDANCE_SPELL_ID) or GetSpellInfo(ABUNDANCE_SPELL_ID)
local GetThresholdConfig
for spellId in pairs(TRACKED_HOT_SPELL_IDS) do
    local spellName = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellId) or GetSpellInfo(spellId)
    if spellName then
        TRACKED_HOT_NAMES[spellName] = true
        TRACKED_HOT_SPELL_NAMES[spellId] = spellName
    end
end

local function HasAbundanceTalent()
    if IsSpellKnownOrOverridesKnown and IsSpellKnownOrOverridesKnown(ABUNDANCE_SPELL_ID) then
        return true
    end

    if IsPlayerSpell and IsPlayerSpell(ABUNDANCE_SPELL_ID) then
        return true
    end

    return false
end

local trackedUnits = { "player" }

local function GetTrackedUnits()
    trackedUnits[1] = "player"
    for index = #trackedUnits, 2, -1 do
        trackedUnits[index] = nil
    end

    if IsInRaid() then
        for index = 1, GetNumGroupMembers() do
            trackedUnits[#trackedUnits + 1] = "raid" .. index
        end
    elseif IsInGroup() then
        for index = 1, GetNumSubgroupMembers() do
            trackedUnits[#trackedUnits + 1] = "party" .. index
        end
    end

    return trackedUnits
end

local function ScanUnitByName(unit, expirations, maxDurationRef)
    if not UnitAura then
        return 0
    end

    local now = GetTime()
    local added = 0

    for _, spellName in pairs(TRACKED_HOT_SPELL_NAMES) do
        local name, _, _, _, _, duration, expirationTime = UnitAura(unit, spellName, nil, "HELPFUL|PLAYER")
        if name and (expirationTime or 0) > now then
            expirations[#expirations + 1] = expirationTime
            maxDurationRef.value = math.max(maxDurationRef.value or 0, duration or 0)
            added = added + 1
        end
    end

    return added
end

local function CollectUnitAuraExpirationsModern(unit, expirations, maxDurationRef)
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName) then
        return false
    end

    local now = GetTime()
    local added = false

    for _, spellName in pairs(TRACKED_HOT_SPELL_NAMES) do
        local aura = C_UnitAuras.GetAuraDataBySpellName(unit, spellName, "HELPFUL|PLAYER")
        if aura then
            local expirationTime = aura.expirationTime or 0
            if expirationTime > now then
                expirations[#expirations + 1] = expirationTime
                maxDurationRef.value = math.max(maxDurationRef.value or 0, aura.duration or 0)
                added = true
            end
        end
    end

    return added
end

local function CollectUnitAuraExpirations(unit, expirations, maxDurationRef)
    if not UnitExists(unit) then
        return
    end

    local now = GetTime()
    local beforeCount = #expirations

    if CollectUnitAuraExpirationsModern(unit, expirations, maxDurationRef) then
        return
    end

    if ScanUnitByName(unit, expirations, maxDurationRef) > 0 then
        return
    end

    if UnitBuff then
        for _, spellName in pairs(TRACKED_HOT_SPELL_NAMES) do
            local name, _, _, _, _, duration, expirationTime = UnitBuff(unit, spellName, nil, "PLAYER")
            if name and (expirationTime or 0) > now then
                expirations[#expirations + 1] = expirationTime
                maxDurationRef.value = math.max(maxDurationRef.value or 0, duration or 0)
            end
        end
    end

    if #expirations > beforeCount then
        return
    end

    if UnitBuff then
        for index = 1, 255 do
            local name, _, _, _, _, duration, expirationTime, sourceUnit, _, _, spellId = UnitBuff(unit, index, "PLAYER")
            if not name then
                break
            end

            local isTrackedSpell = (spellId and TRACKED_HOT_SPELL_IDS[spellId]) or (name and TRACKED_HOT_NAMES[name])
            if isTrackedSpell and (expirationTime or 0) > now then
                expirations[#expirations + 1] = expirationTime
                maxDurationRef.value = math.max(maxDurationRef.value or 0, duration or 0)
            end
        end
    end

    if #expirations > beforeCount then
        return
    end

    if UnitBuff then
        for index = 1, 255 do
            local name, _, _, _, _, duration, expirationTime, sourceUnit, _, _, spellId = UnitBuff(unit, index)
            if not name then
                break
            end

            local isTrackedSpell = (spellId and TRACKED_HOT_SPELL_IDS[spellId]) or (name and TRACKED_HOT_NAMES[name])
            if isTrackedSpell and sourceUnit and UnitIsUnit(sourceUnit, "player") and (expirationTime or 0) > now then
                expirations[#expirations + 1] = expirationTime
                maxDurationRef.value = math.max(maxDurationRef.value or 0, duration or 0)
            end
        end
    end

    if #expirations > beforeCount then
        return
    end

    if UnitAura then
        for index = 1, 255 do
            local name, _, _, _, _, expirationTime, sourceUnit, _, _, spellId = UnitAura(unit, index, "HELPFUL")
            if not name then
                break
            end

            local isTrackedSpell = (spellId and TRACKED_HOT_SPELL_IDS[spellId]) or (name and TRACKED_HOT_NAMES[name])
            if isTrackedSpell and sourceUnit and UnitIsUnit(sourceUnit, "player") then
                if (expirationTime or 0) > now then
                    expirations[#expirations + 1] = expirationTime
                    maxDurationRef.value = math.max(maxDurationRef.value or 0, 0)
                end
            end
        end
    end
end

local function GetTimelineData(expirations, maxDuration)
    local now = GetTime()
    local remainingDurations = {}

    for _, expirationTime in ipairs(expirations or {}) do
        local remaining = expirationTime - now
        if remaining > 0 then
            remainingDurations[#remainingDurations + 1] = remaining
        end
    end

    table.sort(remainingDurations, function(a, b)
        return a > b
    end)

    local totalActive = #remainingDurations
    local currentCount = math.min(totalActive, MAX_STACKS)
    local dangerThreshold, warningThreshold = GetThresholdConfig()
    local totalDuration = math.max(maxDuration or 0, remainingDurations[1] or 0)

    if currentCount == 0 then
        return {
            count = 0,
            totalActive = 0,
            segments = {},
            totalDuration = totalDuration,
        }
    end

    local segments = {}
    local healthyDuration = currentCount >= warningThreshold and math.min(remainingDurations[warningThreshold] or 0, totalDuration) or 0
    local warningDuration = currentCount >= dangerThreshold and math.min(remainingDurations[dangerThreshold] or 0, totalDuration) or 0
    local dangerDuration = math.min(remainingDurations[1] or 0, totalDuration)

    local function CountDurationsInRange(startTime, endTime)
        local countInRange = 0
        for _, duration in ipairs(remainingDurations) do
            if duration > startTime and duration <= endTime then
                countInRange = countInRange + 1
            end
        end
        return countInRange
    end

    if healthyDuration > 0 then
        segments[#segments + 1] = {
            color = "healthy",
            startTime = 0,
            endTime = healthyDuration,
            stackCount = CountDurationsInRange(0, healthyDuration),
        }
    end

    if warningDuration > healthyDuration then
        segments[#segments + 1] = {
            color = "warning",
            startTime = healthyDuration,
            endTime = warningDuration,
            stackCount = CountDurationsInRange(healthyDuration, warningDuration),
        }
    end

    if dangerDuration > warningDuration then
        segments[#segments + 1] = {
            color = "danger",
            startTime = warningDuration,
            endTime = dangerDuration,
            stackCount = CountDurationsInRange(warningDuration, dangerDuration),
        }
    end

    return {
        count = currentCount,
        totalActive = totalActive,
        segments = segments,
        totalDuration = totalDuration,
    }
end

local function GetAbundanceBuffInfo()
    if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        local aura = C_UnitAuras.GetPlayerAuraBySpellID(ABUNDANCE_SPELL_ID)
        if aura then
            return rawget(aura, "applications") or rawget(aura, "count") or 0, rawget(aura, "expirationTime") or 0, rawget(aura, "duration") or 0
        end
    end

    if not ABUNDANCE_SPELL_NAME or not UnitBuff then
        return 0, 0, 0
    end

    local name, _, count, _, _, duration, expirationTime = UnitBuff("player", ABUNDANCE_SPELL_NAME)
    if not name then
        return 0, 0, 0
    end

    return count or 0, expirationTime or 0, duration or 0
end

local function FormatSeconds(value)
    if Addon:GetSetting("showDecimalTimers") == false then
        return tostring(math.ceil(value))
    end

    if value < 10 then
        return string.format("%.1f", value)
    end

    return tostring(math.ceil(value))
end

function Addon:GetAbundanceCount()
    self.seenUnits = self.seenUnits or {}
    self.expirations = self.expirations or {}

    local seen = self.seenUnits
    local expirations = self.expirations
    local maxDurationRef = { value = 0 }

    for key in pairs(seen) do
        seen[key] = nil
    end

    for index = #expirations, 1, -1 do
        expirations[index] = nil
    end

    for _, unit in ipairs(GetTrackedUnits()) do
        local guid = UnitGUID(unit)
        if guid and not seen[guid] then
            seen[guid] = true
            CollectUnitAuraExpirations(unit, expirations, maxDurationRef)
        end
    end

    local abundanceCount, abundanceExpiration, abundanceDuration = GetAbundanceBuffInfo()

    if #expirations == 0 and abundanceCount > 0 and abundanceExpiration > GetTime() then
        for index = 1, math.min(abundanceCount, MAX_STACKS) do
            expirations[#expirations + 1] = abundanceExpiration
        end
        maxDurationRef.value = math.max(maxDurationRef.value or 0, abundanceDuration or 0, abundanceExpiration - GetTime())
    end

    self.maxDuration = maxDurationRef.value
    local timeline = GetTimelineData(expirations, self.maxDuration)
    return timeline.count
end

local function GetSegmentColor(count)
    local dangerThreshold = Addon:GetSetting("dangerThreshold") or 5
    local warningThreshold = Addon:GetSetting("warningThreshold") or 9

    if warningThreshold < dangerThreshold then
        warningThreshold = dangerThreshold
    end

    if count < dangerThreshold then
        return 0.72, 0.18, 0.18, 0.95
    end

    if count < warningThreshold then
        return 0.86, 0.54, 0.08, 0.95
    end

    return 0.28, 0.62, 0.24, 0.9
end

GetThresholdConfig = function()
    local dangerThreshold = Addon:GetSetting("dangerThreshold") or 5
    local warningThreshold = Addon:GetSetting("warningThreshold") or 9

    if warningThreshold < dangerThreshold then
        warningThreshold = dangerThreshold
    end

    return dangerThreshold, warningThreshold
end

local function GetSegmentColorKey(color)
    return color
end

local function GetSegmentColorForBand(color)
    local dangerThreshold, warningThreshold = GetThresholdConfig()

    if color == "danger" then
        return GetSegmentColor(dangerThreshold - 1)
    end

    if color == "warning" then
        return GetSegmentColor(dangerThreshold)
    end

    return GetSegmentColor(warningThreshold)
end

local function GetSegmentColorLegacy(index)
    if index == 1 then
        return 0.28, 0.62, 0.24, 0.9
    end

    if index == 2 then
        return 0.86, 0.54, 0.08, 0.95
    end

    return 0.72, 0.18, 0.18, 0.95
end

function Addon:ApplyLayout()
    if not self.bar then
        return
    end

    self.bar:ClearAllPoints()
    self.bar:SetPoint(
        self:GetSetting("point") or "CENTER",
        UIParent,
        self:GetSetting("relativePoint") or "CENTER",
        self:GetSetting("x") or 0,
        self:GetSetting("y") or -170
    )
    self.bar:SetScale(self:GetSetting("scale") or 1)
    self.bar:SetSize(self:GetSetting("width") or 240, self:GetSetting("height") or 22)
    self.bar:SetMovable(not self:GetSetting("locked"))
    self.bar:EnableMouse(not self:GetSetting("locked"))

    local height = self.bar:GetHeight()
    local showCounter = self:GetSetting("showCounter") ~= false
    local counterWidth = showCounter and height or 0
    local counterFontSize = self:GetSetting("counterFontSize") or 12
    local timerFontSize = self:GetSetting("timerFontSize") or 8
    local stackLabelFontSize = self:GetSetting("stackLabelFontSize") or 8

    self.bar.countText:SetFont(STANDARD_TEXT_FONT, counterFontSize, "")

    self.bar.bars:ClearAllPoints()
    self.bar.bars:SetPoint("TOPLEFT", self.bar, "TOPLEFT", counterWidth > 0 and (counterWidth - 1) or 0, 0)
    self.bar.bars:SetPoint("BOTTOMRIGHT", self.bar, "BOTTOMRIGHT", 0, 0)

    self.bar.counter:ClearAllPoints()
    if showCounter then
        self.bar.counter:SetPoint("TOPLEFT", self.bar, "TOPLEFT", 0, 0)
        self.bar.counter:SetPoint("BOTTOMLEFT", self.bar, "BOTTOMLEFT", 0, 0)
        self.bar.counter:SetWidth(counterWidth)
        self.bar.counter:Show()
    else
        self.bar.counter:Hide()
    end

    self.bar.barscontainer:SetPoint("TOPLEFT", self.bar.bars, "TOPLEFT", 1, -1)
    self.bar.barscontainer:SetPoint("BOTTOMRIGHT", self.bar.bars, "BOTTOMRIGHT", -1, 1)

    self.bar.countText:ClearAllPoints()
    self.bar.countText:SetPoint("CENTER", self.bar.counter, "CENTER", 0, 0)

    for _, segment in ipairs(self.bar.segments) do
        segment:ClearAllPoints()
        segment.label:ClearAllPoints()
        segment.label:SetFont(STANDARD_TEXT_FONT, timerFontSize, "")
        segment.stackLabel:SetFont(STANDARD_TEXT_FONT, stackLabelFontSize, "")
    end
end

function Addon:UpdateTimelineVisuals()
    if not self.bar then
        return
    end

    local timeline = GetTimelineData(self.expirations or {}, self.maxDuration or 0)
    local count = timeline.count
    local totalActive = timeline.totalActive or count
    local known = HasAbundanceTalent()
    local inCombatOnly = self:GetSetting("inCombatOnly") == true
    local shouldShow = count > 0 or (known and self:GetSetting("showWhenInactive"))

    if inCombatOnly and not InCombatLockdown() then
        shouldShow = false
    end

    if not shouldShow then
        self.bar:Hide()
        return
    end

    self.bar:Show()
    self.bar.countText:SetText(tostring(totalActive))
    if self:GetSetting("showCounter") ~= false then
        self.bar.countText:Show()
    else
        self.bar.countText:Hide()
    end

    local barWidth = math.max(self.bar.barscontainer:GetWidth(), 1)
    local totalDuration = math.max(timeline.totalDuration, 0.001)
    local frameWidthUnit = barWidth / totalDuration
    local minInsideWidth = 24
    local previousLabelRight = -math.huge
    local lastLabelByColor = {}
    local showTimers = self:GetSetting("showTimers") ~= false
    local showStackLabels = self:GetSetting("showStackLabels") == true
    local stackLabelOffset = self:GetSetting("stackLabelOffset") or 4
    local dominantColor = nil

    for index, data in ipairs(timeline.segments) do
        local segment = self.bar.segments[index]
        local leftOffset = data.startTime * frameWidthUnit
        local rightOffset = data.endTime * frameWidthUnit

        if rightOffset - leftOffset > 0.5 then
            local r, g, b, a = GetSegmentColorForBand(data.color)
            segment:SetVertexColor(r, g, b, a)
            segment:ClearAllPoints()
            segment:SetPoint("TOPLEFT", self.bar.barscontainer, "TOPLEFT", leftOffset, 0)
            segment:SetPoint("BOTTOMLEFT", self.bar.barscontainer, "BOTTOMLEFT", leftOffset, 0)
            segment:SetPoint("RIGHT", self.bar.barscontainer, "LEFT", rightOffset, 0)
            segment:Show()
            dominantColor = dominantColor or { r, g, b }

            segment.label:SetText(FormatSeconds(data.endTime))
            segment.label:ClearAllPoints()
            local segmentWidth = segment:GetWidth()
            if segmentWidth >= minInsideWidth then
                segment.label:SetPoint("CENTER", segment, "CENTER", 0, 0)
            else
                segment.label:SetPoint("LEFT", segment, "RIGHT", 3, 0)
            end

            segment.stackLabel:SetText(tostring(data.stackCount or 0))
            segment.stackLabel:ClearAllPoints()
            if segmentWidth >= minInsideWidth then
                segment.stackLabel:SetPoint("TOP", segment.label, "BOTTOM", 0, -stackLabelOffset)
            else
                segment.stackLabel:SetPoint("TOPLEFT", segment.label, "BOTTOMLEFT", 0, -stackLabelOffset)
            end

            local labelLeft = segment.label:GetLeft() or 0
            local labelRight = segment.label:GetRight() or 0
            if not showTimers or labelLeft <= previousLabelRight then
                segment.label:Hide()
                segment.stackLabel:Hide()
            else
                segment.label:Show()
                previousLabelRight = labelRight
                lastLabelByColor[GetSegmentColorKey(data.color)] = segment.label
                if showStackLabels then
                    segment.stackLabel:Show()
                else
                    segment.stackLabel:Hide()
                end
            end
        else
            segment:Hide()
            segment.label:Hide()
            segment.stackLabel:Hide()
        end
    end

    local seenLabels = {}
    for index = #timeline.segments, 1, -1 do
        local data = timeline.segments[index]
        local segment = self.bar.segments[index]
        local winningLabel = lastLabelByColor[GetSegmentColorKey(data.color)]
        if segment:IsShown() and segment.label:IsShown() then
            if winningLabel ~= segment.label or seenLabels[winningLabel] then
                segment.label:Hide()
                segment.stackLabel:Hide()
            else
                seenLabels[winningLabel] = true
            end
        end
    end

    for index = #timeline.segments + 1, #self.bar.segments do
        self.bar.segments[index]:Hide()
        self.bar.segments[index].label:Hide()
        self.bar.segments[index].stackLabel:Hide()
    end

    if dominantColor then
        self.bar.countText:SetTextColor(dominantColor[1], dominantColor[2], dominantColor[3], 1)
    else
        self.bar.countText:SetTextColor(1, 1, 1, 1)
    end

end

function Addon:UpdateBar()
    if not self.bar then
        return
    end

    self:GetAbundanceCount()
    self:UpdateTimelineVisuals()
end

function Addon:RefreshBar()
    self:UpdateBar()
end

function Addon:InitializeBar()
    if self.bar then
        self:ApplyLayout()
        self:UpdateBar()
        return
    end

    local bar = CreateFrame("Frame", "AbundanceTrackerBar", UIParent, "BackdropTemplate")
    bar:SetFrameStrata("MEDIUM")
    bar:SetClampedToScreen(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function(self)
        if not Addon:GetSetting("locked") then
            self:StartMoving()
        end
    end)
    bar:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        Addon:SavePosition()
    end)

    local backdrop = {
        bgFile = "Interface/Buttons/WHITE8X8",
        edgeFile = "Interface/Buttons/WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    }

    bar.bars = CreateFrame("Frame", nil, bar, "BackdropTemplate")
    bar.bars:SetBackdrop(backdrop)
    bar.bars:SetBackdropColor(0, 0, 0, 0.6)
    bar.bars:SetBackdropBorderColor(0, 0, 0, 1)

    bar.barscontainer = CreateFrame("Frame", nil, bar.bars)
    bar.background = bar.barscontainer:CreateTexture(nil, "BACKGROUND")
    bar.background:SetAllPoints(bar.barscontainer)
    bar.background:SetTexture("Interface\\Buttons\\WHITE8X8")
    bar.background:SetVertexColor(0, 0, 0, 0.2)

    bar.counter = CreateFrame("Frame", nil, bar, "BackdropTemplate")
    bar.counter:SetBackdrop(backdrop)
    bar.counter:SetBackdropColor(0, 0, 0, 0.6)
    bar.counter:SetBackdropBorderColor(0, 0, 0, 1)

    bar.segments = {}
    for index = 1, 3 do
        local segment = bar.barscontainer:CreateTexture(nil, "ARTWORK")
        local r, g, b, a = GetSegmentColorLegacy(index)
        segment:SetTexture("Interface\\Buttons\\WHITE8X8")
        segment:SetVertexColor(r, g, b, a)

        local label = bar.barscontainer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetTextColor(1, 1, 1)
        label:SetShadowOffset(1, -1)
        label:SetShadowColor(0, 0, 0, 1)

        local stackLabel = bar.barscontainer:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        stackLabel:SetTextColor(0.85, 0.85, 0.85)
        stackLabel:SetShadowOffset(1, -1)
        stackLabel:SetShadowColor(0, 0, 0, 1)

        segment.label = label
        segment.stackLabel = stackLabel
        bar.segments[index] = segment
    end

    bar.countText = bar.counter:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    bar.countText:SetJustifyH("CENTER")
    bar.countText:SetTextColor(1, 1, 1)
    bar.countText:SetShadowOffset(1, -1)
    bar.countText:SetShadowColor(0, 0, 0, 1)

    self.bar = bar
    self.eventFrame = self.eventFrame or CreateFrame("Frame")
    self.eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    self.eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    self.eventFrame:RegisterEvent("PLAYER_TALENT_UPDATE")
    self.eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    self.eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    self.eventFrame:RegisterEvent("UNIT_AURA")
    self.eventFrame:SetScript("OnEvent", function(_, event, unit)
        if event ~= "UNIT_AURA" or not unit or UnitInParty(unit) or UnitInRaid(unit) or UnitIsUnit(unit, "player") then
            Addon:UpdateBar()
        end
    end)

    bar.visualElapsed = 0
    bar.scanElapsed = 0
    bar:SetScript("OnUpdate", function(_, elapsed)
        bar.visualElapsed = bar.visualElapsed + elapsed
        bar.scanElapsed = bar.scanElapsed + elapsed

        if bar.scanElapsed >= 0.1 then
            bar.scanElapsed = 0
            Addon:GetAbundanceCount()
        end

        if bar.visualElapsed >= 0.03 then
            bar.visualElapsed = 0
            Addon:UpdateTimelineVisuals()
        end
    end)

    self:ApplyLayout()
    self:UpdateBar()
end
