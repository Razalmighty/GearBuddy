-- Metadata-driven action context resolution.
--
-- This module does not inspect TP, cast spells, choose targets, or equip gear.
-- It only turns a known action metadata row plus current read-only state into a
-- deterministic context object for policy selection and UI explanation.

local actionContext = {};
actionContext.__index = actionContext;

local allowedCategories = {
    physical = true,
    magical = true,
    debuff = true,
    healing = true,
    breath = true,
    buff = true,
    drain = true,
    dispel = true,
    status = true,
};

local allowedConfidence = {
    high = true,
    medium = true,
    low = true,
};

local function copy(value)
    if type(value) ~= "table" then
        return value;
    end
    local result = {};
    for key,item in pairs(value) do
        result[key] = copy(item);
    end
    return result;
end

local function normalizedName(value)
    return (string.lower(tostring(value or "")):gsub("%s+", " "));
end

local function integer(value, fallback)
    if type(value) ~= "number" then
        return fallback;
    end
    value = math.floor(value);
    if value < 1 then
        return fallback;
    end
    return value;
end

local function normalizeWsc(value)
    local result = {};
    if type(value) ~= "table" then
        return result;
    end
    for stat,coefficient in pairs(value) do
        if type(stat) == "string"
            and type(coefficient) == "number"
            and coefficient >= 0 then
            result[string.lower(stat)] = coefficient;
        end
    end
    return result;
end

local function normalizeStats(value)
    local result = {};
    if type(value) ~= "table" then
        return result;
    end
    for _,stat in ipairs(value) do
        if type(stat) == "string" and stat ~= "" then
            table.insert(result, string.lower(stat));
        end
    end
    return result;
end

local function validate(metadata, requireVerified)
    if type(metadata) ~= "table" then
        return false, "metadata_not_table";
    end
    if type(metadata.id) ~= "number" or metadata.id < 1 then
        return false, "missing_action_id";
    end
    if type(metadata.name) ~= "string" or metadata.name == "" then
        return false, "missing_action_name";
    end
    if type(metadata.job) ~= "string" or metadata.job == "" then
        return false, "missing_action_job";
    end
    if not allowedCategories[metadata.category] then
        return false, "invalid_action_category";
    end
    if type(metadata.context) ~= "string" or metadata.context == "" then
        return false, "missing_action_context";
    end
    if metadata.hit_count ~= nil
        and integer(metadata.hit_count, nil) == nil then
        return false, "invalid_hit_count";
    end
    if metadata.wsc ~= nil and type(metadata.wsc) ~= "table" then
        return false, "invalid_wsc";
    end
    if metadata.dominant_stats ~= nil and type(metadata.dominant_stats) ~= "table" then
        return false, "invalid_dominant_stats";
    end
    if metadata.aliases ~= nil and type(metadata.aliases) ~= "table" then
        return false, "invalid_action_aliases";
    end
    if requireVerified then
        if metadata.verification ~= "Verified" then
            return false, "action_not_verified";
        end
        if not allowedConfidence[metadata.confidence] then
            return false, "invalid_action_confidence";
        end
        if type(metadata.source_id) ~= "string" or metadata.source_id == "" then
            return false, "missing_action_source";
        end
        if integer(metadata.required_level, nil) == nil then
            return false, "invalid_required_level";
        end
    end
    return true;
end

local function buffActive(state, key)
    return state ~= nil
        and type(state.buffs) == "table"
        and state.buffs[key] == true;
end

local function planEnabled(state, key)
    return state ~= nil
        and state.ui ~= nil
        and type(state.ui[key]) == "table"
        and state.ui[key][1] == true;
end

function actionContext.new(metadata, diagnostics, options)
    options = options or {};
    local instance = setmetatable({
        diagnostics = diagnostics,
        by_id = {},
        by_name = {},
        rejected = {},
        metadata_version = options.metadata_version or 1,
        require_verified = options.require_verified == true,
    }, actionContext);
    for _,row in ipairs(metadata or {}) do
        instance:register(row);
    end
    return instance;
end

function actionContext:register(metadata)
    local ok, reason = validate(metadata, self.require_verified);
    if not ok then
        table.insert(self.rejected, {
            id = metadata and metadata.id or nil,
            reason = reason,
        });
        if self.diagnostics ~= nil then
            self.diagnostics:add("action_metadata", string.format(
                "rejected %s",
                reason
            ));
        end
        return false, reason;
    end

    local row = copy(metadata);
    row.job = string.upper(row.job);
    row.category = string.lower(row.category);
    row.context = string.lower(row.context);
    row.hit_count = integer(row.hit_count, 1);
    row.wsc = normalizeWsc(row.wsc);
    row.dominant_stats = normalizeStats(row.dominant_stats);
    row.multi_hit = row.hit_count > 1;
    row.name_key = normalizedName(row.name);
    if self.by_id[row.id] ~= nil then
        table.insert(self.rejected, { id = row.id, reason = "duplicate_action_id" });
        if self.diagnostics ~= nil then
            self.diagnostics:add("action_metadata", "rejected duplicate_action_id");
        end
        return false, "duplicate_action_id";
    end
    local nameKeys = { row.name_key };
    for _,alias in ipairs(row.aliases or {}) do
        table.insert(nameKeys, normalizedName(alias));
    end
    for _,nameKey in ipairs(nameKeys) do
        if self.by_name[nameKey] ~= nil then
            table.insert(self.rejected, { id = row.id, reason = "duplicate_action_name" });
            if self.diagnostics ~= nil then
                self.diagnostics:add("action_metadata", "rejected duplicate_action_name");
            end
            return false, "duplicate_action_name";
        end
    end
    self.by_id[row.id] = row;
    for _,nameKey in ipairs(nameKeys) do
        self.by_name[nameKey] = row;
    end
    return true;
