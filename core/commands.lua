local commands = {};

local function tokens(text)
    local result = {};
    for token in string.gmatch(text or "", "%S+") do
        table.insert(result, token);
    end
    return result;
end

local function lower(value)
    return string.lower(tostring(value or ""));
end

local function joinFrom(values, first)
    local result = {};
    for index = first,#values do
        table.insert(result, values[index]);
    end
    return table.concat(result, " ");
end

local function setToggle(buffer, mode)
    if mode == "on" then
        buffer[1] = true;
    elseif mode == "off" then
        buffer[1] = false;
    elseif mode == "toggle" or mode == "" then
        buffer[1] = not buffer[1];
    else
        return false;
    end
    return true;
end

local function handlePin(app, args)
    local job,contextKey,profileKey = app:activePinScope();
    local slotName = args[3];
    local value = args[4];
    if args[6] ~= nil then
        contextKey = args[3];
        profileKey = args[4];
        slotName = args[5];
        value = args[6];
    end
    if slotName == nil or value == nil then
        app:message("Use /gb pin <slot> <item-id|auto>, or /gb pin <context> <profile> <slot> <item-id|auto>.");
        return;
    end
    if lower(value) == "auto" then
        local ok,reason = app:clearGearPin(
            job,
            contextKey,
            profileKey,
            slotName
        );
        if ok then
            app:message("Manual pin cleared; GearBuddy will choose this slot.");
        else
            app:message("Could not clear pin: " .. tostring(reason));
        end
        return;
    end
    local itemId = tonumber(value);
    if itemId == nil then
        app:message("A manual pin must use an owned item ID or auto.");
        return;
    end
    local ok,reason = app:setGearPin(
        job,
        contextKey,
        profileKey,
        slotName,
        itemId
    );
    if ok then
        app:message("Manual pin saved. The remaining slots will optimize around it.");
    else
        app:message("Pin rejected: " .. tostring(reason));
    end
end

function commands.handle(app, event)
    local args = tokens(event.command);
    local root = lower(args[1]);
    if root ~= "/gb" and root ~= "/gearbuddy" then
        return false;
    end
    event.blocked = true;
    local action = lower(args[2]);

    if action == "" then
        app.state.ui.open[1] = not app.state.ui.open[1];
    elseif action == "show" then
        app.state.ui.open[1] = true;
    elseif action == "hide" then
        app.state.ui.open[1] = false;
    elseif action == "refresh" then
        app:scheduleRefresh("manual_command", 0);
        app:message("Inventory refresh scheduled.");
    elseif action == "status" then
        app:printStatus();
    elseif action == "diag" then
        app:printDiagnostics();
    elseif action == "selftest" then
        app:runSelfTest(lower(args[3]) == "verbose");
    elseif action == "report" then
        app:printApprovalReport();
    elseif action == "contexts" then
        app:printContexts();
    elseif action == "actions" then
        app:printActions();
    elseif action == "action" then
        app:previewAction(joinFrom(args, 3));
    elseif action == "pin" then
        handlePin(app, args);
    elseif action == "pins" then
        app:printPins(args[3], args[4]);
    elseif action == "job" then
        if not app:setJob(string.upper(args[3] or "")) then
            app:message("Job must be AUTO, BLU, or BLM.");
        end
    elseif action == "context" then
        if not app:setContext(args[3]) then
            app:message("Unknown context. Use /gb contexts.");
        end
    elseif action == "weapons" then
        local mode = lower(args[3]);
        if mode == "lock" then
            app:setWeaponsLocked(true);
        elseif mode == "unlock" then
            app:setWeaponsLocked(false);
        else
            app:message("Use /gb weapons lock or /gb weapons unlock.");
        end
    elseif action == "learn" then
        if setToggle(app.state.ui.learn_plan, lower(args[3])) then
            app:planningModeChanged();
        else
            app:message("Use on, off, or toggle.");
        end
    elseif action == "evasion" then
        if setToggle(app.state.ui.evasion_plan, lower(args[3])) then
            app:planningModeChanged();
        else
            app:message("Use on, off, or toggle.");
        end
    elseif action == "chain" then
        if setToggle(app.state.ui.chain_plan, lower(args[3])) then
            app:planningModeChanged();
        else
            app:message("Use on, off, or toggle.");
        end
    elseif action == "burst" then
        if setToggle(app.state.ui.burst_plan, lower(args[3])) then
            app:planningModeChanged();
        else
            app:message("Use on, off, or toggle.");
        end
    elseif action == "hud" then
        if not setToggle(app.state.ui.hud, lower(args[3])) then
            app:message("Use on, off, or toggle.");
        end
    else
        app:message("Commands: show, hide, refresh, status, diag, selftest [verbose], report, contexts, actions, action, pin, pins, job, context, weapons, learn, evasion, chain, burst, hud.");
    end
    return true;
end

return commands;
