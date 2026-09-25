local score = {};

local function copyMap(source)
    local result = {};
    for key,value in pairs(source or {}) do
        result[key] = value;
    end
    return result;
end

function score.extend(state, candidate, slotName)
    local nextState = {
        selected = copyMap(state.selected),
        used = copyMap(state.used),
        stats = copyMap(state.stats),
        tags = copyMap(state.tags),
        signature = state.signature,
    };
    if candidate == nil then
        nextState.signature = nextState.signature .. "|" .. slotName .. "=-";
        return nextState;
    end

    nextState.selected[slotName] = candidate;
    nextState.used[candidate.instance_key] = true;
    for stat,value in pairs(candidate.stats or {}) do
        nextState.stats[stat] = (nextState.stats[stat] or 0) + value;
    end
    for tag,value in pairs(candidate.tags or {}) do
        if value then
            nextState.tags[tag] = true;
        end
    end
    nextState.signature = nextState.signature .. "|" .. slotName .. "="
        .. string.format("%05d:%s", candidate.item_id, candidate.instance_key);
    return nextState;
end

local function requiredCount(state, policy)
    local count = 0;
    for _,tag in ipairs(policy.required_tags or {}) do
        if state.tags[tag] then
            count = count + 1;
        end
    end
    return count;
end

local function objectiveValue(state, objective)
    local value = state.stats[objective.stat] or 0;
    if objective.cap ~= nil then
        value = math.min(value, objective.cap);
    end
    if objective.target ~= nil then
        value = math.min(value, objective.target);
    end
    if objective.direction == "min" then
        value = -value;
    end
    return value;
end

function score.better(left, right, policy)
    local leftRequired = requiredCount(left, policy);
    local rightRequired = requiredCount(right, policy);
    if leftRequired ~= rightRequired then
        return leftRequired > rightRequired;
    end
    for _,objective in ipairs(policy.objectives or {}) do
        local leftValue = objectiveValue(left, objective);
        local rightValue = objectiveValue(right, objective);
        if leftValue ~= rightValue then
            return leftValue > rightValue;
        end
    end
    return left.signature < right.signature;
end

function score.objectiveResults(state, policy)
    local result = {};
    for rank,objective in ipairs(policy.objectives or {}) do
        local raw = state.stats[objective.stat] or 0;
        table.insert(result, {
            rank = rank,
            stat = objective.stat,
            label = objective.label,
            raw = raw,
            compared = objectiveValue(state, objective),
            cap = objective.cap,
            target = objective.target,
            direction = objective.direction,
        });
    end
    return result;
end

return score;
