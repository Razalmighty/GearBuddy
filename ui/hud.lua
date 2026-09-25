local imgui = require("imgui");

local hud = {};
hud.__index = hud;

function hud.new()
    return setmetatable({}, hud);
end

local function indicator(enabled, label)
    if enabled then
        imgui.TextColored({ 0.25, 0.95, 0.40, 1.00 }, label .. " ON");
    else
        imgui.TextColored({ 0.55, 0.55, 0.55, 1.00 }, label .. " OFF");
    end
end

function hud:render(app)
    local state = app.state;
    if not state.ui.hud[1] then
        return;
    end
    if imgui.Begin(
        "GearBuddy Indicators##GearBuddyHud",
        state.ui.hud,
        ImGuiWindowFlags_AlwaysAutoResize
    ) then
        imgui.TextColored({ 0.25, 0.85, 1.00, 1.00 }, "GearBuddy READ ONLY");
        indicator(state.indicators.learn, "Learn");
        imgui.SameLine();
        indicator(state.indicators.chain, "Chain");
        imgui.SameLine();
        indicator(state.indicators.burst, "Burst");
        imgui.SameLine();
        indicator(state.indicators.evasion, "Evasion");
    end
    imgui.End();
end

return hud;
