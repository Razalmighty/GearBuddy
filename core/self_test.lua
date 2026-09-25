-- Read-only compatibility and safety probes for approval testing.
--
-- The self-test observes already-cached GearBuddy state and obtains Ashita
-- manager objects, but it never enumerates bag slots, equips gear, sends a
-- command, or injects a packet.

local selfTest = {};
selfTest.__index = selfTest;

local validStatus = { pass = true, warn = true, fail = true };

local function readable(value)
    value = tostring(value or "");
    value = value:gsub("[%c]+", " ");
    if #value > 180 then
        return string.sub(value, 1, 177) .. "...";
    end
    return value;
end

local function add(report, key, label, status, detail)
    status = validStatus[status] and status or "fail";
    table.insert(report.checks, {
        key = key,
        label = label,
        status = status,
        detail = readable(detail),
    });
    report.counts[status] = report.counts[status] + 1;
end

local function finish(report)
    if report.counts.fail > 0 then
        report.status = "fail";
    elseif report.counts.warn > 0 then
        report.status = "warn";
    else
        report.status = "pass";
    end
    report.completed_at = os.clock();
    return report;
end

local function call(object, method)
    if object == nil then
        return false, nil, "object unavailable";
    end
    local ok, member = pcall(function() return object[method]; end);
    if not ok or type(member) ~= "function" then
        return false, nil, method .. " unavailable";
    end
    local invoked, value = pcall(function() return member(object); end);
    if not invoked then
        return false, nil, value;
    end
    if value == nil then
        return false, nil, method .. " returned nil";
    end
    return true, value, nil;
end

local function field(object, name)
    if object == nil then
        return nil;
    end
    local ok, value = pcall(function() return object[name]; end);
    if ok then
        return value;
    end
    return nil;
end

local function registryCount(registry)
    if registry == nil or type(registry.count) ~= "function" then
        return nil;
    end
    local ok, value = pcall(function() return registry:count(); end);
    if ok and type(value) == "number" then
        return value;
    end
    return nil;
end

local function firstInventoryEntry(inventory)
    if type(inventory) ~= "table" then
        return nil;
    end
    if type(inventory.items) == "table" and inventory.items[1] ~= nil then
        return inventory.items[1];
    end
    for _,instances in pairs(inventory.by_id or {}) do
        if type(instances) == "table" and instances[1] ~= nil then
            return instances[1];
        end
    end
    return nil;
end

function selfTest.new(config, diagnostics)
    return setmetatable({
        config = config or {},
        diagnostics = diagnostics,
    }, selfTest);
end

