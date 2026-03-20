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

local function GetTrackedUnits()
    local units = { "player" }

    if IsInRaid() then
        for index = 1, GetNumGroupMembers() do
            units[#units + 1] = "raid" .. index
        end
    elseif IsInGroup() then
        for index = 1, GetNumSubgroupMembers() do
            units[#units + 1] = "party" .. index
        end
    end

    return units
end

local function ScanUnitByName(unit, expirations, maxDurationRef)
    if not UnitAura then
        return 0
    end

    local now = GetTime()
    local added = 0

    for spellId, spellName in pairs(TRACKED_HOT_SPELL_NAMES) do
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
    if not (C_UnitAuras and C_UnitAuras.GetAuraSlots and C_UnitAuras.GetAuraDataBySlot) then
        return false
    end

    local now = GetTime()
    local slots = { C_UnitAuras.GetAuraSlots(unit, "HELPFUL|PLAYER") }
    local added = false

    for index = 2, #slots do
        local slot = slots[index]
        if type(slot) == "number" then
            local aura = C_UnitAuras.GetAuraDataBySlot(unit, slot)
            if aura then
                local spellId = rawget(aura, "spellId")
                local name = rawget(aura, "name")
                local duration = rawget(aura, "duration") or 0
                local expirationTime = rawget(aura, "expirationTime") or 0
                if ((spellId and TRACKED_HOT_SPELL_IDS[spellId]) or (name and TRACKED_HOT_NAMES[name])) and expirationTime > now then
                    expirations[#expirations + 1] = expirationTime
                    maxDurationRef.value = math.max(maxDurationRef.value or 0, duration)
                    added = true
                end
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
        for spellId, spellName in pairs(TRACKED_HOT_SPELL_NAMES) do
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

    local currentCount = math.min(#remainingDurations, MAX_STACKS)
    local dangerThreshold, warningThreshold = GetThresholdConfig()
    local totalDuration = math.max(maxDuration or 0, remainingDurations[1] or 0)

    if currentCount == 0 then
        return {
            count = 0,
            segments = {},
            totalDuration = totalDuration,
        }
    end

    local segments = {}
    local healthyDuration = currentCount >= warningThreshold and math.min(remainingDurations[warningThreshold] or 0, totalDuration) or 0
    local warningDuration = currentCount >= dangerThreshold and math.min(remainingDurations[dangerThreshold] or 0, totalDuration) or 0
    local dangerDuration = math.min(remainingDurations[1] or 0, totalDuration)

    if healthyDuration > 0 then
        segments[#segments + 1] = {
            color = "healthy",
            startTime = 0,
            endTime = healthyDuration,
        }
    end

    if warningDuration > healthyDuration then
        segments[#segments + 1] = {
            color = "warning",
            startTime = healthyDuration,
            endTime = warningDuration,
        }
    end

    if dangerDuration > warningDuration then
        segments[#segments + 1] = {
            color = "danger",
            startTime = warningDuration,
            endTime = dangerDuration,
        }
    end

    return {
        count = currentCount,
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
    if value < 10 then
        return string.format("%.1f", value)
    end

    return tostring(math.ceil(value))
end

function Addon:GetAbundanceCount()
    local seen = {}
    local expirations = {}
    local maxDurationRef = { value = 0 }

    for _, unit in ipairs(GetTrackedUnits()) do
        local guid = UnitGUID(unit)
        if guid and not seen[guid] then
            seen[guid] = true
            CollectUnitAuraExpirations(unit, expirations, maxDurationRef)
        end
    end

    local abundanceCount, abundanceExpiration, abundanceDuration = GetAbundanceBuffInfo()
    self.debugInfo = {
        expirations = #expirations,
        abundanceCount = abundanceCount,
    }

    if #expirations == 0 and abundanceCount > 0 and abundanceExpiration > GetTime() then
        for index = 1, math.min(abundanceCount, MAX_STACKS) do
            expirations[#expirations + 1] = abundanceExpiration
        end
        maxDurationRef.value = math.max(maxDurationRef.value or 0, abundanceDuration or 0, abundanceExpiration - GetTime())
    end

    self.expirations = expirations
    self.maxDuration = maxDurationRef.value
    local timeline = GetTimelineData(expirations, self.maxDuration)
    return timeline.count
end

function Addon:DebugAuraScan()
    local lines = {}
    local units = GetTrackedUnits()

    for _, unit in ipairs(units) do
        if UnitExists(unit) then
            local found = {}

            for spellId, spellName in pairs(TRACKED_HOT_SPELL_NAMES) do
                local auraName, _, _, _, _, expirationTime = UnitAura and UnitAura(unit, spellName, nil, "HELPFUL|PLAYER")
                if auraName then
                    found[#found + 1] = string.format("%s(%d) %.1fs", spellName, spellId, math.max((expirationTime or 0) - GetTime(), 0))
                end
            end

            if #found > 0 then
                lines[#lines + 1] = string.format("%s -> %s", unit, table.concat(found, ", "))
            end
        end
    end

    local abundanceName = ABUNDANCE_SPELL_NAME or "Abundance"
    local auraName, _, count, _, _, expirationTime = UnitAura and UnitAura("player", abundanceName, nil, "HELPFUL")
    if auraName then
        lines[#lines + 1] = string.format("player buff -> %s x%d %.1fs", abundanceName, count or 0, math.max((expirationTime or 0) - GetTime(), 0))
    else
        lines[#lines + 1] = "player buff -> Abundance not found"
    end

    if #lines == 0 then
        lines[1] = "no tracked auras found"
    end

    DEFAULT_CHAT_FRAME:AddMessage("AbundanceTracker debug: " .. table.concat(lines, " | "))
end

function Addon:DebugPlayerBuffs()
    local lines = {}

    if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        local abundanceAura = C_UnitAuras.GetPlayerAuraBySpellID(ABUNDANCE_SPELL_ID)
        if abundanceAura then
            lines[#lines + 1] = string.format(
                "player abundance modern id=%s count=%s rem=%.1f",
                tostring(rawget(abundanceAura, "spellId")),
                tostring(rawget(abundanceAura, "applications") or rawget(abundanceAura, "count") or 0),
                math.max((rawget(abundanceAura, "expirationTime") or 0) - GetTime(), 0)
            )
        else
            lines[#lines + 1] = "player abundance modern not found"
        end

        local slots = { C_UnitAuras.GetAuraSlots("player", "HELPFUL") }
        local preview = {}
        for index = 2, math.min(#slots, 12) do
            local slot = slots[index]
            if type(slot) == "number" then
                local aura = C_UnitAuras.GetAuraDataBySlot("player", slot)
                if aura then
                    preview[#preview + 1] = string.format(
                        "%s(id=%s,count=%s)",
                        tostring(rawget(aura, "name")),
                        tostring(rawget(aura, "spellId")),
                        tostring(rawget(aura, "applications") or rawget(aura, "count") or 0)
                    )
                end
            end
        end
        if #preview > 0 then
            lines[#lines + 1] = "modern buffs -> " .. table.concat(preview, ", ")
        end
    end

    if UnitBuff then
        for index = 1, 40 do
            local name, _, count, _, duration, expirationTime, sourceUnit, _, _, spellId = UnitBuff("player", index)
            if not name then
                break
            end

            lines[#lines + 1] = string.format(
                "%d:%s id=%s count=%s src=%s rem=%.1f",
                index,
                name,
                tostring(spellId),
                tostring(count or 0),
                tostring(sourceUnit),
                math.max((expirationTime or 0) - GetTime(), 0)
            )
        end
    end

    if #lines == 0 then
        lines[1] = "no player buffs found"
    end

    DEFAULT_CHAT_FRAME:AddMessage("AbundanceTracker buffs: " .. table.concat(lines, " | "))
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

    self.bar.countText:ClearAllPoints()
    self.bar.countText:SetPoint("RIGHT", self.bar, "LEFT", -4, 0)

    self.bar.background:SetPoint("TOPLEFT", self.bar, "TOPLEFT", 1, -1)
    self.bar.background:SetPoint("BOTTOMRIGHT", self.bar, "BOTTOMRIGHT", -1, 1)

    for _, segment in ipairs(self.bar.segments) do
        segment:ClearAllPoints()
        segment.label:ClearAllPoints()
    end
end

function Addon:UpdateTimelineVisuals()
    if not self.bar then
        return
    end

    local timeline = GetTimelineData(self.expirations or {}, self.maxDuration or 0)
    local count = timeline.count
    local known = HasAbundanceTalent()
    local shouldShow = count > 0 or (known and self:GetSetting("showWhenInactive"))

    if not shouldShow then
        self.bar:Hide()
        return
    end

    self.bar:Show()
    self.bar.countText:SetText(tostring(count))
    if self:GetSetting("showCountText") then
        self.bar.countText:Show()
    else
        self.bar.countText:Hide()
    end

    local barWidth = math.max(self.bar.background:GetWidth(), 1)
    local totalDuration = math.max(timeline.totalDuration, 0.001)
    local frameWidthUnit = barWidth / totalDuration
    local minInsideWidth = 24
    local previousLabelRight = -math.huge
    local lastLabelByColor = {}

    for index, data in ipairs(timeline.segments) do
        local segment = self.bar.segments[index]
        local leftOffset = data.startTime * frameWidthUnit
        local rightOffset = data.endTime * frameWidthUnit

        if rightOffset - leftOffset > 0.5 then
            local r, g, b, a = GetSegmentColorForBand(data.color)
            segment:SetColorTexture(r, g, b, a)
            segment:ClearAllPoints()
            segment:SetPoint("TOPLEFT", self.bar.background, "TOPLEFT", leftOffset, 0)
            segment:SetPoint("BOTTOMLEFT", self.bar.background, "BOTTOMLEFT", leftOffset, 0)
            segment:SetPoint("RIGHT", self.bar.background, "LEFT", rightOffset, 0)
            segment:Show()

            segment.label:SetText(FormatSeconds(data.endTime))
            segment.label:ClearAllPoints()
            local segmentWidth = segment:GetWidth()
            if segmentWidth >= minInsideWidth then
                segment.label:SetPoint("CENTER", segment, "CENTER", 0, 0)
            else
                segment.label:SetPoint("LEFT", segment, "RIGHT", 3, 0)
            end

            local labelLeft = segment.label:GetLeft() or 0
            local labelRight = segment.label:GetRight() or 0
            if labelLeft <= previousLabelRight then
                segment.label:Hide()
            else
                segment.label:Show()
                previousLabelRight = labelRight
                lastLabelByColor[GetSegmentColorKey(data.color)] = segment.label
            end
        else
            segment:Hide()
            segment.label:Hide()
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
            else
                seenLabels[winningLabel] = true
            end
        end
    end

    for index = #timeline.segments + 1, #self.bar.segments do
        self.bar.segments[index]:Hide()
        self.bar.segments[index].label:Hide()
    end

    self.bar.tooltipText = string.format(
        "Abundance: %d active HoTs (%d%% cost reduction / crit).",
        count,
        count * 8
    )
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

    bar:SetBackdrop({
        bgFile = "Interface/Buttons/WHITE8X8",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    bar:SetBackdropColor(0.02, 0.04, 0.02, 0.72)
    bar:SetBackdropBorderColor(0.2, 0.35, 0.2, 0.95)

    bar.background = bar:CreateTexture(nil, "BACKGROUND")
    bar.background:SetColorTexture(0.03, 0.03, 0.03, 0.75)

    bar.segments = {}
    for index = 1, 3 do
        local segment = bar:CreateTexture(nil, "ARTWORK")
        local r, g, b, a = GetSegmentColorLegacy(index)
        segment:SetColorTexture(r, g, b, a)

        local label = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetTextColor(1, 1, 1)

        segment.label = label
        bar.segments[index] = segment
    end

    bar.countText = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    bar.countText:SetJustifyH("LEFT")
    bar.countText:SetTextColor(0.92, 0.98, 0.92)

    bar:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("AbundanceTracker")
        GameTooltip:AddLine(self.tooltipText or "Abundance: 0 active HoTs (0% cost reduction / crit).", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    bar:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    self.bar = bar
    self.eventFrame = self.eventFrame or CreateFrame("Frame")
    self.eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    self.eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    self.eventFrame:RegisterEvent("PLAYER_TALENT_UPDATE")
    self.eventFrame:RegisterEvent("UNIT_AURA")
    self.eventFrame:SetScript("OnEvent", function(_, event, unit)
        if event ~= "UNIT_AURA" or not unit or UnitInParty(unit) or UnitInRaid(unit) or UnitIsUnit(unit, "player") then
            Addon:UpdateBar()
        end
    end)

    bar:SetScript("OnUpdate", function()
        Addon:GetAbundanceCount()
        Addon:UpdateTimelineVisuals()
    end)

    self:ApplyLayout()
    self:UpdateBar()
end
