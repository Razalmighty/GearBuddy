-- Candidate construction shared by formula selection and manual gear pins.

local Legality = require("core.item_legality");

local candidate = {};

local function contains(values, expected)
    for _,value in ipairs(values or {}) do
        if value == expected then
            return true;
        end
    end
    return false;
end

local function effectApplies(effect, contextKey)
    return contains(effect.applies_to, contextKey)
        and (effect.condition_type == "Always"
            or effect.condition_type == "Equipped"
            or effect.condition_type == "Correlation applies");
end

function candidate.build(
    catalogItem,
    inventoryItem,
    slot,
    contextKey,
    effects,
    verifiedPolicy,
    selectionSource
)
    local trusted = catalogItem ~= nil
        and catalogItem.verification == verifiedPolicy;
    local stats = {};
    local tags = {};

    if trusted then
        for stat,value in pairs(catalogItem.stats or {}) do
            if type(value) == "number" then
                stats[stat] = value;
            end
        end
        for _,effect in ipairs(effects.by_item[catalogItem.id] or {}) do
            if effectApplies(effect, contextKey) then
                if effect.tag ~= nil and effect.verified_text == true then
                    tags[effect.tag] = true;
                end
                if effect.stat ~= nil
                    and type(effect.value) == "number"
                    and effect.verification == "Verified" then
                    stats[effect.stat] = (stats[effect.stat] or 0) + effect.value;
                end
            end
        end
    end

    local itemId = inventoryItem.item_id
        or (catalogItem and catalogItem.id)
        or 0;
    return {
        item_id = itemId,
        name = (catalogItem and catalogItem.name)
            or Legality.resourceName(inventoryItem.resource)
            or ("Item " .. tostring(itemId)),
        slot = slot.name,
        catalog_slots = catalogItem and catalogItem.slots or nil,
        bag = inventoryItem.bag,
        index = inventoryItem.index,
        instance_key = inventoryItem.instance_key,
        stats = stats,
        tags = tags,
        verification = catalogItem and catalogItem.verification or "Uncatalogued",
        source_id = catalogItem and catalogItem.source_id or "Ashita resource",
        selection_source = selectionSource or "formula",
        stats_trusted = trusted,
    };
end

return candidate;
