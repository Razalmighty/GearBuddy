local config = require("config.defaults");
local catalog = require("data.catalog");
local effects = require("data.effects");
local actionData = require("data.actions");
local mechanicsData = require("data.mechanics");
local schema = require("data.schema");
local State = require("core.state");
local Scheduler = require("core.scheduler");
local Diagnostics = require("core.diagnostics");
local InventoryIndex = require("core.inventory_index");
local Context = require("core.context");
local Policy = require("core.policy");
local Resolver = require("core.resolver");
local ResolvedCache = require("core.resolved_cache");
local EquipPlan = require("core.equip_plan");
local Preview = require("core.preview");
local Persistence = require("core.persistence");
local ActionContext = require("core.action_context");
local ActionMechanics = require("core.action_mechanics");
local SelfTest = require("core.self_test");
local GearPins = require("core.gear_pins");
local Upgrade = require("core.upgrade");
local Commands = require("core.commands");
local Console = require("ui.console");
local Hud = require("ui.hud");

local app = {};
app.__index = app;

local function mapSignature(values)
    local keys = {};
    for key,value in pairs(values or {}) do
        if value then
            table.insert(keys, tostring(key));
        end
    end
    table.sort(keys);
    return table.concat(keys, ",");
end

function app.new()
    local diagnostics = Diagnostics.new(80);
    local gearPins = GearPins.new(config, catalog, effects, diagnostics);
    local instance = setmetatable({
        state = State.new(),
        config = config,
        diagnostics = diagnostics,
        scheduler = Scheduler.new(
            config.debounce_seconds,
            config.maximum_debounce_seconds
        ),
        inventory = InventoryIndex.new(config, catalog, diagnostics),
        context = Context.new(diagnostics),
        policy = Policy.new(diagnostics),
        gear_pins = gearPins,
        resolver = Resolver.new(config, catalog, effects, diagnostics, gearPins),
        action_context = ActionContext.new(actionData.actions, diagnostics, {
            metadata_version = actionData.data_version or actionData.schema_version,
            require_verified = true,
        }),
        action_mechanics = ActionMechanics.new(mechanicsData, diagnostics),
        self_test_runner = SelfTest.new(config, diagnostics),
        cache = ResolvedCache.new(128),
        persistence = Persistence.new(diagnostics),
        console = Console.new(),
        hud = Hud.new(),
        next_player_refresh = 0,
    }, app);
    instance.upgrade = Upgrade.new(
        config,
        catalog,
        instance.resolver,
        diagnostics
    );
    return instance;
end

function app:message(text)
    print(string.format("[GearBuddy] %s", tostring(text)));
end

function app:onLoad()
    self.state.loaded = true;
    self.persistence:load(self.state, self.policy);
    self.context:refreshPlayer(self.state);
    self.context:refreshBuffs(self.state);
    self:scheduleRefresh("addon_load", 0.75);
    self.diagnostics:add("lifecycle", "loaded read-only alpha");
    self:message("v0.1.0-alpha.8 loaded in READ-ONLY mode. Use /gb.");
end

function app:onUnload()
    self.persistence:save(self.state, self.policy);
    self.state.loaded = false;
    self.diagnostics:add("lifecycle", "unloaded");
end

function app:onPacketIn(event)
    local contextReason = schema.context_packets[event.id];
    local inventoryReason = schema.inventory_packets[event.id];
    if contextReason ~= nil then
        self.context:refreshPlayer(self.state);
        self.state.dirty_result = true;
        self:scheduleRefresh(contextReason);
    elseif inventoryReason ~= nil then
        self:scheduleRefresh(inventoryReason);
    end
end

function app:onCommand(event)
    Commands.handle(self, event);
end

function app:scheduleRefresh(reason, delay)
    self.scheduler:request(reason, delay);
    self.diagnostics:add("schedule", tostring(reason));
end

function app:effectiveJob()
    return self.context:effectiveJob(self.state);
end

function app:activeContext()
    local job = self:effectiveJob();
    return self.state.selected_context[job];
end

function app:activePinScope()
    local job = self:effectiveJob();
    local contextKey = self.state.selected_context[job];
    local active = contextKey and self.policy:get(job, contextKey, self.state)
        or nil;
    return job, contextKey, active and active.profile_key or nil;
end

function app:resolveAction(action)
    local resolved = self.action_mechanics:annotate(
        self.action_context:resolve(action, self.state)
    );
    if resolved.signature ~= self.state.action_context.signature then
        self.state.action_context = resolved;
        self.state.dirty_result = true;
    end
    return resolved;
