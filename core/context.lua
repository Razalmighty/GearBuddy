local context = {};
context.__index = context;

local function safe(method, fallback)
    local ok, value = pcall(method);
    if ok and value ~= nil then
        return value;
    end
    return fallback;
end

local function normalized(value)
    return string.lower(tostring(value or "")):gsub("[^a-z0-9]", "");
end

local function sameSet(left, right)
    for key,value in pairs(left) do
        if right[key] ~= value then
            return false;
        end
    end
    for key,value in pairs(right) do
        if left[key] ~= value then
            return false;
        end
    end
    return true;
end

function context.new(diagnostics)
    return setmetatable({
        diagnostics = diagnostics,
    }, context);
end

function context:refreshPlayer(state)
    local memory = AshitaCore:GetMemoryManager();
    local player = memory:GetPlayer();
    local party = memory:GetParty();
    if player == nil then
        return false;
    end

    local jobId = safe(function() return player:GetMainJob(); end, 0);
    local effectiveLevel = safe(function() return player:GetMainJobLevel(); end, 0);
    local naturalLevel = safe(function() return player:GetJobLevel(jobId); end, effectiveLevel);
    local zone = safe(function() return party:GetMemberZone(0); end, 0);
    local job = safe(function()
        return AshitaCore:GetResourceManager():GetString("jobs.names_abbr", jobId);
    end, "Unknown");
    job = string.upper(tostring(job or "Unknown"));

    local changed = state.player.live_job_id ~= jobId
        or state.player.effective_level ~= effectiveLevel
        or state.player.natural_level ~= naturalLevel
        or state.player.zone ~= zone;
    state.player.live_job_id = jobId;
    state.player.live_job = job;
    state.player.effective_level = effectiveLevel;
    state.player.natural_level = naturalLevel;
    state.player.zone = zone;
    if changed then
        self.diagnostics:add("context", string.format(
            "player job=%s effective=%d natural=%d zone=%d",
            job,
            effectiveLevel,
            naturalLevel,
            zone
        ));
    end
    return changed;
end

function context:refreshBuffs(state)
    local buffs = {};
    local player = AshitaCore:GetMemoryManager():GetPlayer();
    if player ~= nil then
        local raw = safe(function() return player:GetBuffs(); end, {});
        for _,buffId in pairs(raw or {}) do
            if type(buffId) == "number" and buffId >= 0 and buffId < 0xFFFF then
                local name = safe(function()
                    return AshitaCore:GetResourceManager():GetString("buffs.names", buffId);
                end, nil);
                if name ~= nil and name ~= "" then
                    buffs[normalized(name)] = true;
                end
            end
        end
    end
    local changed = not sameSet(state.buffs, buffs);
    state.buffs = buffs;
    self:updateIndicators(state);
    if changed then
        self.diagnostics:add("buffs", "named buff state changed");
    end
    return changed;
end

function context:updateIndicators(state)
    state.indicators.learn = state.ui.learn_plan[1];
    state.indicators.evasion = state.ui.evasion_plan[1];
    state.indicators.chain = state.ui.chain_plan[1]
        or state.buffs.chainaffinity == true;
    state.indicators.burst = state.ui.burst_plan[1]
        or state.buffs.burstaffinity == true;
end

function context:effectiveJob(state)
    if state.selected_job == "AUTO" then
        return state.player.live_job;
    end
    return state.selected_job;
end

return context;
