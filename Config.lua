local _, Addon = ...

local configFrame = nil

local function CreateCheckbox(parent, label, dbKey, onClick)
    local checkbox = CreateFrame("CheckButton", nil, parent, "InterfaceOptionsCheckButtonTemplate")
    checkbox.Text:SetText(label)
    checkbox.Text:SetFontObject("GameFontNormal")

    checkbox:SetChecked(Addon:GetSetting(dbKey))
    checkbox:SetScript("OnClick", function(self)
        Addon:SetSetting(dbKey, self:GetChecked())
        if onClick then
            onClick(self:GetChecked())
        end
    end)

    return checkbox
end

local function CreateSlider(parent, label, dbKey, minVal, maxVal, step, yOffset, formatValue)
    local container = CreateFrame("Frame", nil, parent)
    container:SetPoint("TOPLEFT", 0, yOffset)
    container:SetPoint("TOPRIGHT", 0, yOffset)
    container:SetHeight(32)

    local currentValue = Addon:GetSetting(dbKey)
    if type(currentValue) ~= "number" then
        currentValue = minVal
    end

    local labelText = container:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    labelText:SetPoint("LEFT", 0, 0)
    labelText:SetWidth(130)
    labelText:SetJustifyH("LEFT")
    labelText:SetText(label)

    local sliderFrame = CreateFrame("Frame", nil, container, "MinimalSliderWithSteppersTemplate")
    sliderFrame:SetPoint("LEFT", labelText, "RIGHT", 8, 0)
    sliderFrame:SetPoint("RIGHT", -40, 0)
    sliderFrame:SetHeight(16)

    local steps = math.floor((maxVal - minVal) / step + 0.5)

    local formatter = CreateMinimalSliderFormatter(
        MinimalSliderWithSteppersMixin.Label.Right,
        function(value)
            if formatValue then
                return formatValue(value)
            end

            return tostring(math.floor(value + 0.5))
        end
    )

    sliderFrame.initInProgress = true
    sliderFrame:Init(currentValue, minVal, maxVal, steps, {
        [MinimalSliderWithSteppersMixin.Label.Right] = formatter,
    })
    sliderFrame.initInProgress = false

    if sliderFrame.MinText then sliderFrame.MinText:Hide() end
    if sliderFrame.MaxText then sliderFrame.MaxText:Hide() end

    if sliderFrame.Slider then
        sliderFrame.Slider:HookScript("OnValueChanged", function(_, value)
            if sliderFrame.initInProgress then
                return
            end

            value = math.floor(value / step + 0.5) * step
            Addon:SetSetting(dbKey, value)
        end)
    end

    return container
end

local function CreateConfigFrame()
    local frame = CreateFrame("Frame", "AbundanceTrackerConfigFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(400, 380)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)

    frame.TitleText:SetText("Abundance Tracker")
    frame.CloseButton:SetScript("OnClick", function()
        frame:Hide()
    end)

    tinsert(UISpecialFrames, "AbundanceTrackerConfigFrame")

    local content = CreateFrame("Frame", nil, frame)
    content:SetPoint("TOPLEFT", frame.InsetBg, "TOPLEFT", 10, -10)
    content:SetPoint("BOTTOMRIGHT", frame.InsetBg, "BOTTOMRIGHT", -20, 10)

    local y = 0

    local lockCheckbox = CreateCheckbox(content, "Lock bar position", "locked")
    lockCheckbox:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)

    y = y - 35

    local showInactiveCheckbox = CreateCheckbox(content, "Show bar at 0 stacks", "showWhenInactive")
    showInactiveCheckbox:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)

    y = y - 40

    local showCountCheckbox = CreateCheckbox(content, "Show stack count beside bar", "showCountText")
    showCountCheckbox:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)

    y = y - 40

    CreateSlider(content, "Red below", "dangerThreshold", 1, 12, 1, y)

    y = y - 38

    CreateSlider(content, "Yellow below", "warningThreshold", 1, 12, 1, y)

    y = y - 38

    y = y - 4

    CreateSlider(content, "Scale", "scale", 0.5, 2, 0.05, y, function(value)
        return string.format("%.2fx", value)
    end)

    y = y - 38

    CreateSlider(content, "Width", "width", 180, 360, 5, y)

    y = y - 38

    CreateSlider(content, "Height", "height", 16, 40, 1, y)

    y = y - 42

    local resetButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    resetButton:SetSize(120, 24)
    resetButton:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
    resetButton:SetText("Reset Position")
    resetButton:SetScript("OnClick", function()
        Addon:ResetPosition()
    end)

    local hint = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", resetButton, "BOTTOMLEFT", 0, -12)
    hint:SetText("Use /abt lock, /abt unlock, or drag the bar when unlocked.")
    hint:SetTextColor(0.75, 0.82, 0.75)

    return frame
end

function Addon:OpenConfig()
    if not configFrame then
        configFrame = CreateConfigFrame()
        configFrame:Show()
        return
    end

    if configFrame:IsShown() then
        configFrame:Hide()
    else
        configFrame:Show()
    end
end
