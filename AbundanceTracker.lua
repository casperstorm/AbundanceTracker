local addonName, Addon = ...

local defaults = {
    locked = false,
    point = "CENTER",
    relativePoint = "CENTER",
    x = 0,
    y = -170,
    scale = 1,
    width = 200,
    height = 15,
    showWhenInactive = true,
    inCombatOnly = false,
    showCounter = true,
    showTimers = true,
    showStackLabels = false,
    stackLabelOffset = 4,
    counterFontSize = 12,
    timerFontSize = 8,
    stackLabelFontSize = 8,
    showDecimalTimers = true,
    dangerThreshold = 5,
    warningThreshold = 9,
}

local function InitializeDB()
    if not AbundanceTrackerDB then
        AbundanceTrackerDB = {}
    end

    for key, value in pairs(defaults) do
        if AbundanceTrackerDB[key] == nil then
            AbundanceTrackerDB[key] = value
        end
    end
end

function Addon:GetSetting(key)
    return AbundanceTrackerDB and AbundanceTrackerDB[key]
end

function Addon:SetSetting(key, value)
    if not AbundanceTrackerDB then
        AbundanceTrackerDB = {}
    end

    AbundanceTrackerDB[key] = value

    if Addon.ApplyLayout then
        Addon:ApplyLayout()
    end

    if Addon.UpdateBar then
        Addon:UpdateBar()
    end

end

local function SaveFramePosition(frame, prefix)
    if not frame or not AbundanceTrackerDB then
        return
    end

    local pointKey = prefix == "" and "point" or (prefix .. "Point")
    local relativePointKey = prefix == "" and "relativePoint" or (prefix .. "RelativePoint")
    local xKey = prefix == "" and "x" or (prefix .. "X")
    local yKey = prefix == "" and "y" or (prefix .. "Y")
    local point, _, relativePoint, x, y = frame:GetPoint(1)
    AbundanceTrackerDB[pointKey] = point or defaults[pointKey]
    AbundanceTrackerDB[relativePointKey] = relativePoint or defaults[relativePointKey]
    AbundanceTrackerDB[xKey] = x or defaults[xKey]
    AbundanceTrackerDB[yKey] = y or defaults[yKey]
end

local function ResetFramePosition(prefix)
    if not AbundanceTrackerDB then
        return
    end

    local pointKey = prefix == "" and "point" or (prefix .. "Point")
    local relativePointKey = prefix == "" and "relativePoint" or (prefix .. "RelativePoint")
    local xKey = prefix == "" and "x" or (prefix .. "X")
    local yKey = prefix == "" and "y" or (prefix .. "Y")
    AbundanceTrackerDB[pointKey] = defaults[pointKey]
    AbundanceTrackerDB[relativePointKey] = defaults[relativePointKey]
    AbundanceTrackerDB[xKey] = defaults[xKey]
    AbundanceTrackerDB[yKey] = defaults[yKey]
end

function Addon:SavePosition()
    SaveFramePosition(self.bar, "")
end

function Addon:ResetPosition()
    ResetFramePosition("")

    if self.ApplyLayout then
        self:ApplyLayout()
    end
end

local function RegisterOptionsPanel()
    local panel = CreateFrame("Frame")
    panel.name = "AbundanceTracker"

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("AbundanceTracker")

    local openBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    openBtn:SetSize(150, 24)
    openBtn:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12)
    openBtn:SetText("Open Settings")
    openBtn:SetScript("OnClick", function()
        HideUIPanel(SettingsPanel)
        Addon:OpenConfig()
    end)

    local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
    category.ID = panel.name
    Settings.RegisterAddOnCategory(category)
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

frame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        InitializeDB()
        RegisterOptionsPanel()
    elseif event == "PLAYER_LOGIN" then
        Addon:InitializeBar()
    end
end)

SLASH_ABUNDANCETRACKER1 = "/abundance"
SLASH_ABUNDANCETRACKER2 = "/abundancetracker"
SLASH_ABUNDANCETRACKER3 = "/abt"

SlashCmdList["ABUNDANCETRACKER"] = function(msg)
    msg = msg and msg:lower() or ""

    if msg == "lock" then
        Addon:SetSetting("locked", true)
        return
    end

    if msg == "unlock" then
        Addon:SetSetting("locked", false)
        return
    end

    if msg == "reset" then
        Addon:ResetPosition()
        return
    end

    Addon:OpenConfig()
end
