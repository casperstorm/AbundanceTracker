local _, Addon = ...

local ABUNDANCE_SPELL_ID = 207383
local REJUVENATION_SPELL_ID = 774
local MAX_STACKS = 12

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

local function UnitHasPlayerRejuvenation(unit)
    if not UnitExists(unit) then
        return false
    end

    local aura = AuraUtil.FindAuraBySpellID(REJUVENATION_SPELL_ID, unit, "HELPFUL|PLAYER")
    return aura ~= nil
end

function Addon:GetAbundanceCount()
    local seen = {}
    local count = 0

    for _, unit in ipairs(GetTrackedUnits()) do
        local guid = UnitGUID(unit)
        if guid and not seen[guid] then
            seen[guid] = true
            if UnitHasPlayerRejuvenation(unit) then
                count = count + 1
            end
        end
    end

    return math.min(count, MAX_STACKS)
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

    local width = self.bar:GetWidth()
    local height = self.bar:GetHeight()
    local segmentWidth = width / MAX_STACKS

    for index, segment in ipairs(self.bar.segments) do
        segment:ClearAllPoints()
        segment:SetSize(segmentWidth - 1, height - 2)
        segment:SetPoint("TOPLEFT", self.bar, "TOPLEFT", (index - 1) * segmentWidth + 1, -1)
    end
end

function Addon:UpdateBar()
    if not self.bar then
        return
    end

    local known = IsPlayerSpell(ABUNDANCE_SPELL_ID)
    local count = known and self:GetAbundanceCount() or 0
    local shouldShow = known and (self:GetSetting("showWhenInactive") or count > 0)

    if not shouldShow then
        self.bar:Hide()
        return
    end

    self.bar:Show()

    local percent = count * 8
    self.bar.maxText:SetText(tostring(MAX_STACKS))

    if count > 1 then
        self.bar.previousText:SetText(tostring(count - 1))
        self.bar.previousText:Show()
    else
        self.bar.previousText:Hide()
    end

    self.bar.edgeText:SetText(tostring(count))
    self.bar.edgeText:Show()

    for index, segment in ipairs(self.bar.segments) do
        if index < count then
            segment:SetColorTexture(0.28, 0.62, 0.24, 0.9)
        elseif index == count and count > 0 then
            segment:SetColorTexture(0.86, 0.54, 0.08, 0.95)
        else
            segment:SetColorTexture(0.05, 0.08, 0.05, 0.45)
        end
    end

    local width = self.bar:GetWidth()
    local segmentWidth = width / MAX_STACKS
    if count > 1 then
        local previousX = ((count - 2) * segmentWidth) + (segmentWidth / 2)
        self.bar.previousText:ClearAllPoints()
        self.bar.previousText:SetPoint("CENTER", self.bar, "LEFT", previousX, 0)
    end

    if count > 0 then
        local x = ((count - 1) * segmentWidth) + (segmentWidth / 2)
        self.bar.edgeText:ClearAllPoints()
        self.bar.edgeText:SetPoint("CENTER", self.bar, "LEFT", x, 0)
    else
        self.bar.edgeText:ClearAllPoints()
        self.bar.edgeText:SetPoint("CENTER", self.bar, "LEFT", segmentWidth / 2, 0)
    end

    self.bar.tooltipText = string.format("Abundance: %d Rejuvenations active (%d%% cost reduction / crit).", count, percent)
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

    bar.segments = {}
    for index = 1, MAX_STACKS do
        local segment = bar:CreateTexture(nil, "ARTWORK")
        bar.segments[index] = segment
    end

    bar.previousText = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.previousText:SetTextColor(0.85, 0.92, 0.85)

    bar.edgeText = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    bar.edgeText:SetTextColor(1, 1, 1)

    bar.maxText = bar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    bar.maxText:SetPoint("RIGHT", bar, "RIGHT", -6, 0)
    bar.maxText:SetJustifyH("RIGHT")
    bar.maxText:SetTextColor(0.92, 0.98, 0.92)

    bar:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("AbundanceTracker")
        GameTooltip:AddLine(self.tooltipText or "Abundance: 0 Rejuvenations active (0% cost reduction / crit).", 1, 1, 1, true)
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

    self:ApplyLayout()
    self:UpdateBar()
end
