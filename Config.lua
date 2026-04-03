local _, Addon = ...

local configFrame = nil

local function CreateCheckbox(parent, label, dbKey, yOffset)
    local checkbox = CreateFrame("CheckButton", nil, parent, "InterfaceOptionsCheckButtonTemplate")
    checkbox.Text:SetText(label)
    checkbox.Text:SetFontObject("GameFontNormal")
    checkbox:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, yOffset)
    checkbox:SetChecked(Addon:GetSetting(dbKey))
    checkbox:SetScript("OnClick", function(self)
        Addon:SetSetting(dbKey, self:GetChecked())
    end)
    return checkbox
end

local function CreateSlider(parent, label, dbKey, minVal, maxVal, step, yOffset, formatValue)
    local container = CreateFrame("Frame", nil, parent)
    container:SetPoint("TOPLEFT", 0, yOffset)
    container:SetPoint("TOPRIGHT", 0, yOffset)
    container:SetHeight(32)

    local labelText = container:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    labelText:SetPoint("LEFT", 0, 0)
    labelText:SetWidth(140)
    labelText:SetJustifyH("LEFT")
    labelText:SetText(label)

    local currentValue = Addon:GetSetting(dbKey)
    if type(currentValue) ~= "number" then
        currentValue = minVal
    end

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
            if step < 1 then
                return string.format("%.1f", value)
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

local function GetDropdownLabel(options, value)
    for _, option in ipairs(options) do
        if option.value == value then
            return option.label
        end
    end

    return options[1] and options[1].label or ""
end

local function CreateDropdown(parent, label, dbKey, options, yOffset)
    local container = CreateFrame("Frame", nil, parent)
    container:SetPoint("TOPLEFT", 0, yOffset)
    container:SetPoint("TOPRIGHT", 0, yOffset)
    container:SetHeight(52)

    local labelText = container:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    labelText:SetPoint("TOPLEFT", 0, 0)
    labelText:SetText(label)

    local dropdown = CreateFrame("Frame", nil, container, "UIDropDownMenuTemplate")
    dropdown:SetPoint("TOPLEFT", labelText, "BOTTOMLEFT", -16, -6)
    UIDropDownMenu_SetWidth(dropdown, 160)
    UIDropDownMenu_SetText(dropdown, GetDropdownLabel(options, Addon:GetSetting(dbKey)))

    UIDropDownMenu_Initialize(dropdown, function(self, level)
        for _, option in ipairs(options) do
            local optionValue = option.value
            local optionLabel = option.label
            local info = UIDropDownMenu_CreateInfo()
            info.text = optionLabel
            info.value = optionValue
            info.checked = Addon:GetSetting(dbKey) == optionValue
            info.func = function()
                Addon:SetSetting(dbKey, optionValue)
                UIDropDownMenu_SetText(dropdown, optionLabel)
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)

    return container
end

local function CreateConfigFrame()
    local frame = CreateFrame("Frame", "AbundanceTrackerConfigFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(420, 700)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame.TitleText:SetText("Abundance Tracker")
    frame.CloseButton:SetScript("OnClick", function() frame:Hide() end)

    tinsert(UISpecialFrames, "AbundanceTrackerConfigFrame")

    local content = CreateFrame("Frame", nil, frame)
    content:SetPoint("TOPLEFT", frame.InsetBg, "TOPLEFT", 14, -14)
    content:SetPoint("BOTTOMRIGHT", frame.InsetBg, "BOTTOMRIGHT", -26, 14)

    local y = 0
    CreateCheckbox(content, "Lock bar position", "locked", y)
    y = y - 35
    CreateDropdown(content, "Visibility", "visibilityMode", {
        { label = "Always", value = "always" },
        { label = "Raid Only", value = "raid" },
    }, y)
    y = y - 62
    CreateCheckbox(content, "Show stack counter", "showCounter", y)
    y = y - 40
    CreateCheckbox(content, "Show timer labels", "showTimers", y)
    y = y - 40
    CreateCheckbox(content, "Show stack labels", "showStackLabels", y)
    y = y - 40
    CreateCheckbox(content, "Show decimal timers", "showDecimalTimers", y)
    y = y - 40
    CreateSlider(content, "Stack label Y offset", "stackLabelOffset", 0, 12, 1, y)
    y = y - 38
    CreateSlider(content, "Counter font size", "counterFontSize", 8, 24, 1, y)
    y = y - 38
    CreateSlider(content, "Timer font size", "timerFontSize", 6, 24, 1, y)
    y = y - 38
    CreateSlider(content, "Stack font size", "stackLabelFontSize", 6, 24, 1, y)
    y = y - 38
    CreateSlider(content, "Red below", "dangerThreshold", 1, 12, 1, y)
    y = y - 38
    CreateSlider(content, "Yellow below", "warningThreshold", 1, 12, 1, y)
    y = y - 38
    CreateSlider(content, "Scale", "scale", 0.5, 2, 0.05, y, function(value)
        return string.format("%.2fx", value)
    end)
    y = y - 38
    CreateSlider(content, "Width", "width", 120, 360, 1, y)
    y = y - 38
    CreateSlider(content, "Height", "height", 10, 40, 1, y)
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
