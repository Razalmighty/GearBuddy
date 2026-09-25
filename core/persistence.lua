-- User-preference persistence.
--
-- Only local preferences are stored.  Gear pins are stable item-ID preferences,
-- not resolved bag/index equipment.  Inventory entries, resolved equipment,
-- buffs, player state, and any future executable action state are intentionally
-- excluded from this document.

local schema = require("data.schema");

local persistence = {};
persistence.__index = persistence;

local schemaVersion = 2;
local toSettingsTable;
local normalizeContext;

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

local function replaceTable(destination, source)
    for key,_ in pairs(destination or {}) do
        destination[key] = nil;
    end
    for key,value in pairs(source or {}) do
        destination[key] = toSettingsTable(value);
    end
end

local function bool(value, fallback)
    if type(value) == "boolean" then
        return value;
    end
    return fallback;
end

local function number(value, fallback, minimum, maximum)
    if type(value) ~= "number" then
        return fallback;
    end
    value = math.floor(value + 0.5);
    if minimum ~= nil then
        value = math.max(minimum, value);
    end
    if maximum ~= nil then
        value = math.min(maximum, value);
    end
    return value;
end

local function list(value)
    local result = {};
    local seen = {};
    if type(value) ~= "table" then
        return result;
    end
    for _,item in ipairs(value) do
        if type(item) == "string" and item ~= "" and not seen[item] then
            table.insert(result, item);
            seen[item] = true;
        end
    end
    return result;
end

local function unwrap(value, fallback)
    if type(value) == "table" and value[1] ~= nil then
        return value[1];
    end
    if value ~= nil then
        return value;
    end
    return fallback;
end

local function defaultDocument(state)
    return {
        schema_version = schemaVersion,
        selected_job = state.selected_job,
        selected_context = copy(state.selected_context),
        priority_overrides = copy(state.priority_overrides),
        gear_pins = copy(state.gear_pins),
        ui = {
            weapons_locked = unwrap(state.ui.weapons_locked, true),
            learn_plan = unwrap(state.ui.learn_plan, false),
            evasion_plan = unwrap(state.ui.evasion_plan, false),
            chain_plan = unwrap(state.ui.chain_plan, false),
            burst_plan = unwrap(state.ui.burst_plan, false),
            blm_nuke_balance = unwrap(state.ui.blm_nuke_balance, 50),
            hud = unwrap(state.ui.hud, true),
            open = unwrap(state.ui.open, true),
        },
    };
end

local function normalizeGearPins(raw, policy)
    local result = {};
    if type(raw) ~= "table" then
        return result;
    end
    for key,slots in pairs(raw) do
        if type(key) == "string" and type(slots) == "table" then
            local job,contextKey,profileKey = key:match(
                "^(%a+):([%w_]+):([%w_]+)$"
            );
            local validContext = (job == "BLU" or job == "BLM")
                and normalizeContext(policy, job, contextKey, nil) ~= nil;
            local validProfile = validContext
                and policy ~= nil
                and type(policy.normalizeProfile) == "function"
                and policy:normalizeProfile(job, contextKey, profileKey) ~= nil;
            if validProfile then
                local cleanSlots = {};
                for slotName,pin in pairs(slots) do
                    local slot = schema.normalizeSlot(slotName);
                    local itemId = type(pin) == "table" and pin.item_id or pin;
                    if slot ~= nil
                        and type(itemId) == "number"
                        and itemId == itemId
                        and itemId >= 1
                        and itemId == math.floor(itemId) then
                        cleanSlots[slot.name] = {
                            item_id = itemId,
                            mode = "force",
                        };
                    end
                end
                if next(cleanSlots) ~= nil then
                    result[job .. ":" .. contextKey .. ":" .. profileKey] = cleanSlots;
                end
            end
        end
    end
    return result;
end

function normalizeContext(policy, job, value, fallback)
    if policy ~= nil and type(policy.normalizeContext) == "function" then
        local ok, result = pcall(function()
            return policy:normalizeContext(job, value);
        end);
        if ok and result ~= nil then
            return result;
        end
    end
    return fallback;
end

