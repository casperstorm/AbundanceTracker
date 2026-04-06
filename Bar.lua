local _, Addon = ...

local issecretvalue = issecretvalue
local IsAuraFilteredOutByInstanceID = C_UnitAuras and C_UnitAuras.IsAuraFilteredOutByInstanceID

local ABUNDANCE_SPELL_ID = 207383
local TRACKED_HOT_SPELL_IDS = {
    [774] = true,
    [155777] = true,
}
local REJUVENATION_SPELL_ID = 774
local GERMINATION_SPELL_ID = 155777
local HELPFUL_FILTER = "HELPFUL"
local PLAYER_HELPFUL_FILTER = "HELPFUL|PLAYER"
local MAX_UNIT_AURAS = 40
local MAX_STACKS = 12

local ABUNDANCE_SPELL_NAME = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(ABUNDANCE_SPELL_ID) or GetSpellInfo(ABUNDANCE_SPELL_ID)
local GetThresholdConfig

local function IsVerticalOrientation()
    return Addon:GetSetting("orientation") == "vertical"
end

local function IsReverseProgression()
    return Addon:GetSetting("progressDirection") == "reverse"
end

local function GetBarDimensions()
    local width = Addon:GetSetting("width") or 240
    local height = Addon:GetSetting("height") or 22

    if IsVerticalOrientation() then
        return height, width
    end

    return width, height
end

local function GetCounterSize()
    local barWidth, barHeight = GetBarDimensions()

    if IsVerticalOrientation() then
        return barWidth
    end

    return barHeight
end

local function GetCounterPosition()
    local vertical = IsVerticalOrientation()
    local position = Addon:GetSetting("counterPosition")

    if vertical then
        if position == "top" or position == "bottom" or position == "hide" then
            return position
        end

        return position == "hide" and "hide" or "bottom"
    end

    if position == "left" or position == "right" or position == "hide" then
        return position
    end

    return position == "hide" and "hide" or "left"
end

local function GetBarsContainerLength(bar)
    if not bar then
        return 1
    end

    local showCounter = GetCounterPosition() ~= "hide"
    local counterSize = showCounter and GetCounterSize() or 0

    if IsVerticalOrientation() then
        return math.max((bar:GetHeight() or 0) - counterSize - 2, 1)
    end

    local barsWidth = (bar:GetWidth() or 0) - (counterSize > 0 and (counterSize - 1) or 0)
    return math.max(barsWidth - 2, 1)
end

local function GetLabelRange(label, vertical, reverse)
    if vertical then
        local top = label:GetTop() or 0
        local bottom = label:GetBottom() or 0

        if reverse then
            return bottom, top
        end

        return -top, -bottom
    end

    local left = label:GetLeft() or 0
    local right = label:GetRight() or 0

    if reverse then
        return -right, -left
    end

    return left, right
end

local function ScheduleDelayedFullRefresh()
    if not C_Timer or not C_Timer.After then
        return
    end

    C_Timer.After(0.1, function()
        Addon:RefreshAllTrackedUnits()
        Addon.visualDirty = true
    end)

    C_Timer.After(0.5, function()
        Addon:RefreshAllTrackedUnits()
        Addon.visualDirty = true
    end)
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

local function ClearArray(values)
    for index = #values, 1, -1 do
        values[index] = nil
    end
end

local function ClearMap(values)
    for key in pairs(values) do
        values[key] = nil
    end
end

