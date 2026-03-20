local addonName, Addon = ...

local defaults = {
    locked = false,
    point = "CENTER",
    relativePoint = "CENTER",
    x = 0,
    y = -170,
    scale = 1,
    width = 240,
    height = 22,
    showWhenInactive = true,
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

function Addon:SavePosition()
    if not self.bar then
        return
    end

    local point, _, relativePoint, x, y = self.bar:GetPoint(1)
    AbundanceTrackerDB.point = point or defaults.point
    AbundanceTrackerDB.relativePoint = relativePoint or defaults.relativePoint
    AbundanceTrackerDB.x = x or defaults.x
    AbundanceTrackerDB.y = y or defaults.y
end

function Addon:ResetPosition()
    if not AbundanceTrackerDB then
        return
    end

    AbundanceTrackerDB.point = defaults.point
    AbundanceTrackerDB.relativePoint = defaults.relativePoint
    AbundanceTrackerDB.x = defaults.x
    AbundanceTrackerDB.y = defaults.y

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
