-- Read-only equipment-plan contract.
--
-- The resolver returns an explanatory preview.  This module turns that preview
-- into the narrow object a future bridge/executor can consume without doing a
-- second inventory scan.  It is deliberately fail-closed: alpha plans are
-- never executable and locked weapon slots are never represented as swaps.

local equipPlan = {};
local schema = require("data.schema");

local function copyEntry(candidate)
    if candidate == nil then
        return nil;
    end
    return {
        item_id = candidate.item_id,
        name = candidate.name,
        bag = candidate.bag,
        index = candidate.index,
        instance_key = candidate.instance_key,
        slot = candidate.slot,
        source_id = candidate.source_id,
        verification = candidate.verification,
        selection_source = candidate.selection_source or "formula",
        stats_trusted = candidate.stats_trusted == true,
    };
end

function equipPlan.fromResult(result, manualSlots)
    local plan = {
        read_only = true,
        executable = false,
        job = result and result.job or nil,
        context = result and result.context or nil,
        profile_key = result and result.profile_key or nil,
        profile_label = result and result.profile_label or nil,
        level = result and result.level or nil,
        inventory_generation = result and result.inventory_generation or nil,
        signature = result and result.signature or "",
        slots = {},
        locked = {},
        unresolved = {},
        pin_status = {},
        warnings = {},
    };

    if result == nil then
        plan.unresolved["__result__"] = "missing_result";
        return plan;
    end

    local selected = result.set or {};
    local locked = result.locked or {};
    local candidates = result.candidate_counts or {};
    for _,slot in ipairs(schema.slots) do
        local slotName = slot.name;
        local status = result.pins and result.pins[slotName] or nil;
        if status ~= nil then
            plan.pin_status[slotName] = {
                status = status.status,
                reason = status.reason,
                item_id = status.item_id,
                stats_trusted = status.stats_trusted,
            };
            if status.status ~= "active" then
                table.insert(plan.warnings, {
                    slot = slotName,
                    kind = "manual_pin_fallback",
                    reason = status.reason,
                    item_id = status.item_id,
                });
            elseif status.stats_trusted ~= true then
                table.insert(plan.warnings, {
                    slot = slotName,
                    kind = "manual_pin_unverified_stats",
                    reason = "stats_unknown",
                    item_id = status.item_id,
                });
            end
        end
    end
    for _,slot in ipairs(schema.slots) do
        local slotName = slot.name;
        if locked[slotName] == true then
            plan.locked[slotName] = "manual_lock";
        elseif selected[slotName] ~= nil then
            plan.slots[slotName] = copyEntry(selected[slotName]);
        elseif (candidates[slotName] or 0) == 0 then
            plan.unresolved[slotName] = "no_verified_owned_candidate";
        else
            plan.unresolved[slotName] = "no_candidate_in_beam";
        end
    end

    return plan;
end

function equipPlan.countSelected(plan)
    local count = 0;
    for _,_ in pairs(plan and plan.slots or {}) do
        count = count + 1;
    end
    return count;
end

return equipPlan;
