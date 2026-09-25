local inventoryIndex = {};
inventoryIndex.__index = inventoryIndex;

local function readField(object, field, fallback)
    local ok, value = pcall(function() return object[field]; end);
    if ok and value ~= nil then
        return value;
    end
    return fallback;
end

function inventoryIndex.new(config, catalog, diagnostics)
    return setmetatable({
        config = config,
        catalog = catalog,
        diagnostics = diagnostics,
    }, inventoryIndex);
end

function inventoryIndex:refresh(state, reason)
    local ok, result = pcall(function()
        local previous = state.inventory or {};
        local inventory = AshitaCore:GetMemoryManager():GetInventory();
        local resources = AshitaCore:GetResourceManager();
        local items = {};
        local byId = {};
        local catalogMatches = 0;

        for _,bag in ipairs(self.config.inventory_bags) do
            local maximum = inventory:GetContainerCountMax(bag);
            maximum = math.max(0, math.min(maximum or 0, 80));
            for index = 1,maximum do
                local item = inventory:GetContainerItem(bag, index);
                if item ~= nil then
                    local itemId = readField(item, "Id", 0);
                    local count = readField(item, "Count", 0);
                    if itemId > 0 and count > 0 then
                        local resource = resources:GetItemById(itemId);
                        local entry = {
                            item_id = itemId,
                            count = count,
                            bag = bag,
                            index = index,
                            instance_key = string.format("%02d:%02d:%05d", bag, index, itemId),
                            flags = readField(item, "Flags", 0),
                            resource = resource,
                        };
                        table.insert(items, entry);
                        byId[itemId] = byId[itemId] or {};
                        table.insert(byId[itemId], entry);
                        if self.catalog.by_id[itemId] ~= nil then
                            catalogMatches = catalogMatches + 1;
                        end
                    end
                end
            end
        end

        local generation = (previous.generation or 0) + 1;
        local refreshedAt = os.clock();
        local history = {};
        for _,entry in ipairs(previous.refresh_history or {}) do
            table.insert(history, {
                generation = entry.generation,
                at = entry.at,
                reason = entry.reason,
            });
        end
        table.insert(history, {
            generation = generation,
            at = refreshedAt,
            reason = reason or "scheduled",
        });
        local historyLimit = self.config.inventory_history_limit or 8;
        while #history > historyLimit do
            table.remove(history, 1);
        end

        return {
            generation = generation,
            refresh_count = (previous.refresh_count or 0) + 1,
            last_refresh_at = refreshedAt,
            refresh_history = history,
            items = items,
            by_id = byId,
            total_items = #items,
            catalog_matches = catalogMatches,
            last_reason = reason or "scheduled",
        };
    end);

    if not ok then
        self.diagnostics:add("inventory_error", tostring(result));
        return false, tostring(result);
    end
    state.inventory = result;
    self.diagnostics:add("inventory", string.format(
        "generation=%d items=%d catalog=%d reason=%s",
        result.generation,
        result.total_items,
        result.catalog_matches,
        result.last_reason
    ));
    return true;
end

return inventoryIndex;
