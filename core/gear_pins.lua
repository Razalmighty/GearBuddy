-- Player-authoritative, profile-scoped slot preferences ("Force Swap").
--
-- Pins store stable item IDs rather than transient bag/index positions.  Each
-- resolve maps the preference back to a currently owned legal instance.  A
-- missing, illegal, duplicate, or weapon-locked pin is explained and falls
-- back to formula selection without bypassing any safety rule.

local schema = require("data.schema");
local Candidate = require("core.candidate");
local Legality = require("core.item_legality");

local gearPins = {};
gearPins.__index = gearPins;

local reasonLabels = {
    catalog_slot = "verified catalog slot conflict",
    instance_conflict = "no second physical instance is available",
    invalid_pin = "invalid saved preference",
    job_data = "verified catalog job conflict",
    level = "above the current effective level",
    not_owned = "item is not currently owned",
    resource_flags = "Ashita does not mark the item equippable",
    resource_job = "item cannot be worn by this job",
    resource_level_unknown = "item level is unavailable",
    resource_missing = "Ashita resource metadata is unavailable",
    resource_slot = "item cannot be worn in this slot",
    weapon_lock = "weapon policy has priority",
};

local function positiveInteger(value)
    if type(value) ~= "number"
        or value ~= value
        or value < 1
        or value ~= math.floor(value) then
        return nil;
    end
    return value;
end

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

function gearPins.key(job, contextKey, profileKey)
    return table.concat({
        string.upper(tostring(job or "")),
        string.lower(tostring(contextKey or "")),
        string.lower(tostring(profileKey or "default")),
    }, ":");
end

function gearPins.new(config, catalog, effects, diagnostics)
    return setmetatable({
        config = config,
        catalog = catalog,
        effects = effects,
        diagnostics = diagnostics,
        option_cache = {},
        option_generation = nil,
    }, gearPins);
end

function gearPins:reasonLabel(reason)
    return reasonLabels[reason] or tostring(reason or "unknown");
end

function gearPins:get(state, job, contextKey, profileKey, slotName)
    local group = state.gear_pins
        and state.gear_pins[gearPins.key(job, contextKey, profileKey)];
    local pin = group and group[slotName] or nil;
    if type(pin) == "number" then
        local itemId = positiveInteger(pin);
        return itemId and { item_id = itemId } or nil;
    end
    if type(pin) ~= "table" or positiveInteger(pin.item_id) == nil then
        return nil;
    end
    return copy(pin);
end

function gearPins:set(state, job, contextKey, profileKey, slotName, itemId)
    local normalizedSlot = schema.normalizeSlot(slotName);
    itemId = positiveInteger(itemId);
    if normalizedSlot == nil or itemId == nil then
        return false;
    end
    state.gear_pins = state.gear_pins or {};
    local key = gearPins.key(job, contextKey, profileKey);
    state.gear_pins[key] = state.gear_pins[key] or {};
    state.gear_pins[key][normalizedSlot.name] = {
        item_id = itemId,
        mode = "force",
    };
    return true;
end

function gearPins:clear(state, job, contextKey, profileKey, slotName)
    local normalizedSlot = schema.normalizeSlot(slotName);
    if normalizedSlot == nil or type(state.gear_pins) ~= "table" then
        return false;
    end
    local key = gearPins.key(job, contextKey, profileKey);
    local group = state.gear_pins[key];
    if type(group) ~= "table" or group[normalizedSlot.name] == nil then
        return false;
    end
    group[normalizedSlot.name] = nil;
    if next(group) == nil then
        state.gear_pins[key] = nil;
    end
    return true;
end

function gearPins:count(state, job, contextKey, profileKey)
    local key = gearPins.key(job, contextKey, profileKey);
    local count = 0;
    for _,pin in pairs(state.gear_pins and state.gear_pins[key] or {}) do
        if type(pin) == "table" and positiveInteger(pin.item_id) ~= nil then
            count = count + 1;
        end
    end
    return count;
end

