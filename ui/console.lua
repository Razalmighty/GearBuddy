local imgui = require("imgui");
local schema = require("data.schema");

local console = {};
console.__index = console;

function console.new()
    return setmetatable({}, console);
end

local function coloredStatus(enabled, label)
    if enabled then
        imgui.TextColored({ 0.30, 0.90, 0.45, 1.00 }, label .. ": ON");
    else
        imgui.TextColored({ 0.65, 0.65, 0.65, 1.00 }, label .. ": OFF");
    end
end

local function renderJobSelector(app)
    local state = app.state;
    if imgui.BeginCombo("Preview job", state.selected_job, ImGuiComboFlags_None) then
        for _,job in ipairs(app.policy:jobs()) do
            local selected = state.selected_job == job;
            if imgui.Selectable(job, selected) then
                app:setJob(job);
            end
        end
        imgui.EndCombo();
    end
end

local function renderContextSelector(app)
    local job = app:effectiveJob();
    local currentKey = app.state.selected_context[job];
    local label = currentKey or "Unavailable";
    for _,entry in ipairs(app.policy:contexts(job)) do
        if entry.key == currentKey then
            label = entry.label;
        end
    end
    if imgui.BeginCombo("Context", label, ImGuiComboFlags_None) then
        for _,entry in ipairs(app.policy:contexts(job)) do
            local selected = entry.key == currentKey;
            if imgui.Selectable(entry.label, selected) then
                app:setContext(entry.key);
            end
        end
        imgui.EndCombo();
    end
end

local function renderActionSelector(app)
    local job = app:effectiveJob();
    if job ~= "BLU" then
        return;
    end
    local current = app.state.action_context;
    local label = current.known and current.action_name or "None (manual context)";
    if imgui.BeginCombo("Verified action preview", label, ImGuiComboFlags_None) then
        if imgui.Selectable("None (manual context)", not current.known) then
            app:clearActionPreview();
        end
        local rows = app.action_context:list(
            job,
            app.state.player.effective_level
        );
        for _,row in ipairs(rows) do
            local selected = current.known and current.action_id == row.id;
            local rowLabel = string.format("Lv%d  %s", row.required_level, row.name);
            if imgui.Selectable(rowLabel, selected) then
                app:previewAction(row.id);
            end
        end
        imgui.EndCombo();
    end
    if current.known then
        imgui.TextWrapped(string.format(
            "%s | %s | %s | %s confidence | source %s",
            current.category,
            current.context_key,
            current.element or "None",
            current.confidence,
            current.source_id
        ));
        if current.multi_hit then
            imgui.Text(string.format("Independent hit checks: %d", current.hit_count));
        end
        if #current.dominant_stats > 0 then
            imgui.Text("Qualitative stat focus: " .. table.concat(current.dominant_stats, " / "));
        end
        if current.best_use ~= nil then
            imgui.TextWrapped("Best use: " .. current.best_use);
        end
        if current.job_trait ~= nil and current.job_trait ~= "None" then
            imgui.Text(string.format(
                "Set trait: %s | Tracker priority: %s",
                current.job_trait,
                current.tracker_priority or "Unrated"
            ));
        end
        local mechanics = current.mechanics;
        if mechanics ~= nil and mechanics.known then
            local parts = {};
            for _,outcome in ipairs(mechanics.outcomes or {}) do
                table.insert(parts, outcome.type .. "=" .. outcome.status);
            end
            imgui.TextWrapped("Mechanics evidence: " .. table.concat(parts, " | "));
        else
            imgui.TextColored(
                { 1.00, 0.65, 0.20, 1.00 },
                "Mechanics evidence: pending; no numeric relationship is assumed."
            );
        end
    end
end

local function displayContext(app, job, contextKey)
    for _,entry in ipairs(app.policy:contexts(job)) do
        if entry.key == contextKey then
            return entry.label;
        end
    end
    return contextKey or "Unavailable";
end

local function displayProfile(app, job, contextKey, profileKey)
    for _,entry in ipairs(app.policy:profiles(job, contextKey)) do
        if entry.key == profileKey then
            return entry.label;
        end
    end
    return profileKey or "Unavailable";
end

local function renderForceSwapLauncher(app)
    local state = app.state;
    local buttonLabel = state.ui.force_swap_open[1]
        and "Close Force Swap"
        or "Open Force Swap";
    if imgui.Button(buttonLabel) then
        state.ui.force_swap_open[1] = not state.ui.force_swap_open[1];
    end
    imgui.SameLine();
    imgui.Text("Manual preferences; Auto returns a slot to the formula.");
