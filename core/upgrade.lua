-- Conservative, read-only upgrade recommendations.
--
-- Each unowned verified catalog row is evaluated as a virtual inventory entry
-- through the normal resolver.  This preserves legality, duplicate-instance
-- handling, beam selection, caps, required tags, and weapon policy instead of
-- maintaining a second scoring implementation.

local schema = require("data.schema");
local Preview = require("core.preview");

local upgrade = {};
upgrade.__index = upgrade;

local function contains(values, expected)
    for _,value in ipairs(values or {}) do
        if value == expected then
            return true;
        end
    end
    return false;
end

local function copyList(values)
    local result = {};
    for index,value in ipairs(values or {}) do
        result[index] = value;
    end
    return result;
end

local function copyInventory(byId)
    local result = {};
    for itemId,instances in pairs(byId or {}) do
        result[itemId] = copyList(instances);
    end
    return result;
end

local function catalogSlots(item)
    if type(item.slots) == "table" then
        return item.slots;
    end
    if item.slot ~= nil then
        return { item.slot };
    end
    return {};
end

local function findSlots(item)
    local allowed = {};
    for _,catalogSlot in ipairs(catalogSlots(item)) do
        allowed[catalogSlot] = true;
    end
    local result = {};
    for _,slot in ipairs(schema.slots) do
        if allowed[slot.catalog] then
            table.insert(result, slot);
        end
    end
    return result;
end

local function virtualResource(item, job)
    local slots = findSlots(item);
    local jobId = schema.job_ids[job];
    if #slots == 0 or jobId == nil then
        return nil;
    end
    local slotMask = 0;
    for _,slot in ipairs(slots) do
        slotMask = slotMask + math.pow(2, slot.index - 1);
    end
    return {
        Flags = 0x800,
        Jobs = math.pow(2, jobId),
        Slots = slotMask,
    };
end

local function hasUnprotectedSlot(item, state, config, baseline)
    for _,slot in ipairs(findSlots(item)) do
        local protected = state.ui.weapons_locked[1]
            and config.manual_slots[slot.name] == true;
        local pinned = baseline ~= nil
            and baseline.pinned_slots ~= nil
            and baseline.pinned_slots[slot.name] ~= nil;
        if not protected and not pinned then
            return true;
        end
    end
    return false;
end

local function virtualState(state, item, job)
    local resource = virtualResource(item, job);
    if resource == nil then
        return nil;
    end
    local byId = copyInventory(state.inventory.by_id);
    byId[item.id] = {
        {
            item_id = item.id,
            count = 1,
            bag = -1,
            index = -1,
            instance_key = string.format("upgrade:%05d", item.id),
            flags = resource.Flags,
            resource = resource,
            virtual = true,
        },
    };
    return {
        player = state.player,
        ui = state.ui,
        priority_overrides = state.priority_overrides,
        gear_pins = state.gear_pins,
        pin_revision = state.pin_revision,
        inventory = {
            generation = state.inventory.generation,
            by_id = byId,
        },
    };
end

local function objectiveValue(stats, objective)
    local value = stats[objective.stat] or 0;
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

local function requiredCount(tags, policy)
    local count = 0;
    for _,tag in ipairs(policy.required_tags or {}) do
        if tags[tag] then
            count = count + 1;
        end
    end
    return count;
end

local function compareResults(before, after, policy)
    local beforeRequired = requiredCount(before.tags or {}, policy);
    local afterRequired = requiredCount(after.tags or {}, policy);
    if beforeRequired ~= afterRequired then
        return afterRequired > beforeRequired, afterRequired - beforeRequired, nil;
    end
    for rank,objective in ipairs(policy.objectives or {}) do
        local beforeValue = objectiveValue(before.stats or {}, objective);
        local afterValue = objectiveValue(after.stats or {}, objective);
        if beforeValue ~= afterValue then
            return afterValue > beforeValue, 0, rank;
        end
    end
    return false, 0, nil;
end