function selfTest:run(app, runtime)
    local state = app and app.state or {};
    local inventory = state.inventory or {};
    local report = {
        version = self.config.version or "unknown",
        started_at = os.clock(),
        completed_at = nil,
        status = "running",
        checks = {},
        counts = { pass = 0, warn = 0, fail = 0 },
    };

    add(
        report,
        "read_only_config",
        "Read-only configuration",
        self.config.read_only == true and "pass" or "fail",
        self.config.read_only == true
            and "read_only=true"
            or "read_only must remain true"
    );
    add(
        report,
        "executor_absent",
        "Equipment executor boundary",
        app ~= nil and app.executor == nil and "pass" or "fail",
        app ~= nil and app.executor == nil
            and "no equipment executor is attached"
            or "unexpected equipment executor is attached"
    );

    runtime = runtime or {};
    local ashitaCore = runtime.AshitaCore;
    if ashitaCore == nil and _G ~= nil then
        ashitaCore = rawget(_G, "AshitaCore");
    end
    local ashitaApi = runtime.ashita;
    if ashitaApi == nil and _G ~= nil then
        ashitaApi = rawget(_G, "ashita");
    end

    if ashitaCore == nil then
        add(report, "ashita_core", "AshitaCore", "fail", "global unavailable");
    else
        add(report, "ashita_core", "AshitaCore", "pass", "global available");
    end

    local memoryOk, memory, memoryError = call(ashitaCore, "GetMemoryManager");
    add(
        report,
        "memory_manager",
        "Memory manager",
        memoryOk and "pass" or "fail",
        memoryOk and "available" or memoryError
    );
    local resourcesOk, _, resourcesError = call(ashitaCore, "GetResourceManager");
    add(
        report,
        "resource_manager",
        "Resource manager",
        resourcesOk and "pass" or "fail",
        resourcesOk and "available" or resourcesError
    );

    for _,probe in ipairs({
        { "GetPlayer", "memory_player", "Player memory" },
        { "GetParty", "memory_party", "Party memory" },
        { "GetInventory", "memory_inventory", "Inventory memory" },
    }) do
        local ok, _, reason = call(memory, probe[1]);
        add(
            report,
            probe[2],
            probe[3],
            ok and "pass" or "fail",
            ok and "available" or reason
        );
    end

    local eventRegister = field(field(ashitaApi, "events"), "register");
    add(
        report,
        "event_registration",
        "Ashita event registration",
        type(eventRegister) == "function" and "pass" or "fail",
        type(eventRegister) == "function" and "available" or "ashita.events.register unavailable"
    );

    local persistenceAvailable = app ~= nil
        and app.persistence ~= nil
        and app.persistence.backend ~= nil;
    add(
        report,
        "settings_backend",
        "Settings persistence",
        persistenceAvailable and "pass" or "warn",
        persistenceAvailable and "backend available" or "backend unavailable; preferences remain session-only"
    );

    local generation = tonumber(inventory.generation) or 0;
    local refreshCount = tonumber(inventory.refresh_count) or 0;
    if generation > 0 then
        add(
            report,
            "inventory_generation",
            "Scheduled inventory cache",
            "pass",
            string.format(
                "generation=%d refreshes=%d reason=%s",
                generation,
                refreshCount,
                tostring(inventory.last_reason or "unknown")
            )
        );
    else
        add(
            report,
            "inventory_generation",
            "Scheduled inventory cache",
            "warn",
            "first scheduled refresh has not completed"
        );
    end

    local history = inventory.refresh_history or {};
    local lastHistory = history[#history];
    if generation == 0 then
        add(report, "refresh_history", "Refresh observability", "warn", "no refresh recorded yet");
    elseif type(lastHistory) == "table"
        and lastHistory.generation == generation
        and refreshCount >= generation then
        add(
            report,
            "refresh_history",
            "Refresh observability",
            "pass",
            string.format("%d bounded refresh record(s)", #history)
        );
    else
        add(
            report,
            "refresh_history",
            "Refresh observability",
            "fail",
            "latest refresh record does not match the cache generation"
        );
    end

    local cachedEntry = firstInventoryEntry(inventory);
    if cachedEntry == nil then
        add(
            report,
            "cached_item_shape",
            "Cached item shape",
            "warn",
            "cache contains no item to inspect"
        );
    else
        local entryShape = type(cachedEntry.item_id) == "number"
            and type(cachedEntry.bag) == "number"
            and type(cachedEntry.index) == "number"
            and type(cachedEntry.instance_key) == "string";
        add(
            report,
            "cached_item_shape",
            "Cached item shape",
            entryShape and "pass" or "fail",
            entryShape and "stable ID, location, and instance key present"
                or "cached item is missing a required field"
        );

        local resourceShape = cachedEntry.resource ~= nil
            and field(cachedEntry.resource, "Flags") ~= nil
            and field(cachedEntry.resource, "Jobs") ~= nil
            and field(cachedEntry.resource, "Slots") ~= nil
            and field(cachedEntry.resource, "Level") ~= nil;
        local resourceStatus = resourceShape and "pass" or "warn";
        add(
            report,
            "cached_resource_shape",
            "Cached resource shape",
            resourceStatus,
            resourceShape and "Flags, Jobs, Slots, and Level present"
                or "sample resource is missing; affected items fail legality closed"
        );
    end

    local player = state.player or {};
    local effectiveLevel = tonumber(player.effective_level) or 0;
    local liveJob = tostring(player.live_job or "Unknown");
    local contextOk = effectiveLevel >= 1 and effectiveLevel <= 99
        and liveJob ~= "" and liveJob ~= "Unknown";
    add(
        report,
        "player_context",
        "Player context",
        contextOk and "pass" or "warn",
        contextOk and string.format("job=%s effective_level=%d", liveJob, effectiveLevel)
            or "live job or effective level is not ready"
    );

    local result = state.result;
    if result == nil or result.error ~= nil then
        add(
            report,
            "preview_plan",
            "Preview plan safety",
            "warn",
            result and result.error or "preview not calculated"
        );
    elseif type(result.equip_plan) ~= "table" then
        add(report, "preview_plan", "Preview plan safety", "fail", "equip plan missing");
    else
        local safe = result.equip_plan.read_only == true
            and result.equip_plan.executable == false;
        add(
            report,
            "preview_plan",
            "Preview plan safety",
            safe and "pass" or "fail",
            safe and "read_only=true executable=false"
                or "preview plan crossed the read-only boundary"
        );
    end

    local actionCount = registryCount(app and app.action_context);
    local expectedActions = self.config.expected_verified_actions;
    local actionOk = actionCount ~= nil and actionCount > 0;
    local actionStatus = actionOk and "pass" or "fail";
    if actionOk and expectedActions ~= nil and actionCount ~= expectedActions then
        actionStatus = "warn";
    end
    add(
        report,
        "action_registry",
        "Verified action registry",
        actionStatus,
        string.format("loaded=%s expected=%s", tostring(actionCount), tostring(expectedActions))
    );

    local mechanicsCount = registryCount(app and app.action_mechanics);
    local expectedMechanics = self.config.expected_mechanics_rows;
    local mechanicsOk = mechanicsCount ~= nil and mechanicsCount > 0;
    local mechanicsStatus = mechanicsOk and "pass" or "fail";
    if mechanicsOk and expectedMechanics ~= nil and mechanicsCount ~= expectedMechanics then
        mechanicsStatus = "warn";
    end
    add(
        report,
        "mechanics_registry",
        "Mechanics evidence registry",
        mechanicsStatus,
        string.format("loaded=%s expected=%s", tostring(mechanicsCount), tostring(expectedMechanics))
    );

    finish(report);
    if self.diagnostics ~= nil then
        self.diagnostics:add("self_test", string.format(
            "%s pass=%d warn=%d fail=%d",
            report.status,
            report.counts.pass,
            report.counts.warn,
            report.counts.fail
        ));
    end
    return report;
end

function selfTest.format(report, verbose)
    report = report or {
        status = "not_run",
        counts = { pass = 0, warn = 0, fail = 0 },
        checks = {},
    };
    local counts = report.counts or {};
    local lines = {
        string.format(
            "Self-test %s: %d pass, %d warning(s), %d failure(s).",
            string.upper(tostring(report.status or "not_run")),
            counts.pass or 0,
            counts.warn or 0,
            counts.fail or 0
        ),
    };
    for _,check in ipairs(report.checks or {}) do
        if verbose or check.status ~= "pass" then
            table.insert(lines, string.format(
                "[%s] %s: %s",
                string.upper(check.status),
                check.label,
                check.detail
            ));
        end
    end
    return lines;
end

return selfTest;