end

local function renderForceSwap(app)
    local state = app.state;
    if not state.ui.force_swap_open[1] then
        return;
    end
    if imgui.Begin(
        "GearBuddy Force Swap##GearBuddyForceSwapWindow",
        state.ui.force_swap_open,
        ImGuiWindowFlags_AlwaysAutoResize
    ) then
        local job,contextKey,profileKey = app:pinEditorScope();
        if contextKey == nil or profileKey == nil then
            imgui.TextWrapped("Force Swap is available for a supported preview job.");
        else
            imgui.TextColored({ 0.25, 0.85, 1.00, 1.00 }, "READ-ONLY PREFERENCES");
            imgui.TextWrapped(
                "Pins use stable item IDs. Dropdowns read the cached inventory only; "
                .. "they do not trigger another game inventory scan."
            );
            if imgui.BeginCombo(
                "Override set",
                displayContext(app, job, contextKey),
                ImGuiComboFlags_None
            ) then
                for _,entry in ipairs(app.policy:contexts(job)) do
                    if imgui.Selectable(entry.label, entry.key == contextKey) then
                        app:setPinEditorContext(entry.key);
                    end
                end
                imgui.EndCombo();
            end

            -- Context may have changed in the combo above.
            job,contextKey,profileKey = app:pinEditorScope();
            if imgui.BeginCombo(
                "Priority profile",
                displayProfile(app, job, contextKey, profileKey),
                ImGuiComboFlags_None
            ) then
                for _,entry in ipairs(app.policy:profiles(job, contextKey)) do
                    if imgui.Selectable(entry.label, entry.key == profileKey) then
                        app:setPinEditorProfile(entry.key);
                    end
                end
                imgui.EndCombo();
            end
            job,contextKey,profileKey = app:pinEditorScope();

            if imgui.Button("Use this priority profile") then
                app:usePinEditorProfile();
            end
            imgui.SameLine();
            imgui.Text(string.format(
                "%s / %s / %s",
                job,
                displayContext(app, job, contextKey),
                displayProfile(app, job, contextKey, profileKey)
            ));

            local result = state.result;
            local showingActiveResult = result ~= nil
                and result.error == nil
                and result.job == job
                and result.context == contextKey
                and result.profile_key == profileKey;
            for _,slot in ipairs(schema.slots) do
                local pin = app.gear_pins:get(
                    state,
                    job,
                    contextKey,
                    profileKey,
                    slot.name
                );
                local preview = app.gear_pins:label(
                    state,
                    job,
                    contextKey,
                    profileKey,
                    slot.name
                );
                if imgui.BeginCombo(
                    slot.name .. "##GearBuddyForceSwap" .. slot.name,
                    preview,
                    ImGuiComboFlags_None
                ) then
                    if imgui.Selectable("Auto (GearBuddy)", pin == nil) then
                        app:clearGearPin(job, contextKey, profileKey, slot.name);
                    end
                    local options = app:pinOptions(job, slot.name);
                    if #options == 0 then
                        imgui.Text("No owned legal items for this slot.");
                    end
                    for _,option in ipairs(options) do
                        local detail = option.stats_trusted
                            and ""
                            or " [stats unverified]";
                        local copies = option.owned_count > 1
                            and (" x" .. tostring(option.owned_count))
                            or "";
                        local label = string.format(
                            "%s [%d]%s%s",
                            option.name,
                            option.item_id,
                            copies,
                            detail
                        );
                        local selected = pin ~= nil
                            and pin.item_id == option.item_id;
                        if imgui.Selectable(label, selected) then
                            app:setGearPin(
                                job,
                                contextKey,
                                profileKey,
                                slot.name,
                                option.item_id
                            );
                        end
                    end
                    imgui.EndCombo();
                end

                if pin ~= nil then
                    imgui.SameLine();
                    local status = showingActiveResult
                        and result.pins[slot.name]
                        or nil;
                    if status == nil then
                        imgui.TextColored({ 0.45, 0.75, 1.00, 1.00 }, "Saved");
                    elseif status.status == "active" and status.stats_trusted then
                        imgui.TextColored({ 0.30, 0.90, 0.45, 1.00 }, "Manual");
                    elseif status.status == "active" then
                        imgui.TextColored(
                            { 1.00, 0.65, 0.20, 1.00 },
                            "Manual; stats remain unknown"
                        );
                    else
                        imgui.TextColored(
                            { 1.00, 0.45, 0.30, 1.00 },
                            "Formula fallback: "
                                .. app.gear_pins:reasonLabel(status.reason)
                        );
                    end
                end
            end
        end
    end
    imgui.End();
