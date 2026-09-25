local schema = require("data.schema");
local score = require("core.score");
local Candidate = require("core.candidate");
local Legality = require("core.item_legality");

local resolver = {};
resolver.__index = resolver;

function resolver.new(config, catalog, effects, diagnostics, gearPins)
    return setmetatable({
        config = config,
        catalog = catalog,
        effects = effects,
        diagnostics = diagnostics,
        gear_pins = gearPins,
    }, resolver);
end

function resolver:eligible(catalogItem, inventoryItem, slot, job, level)
    return Legality.automatic(
        catalogItem,
        inventoryItem,
        slot,
        job,
        level,
        self.config.verified_item_policy
    );
end

function resolver:candidatesForSlot(state, slot, job, level, contextKey)
    local result = {};
    for itemId,instances in pairs(state.inventory.by_id) do
        local catalogItem = self.catalog.by_id[itemId];
        if catalogItem ~= nil then
            for _,inventoryItem in ipairs(instances) do
                local eligible = self:eligible(
                    catalogItem,
                    inventoryItem,
                    slot,
                    job,
                    level
                );
                if eligible then
                    table.insert(result, Candidate.build(
                        catalogItem,
                        inventoryItem,
                        slot,
                        contextKey,
                        self.effects,
                        self.config.verified_item_policy,
                        "formula"
                    ));
                end
            end
        end
    end
    table.sort(result, function(left, right)
        if left.item_id ~= right.item_id then
            return left.item_id < right.item_id;
        end
        return left.instance_key < right.instance_key;
    end);
    return result;
end

function resolver:resolve(state, job, contextKey, activePolicy, options)
    local level = state.player.effective_level;
    local profileKey = activePolicy.profile_key
        or (activePolicy.objectives[1] and activePolicy.objectives[1].stat)
        or "default";
    local locked = {};
    local pinned = {};
    local pinStatuses = {};
    local reserved = {};
    local manualPinCount = 0;
    local pinFallbackCount = 0;

    -- Resolve every pin first so its physical instance and trusted stats are
    -- present before the beam considers any automatic slot.  This lets caps,
    -- required effects, and the remaining objective ordering optimize around
    -- the player's fixed choices instead of merely replacing the final set.
    for _,slot in ipairs(schema.slots) do
        local isLocked = state.ui.weapons_locked[1]
            and self.config.manual_slots[slot.name];
        if isLocked then
            locked[slot.name] = true;
        end
        if self.gear_pins ~= nil then
            local configured = self.gear_pins:get(
                state,
                job,
                contextKey,
                profileKey,
                slot.name
            );
            if configured ~= nil then
                if isLocked then
                    pinStatuses[slot.name] = {
                        status = "inactive",
                        reason = "weapon_lock",
                        item_id = configured.item_id,
                    };
                else
                    local selected,status = self.gear_pins:resolve(
                        state,
                        slot,
                        job,
                        level,
                        contextKey,
                        profileKey,
                        reserved
                    );
                    pinStatuses[slot.name] = status;
                    if selected ~= nil then
                        pinned[slot.name] = selected;
                        reserved[selected.instance_key] = slot.name;
                        manualPinCount = manualPinCount + 1;
                    else
                        pinFallbackCount = pinFallbackCount + 1;
                    end
                end
            end
        end
    end

    local beam = {
        {
            selected = {},
            used = {},
            stats = {},
            tags = {},
            signature = "",
        },
    };
    local candidateCounts = {};

    for _,slot in ipairs(schema.slots) do
        if pinned[slot.name] ~= nil then
            beam[1] = score.extend(beam[1], pinned[slot.name], slot.name);
        end
    end

    for _,slot in ipairs(schema.slots) do
        if locked[slot.name] then
            candidateCounts[slot.name] = 0;
        elseif pinned[slot.name] ~= nil then
            candidateCounts[slot.name] = 1;
        else
            local candidates = self:candidatesForSlot(
                state,
                slot,
                job,
                level,
                contextKey
            );
            candidateCounts[slot.name] = #candidates;
            local expanded = {};
            for _,partial in ipairs(beam) do
                table.insert(expanded, score.extend(partial, nil, slot.name));
                for _,candidate in ipairs(candidates) do
                    if not partial.used[candidate.instance_key] then
                        table.insert(expanded, score.extend(
                            partial,
                            candidate,
                            slot.name
                        ));
                    end
                end
            end
            table.sort(expanded, function(left, right)
                return score.better(left, right, activePolicy);
            end);
            beam = {};
            local keep = math.min(#expanded, self.config.beam_width);
            for index = 1,keep do
                beam[index] = expanded[index];
            end
        end
    end

    local best = beam[1] or {
        selected = {},
        stats = {},
        tags = {},
        signature = "",
    };
    local missingTags = {};
    for _,tag in ipairs(activePolicy.required_tags or {}) do
        if not best.tags[tag] then
            table.insert(missingTags, tag);
        end
    end
    local result = {
        job = job,
        context = contextKey,
        context_label = activePolicy.label,
        profile_key = profileKey,
        profile_label = activePolicy.profile_label or profileKey,
        level = level,
        set = best.selected,
        locked = locked,
        pins = pinStatuses,
        pinned_slots = pinned,
        manual_pin_count = manualPinCount,
        pin_fallback_count = pinFallbackCount,
        stats = best.stats,
        tags = best.tags,
        missing_tags = missingTags,
        objectives = score.objectiveResults(best, activePolicy),
        candidate_counts = candidateCounts,
        inventory_generation = state.inventory.generation,
        beam_width = self.config.beam_width,
        signature = best.signature,
    };
    if not (options and options.silent) then
        self.diagnostics:add("resolve", string.format(
            "%s/%s/%s level=%d generation=%d selected=%d pins=%d fallback=%d",
            job,
            contextKey,
            profileKey,
            level,
            state.inventory.generation,
            self:selectedCount(result),
            manualPinCount,
            pinFallbackCount
        ));
    end
    return result;
end

function resolver:selectedCount(result)
    local count = 0;
    for _,_ in pairs(result.set or {}) do
        count = count + 1;
    end
    return count;
end

return resolver;