local function normalizeDocument(raw, defaults, policy)
    raw = type(raw) == "table" and raw or {};
    local result = copy(defaults);
    result.schema_version = schemaVersion;

    if raw.schema_version == 1 or raw.schema_version == schemaVersion then
        if raw.selected_job == "AUTO"
            or raw.selected_job == "BLU"
            or raw.selected_job == "BLM" then
            result.selected_job = raw.selected_job;
        end

        for _,job in ipairs({ "BLU", "BLM" }) do
            local fallback = defaults.selected_context[job];
            result.selected_context[job] = normalizeContext(
                policy,
                job,
                raw.selected_context and raw.selected_context[job],
                fallback
            );
        end

        result.priority_overrides = {};
        if type(raw.priority_overrides) == "table" then
            for key,order in pairs(raw.priority_overrides) do
                if type(key) == "string" and type(order) == "table" then
                    local job,contextKey = key:match("^(%a+):([%w_]+)$");
                    if (job == "BLU" or job == "BLM")
                        and normalizeContext(policy, job, contextKey, nil) ~= nil then
                        result.priority_overrides[key] = list(order);
                    end
                end
            end
        end


        -- Schema v1 migrates with an empty pin map.  Pins only become trusted
        -- preferences after the v2 structural validation above.
        result.gear_pins = {};
        if raw.schema_version == schemaVersion then
            result.gear_pins = normalizeGearPins(raw.gear_pins, policy);
        end

        local ui = type(raw.ui) == "table" and raw.ui or {};
        result.ui.weapons_locked = bool(ui.weapons_locked, defaults.ui.weapons_locked);
        result.ui.learn_plan = bool(ui.learn_plan, defaults.ui.learn_plan);
        result.ui.evasion_plan = bool(ui.evasion_plan, defaults.ui.evasion_plan);
        result.ui.chain_plan = bool(ui.chain_plan, defaults.ui.chain_plan);
        result.ui.burst_plan = bool(ui.burst_plan, defaults.ui.burst_plan);
        result.ui.blm_nuke_balance = number(
            ui.blm_nuke_balance,
            defaults.ui.blm_nuke_balance,
            0,
            100
        );
        result.ui.hud = bool(ui.hud, defaults.ui.hud);
        result.ui.open = bool(ui.open, defaults.ui.open);
    end

    return result;
end

function toSettingsTable(value)
    if type(value) ~= "table" then
        return value;
    end
    local result = {};
    for key,item in pairs(value) do
        result[key] = toSettingsTable(item);
    end
    if type(T) == "function" then
        local ok, converted = pcall(function() return T(result); end);
        if ok and converted ~= nil then
            return converted;
        end
    end
    return result;
end

local function ashitaBackend()
    local ok, module = pcall(require, "settings");
    if not ok or module == nil then
        return nil;
    end
    return {
        module = module,
        document = nil,
    };
end

function persistence.new(diagnostics, backend)
    return setmetatable({
        diagnostics = diagnostics,
        backend = backend or ashitaBackend(),
        document = nil,
        defaults = nil,
    }, persistence);
end

function persistence:load(state, policy)
    local defaults = defaultDocument(state);
    self.defaults = defaults;
    local raw = nil;
    if self.backend ~= nil and type(self.backend.load) == "function" then
        local ok, loaded = pcall(function()
            return self.backend:load(toSettingsTable(defaults));
        end);
        if ok then
            raw = loaded;
        else
            self.diagnostics:add("settings_error", "load failed; using defaults");
        end
    elseif self.backend ~= nil and self.backend.module ~= nil then
        local ok, loaded = pcall(function()
            return self.backend.module.load(toSettingsTable(defaults));
        end);
        if ok then
            raw = loaded;
            self.backend.document = loaded;
        else
            self.diagnostics:add("settings_error", "load failed; using defaults");
        end
    end

    local clean = normalizeDocument(raw, defaults, policy);
    state.selected_job = clean.selected_job;
    state.selected_context = copy(clean.selected_context);
    state.priority_overrides = copy(clean.priority_overrides);
    state.gear_pins = copy(clean.gear_pins);
    state.ui.weapons_locked[1] = clean.ui.weapons_locked;
    state.ui.learn_plan[1] = clean.ui.learn_plan;
    state.ui.evasion_plan[1] = clean.ui.evasion_plan;
    state.ui.chain_plan[1] = clean.ui.chain_plan;
    state.ui.burst_plan[1] = clean.ui.burst_plan;
    state.ui.blm_nuke_balance[1] = clean.ui.blm_nuke_balance;
    state.ui.hud[1] = clean.ui.hud;
    state.ui.open[1] = clean.ui.open;
    state.policy_revision = state.policy_revision + 1;
    state.pin_revision = (state.pin_revision or 0) + 1;
    state.dirty_result = true;
    self.document = clean;
    self.diagnostics:add("settings", "preferences loaded");
    return true;
end

function persistence:snapshot(state, policy)
    local defaults = self.defaults or defaultDocument(state);
    return normalizeDocument(defaultDocument(state), defaults, policy);
end

function persistence:save(state, policy)
    local document = self:snapshot(state, policy);
    self.document = document;
    if self.backend == nil then
        return false;
    end

    if type(self.backend.save) == "function" then
        local ok = pcall(function() self.backend:save(document); end);
        if not ok then
            self.diagnostics:add("settings_error", "save failed");
            return false;
        end
        self.diagnostics:add("settings", "preferences saved");
        return true;
    end

    if self.backend.module ~= nil then
        if type(self.backend.document) == "table" then
            replaceTable(self.backend.document, document);
        else
            self.backend.document = toSettingsTable(document);
        end
        local ok = pcall(function() self.backend.module.save(); end);
        if not ok then
            self.diagnostics:add("settings_error", "save failed");
            return false;
        end
        self.diagnostics:add("settings", "preferences saved");
        return true;
    end
    return false;
end

return persistence;