end

local function renderModes(app)
    local state = app.state;
    if imgui.Checkbox("Lock Main / Sub / Range / Ammo", state.ui.weapons_locked) then
        app:setWeaponsLocked(state.ui.weapons_locked[1]);
    end
    if app:effectiveJob() == "BLU" then
        if imgui.Checkbox("Learn plan", state.ui.learn_plan) then
            app:planningModeChanged();
        end
        imgui.SameLine();
        if imgui.Checkbox("Evasion plan", state.ui.evasion_plan) then
            app:planningModeChanged();
        end
        if imgui.Checkbox("Chain plan", state.ui.chain_plan) then
            app:planningModeChanged();
        end
        imgui.SameLine();
        if imgui.Checkbox("Burst plan", state.ui.burst_plan) then
            app:planningModeChanged();
        end
    elseif app:effectiveJob() == "BLM" and app:activeContext() == "nuke" then
        imgui.Text("Nuke bias: 0 = accuracy, 100 = damage");
        if imgui.SliderInt(
            "##GearBuddyNukeBalance",
            state.ui.blm_nuke_balance,
            0,
            100,
            "%d",
            ImGuiSliderFlags_AlwaysClamp
        ) then
            app:nukeBalanceChanged();
        end
    end
end

local function renderIndicators(state)
    coloredStatus(state.indicators.learn, "Learn");
    imgui.SameLine();
    coloredStatus(state.indicators.chain, "Chain");
    imgui.SameLine();
    coloredStatus(state.indicators.burst, "Burst");
    imgui.SameLine();
    coloredStatus(state.indicators.evasion, "Evasion");
end

local function renderApprovalControls(app)
    if imgui.Button("Run self-test") then
        app:runSelfTest(false);
    end
    imgui.SameLine();
    if imgui.Button("Print approval report") then
        app:printApprovalReport();
    end

    local report = app.state.self_test or {};
    local status = report.status or "not_run";
    local color = { 0.65, 0.65, 0.65, 1.00 };
    if status == "pass" then
        color = { 0.30, 0.90, 0.45, 1.00 };
    elseif status == "warn" then
        color = { 1.00, 0.65, 0.20, 1.00 };
    elseif status == "fail" then
        color = { 1.00, 0.35, 0.25, 1.00 };
    end
    local counts = report.counts or {};
    imgui.TextColored(color, string.format(
        "Self-test: %s (%d pass / %d warn / %d fail)",
        string.upper(status),
        counts.pass or 0,
        counts.warn or 0,
        counts.fail or 0
    ));
    for _,check in ipairs(report.checks or {}) do
        if check.status ~= "pass" then
            imgui.TextWrapped(string.format(
                "[%s] %s: %s",
                string.upper(check.status),
                check.label,
                check.detail
            ));
        end
    end
end

local function renderPriorities(app)
    local job = app:effectiveJob();
    local contextKey = app:activeContext();
    local active = app.policy:get(job, contextKey, app.state);
    if active == nil then
        imgui.TextWrapped("No policy is available for the selected job and context.");
        return;
    end
    imgui.Text("Strict objective order");
    for index,objective in ipairs(active.objectives) do
        if imgui.Button("Up##GearBuddyPriorityUp" .. index) then
            app:moveObjective(index, -1);
        end
        imgui.SameLine();
        if imgui.Button("Down##GearBuddyPriorityDown" .. index) then
            app:moveObjective(index, 1);
        end
        imgui.SameLine();
        local suffix = "";
        if objective.cap ~= nil then
            suffix = " (cap " .. tostring(objective.cap) .. ")";
        elseif objective.target ~= nil then
            suffix = " (target " .. tostring(objective.target) .. ")";
        end
        imgui.Text(string.format("%d. %s%s", index, objective.label, suffix));
    end
end