end

function app:clearActionPreview()
    self.state.action_context = {
        signature = "none",
        known = false,
    };
    self.state.dirty_result = true;
    self.diagnostics:add("action_preview", "cleared");
end

function app:previewAction(value)
    local text = tostring(value or "");
    local normalized = string.lower(text);
    if normalized == "" or normalized == "clear" or normalized == "none" then
        self:clearActionPreview();
        self:message("Manual action preview cleared.");
        return true;
    end

    local lookup = tonumber(text) or text;
    local resolved = self.action_mechanics:annotate(
        self.action_context:resolve(lookup, self.state)
    );
    if not resolved.known then
        self:message("Unknown or unverified action. Use /gb actions.");
        return false;
    end

    local job = self:effectiveJob();
    if resolved.job ~= job then
        self:message(string.format(
            "%s is registered for %s, not the current preview job %s.",
            resolved.action_name,
            resolved.job,
            job
        ));
        return false;
    end
    if resolved.required_level ~= nil
        and resolved.required_level > self.state.player.effective_level then
        self:message(string.format(
            "%s requires level %d; effective level is %d.",
            resolved.action_name,
            resolved.required_level,
            self.state.player.effective_level
        ));
        return false;
    end
    if self.policy:get(job, resolved.context_key, self.state) == nil then
        self:message("Verified action has no available preview policy.");
        return false;
    end

    self.state.action_context = resolved;
    self.state.selected_context[job] = resolved.context_key;
    self.state.dirty_result = true;
    self.diagnostics:add("action_preview", string.format(
        "%s -> %s/%s",
        resolved.action_name,
        job,
        resolved.context_key
    ));
    self:message(string.format(
        "Previewing %s as %s/%s (read-only).",
        resolved.action_name,
        job,
        resolved.context_key
    ));
    return true;
end

function app:cacheKey(job, contextKey)
    return table.concat({
        tostring(self.state.inventory.generation),
        tostring(job),
        tostring(self.state.player.effective_level),
        tostring(contextKey),
        tostring(self.state.policy_revision),
        tostring(self.state.pin_revision),
        tostring(self.state.ui.weapons_locked[1]),
        tostring(self.state.ui.blm_nuke_balance[1]),
        tostring(self.config.cache_schema_version),
        tostring(self.config.weapon_policy_version),
        tostring(self.config.manual_override_policy_version),
        tostring(catalog.data_version or catalog.schema_version),
        tostring(effects.data_version or effects.schema_version),
        tostring(actionData.data_version or actionData.schema_version),
        tostring(mechanicsData.data_version or mechanicsData.schema_version),
        tostring(self.state.action_context.signature),
        mapSignature(self.state.buffs),
        tostring(self.state.indicators.learn),
        tostring(self.state.indicators.evasion),
        tostring(self.state.indicators.chain),
        tostring(self.state.indicators.burst),
    }, ":");
end

function app:ensureResolved()
    if not self.state.dirty_result then
        return;
    end
    local job = self:effectiveJob();
    local contextKey = self.state.selected_context[job];
    if self.state.inventory.generation == 0 then
        self.state.result = { error = "Waiting for the first scheduled inventory scan." };
        self.state.dirty_result = false;
        return;
    end
    if contextKey == nil then
        self.state.result = { error = "No preview policy for job " .. tostring(job) .. "." };
        self.state.dirty_result = false;
        return;
    end
    local activePolicy = self.policy:get(job, contextKey, self.state);
    if activePolicy == nil then
        self.state.result = { error = "Policy not found for " .. job .. "/" .. contextKey .. "." };
        self.state.dirty_result = false;
        return;
    end

    local key = self:cacheKey(job, contextKey);
    local cached = self.cache:get(key);
    if cached == nil then
        cached = self.resolver:resolve(
            self.state,
            job,
            contextKey,
            activePolicy
        );
        self.cache:put(key, cached);
    end
    self.state.result = cached;
    if cached.equip_plan == nil then
        cached.equip_plan = EquipPlan.fromResult(
            cached,
            self.config.manual_slots
        );
        cached.preview = Preview.explain(cached, activePolicy);
    end
    if cached.upgrades == nil then
        cached.upgrades = self.upgrade:recommend(
            self.state,
            cached,
            job,
            contextKey,
            activePolicy
        );
    end
    self.state.result_key = key;
    self.state.dirty_result = false;
end