function gearPins:label(state, job, contextKey, profileKey, slotName)
    local pin = self:get(state, job, contextKey, profileKey, slotName);
    if pin == nil then
        return "Auto (GearBuddy)";
    end
    local catalogItem = self.catalog.by_id[pin.item_id];
    if catalogItem ~= nil and catalogItem.name ~= nil then
        return string.format("%s [%d]", catalogItem.name, pin.item_id);
    end
    local instances = state.inventory.by_id[pin.item_id] or {};
    local resourceName = instances[1]
        and Legality.resourceName(instances[1].resource)
        or nil;
    return string.format("%s [%d]", resourceName or "Unknown item", pin.item_id);
end

function gearPins:options(state, slot, job, level)
    if self.option_generation ~= state.inventory.generation then
        self.option_cache = {};
        self.option_generation = state.inventory.generation;
    end
    local cacheKey = table.concat({
        tostring(state.inventory.generation or 0),
        tostring(job),
        tostring(level),
        tostring(slot.name),
    }, ":");
    if self.option_cache[cacheKey] ~= nil then
        return self.option_cache[cacheKey];
    end

    local rows = {};
    for itemId,instances in pairs(state.inventory.by_id or {}) do
        local catalogItem = self.catalog.by_id[itemId];
        local legalCount = 0;
        local firstLegal = nil;
        for _,inventoryItem in ipairs(instances) do
            local legal = Legality.manual(
                catalogItem,
                inventoryItem,
                slot,
                job,
                level,
                self.config.verified_item_policy
            );
            if legal then
                legalCount = legalCount + 1;
                firstLegal = firstLegal or inventoryItem;
            end
        end
        if firstLegal ~= nil then
            local trusted = catalogItem ~= nil
                and catalogItem.verification == self.config.verified_item_policy;
            table.insert(rows, {
                item_id = itemId,
                name = (catalogItem and catalogItem.name)
                    or Legality.resourceName(firstLegal.resource)
                    or ("Item " .. tostring(itemId)),
                owned_count = legalCount,
                verification = catalogItem and catalogItem.verification
                    or "Uncatalogued",
                stats_trusted = trusted,
            });
        end
    end
    table.sort(rows, function(left, right)
        if left.name ~= right.name then
            return left.name < right.name;
        end
        return left.item_id < right.item_id;
    end);
    self.option_cache[cacheKey] = rows;
    return rows;
end

function gearPins:resolve(
    state,
    slot,
    job,
    level,
    contextKey,
    profileKey,
    reserved
)
    local pin = self:get(state, job, contextKey, profileKey, slot.name);
    if pin == nil then
        return nil, nil;
    end
    local itemId = positiveInteger(pin.item_id);
    if itemId == nil then
        return nil, {
            status = "fallback",
            reason = "invalid_pin",
        };
    end

    local instances = state.inventory.by_id[itemId] or {};
    if #instances == 0 then
        return nil, {
            status = "fallback",
            reason = "not_owned",
            item_id = itemId,
        };
    end
    local ordered = {};
    for _,instance in ipairs(instances) do
        table.insert(ordered, instance);
    end
    table.sort(ordered, function(left, right)
        return tostring(left.instance_key) < tostring(right.instance_key);
    end);

    local catalogItem = self.catalog.by_id[itemId];
    local failureReason = nil;
    local foundLegalButReserved = false;
    for _,inventoryItem in ipairs(ordered) do
        local legal, reason = Legality.manual(
            catalogItem,
            inventoryItem,
            slot,
            job,
            level,
            self.config.verified_item_policy
        );
        if legal then
            if not reserved[inventoryItem.instance_key] then
                local selected = Candidate.build(
                    catalogItem,
                    inventoryItem,
                    slot,
                    contextKey,
                    self.effects,
                    self.config.verified_item_policy,
                    "manual"
                );
                return selected, {
                    status = "active",
                    reason = "manual_pin",
                    item_id = itemId,
                    name = selected.name,
                    stats_trusted = selected.stats_trusted,
                    instance_key = selected.instance_key,
                };
            end
            foundLegalButReserved = true;
        else
            failureReason = failureReason or reason;
        end
    end

    return nil, {
        status = "fallback",
        reason = foundLegalButReserved and "instance_conflict"
            or (failureReason or "invalid_pin"),
        item_id = itemId,
        name = catalogItem and catalogItem.name or nil,
    };
end

return gearPins;