local function AppendExpiration(expirations, expirationTime, duration, maxDurationRef)
    if not expirationTime or expirationTime <= GetTime() then
        return false
    end

    expirations[#expirations + 1] = expirationTime
    maxDurationRef.value = math.max(maxDurationRef.value or 0, duration or 0)
    return true
end

local function GetTrackedSpellId(auraData)
    if not auraData then
        return nil
    end

    local spellId = rawget(auraData, "spellId")
    if spellId and issecretvalue and issecretvalue(spellId) then
        spellId = nil
    end

    if spellId and TRACKED_HOT_SPELL_IDS[spellId] then
        return spellId
    end

    return nil
end

local function IsPlayerTrackedAura(unit, auraData)
    local spellId = GetTrackedSpellId(auraData)
    if not spellId then
        return false
    end

    local auraInstanceID = rawget(auraData, "auraInstanceID")
    if unit and auraInstanceID and IsAuraFilteredOutByInstanceID then
        local ok, isFilteredOut = pcall(IsAuraFilteredOutByInstanceID, unit, auraInstanceID, PLAYER_HELPFUL_FILTER)
        if ok then
            return not isFilteredOut, spellId
        end
    end

    local isFromPlayer = rawget(auraData, "isFromPlayerOrPlayerPet")
    if isFromPlayer ~= nil then
        return isFromPlayer == true, spellId
    end

    local sourceUnit = rawget(auraData, "sourceUnit")
    if sourceUnit then
        return UnitIsUnit(sourceUnit, "player"), spellId
    end

    return false
end

local function ResetTrackedAuraState(auraState)
    auraState.rejuvExpiration = 0
    auraState.rejuvDuration = 0
    auraState.germExpiration = 0
    auraState.germDuration = 0
end

local function AddTrackedAuraData(unit, auraState, auraData)
    local isTracked, spellId = IsPlayerTrackedAura(unit, auraData)
    if not isTracked then
        return false
    end

    local expirationTime = rawget(auraData, "expirationTime") or 0
    local duration = rawget(auraData, "duration") or 0

    if spellId == REJUVENATION_SPELL_ID then
        if expirationTime > (auraState.rejuvExpiration or 0) then
            auraState.rejuvExpiration = expirationTime
            auraState.rejuvDuration = duration
        end
        return true
    end

    if spellId == GERMINATION_SPELL_ID then
        if expirationTime > (auraState.germExpiration or 0) then
            auraState.germExpiration = expirationTime
            auraState.germDuration = duration
        end
        return true
    end

    return false
end

local function AppendTrackedAuraState(expirations, auraState, maxDurationRef)
    AppendExpiration(expirations, auraState.rejuvExpiration, auraState.rejuvDuration, maxDurationRef)
    AppendExpiration(expirations, auraState.germExpiration, auraState.germDuration, maxDurationRef)
end

local AuraScanState = {
    trackedAuras = nil,
}

local function ForEachTrackedHelpfulAura(auraData)
    local state = AuraScanState
    AddTrackedAuraData(state.unit, state.trackedAuras, auraData)
    return false
end

local function ScanUnitTrackedAuras(unit, auraState)
    ResetTrackedAuraState(auraState)

    if not UnitExists(unit) then
        return
    end

    if C_UnitAuras and C_UnitAuras.GetUnitAuras then
        local helpfulAuras = C_UnitAuras.GetUnitAuras(unit, HELPFUL_FILTER, MAX_UNIT_AURAS)
        if helpfulAuras then
            for _, auraData in ipairs(helpfulAuras) do
                AddTrackedAuraData(unit, auraState, auraData)
            end
            return
        end
    end

    if AuraUtil and AuraUtil.ForEachAura then
        AuraScanState.unit = unit
        AuraScanState.trackedAuras = auraState
        AuraUtil.ForEachAura(unit, HELPFUL_FILTER, nil, ForEachTrackedHelpfulAura, true)
        AuraScanState.unit = nil
        AuraScanState.trackedAuras = nil
        return
    end

    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        for index = 1, MAX_UNIT_AURAS do
            local auraData = C_UnitAuras.GetAuraDataByIndex(unit, index, HELPFUL_FILTER)
            if not auraData then
                break
            end

            AddTrackedAuraData(unit, auraState, auraData)
        end
    end
end

local function SortDescending(a, b)
    return a > b
end

local function CountDurationsInRange(remainingDurations, startTime, endTime)
    local countInRange = 0
    for index = 1, #remainingDurations do
        local duration = remainingDurations[index]
        if duration > startTime and duration <= endTime then
            countInRange = countInRange + 1
        end
    end
    return countInRange
end

local function SetTimelineSegment(segment, color, startTime, endTime, stackCount)
    segment.color = color
    segment.startTime = startTime
    segment.endTime = endTime
    segment.stackCount = stackCount
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

local function PlayerHasAbundanceTalent()
    return IsPlayerSpell and IsPlayerSpell(ABUNDANCE_SPELL_ID) == true
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

function Addon:RebuildExpirationsFromCache()
    self.expirations = self.expirations or {}
    self.maxDurationRef = self.maxDurationRef or { value = 0 }

    local expirations = self.expirations
    local maxDurationRef = self.maxDurationRef
    maxDurationRef.value = 0
    ClearArray(expirations)

    if self.unitAuraCache then
        for _, auraState in pairs(self.unitAuraCache) do
            AppendTrackedAuraState(expirations, auraState, maxDurationRef)
        end
    end

    self.maxDuration = maxDurationRef.value
end

function Addon:RefreshAbundanceBuff()
    local abundanceCount, abundanceExpiration = GetAbundanceBuffInfo()
    self.abundanceCount = math.min(abundanceCount or 0, MAX_STACKS)
    self.abundanceExpiration = abundanceExpiration or 0
end

function Addon:ScanTrackedUnit(unit)
    self.unitAuraCache = self.unitAuraCache or {}

    local guid = UnitGUID(unit)
    if not guid then
        return false
    end

    local auraState = self.unitAuraCache[guid]
    if not auraState then
        auraState = {}
        self.unitAuraCache[guid] = auraState
    end

    ScanUnitTrackedAuras(unit, auraState)
    return true
end

function Addon:RefreshAllTrackedUnits()
    self.seenUnits = self.seenUnits or {}
    self.activeGuids = self.activeGuids or {}
    self.unitAuraCache = self.unitAuraCache or {}

    local seen = self.seenUnits
    local activeGuids = self.activeGuids
    ClearMap(seen)
    ClearMap(activeGuids)

    for _, unit in ipairs(GetTrackedUnits()) do
        local guid = UnitGUID(unit)
        if guid and not seen[guid] then
            seen[guid] = true
            activeGuids[guid] = true
            self:ScanTrackedUnit(unit)
        end
    end

    for guid in pairs(self.unitAuraCache) do
        if not activeGuids[guid] then
            self.unitAuraCache[guid] = nil
        end
    end

    self:RebuildExpirationsFromCache()
    self:RefreshAbundanceBuff()
end

function Addon:RefreshTrackedUnit(unit)
    if not unit or not (UnitIsUnit(unit, "player") or UnitInParty(unit) or UnitInRaid(unit)) then
        return
    end

    if self:ScanTrackedUnit(unit) then
        self:RebuildExpirationsFromCache()
    end

    if UnitIsUnit(unit, "player") then
        self:RefreshAbundanceBuff()
    end
end

function Addon:ClearTrackedUnitCache()
    self.unitAuraCache = self.unitAuraCache or {}
    self.expirations = self.expirations or {}
    self.maxDurationRef = self.maxDurationRef or { value = 0 }

    ClearMap(self.unitAuraCache)
    ClearArray(self.expirations)
    self.maxDurationRef.value = 0
    self.maxDuration = 0
    self.abundanceCount = 0
    self.abundanceExpiration = 0
end

function Addon:GetAbundanceCount()
    self:RefreshAllTrackedUnits()
    return self.abundanceCount
end

function Addon:GetTimelineData()
    self.timelineData = self.timelineData or {
        remainingDurations = {},
        segments = {
            {},
            {},
            {},
        },
        segmentCount = 0,
        count = 0,
        totalActive = 0,
        totalDuration = 0,
    }

    local timeline = self.timelineData
    local remainingDurations = timeline.remainingDurations
    ClearArray(remainingDurations)

    local now = GetTime()
    local expirations = self.expirations or {}
    for index = 1, #expirations do
        local remaining = expirations[index] - now
        if remaining > 0 then
            remainingDurations[#remainingDurations + 1] = remaining
        end
    end

    table.sort(remainingDurations, SortDescending)

    local totalActive = #remainingDurations
    local currentCount = math.min(totalActive, MAX_STACKS)
    local dangerThreshold, warningThreshold = GetThresholdConfig()
    local totalDuration = math.max(self.maxDuration or 0, remainingDurations[1] or 0)

    timeline.count = currentCount
    timeline.totalActive = totalActive
    timeline.totalDuration = totalDuration
    timeline.segmentCount = 0

    if currentCount == 0 then
        return timeline
    end

    local healthyDuration = currentCount >= warningThreshold and math.min(remainingDurations[warningThreshold] or 0, totalDuration) or 0
    local warningDuration = currentCount >= dangerThreshold and math.min(remainingDurations[dangerThreshold] or 0, totalDuration) or 0
    local dangerDuration = math.min(remainingDurations[1] or 0, totalDuration)

    if healthyDuration > 0 then
        timeline.segmentCount = timeline.segmentCount + 1
        SetTimelineSegment(
            timeline.segments[timeline.segmentCount],
            "healthy",
            0,
            healthyDuration,
            CountDurationsInRange(remainingDurations, 0, healthyDuration)
        )
    end

    if warningDuration > healthyDuration then
        timeline.segmentCount = timeline.segmentCount + 1
        SetTimelineSegment(
            timeline.segments[timeline.segmentCount],
            "warning",
            healthyDuration,
            warningDuration,
            CountDurationsInRange(remainingDurations, healthyDuration, warningDuration)
        )
    end

    if dangerDuration > warningDuration then
        timeline.segmentCount = timeline.segmentCount + 1
        SetTimelineSegment(
            timeline.segments[timeline.segmentCount],
            "danger",
            warningDuration,
            dangerDuration,
            CountDurationsInRange(remainingDurations, warningDuration, dangerDuration)
        )
    end

    return timeline
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

function Addon:ShouldShowBar()
    local visibilityMode = self:GetSetting("visibilityMode") or "always"

    if self:GetSetting("onlyShowWithAbundanceTalent") ~= false and not PlayerHasAbundanceTalent() then
        return false
    end

    if visibilityMode == "raid" then
        return IsInRaid()
    end

    return true
end

function Addon:ApplyLayout()
    if not self.bar then
        return
    end

    local barWidth, barHeight = GetBarDimensions()
    local vertical = IsVerticalOrientation()
    local counterPosition = GetCounterPosition()
    local showCounter = counterPosition ~= "hide"
    local counterSize = showCounter and GetCounterSize() or 0

    self.bar:ClearAllPoints()
    self.bar:SetPoint(
        self:GetSetting("point") or "CENTER",
        UIParent,
        self:GetSetting("relativePoint") or "CENTER",
        self:GetSetting("x") or 0,
        self:GetSetting("y") or -170
    )
    self.bar:SetScale(self:GetSetting("scale") or 1)
    self.bar:SetSize(barWidth, barHeight)
    self.bar:SetMovable(not self:GetSetting("locked"))
    self.bar:EnableMouse(not self:GetSetting("locked"))

    local counterFontSize = self:GetSetting("counterFontSize") or 12
    local timerFontSize = self:GetSetting("timerFontSize") or 8
    local stackLabelFontSize = self:GetSetting("stackLabelFontSize") or 8

    self.bar.countText:SetFont(STANDARD_TEXT_FONT, counterFontSize, "")

    self.bar.counter:ClearAllPoints()
    if showCounter then
        if vertical then
            if counterPosition == "top" then
                self.bar.counter:SetPoint("TOPLEFT", self.bar, "TOPLEFT", 0, 0)
                self.bar.counter:SetPoint("TOPRIGHT", self.bar, "TOPRIGHT", 0, 0)
            else
                self.bar.counter:SetPoint("BOTTOMLEFT", self.bar, "BOTTOMLEFT", 0, 0)
                self.bar.counter:SetPoint("BOTTOMRIGHT", self.bar, "BOTTOMRIGHT", 0, 0)
            end
            self.bar.counter:SetHeight(counterSize)
        else
            if counterPosition == "right" then
                self.bar.counter:SetPoint("TOPRIGHT", self.bar, "TOPRIGHT", 0, 0)
                self.bar.counter:SetPoint("BOTTOMRIGHT", self.bar, "BOTTOMRIGHT", 0, 0)
            else
                self.bar.counter:SetPoint("TOPLEFT", self.bar, "TOPLEFT", 0, 0)
                self.bar.counter:SetPoint("BOTTOMLEFT", self.bar, "BOTTOMLEFT", 0, 0)
            end
            self.bar.counter:SetWidth(counterSize)
        end
        self.bar.counter:Show()
    else
        self.bar.counter:Hide()
    end

    self.bar.bars:ClearAllPoints()
    if vertical then
        if showCounter and counterPosition == "top" then
            self.bar.bars:SetPoint("TOPLEFT", self.bar.counter, "BOTTOMLEFT", 0, 0)
            self.bar.bars:SetPoint("TOPRIGHT", self.bar.counter, "BOTTOMRIGHT", 0, 0)
            self.bar.bars:SetPoint("BOTTOMRIGHT", self.bar, "BOTTOMRIGHT", 0, 0)
        elseif showCounter and counterPosition == "bottom" then
            self.bar.bars:SetPoint("TOPLEFT", self.bar, "TOPLEFT", 0, 0)
            self.bar.bars:SetPoint("BOTTOMRIGHT", self.bar.counter, "TOPRIGHT", 0, 0)
        else
            self.bar.bars:SetPoint("TOPLEFT", self.bar, "TOPLEFT", 0, 0)
            self.bar.bars:SetPoint("BOTTOMRIGHT", self.bar, "BOTTOMRIGHT", 0, 0)
        end
    else
        if showCounter and counterPosition == "right" then
            self.bar.bars:SetPoint("TOPLEFT", self.bar, "TOPLEFT", 0, 0)
            self.bar.bars:SetPoint("BOTTOMLEFT", self.bar, "BOTTOMLEFT", 0, 0)
            self.bar.bars:SetPoint("RIGHT", self.bar.counter, "LEFT", 0, 0)
        else
            self.bar.bars:SetPoint("TOPLEFT", self.bar, "TOPLEFT", counterSize > 0 and (counterSize - 1) or 0, 0)
            self.bar.bars:SetPoint("BOTTOMRIGHT", self.bar, "BOTTOMRIGHT", 0, 0)
        end
    end

    self.bar.barscontainer:ClearAllPoints()
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

    local timeline = self:GetTimelineData()
    local count = timeline.count
    self.bar.countText:SetText(tostring(count))
    if GetCounterPosition() ~= "hide" then
        self.bar.countText:Show()
    else
        self.bar.countText:Hide()
    end

    local barLength = GetBarsContainerLength(self.bar)
    local totalDuration = math.max(timeline.totalDuration, 0.001)
    local frameWidthUnit = barLength / totalDuration
    local minInsideWidth = 24
    local vertical = IsVerticalOrientation()
    local reverse = IsReverseProgression()
    local previousLabelEdge = nil
    self.lastLabelByColor = self.lastLabelByColor or {}
    self.seenLabels = self.seenLabels or {}
    local lastLabelByColor = self.lastLabelByColor
    local seenLabels = self.seenLabels
    ClearMap(lastLabelByColor)
    ClearMap(seenLabels)
    local showTimers = self:GetSetting("showTimers") ~= false
    local showStackLabels = self:GetSetting("showStackLabels") == true
    local stackLabelOffset = self:GetSetting("stackLabelOffset") or 4

    for index = 1, timeline.segmentCount do
        local data = timeline.segments[index]
        local segment = self.bar.segments[index]
        local startOffset = data.startTime * frameWidthUnit
        local endOffset = data.endTime * frameWidthUnit

        if endOffset - startOffset > 0.5 then
            local r, g, b, a = GetSegmentColorForBand(data.color)
            segment:SetVertexColor(r, g, b, a)
            segment:ClearAllPoints()
            if vertical then
                if reverse then
                    segment:SetPoint("BOTTOMLEFT", self.bar.barscontainer, "BOTTOMLEFT", 0, startOffset)
                    segment:SetPoint("BOTTOMRIGHT", self.bar.barscontainer, "BOTTOMRIGHT", 0, startOffset)
                    segment:SetPoint("TOPLEFT", self.bar.barscontainer, "BOTTOMLEFT", 0, endOffset)
                    segment:SetPoint("TOPRIGHT", self.bar.barscontainer, "BOTTOMRIGHT", 0, endOffset)
                else
                    segment:SetPoint("TOPLEFT", self.bar.barscontainer, "TOPLEFT", 0, -startOffset)
                    segment:SetPoint("TOPRIGHT", self.bar.barscontainer, "TOPRIGHT", 0, -startOffset)
                    segment:SetPoint("BOTTOMLEFT", self.bar.barscontainer, "TOPLEFT", 0, -endOffset)
                    segment:SetPoint("BOTTOMRIGHT", self.bar.barscontainer, "TOPRIGHT", 0, -endOffset)
                end
            else
                if reverse then
                    segment:SetPoint("TOPRIGHT", self.bar.barscontainer, "TOPRIGHT", -startOffset, 0)
                    segment:SetPoint("BOTTOMRIGHT", self.bar.barscontainer, "BOTTOMRIGHT", -startOffset, 0)
                    segment:SetPoint("LEFT", self.bar.barscontainer, "RIGHT", -endOffset, 0)
                else
                    segment:SetPoint("TOPLEFT", self.bar.barscontainer, "TOPLEFT", startOffset, 0)
                    segment:SetPoint("BOTTOMLEFT", self.bar.barscontainer, "BOTTOMLEFT", startOffset, 0)
                    segment:SetPoint("RIGHT", self.bar.barscontainer, "LEFT", endOffset, 0)
                end
            end
            segment:Show()

            segment.label:SetText(FormatSeconds(data.endTime))
            segment.label:ClearAllPoints()
            local segmentExtent = vertical and segment:GetHeight() or segment:GetWidth()
            if segmentExtent >= minInsideWidth then
                segment.label:SetPoint("CENTER", segment, "CENTER", 0, 0)
            else
                if reverse and not vertical then
                    segment.label:SetPoint("RIGHT", segment, "LEFT", -3, 0)
                else
                    segment.label:SetPoint("LEFT", segment, "RIGHT", 3, 0)
                end
            end

            segment.stackLabel:SetText(tostring(data.stackCount or 0))
            segment.stackLabel:ClearAllPoints()
            if segmentExtent >= minInsideWidth then
                segment.stackLabel:SetPoint("TOP", segment.label, "BOTTOM", 0, -stackLabelOffset)
            else
                segment.stackLabel:SetPoint("TOPLEFT", segment.label, "BOTTOMLEFT", 0, -stackLabelOffset)
            end

            local labelStart, labelEnd = GetLabelRange(segment.label, vertical, reverse)
            if not showTimers or (previousLabelEdge ~= nil and labelStart <= previousLabelEdge) then
                segment.label:Hide()
                segment.stackLabel:Hide()
            else
                segment.label:Show()
                previousLabelEdge = labelEnd
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

    for index = timeline.segmentCount, 1, -1 do
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

    for index = timeline.segmentCount + 1, #self.bar.segments do
        self.bar.segments[index]:Hide()
        self.bar.segments[index].label:Hide()
        self.bar.segments[index].stackLabel:Hide()
    end

    local countR, countG, countB = GetSegmentColor(count)
    self.bar.countText:SetTextColor(countR, countG, countB, 1)

end

function Addon:UpdateBar()
    if not self.bar then
        return
    end

    if not self:ShouldShowBar() then
        self.bar:Hide()
        self.visualDirty = false
        return
    end

    self.bar:Show()

    self:UpdateTimelineVisuals()
    self.visualDirty = false
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
    self.eventFrame:RegisterEvent("PLAYER_DEAD")
    self.eventFrame:RegisterEvent("PLAYER_ALIVE")
    self.eventFrame:RegisterEvent("PLAYER_UNGHOST")
    self.eventFrame:RegisterEvent("UNIT_OTHER_PARTY_CHANGED")
    self.eventFrame:RegisterEvent("UNIT_AURA")
    self.eventFrame:RegisterEvent("UNIT_PHASE")
    self.eventFrame:RegisterEvent("UNIT_CONNECTION")
    self.eventFrame:SetScript("OnEvent", function(_, event, unit)
        if event == "UNIT_AURA" then
            if unit and (UnitInParty(unit) or UnitInRaid(unit) or UnitIsUnit(unit, "player")) then
                Addon:RefreshTrackedUnit(unit)
                Addon.visualDirty = true
            end
        elseif event == "PLAYER_DEAD" then
            Addon:ClearTrackedUnitCache()
            Addon.visualDirty = true
        elseif event == "PLAYER_ALIVE" or event == "PLAYER_UNGHOST" then
            Addon:RefreshAllTrackedUnits()
            Addon.visualDirty = true
            ScheduleDelayedFullRefresh()
        elseif event == "UNIT_PHASE" or event == "UNIT_CONNECTION" or event == "UNIT_OTHER_PARTY_CHANGED" then
            Addon:RefreshAllTrackedUnits()
            Addon.visualDirty = true
            ScheduleDelayedFullRefresh()
        else
            Addon:RefreshAllTrackedUnits()
            Addon.visualDirty = true
            ScheduleDelayedFullRefresh()
        end

        if Addon.bar and not Addon.bar:IsShown() then
            Addon:UpdateBar()
        end
    end)

    bar.visualElapsed = 0
    bar.hiddenRefreshElapsed = 0
    bar:SetScript("OnUpdate", function(_, elapsed)
        bar.visualElapsed = bar.visualElapsed + elapsed
        bar.hiddenRefreshElapsed = bar.hiddenRefreshElapsed + elapsed

        if bar.hiddenRefreshElapsed >= 0.2 and not bar:IsShown() then
            bar.hiddenRefreshElapsed = 0
            Addon:RefreshAllTrackedUnits()
            Addon.visualDirty = true
        end

        if bar.visualElapsed >= 0.03 and (Addon.visualDirty or bar:IsShown()) then
            bar.visualElapsed = 0
            Addon:UpdateBar()
        end
    end)

    self:ApplyLayout()
    self.visualDirty = true
    self:RefreshAllTrackedUnits()
    self:UpdateBar()
end