function app:tick()
    local now = os.clock();
    if now >= self.next_player_refresh then
        self.next_player_refresh = now + 0.50;
        if self.context:refreshPlayer(self.state) then
            self.state.dirty_result = true;
            self:scheduleRefresh("observed_context_change");
        end
    end
    if now >= self.state.next_buff_refresh then
        self.state.next_buff_refresh = now + self.config.buff_refresh_seconds;
        if self.context:refreshBuffs(self.state) then
            self.state.dirty_result = true;
        end
    end

    local reasons = self.scheduler:poll();
    if reasons ~= nil then
        self.context:refreshPlayer(self.state);
        local refreshed = self.inventory:refresh(self.state, reasons);
        if refreshed then
            self.cache:clear();
            self.state.dirty_result = true;
        end
    end
    self:ensureResolved();
end

function app:present()
    local ok, message = pcall(function()
        self:tick();
        self.console:render(self);
        self.hud:render(self);
    end);
    if not ok then
        self.diagnostics:add("render_error", tostring(message));
    end
end

function app:setJob(job)
    if job ~= "AUTO" and job ~= "BLU" and job ~= "BLM" then
        return false;
    end
    self.state.selected_job = job;
    local effective = self:effectiveJob();
    if self.state.selected_context[effective] == nil then
        self.state.selected_context[effective] = self.policy:defaultContext(effective);
    end
    self.state.dirty_result = true;
    self.persistence:save(self.state, self.policy);
    self.diagnostics:add("ui", "job=" .. job);
    return true;
end

function app:setContext(value)
    local job = self:effectiveJob();
    local key = self.policy:normalizeContext(job, value);
    if key == nil then
        return false;
    end
    self.state.selected_context[job] = key;
    self.state.dirty_result = true;
    self.persistence:save(self.state, self.policy);
    self.diagnostics:add("ui", "context=" .. job .. "/" .. key);
    return true;
end

function app:setWeaponsLocked(locked)
    self.state.ui.weapons_locked[1] = locked == true;
    self.state.policy_revision = self.state.policy_revision + 1;
    self.state.dirty_result = true;
    self.persistence:save(self.state, self.policy);
    self.diagnostics:add("ui", "weapons_locked=" .. tostring(locked));
end

function app:planningModeChanged()
    self.context:updateIndicators(self.state);
    self.state.policy_revision = self.state.policy_revision + 1;
    self.state.dirty_result = true;
    self.persistence:save(self.state, self.policy);
    self.diagnostics:add("ui", "BLU planning mode changed");
end

function app:nukeBalanceChanged()
    -- The focused slider changes the default nuke ordering, but it must not
    -- erase a user's explicit priority-rack order.  Invalidate the prepared
    -- preview and let policy:get() apply the existing override afterward.
    self.state.policy_revision = self.state.policy_revision + 1;
    self.state.dirty_result = true;
    self.persistence:save(self.state, self.policy);
    self.diagnostics:add("ui", "BLM nuke balance=" .. tostring(
        self.state.ui.blm_nuke_balance[1]
    ));
end

function app:moveObjective(index, delta)
    local job = self:effectiveJob();
    local contextKey = self.state.selected_context[job];
    local changed = self.policy:move(job, contextKey, self.state, index, delta);
    if changed then
        self.persistence:save(self.state, self.policy);
    end
    return changed;
end

function app:pinEditorScope()
    local job = self:effectiveJob();
    if job ~= "BLU" and job ~= "BLM" then
        return job, nil, nil;
    end
    local contextKey = self.state.ui.force_swap_context[job];
    if self.policy:normalizeContext(job, contextKey) == nil then
        contextKey = self.state.selected_context[job]
            or self.policy:defaultContext(job);
        self.state.ui.force_swap_context[job] = contextKey;
    end

    local profileMapKey = job .. ":" .. tostring(contextKey);
    local profileKey = self.state.ui.force_swap_profile[profileMapKey];
    if self.policy:normalizeProfile(job, contextKey, profileKey) == nil then
        local active = self.policy:get(job, contextKey, self.state);
        profileKey = active and active.profile_key or nil;
        if profileKey == nil then
            local profiles = self.policy:profiles(job, contextKey);
            profileKey = profiles[1] and profiles[1].key or nil;
        end
        self.state.ui.force_swap_profile[profileMapKey] = profileKey;
    end
    return job, contextKey, profileKey;
end