local function renderPreview(app)
    local result = app.state.result;
    if result == nil then
        imgui.Text("Preview not calculated.");
        return;
    end
    if result.error ~= nil then
        imgui.TextWrapped(result.error);
        return;
    end

    imgui.Text(string.format(
        "%s / %s / %s priority / effective level %d",
        result.job,
        result.context_label,
        result.profile_label,
        result.level
    ));
    if #result.missing_tags > 0 then
        imgui.TextColored(
            { 1.00, 0.65, 0.20, 1.00 },
            "Missing required effect: " .. table.concat(result.missing_tags, ", ")
        );
    end
    for _,slot in ipairs(schema.slots) do
        local candidate = result.set[slot.name];
        local pinStatus = result.pins[slot.name];
        if result.locked[slot.name] then
            local suffix = pinStatus ~= nil
                and ("; saved pin inactive: "
                    .. app.gear_pins:reasonLabel(pinStatus.reason))
                or "";
            imgui.Text(slot.name .. ": [manual lock" .. suffix .. "]");
        elseif candidate ~= nil then
            local selectedBy = candidate.selection_source == "manual"
                and "Manual"
                or "Formula";
            local trust = candidate.stats_trusted == false
                and ", stats unknown"
                or "";
            imgui.Text(string.format(
                "%s: %s  (%s%s, bag %d, index %d, %s)",
                slot.name,
                candidate.name,
                selectedBy,
                trust,
                candidate.bag,
                candidate.index,
                candidate.source_id
            ));
        elseif (result.candidate_counts[slot.name] or 0) > 0 then
            imgui.Text(slot.name .. ": [no candidate improved this priority set]");
        else
            imgui.Text(slot.name .. ": [no verified owned candidate]");
        end
        if pinStatus ~= nil and pinStatus.status == "fallback" then
            imgui.TextColored(
                { 1.00, 0.45, 0.30, 1.00 },
                "  Saved pin fell back to Formula: "
                    .. app.gear_pins:reasonLabel(pinStatus.reason)
            );
        end
    end

    imgui.Separator();
    imgui.Text("Gear-derived objective values");
    for _,objective in ipairs(result.objectives) do
        local detail = string.format("%d. %s: %g", objective.rank, objective.label, objective.raw);
        if objective.cap ~= nil then
            detail = detail .. " (comparison cap " .. tostring(objective.cap) .. ")";
        end
        imgui.Text(detail);
    end
end

local function renderUpgrades(app)
    local result = app.state.result;
    if result == nil or result.error ~= nil then
        return;
    end
    imgui.Separator();
    imgui.Text("Next verified upgrades (read-only; pinned slots preserved)");
    local upgrades = result.upgrades or {};
    if #upgrades == 0 then
        imgui.TextWrapped("No verified unowned item currently improves this full-set preview.");
        return;
    end
    for index,upgrade in ipairs(upgrades) do
        local replacement = upgrade.replaced_name or "[empty slot]";
        local firstDelta = upgrade.objective_deltas
            and upgrade.objective_deltas[upgrade.first_improved_rank or 1];
        local deltaText = "";
        if firstDelta ~= nil and firstDelta.compared_delta ~= 0 then
            deltaText = string.format(
                ", %s %+.2f",
                firstDelta.label,
                firstDelta.compared_delta
            );
        end
        imgui.TextWrapped(string.format(
            "%d. %s -> %s (Lv%d, %s%s)",
            index,
            upgrade.slot,
            upgrade.name,
            upgrade.required_level,
            replacement,
            deltaText
        ));
    end
end

function console:render(app)
    local state = app.state;
    if not state.ui.open[1] then
        renderForceSwap(app);
        return;
    end
    if imgui.Begin(
        "GearBuddy v0.1.0-alpha.8",
        state.ui.open,
        ImGuiWindowFlags_AlwaysAutoResize
    ) then
        imgui.TextColored({ 0.25, 0.85, 1.00, 1.00 }, "READ ONLY");
        imgui.SameLine();
        imgui.Text(string.format(
            "Live %s %d | inventory gen %d / scan %d | %d items | %d catalog matches",
            state.player.live_job,
            state.player.effective_level,
            state.inventory.generation,
            state.inventory.refresh_count or 0,
            state.inventory.total_items,
            state.inventory.catalog_matches
        ));
        if imgui.Button("Refresh inventory") then
            app:scheduleRefresh("ui_button", 0);
        end
        imgui.SameLine();
        imgui.Text("Scheduler: " .. app.scheduler:status());
        imgui.SameLine();
        imgui.Checkbox("HUD", state.ui.hud);
        renderApprovalControls(app);

        imgui.Separator();
        renderJobSelector(app);
        renderContextSelector(app);
        renderActionSelector(app);
        renderModes(app);
        renderIndicators(state);

        imgui.Separator();
        renderPriorities(app);
        imgui.Separator();
        renderForceSwapLauncher(app);
        imgui.Separator();
        renderPreview(app);
        renderUpgrades(app);
    end
    imgui.End();
    renderForceSwap(app);
end

return console;