end

function actionContext:find(action)
    if type(action) == "number" then
        return self.by_id[action];
    end
    if type(action) == "string" then
        return self.by_name[normalizedName(action)];
    end
    if type(action) ~= "table" then
        return nil;
    end
    if type(action.id) == "number" and self.by_id[action.id] ~= nil then
        return self.by_id[action.id];
    end
    if action.name ~= nil then
        return self.by_name[normalizedName(action.name)];
    end
    return nil;
end

function actionContext:resolve(action, state)
    local metadata = self:find(action);
    local result = {
        known = metadata ~= nil,
        metadata_version = self.metadata_version,
        action_id = metadata and metadata.id or (type(action) == "table" and action.id or action),
        action_name = metadata and metadata.name or (type(action) == "table" and action.name or nil),
        job = metadata and metadata.job or nil,
        category = metadata and metadata.category or "unknown",
        context_key = metadata and metadata.context or nil,
        required_level = metadata and metadata.required_level or nil,
        skill = metadata and metadata.skill or nil,
        element = metadata and metadata.element or nil,
        element_id = metadata and metadata.element_id or nil,
        hit_count = metadata and metadata.hit_count or nil,
        multi_hit = metadata and metadata.multi_hit or false,
        wsc = copy(metadata and metadata.wsc or {}),
        dominant_stats = copy(metadata and metadata.dominant_stats or {}),
        accuracy_model = metadata and metadata.accuracy_model or nil,
        verification = metadata and metadata.verification or nil,
        confidence = metadata and metadata.confidence or nil,
        source_id = metadata and metadata.source_id or nil,
        source_ids = copy(metadata and metadata.source_ids or {}),
        horizon_override = copy(metadata and metadata.horizon_override or {}),
        horizon_verification = metadata and metadata.horizon_verification or nil,
        horizon_spell_page = metadata and metadata.horizon_spell_page or nil,
        tracker_priority = metadata and metadata.tracker_priority or nil,
        best_use = metadata and metadata.best_use or nil,
        era_notes = metadata and metadata.era_notes or nil,
        job_trait = metadata and metadata.job_trait or nil,
        source_conflicts = copy(metadata and metadata.source_conflicts or {}),
        tp_behavior = metadata and metadata.tp_behavior or nil,
        chain_behavior = metadata and metadata.chain_behavior or nil,
        burst_behavior = metadata and metadata.burst_behavior or nil,
        metadata_flags = copy(metadata and metadata.flags or {}),
        reason = metadata and "metadata" or "unknown_action",
    };

    -- These are intentionally separate.  Manual planning is user intent; an
    -- active affinity is only true when the named buff is actually present.
    result.chain_active = buffActive(state, "chainaffinity");
    result.burst_active = buffActive(state, "burstaffinity");
    result.chain_plan = planEnabled(state, "chain_plan");
    result.burst_plan = planEnabled(state, "burst_plan");
    result.chain_requested = result.chain_active or result.chain_plan;
    result.burst_requested = result.burst_active or result.burst_plan;
    result.affinity_source = {
        chain = result.chain_active and "active_buff"
            or (result.chain_plan and "manual_plan" or "none"),
        burst = result.burst_active and "active_buff"
            or (result.burst_plan and "manual_plan" or "none"),
    };
    result.signature = table.concat({
        tostring(result.action_id or "unknown"),
        tostring(result.context_key or "unknown"),
        tostring(result.chain_active),
        tostring(result.burst_active),
        tostring(result.chain_plan),
        tostring(result.burst_plan),
    }, "|");

    return result;
end

function actionContext:count()
    local count = 0;
    for _,_ in pairs(self.by_id) do
        count = count + 1;
    end
    return count;
end

function actionContext:list(job, maximumLevel)
    local result = {};
    local normalizedJob = string.upper(tostring(job or ""));
    for _,row in pairs(self.by_id) do
        local legalJob = normalizedJob == "" or row.job == normalizedJob;
        local legalLevel = maximumLevel == nil
            or row.required_level == nil
            or row.required_level <= maximumLevel;
        if legalJob and legalLevel then
            table.insert(result, copy(row));
        end
    end
    table.sort(result, function(left, right)
        local leftLevel = left.required_level or 0;
        local rightLevel = right.required_level or 0;
        if leftLevel ~= rightLevel then
            return leftLevel < rightLevel;
        end
        if left.name ~= right.name then
            return left.name < right.name;
        end
        return left.id < right.id;
    end);
    return result;
end

return actionContext;
