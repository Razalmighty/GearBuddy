local policies = require("data.policies");

local policy = {};
policy.__index = policy;

local contextOrder = {
    BLU = { "engaged", "physical", "magical", "debuff", "drain", "healing", "breath", "buff", "buff_skill", "learning", "evasion", "idle", "pdt", "mdt" },
    BLM = { "nuke", "fast_cast", "resting", "idle", "pdt", "mdt" },
};

local aliases = {
    fastcast = "fast_cast",
    fast = "fast_cast",
    physicalmagic = "physical",
    magicalmagic = "magical",
    drainmagic = "drain",
    skillbuff = "buff_skill",
    breathmagic = "breath",
    learn = "learning",
    magicdefense = "mdt",
    physicaldefense = "pdt",
};

local function deepCopy(value)
    if type(value) ~= "table" then
        return value;
    end
    local result = {};
    for key,item in pairs(value) do
        result[key] = deepCopy(item);
    end
    return result;
end

local function objectiveMap(objectives)
    local result = {};
    for _,objective in ipairs(objectives) do
        result[objective.stat] = objective;
    end
    return result;
end

local function applyStatOrder(result, order)
    local byStat = objectiveMap(result.objectives);
    local reordered = {};
    for _,stat in ipairs(order or {}) do
        if byStat[stat] ~= nil then
            table.insert(reordered, byStat[stat]);
            byStat[stat] = nil;
        end
    end
    for _,objective in ipairs(result.objectives) do
        if byStat[objective.stat] ~= nil then
            table.insert(reordered, objective);
            byStat[objective.stat] = nil;
        end
    end
    result.objectives = reordered;
end

local function actionFocusOrder(result, state)
    local action = state and state.action_context or nil;
    if type(action) ~= "table"
        or action.known ~= true
        or action.job ~= result.job
        or action.context_key ~= result.key
        or type(action.dominant_stats) ~= "table"
        or #action.dominant_stats == 0 then
        return nil;
    end
    local order = {};
    if result.key == "physical" then
        order = { "blue_magic_skill", "accuracy" };
    elseif result.key == "magical"
        or result.key == "debuff"
        or result.key == "drain" then
        order = { "magic_accuracy", "blue_magic_skill" };
    end
    local seen = {};
    for _,stat in ipairs(order) do
        seen[stat] = true;
    end
    for _,stat in ipairs(action.dominant_stats) do
        if not seen[stat] then
            table.insert(order, stat);
            seen[stat] = true;
        end
    end
    return order;
end

function policy.new(diagnostics)
    return setmetatable({
        diagnostics = diagnostics,
    }, policy);
end

function policy:jobs()
    return { "AUTO", "BLU", "BLM" };
end

function policy:contexts(job)
    local result = {};
    local jobData = policies.jobs[job];
    if jobData == nil then
        return result;
    end
    for _,key in ipairs(contextOrder[job] or {}) do
        local value = jobData.contexts[key];
        if value ~= nil then
            table.insert(result, { key = key, label = value.label });
        end
    end
    return result;
end

function policy:normalizeContext(job, value)
    local key = string.lower(tostring(value or "")):gsub("[^a-z0-9_]", "");
    key = aliases[key] or key;
    local jobData = policies.jobs[job];
    if jobData ~= nil and jobData.contexts[key] ~= nil then
        return key;
    end
    return nil;
end

function policy:defaultContext(job)
    local jobData = policies.jobs[job];
    return jobData and jobData.default_context or nil;
end

function policy:profiles(job, contextKey)
    local jobData = policies.jobs[job];
    local source = jobData and jobData.contexts[contextKey] or nil;
    local result = {};
    local seen = {};
    for _,objective in ipairs(source and source.objectives or {}) do
        if not seen[objective.stat] then
            table.insert(result, {
                key = objective.stat,
                label = objective.label,
            });
            seen[objective.stat] = true;
        end
    end
    return result;
end

function policy:normalizeProfile(job, contextKey, value)
    local normalized = string.lower(tostring(value or ""))
        :gsub("[^a-z0-9_]", "");
    for _,entry in ipairs(self:profiles(job, contextKey)) do
        local label = string.lower(entry.label):gsub("[^a-z0-9_]", "");
        if normalized == entry.key or normalized == label then
            return entry.key;
        end
    end
    return nil;
end

function policy:get(job, contextKey, state)
    local jobData = policies.jobs[job];
    if jobData == nil then
        return nil;
    end
    local source = jobData.contexts[contextKey];
    if source == nil then
        return nil;
    end
    local result = deepCopy(source);
    result.job = job;
    result.key = contextKey;

    if result.dynamic_balance == "blm_nuke" then
        local balance = state.ui.blm_nuke_balance[1] or 50;
        if balance <= 33 then
            applyStatOrder(result, {
                "magic_accuracy", "elemental_magic_skill", "magic_attack_bonus", "int", "mp",
            });
        elseif balance >= 67 then
            applyStatOrder(result, {
                "magic_attack_bonus", "int", "magic_accuracy", "elemental_magic_skill", "mp",
            });
        end
    end

    applyStatOrder(result, actionFocusOrder(result, state));

    local overrideKey = job .. ":" .. contextKey;
    applyStatOrder(result, state.priority_overrides[overrideKey]);
    local primary = result.objectives[1];
    result.profile_key = primary and primary.stat or "default";
    result.profile_label = primary and primary.label or "Default";
    return result;
end

function policy:move(job, contextKey, state, index, delta)
    local current = self:get(job, contextKey, state);
    if current == nil then
        return false;
    end
    local destination = index + delta;
    if destination < 1 or destination > #current.objectives then
        return false;
    end
    local order = {};
    for _,objective in ipairs(current.objectives) do
        table.insert(order, objective.stat);
    end
    order[index], order[destination] = order[destination], order[index];
    state.priority_overrides[job .. ":" .. contextKey] = order;
    state.policy_revision = state.policy_revision + 1;
    state.dirty_result = true;
    self.diagnostics:add("policy", string.format(
        "%s/%s objective %d moved to %d",
        job,
        contextKey,
        index,
        destination
    ));
    return true;
end

function policy:clearOverride(job, contextKey, state)
    state.priority_overrides[job .. ":" .. contextKey] = nil;
    state.policy_revision = state.policy_revision + 1;
    state.dirty_result = true;
end

function policy:activateProfile(job, contextKey, state, profileKey)
    profileKey = self:normalizeProfile(job, contextKey, profileKey);
    local current = self:get(job, contextKey, state);
    if profileKey == nil or current == nil then
        return false;
    end
    local order = { profileKey };
    for _,objective in ipairs(current.objectives) do
        if objective.stat ~= profileKey then
            table.insert(order, objective.stat);
        end
    end
    state.priority_overrides[job .. ":" .. contextKey] = order;
    state.policy_revision = state.policy_revision + 1;
    state.dirty_result = true;
    self.diagnostics:add("policy", string.format(
        "%s/%s profile=%s",
        job,
        contextKey,
        profileKey
    ));
    return true;
end

return policy;