local function objectiveDeltas(before, after, policy)
    local result = {};
    for rank,objective in ipairs(policy.objectives or {}) do
        local beforeRaw = (before.stats or {})[objective.stat] or 0;
        local afterRaw = (after.stats or {})[objective.stat] or 0;
        local beforeCompared = objectiveValue(before.stats or {}, objective);
        local afterCompared = objectiveValue(after.stats or {}, objective);
        table.insert(result, {
            rank = rank,
            stat = objective.stat,
            label = objective.label,
            before = beforeRaw,
            after = afterRaw,
            raw_delta = afterRaw - beforeRaw,
            compared_before = beforeCompared,
            compared_after = afterCompared,
            compared_delta = afterCompared - beforeCompared,
            cap = objective.cap,
            target = objective.target,
            direction = objective.direction,
        });
    end
    return result;
end

local function selectedVirtualSlot(result, itemId)
    for slot,candidate in pairs(result.set or {}) do
        if candidate.item_id == itemId
            and candidate.instance_key == string.format("upgrade:%05d", itemId) then
            return slot, candidate;
        end
    end
    return nil, nil;
end

function upgrade.new(config, catalog, resolver, diagnostics)
    return setmetatable({
        config = config,
        catalog = catalog,
        resolver = resolver,
        diagnostics = diagnostics,
    }, upgrade);
end

function upgrade:recommend(state, baseline, job, contextKey, activePolicy)
    if baseline == nil or baseline.error ~= nil or activePolicy == nil then
        return {};
    end
    local level = state.player.effective_level or 0;
    local owned = state.inventory.by_id or {};
    local recommendations = {};
    local evaluated = 0;
    local limit = self.config.upgrade_candidate_limit or 100;

    for _,item in ipairs(self.catalog.items or {}) do
        if evaluated >= limit then
            break;
        end
        if item.verification == self.config.verified_item_policy
            and item.required_level ~= nil
            and item.required_level <= level
            and contains(item.jobs, job)
            and owned[item.id] == nil
            and #findSlots(item) > 0 then
            if hasUnprotectedSlot(item, state, self.config, baseline) then
                evaluated = evaluated + 1;
                local candidateState = virtualState(state, item, job);
                local candidateResult = self.resolver:resolve(
                    candidateState,
                    job,
                    contextKey,
                    activePolicy,
                    { silent = true }
                );
                local selectedSlot, candidate = selectedVirtualSlot(
                    candidateResult,
                    item.id
                );
                if selectedSlot ~= nil then
                    local better, requiredDelta, firstRank = compareResults(
                        baseline,
                        candidateResult,
                        activePolicy
                    );
                    if better then
                        local replaced = baseline.set[selectedSlot];
                        table.insert(recommendations, {
                            item_id = item.id,
                            name = item.name,
                            slot = selectedSlot,
                            required_level = item.required_level,
                            source_id = item.source_id,
                            verification = item.verification,
                            ownership = "unowned",
                            replaced_item_id = replaced and replaced.item_id or nil,
                            replaced_name = replaced and replaced.name or nil,
                            full_set = true,
                            virtual = true,
                            required_tag_delta = requiredDelta,
                            first_improved_rank = firstRank,
                            deltas = Preview.delta(baseline, candidateResult),
                            objective_deltas = objectiveDeltas(
                                baseline,
                                candidateResult,
                                activePolicy
                            ),
                            candidate = {
                                item_id = candidate.item_id,
                                name = candidate.name,
                                slot = candidate.slot,
                            },
                        });
                    end
                end
            end
        end
    end

    table.sort(recommendations, function(left, right)
        if left.required_tag_delta ~= right.required_tag_delta then
            return left.required_tag_delta > right.required_tag_delta;
        end
        if left.first_improved_rank ~= right.first_improved_rank then
            return (left.first_improved_rank or 999)
                < (right.first_improved_rank or 999);
        end
        if left.slot ~= right.slot then
            return left.slot < right.slot;
        end
        return left.item_id < right.item_id;
    end);

    local maximum = self.config.upgrade_result_limit or 10;
    while #recommendations > maximum do
        table.remove(recommendations);
    end
    self.diagnostics:add("upgrade", string.format(
        "%s/%s evaluated=%d recommendations=%d",
        job,
        contextKey,
        evaluated,
        #recommendations
    ));
    return recommendations;
end

return upgrade;
