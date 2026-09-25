-- Deterministic, renderer-independent preview helpers.

local preview = {};

local function copyMap(source)
    local result = {};
    for key,value in pairs(source or {}) do
        result[key] = value;
    end
    return result;
end

local function copyList(source)
    local result = {};
    for index,value in ipairs(source or {}) do
        result[index] = value;
    end
    return result;
end

local function sortedKeys(left, right)
    local keys = {};
    local seen = {};
    for key,_ in pairs(left or {}) do
        seen[key] = true;
    end
    for key,_ in pairs(right or {}) do
        seen[key] = true;
    end
    for key,_ in pairs(seen) do
        table.insert(keys, key);
    end
    table.sort(keys);
    return keys;
end

function preview.explain(result, policy)
    local totals = {};
    for _,stat in ipairs(sortedKeys(result and result.stats or {}, {})) do
        totals[stat] = result.stats[stat];
    end

    local objectives = {};
    for _,objective in ipairs(result and result.objectives or {}) do
        table.insert(objectives, {
            rank = objective.rank,
            stat = objective.stat,
            label = objective.label,
            raw = objective.raw,
            compared = objective.compared,
            cap = objective.cap,
            target = objective.target,
            direction = objective.direction,
        });
    end

    return {
        context = result and result.context or nil,
        context_label = result and result.context_label or nil,
        totals = totals,
        objectives = objectives,
        missing_tags = copyList(result and result.missing_tags or {}),
        candidate_counts = copyMap(result and result.candidate_counts or {}),
        policy_objective_count = #(policy and policy.objectives or {}),
    };
end

function preview.delta(before, after)
    local delta = {
        stats = {},
        slots = {},
    };
    for _,stat in ipairs(sortedKeys(before and before.stats or {}, after and after.stats or {})) do
        local change = (after and after.stats and after.stats[stat] or 0)
            - (before and before.stats and before.stats[stat] or 0);
        if change ~= 0 then
            delta.stats[stat] = change;
        end
    end

    local beforeSet = before and before.set or {};
    local afterSet = after and after.set or {};
    local slots = {};
    for slot,_ in pairs(beforeSet) do
        slots[slot] = true;
    end
    for slot,_ in pairs(afterSet) do
        slots[slot] = true;
    end
    local orderedSlots = {};
    for slot,_ in pairs(slots) do
        table.insert(orderedSlots, slot);
    end
    table.sort(orderedSlots);
    for _,slot in ipairs(orderedSlots) do
        local left = beforeSet[slot];
        local right = afterSet[slot];
        local leftKey = left and left.instance_key or nil;
        local rightKey = right and right.instance_key or nil;
        if leftKey ~= rightKey then
            delta.slots[slot] = {
                before = left and left.name or nil,
                after = right and right.name or nil,
            };
        end
    end
    return delta;
end

return preview;