function app:setPinEditorContext(value)
    local job = self:effectiveJob();
    local contextKey = self.policy:normalizeContext(job, value);
    if contextKey == nil then
        return false;
    end
    self.state.ui.force_swap_context[job] = contextKey;
    local profiles = self.policy:profiles(job, contextKey);
    self.state.ui.force_swap_profile[job .. ":" .. contextKey] =
        profiles[1] and profiles[1].key or nil;
    return true;
end

function app:setPinEditorProfile(value)
    local job,contextKey = self:pinEditorScope();
    local profileKey = self.policy:normalizeProfile(job, contextKey, value);
    if profileKey == nil then
        return false;
    end
    self.state.ui.force_swap_profile[job .. ":" .. contextKey] = profileKey;
    return true;
end

function app:usePinEditorProfile()
    local job,contextKey,profileKey = self:pinEditorScope();
    if contextKey == nil or profileKey == nil then
        return false;
    end
    self.state.selected_context[job] = contextKey;
    local changed = self.policy:activateProfile(
        job,
        contextKey,
        self.state,
        profileKey
    );
    if changed then
        self.persistence:save(self.state, self.policy);
    end
    return changed;
end

function app:pinOptions(job, slotName)
    local slot = schema.normalizeSlot(slotName);
    if slot == nil then
        return {};
    end
    return self.gear_pins:options(
        self.state,
        slot,
        job,
        self.state.player.effective_level
    );
end

function app:setGearPin(job, contextKey, profileKey, slotName, itemId)
    job = string.upper(tostring(job or ""));
    contextKey = self.policy:normalizeContext(job, contextKey);
    profileKey = contextKey
        and self.policy:normalizeProfile(job, contextKey, profileKey)
        or nil;
    local slot = schema.normalizeSlot(slotName);
    itemId = tonumber(itemId);
    if contextKey == nil or profileKey == nil or slot == nil or itemId == nil then
        return false, "invalid_scope";
    end
    if itemId ~= itemId or itemId < 1 or itemId ~= math.floor(itemId) then
        return false, "invalid_item_id";
    end
    local legal = false;
    for _,option in ipairs(self:pinOptions(job, slot.name)) do
        if option.item_id == itemId then
            legal = true;
            break;
        end
    end
    if not legal then
        return false, "not_owned_or_illegal";
    end
    if not self.gear_pins:set(
        self.state,
        job,
        contextKey,
        profileKey,
        slot.name,
        itemId
    ) then
        return false, "invalid_pin";
    end
    self.state.pin_revision = (self.state.pin_revision or 0) + 1;
    self.state.dirty_result = true;
    self.persistence:save(self.state, self.policy);
    self.diagnostics:add("gear_pin", string.format(
        "%s/%s/%s %s=%d",
        job,
        contextKey,
        profileKey,
        slot.name,
        itemId
    ));
    return true;
end

function app:clearGearPin(job, contextKey, profileKey, slotName)
    job = string.upper(tostring(job or ""));
    contextKey = self.policy:normalizeContext(job, contextKey);
    profileKey = contextKey
        and self.policy:normalizeProfile(job, contextKey, profileKey)
        or nil;
    local slot = schema.normalizeSlot(slotName);
    if contextKey == nil or profileKey == nil or slot == nil then
        return false, "invalid_scope";
    end
    local changed = self.gear_pins:clear(
        self.state,
        job,
        contextKey,
        profileKey,
        slot.name
    );
    if changed then
        self.state.pin_revision = (self.state.pin_revision or 0) + 1;
        self.state.dirty_result = true;
        self.persistence:save(self.state, self.policy);
        self.diagnostics:add("gear_pin", string.format(
            "%s/%s/%s %s=auto",
            job,
            contextKey,
            profileKey,
            slot.name
        ));
    end
    return true;
end

function app:printPins(contextValue, profileValue)
    local job = self:effectiveJob();
    local contextKey = contextValue ~= nil
        and self.policy:normalizeContext(job, contextValue)
        or self:activeContext();
    if contextKey == nil then
        self:message("Unknown pin context. Use /gb contexts.");
        return false;
    end
    local active = self.policy:get(job, contextKey, self.state);
    local profileKey = profileValue ~= nil
        and self.policy:normalizeProfile(job, contextKey, profileValue)
        or (active and active.profile_key);
    if profileKey == nil then
        self:message("Unknown priority profile for this context.");
        return false;
    end
    local count = 0;
    for _,slot in ipairs(schema.slots) do
        local pin = self.gear_pins:get(
            self.state,
            job,
            contextKey,
            profileKey,
            slot.name
        );
        if pin ~= nil then
            count = count + 1;
            self:message(string.format(
                "%s/%s/%s %s: %s",
                job,
                contextKey,
                profileKey,
                slot.name,
                self.gear_pins:label(
                    self.state,
                    job,
                    contextKey,
                    profileKey,
                    slot.name
                )
            ));
        end
    end
    if count == 0 then
        self:message(string.format(
            "%s/%s/%s has no manual pins.",
            job,
            contextKey,
            profileKey
        ));
    end
    return true;
