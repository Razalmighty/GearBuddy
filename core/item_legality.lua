-- Shared, fail-closed equipment legality checks.
--
-- Automatic candidates require a fully verified catalog row.  Manual pins may
-- use an uncatalogued or partially verified owned item, but only when Ashita's
-- live resource metadata proves that the item is equippable for the current
-- job, effective level, and physical slot.

local bit = require("bit");
local schema = require("data.schema");

local legality = {};

local function contains(values, expected)
    for _,value in ipairs(values or {}) do
        if value == expected then
            return true;
        end
    end
    return false;
end

function legality.read(resource, field, fallback)
    if resource == nil then
        return fallback;
    end
    local ok, value = pcall(function() return resource[field]; end);
    if ok and value ~= nil then
        return value;
    end
    return fallback;
end

function legality.catalogSlotAllowed(catalogItem, expected)
    if catalogItem == nil then
        return false;
    end
    if type(catalogItem.slots) == "table" then
        return contains(catalogItem.slots, expected);
    end
    -- Compatibility with pre-schema-v2 catalogs during local migration only.
    return catalogItem.slot == expected;
end

function legality.resourceEquippable(resource)
    local flags = legality.read(resource, "Flags", 0);
    return flags ~= 0 and bit.band(flags, 0x800) ~= 0;
end

function legality.resourceAllowsJob(resource, job)
    local jobId = schema.job_ids[job];
    local jobs = legality.read(resource, "Jobs", 0);
    if jobId == nil or jobs == 0 then
        return false;
    end
    return bit.band(jobs, math.pow(2, jobId)) ~= 0;
end

function legality.resourceAllowsSlot(resource, slotIndex)
    local slots = legality.read(resource, "Slots", 0);
    return slots ~= 0
        and bit.band(slots, math.pow(2, slotIndex - 1)) ~= 0;
end

function legality.resourceLevel(resource)
    local value = legality.read(resource, "Level", nil);
    if type(value) ~= "number" or value < 0 then
        return nil;
    end
    return math.floor(value);
end

local function localizedString(value)
    if type(value) == "string" and value ~= "" then
        return value;
    end
    if value == nil then
        return nil;
    end
    -- Ashita resource objects expose localized arrays; test fixtures and
    -- normalized exports may expose the English value directly.
    for _,index in ipairs({ 1, 2, 0 }) do
        local ok, item = pcall(function() return value[index]; end);
        if ok and type(item) == "string" and item ~= "" then
            return item;
        end
    end
    return nil;
end

function legality.resourceName(resource)
    return localizedString(legality.read(resource, "Name", nil))
        or localizedString(legality.read(resource, "LogNameSingular", nil));
end

local function resourceChecks(inventoryItem, slot, job)
    local resource = inventoryItem and inventoryItem.resource or nil;
    if resource == nil then
        return false, "resource_missing";
    end
    if not legality.resourceEquippable(resource) then
        return false, "resource_flags";
    end
    if not legality.resourceAllowsJob(resource, job) then
        return false, "resource_job";
    end
    if not legality.resourceAllowsSlot(resource, slot.index) then
        return false, "resource_slot";
    end
    return true;
end

function legality.automatic(catalogItem, inventoryItem, slot, job, level, verifiedPolicy)
    if catalogItem == nil or catalogItem.verification ~= verifiedPolicy then
        return false, "verification";
    end
    if type(catalogItem.required_level) ~= "number"
        or catalogItem.required_level > level then
        return false, "level";
    end
    if not contains(catalogItem.jobs, job) then
        return false, "job_data";
    end
    if not legality.catalogSlotAllowed(catalogItem, slot.catalog) then
        return false, "catalog_slot";
    end
    return resourceChecks(inventoryItem, slot, job);
end

function legality.manual(catalogItem, inventoryItem, slot, job, level, verifiedPolicy)
    local resourceOk, resourceReason = resourceChecks(inventoryItem, slot, job);
    if not resourceOk then
        return false, resourceReason;
    end

    local resourceLevel = legality.resourceLevel(inventoryItem.resource);
    if resourceLevel == nil then
        return false, "resource_level_unknown";
    end
    if resourceLevel > level then
        return false, "level";
    end

    -- A fully verified catalog row is an additional safety boundary.  Partial
    -- or absent rows never contribute stats, so Ashita resource legality is
    -- sufficient for an explicit manual preference.
    if catalogItem ~= nil and catalogItem.verification == verifiedPolicy then
        if type(catalogItem.required_level) ~= "number"
            or catalogItem.required_level > level then
            return false, "level";
        end
        if not contains(catalogItem.jobs, job) then
            return false, "job_data";
        end
        if not legality.catalogSlotAllowed(catalogItem, slot.catalog) then
            return false, "catalog_slot";
        end
    end
    return true;
end

return legality;