end

function app:printStatus()
    local result = self.state.result or {};
    self:message(string.format(
        "job=%s level=%d context=%s inventory_generation=%d refreshes=%d items=%d catalog_matches=%d scheduler=%s selftest=%s",
        self:effectiveJob(),
        self.state.player.effective_level,
        tostring(self:activeContext()),
        self.state.inventory.generation,
        self.state.inventory.refresh_count or 0,
        self.state.inventory.total_items,
        self.state.inventory.catalog_matches,
        self.scheduler:status(),
        tostring(self.state.self_test.status or "not_run")
    ));
    if result.error ~= nil then
        self:message(result.error);
    else
        self:message(string.format(
            "preview selected=%d upgrades=%d cache_hits=%d cache_misses=%d weapons_locked=%s profile=%s pins=%d fallback=%d",
            self.resolver:selectedCount(result),
            #(result.upgrades or {}),
            self.cache.hits,
            self.cache.misses,
            tostring(self.state.ui.weapons_locked[1]),
            tostring(result.profile_key or "default"),
            result.manual_pin_count or 0,
            result.pin_fallback_count or 0
        ));
    end
end

function app:runSelfTest(verbose, runtime, silent)
    local report = self.self_test_runner:run(self, runtime);
    self.state.self_test = report;
    if not silent then
        for _,line in ipairs(SelfTest.format(report, verbose == true)) do
            self:message(line);
        end
    end
    return report;
end

function app:printApprovalReport()
    local report = self:runSelfTest(false, nil, false);
    local result = self.state.result or {};
    local selected = result.error == nil
        and self.resolver:selectedCount(result)
        or 0;
    self:message(string.format(
        "approval version=%s mode=read-only selftest=%s job=%s level=%d zone=%s context=%s profile=%s",
        tostring(self.config.version),
        tostring(report.status),
        self:effectiveJob(),
        self.state.player.effective_level,
        tostring(self.state.player.zone),
        tostring(self:activeContext()),
        tostring(result.profile_key or "unresolved")
    ));
    self:message(string.format(
        "inventory generation=%d refreshes=%d history=%d items=%d catalog_matches=%d last_reason=%s",
        self.state.inventory.generation or 0,
        self.state.inventory.refresh_count or 0,
        #(self.state.inventory.refresh_history or {}),
        self.state.inventory.total_items or 0,
        self.state.inventory.catalog_matches or 0,
        tostring(self.state.inventory.last_reason or "unknown")
    ));
    self:message(string.format(
        "resolver selected=%d pins=%d fallback=%d cache_hits=%d cache_misses=%d scheduler=%s",
        selected,
        result.manual_pin_count or 0,
        result.pin_fallback_count or 0,
        self.cache.hits,
        self.cache.misses,
        self.scheduler:status()
    ));
    if result.error ~= nil then
        self:message("approval preview=" .. tostring(result.error));
    end
    return report;
end

function app:printDiagnostics()
    local rows = self.diagnostics:recent(12);
    if #rows == 0 then
        self:message("No diagnostics recorded.");
    end
    for _,row in ipairs(rows) do
        self:message(string.format("%.2f [%s] %s", row.at, row.kind, row.message));
    end
end

function app:printContexts()
    local job = self:effectiveJob();
    local names = {};
    for _,entry in ipairs(self.policy:contexts(job)) do
        table.insert(names, entry.key);
    end
    self:message(job .. " contexts: " .. table.concat(names, ", "));
end

function app:printActions()
    local job = self:effectiveJob();
    local rows = self.action_context:list(
        job,
        self.state.player.effective_level
    );
    if #rows == 0 then
        self:message("No verified actions are legal for this preview job and level.");
        return;
    end
    local names = {};
    for _,row in ipairs(rows) do
        table.insert(names, string.format("%s[%d]", row.name, row.id));
    end
    self:message(job .. " verified actions: " .. table.concat(names, ", "));
end

return app;
