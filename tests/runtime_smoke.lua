package.path = "./?.lua;./?/init.lua;" .. package.path;

package.preload["bit"] = function()
    local function band(left, right)
        local result = 0;
        local place = 1;
        while left > 0 and right > 0 do
            local leftBit = left % 2;
            local rightBit = right % 2;
            if leftBit == 1 and rightBit == 1 then
                result = result + place;
            end
            left = math.floor(left / 2);
            right = math.floor(right / 2);
            place = place * 2;
        end
        return result;
    end
    return { band = band };
end;

local config = require("config.defaults");
local catalog = require("data.catalog");
local effects = require("data.effects");
local actionData = require("data.actions");
local mechanicsData = require("data.mechanics");
local Diagnostics = require("core.diagnostics");
local Policy = require("core.policy");
local Resolver = require("core.resolver");
local EquipPlan = require("core.equip_plan");
local Preview = require("core.preview");
local Persistence = require("core.persistence");
local ActionContext = require("core.action_context");
local ActionMechanics = require("core.action_mechanics");
local GearPins = require("core.gear_pins");
local Upgrade = require("core.upgrade");
local ResolvedCache = require("core.resolved_cache");
local Commands = require("core.commands");
local InventoryIndex = require("core.inventory_index");
local SelfTest = require("core.self_test");

assert(actionData.schema_version == 1);
assert(actionData.data_version >= 1);
assert(actionData.server_scope == "HorizonXI");
assert(type(actionData.actions) == "table");

local slotMasks = {
    Main = math.pow(2, 0),
    Sub = math.pow(2, 1),
    Range = math.pow(2, 2),
    Ammo = math.pow(2, 3),
    Head = math.pow(2, 4),
    Body = math.pow(2, 5),
    Hands = math.pow(2, 6),
    Legs = math.pow(2, 7),
    Feet = math.pow(2, 8),
    Ring1 = math.pow(2, 13),
    Ring2 = math.pow(2, 14),
};

local state = {
    player = { effective_level = 60 },
    ui = {
        weapons_locked = { true },
        blm_nuke_balance = { 50 },
    },
    priority_overrides = {},
    policy_revision = 0,
    inventory = {
        generation = 1,
        by_id = {},
    },
};

for index,itemId in ipairs({ 14939, 14928, 15684, 15600, 14521, 15265 }) do
    local item = catalog.by_id[itemId];
    state.inventory.by_id[itemId] = {
        {
            item_id = itemId,
            bag = 0,
            index = index,
            instance_key = string.format("00:%02d:%05d", index, itemId),
            resource = {
                Flags = 0x800,
                Jobs = math.pow(2, 16),
                Slots = slotMasks[item.slots[1]],
            },
        },
    };
end

local diagnostics = Diagnostics.new();
local policy = Policy.new(diagnostics);
local resolver = Resolver.new(config, catalog, effects, diagnostics);

-- One physical instance that supports Main and Sub may occupy either slot, but
-- the beam must never duplicate it. Two instances may legally fill both.
local dualItem = {
    id = 99001,
    name = "Dual Slot Fixture",
    slots = { "Main", "Sub" },
    required_level = 1,
    jobs = { "BLU" },
    stats = { accuracy = 1 },
    verification = "Verified",
    source_id = "TEST",
};
local dualCatalog = {
    items = { dualItem },
    by_id = { [99001] = dualItem },
};
local dualConfig = {
    verified_item_policy = "Verified",
    beam_width = 64,
    manual_slots = { Main = true },
    upgrade_candidate_limit = 10,
    upgrade_result_limit = 10,
};
local dualPolicy = {
    label = "Dual-slot test",
    required_tags = {},
    objectives = {
        { stat = "accuracy", label = "Accuracy", direction = "max" },
    },
};
local dualResource = {
    Flags = 0x800,
    Jobs = math.pow(2, 16),
    Slots = slotMasks.Main + slotMasks.Sub,
    Level = 1,
    Name = "Dual Slot Fixture",
};
local function dualInstance(key, index)
    return {
        item_id = 99001,
        bag = 0,
        index = index,
        instance_key = key,
        resource = dualResource,
    };
end
local dualDiagnostics = Diagnostics.new();
local dualResolver = Resolver.new(
    dualConfig,
    dualCatalog,
    { by_item = {} },
    dualDiagnostics
);
local oneInstanceState = {
    player = { effective_level = 75 },
    ui = { weapons_locked = { false } },
    priority_overrides = {},
    inventory = {
        generation = 1,
        by_id = { [99001] = { dualInstance("dual:a", 1) } },
    },
};
local oneInstance = dualResolver:resolve(
    oneInstanceState,
    "BLU",
    "engaged",
    dualPolicy
);
assert(dualResolver:selectedCount(oneInstance) == 1);
local oneCandidate = oneInstance.set.Main or oneInstance.set.Sub;
assert(oneCandidate ~= nil);
assert(oneCandidate.slot == "Main" or oneCandidate.slot == "Sub");

local twoInstanceState = {
    player = { effective_level = 75 },
    ui = { weapons_locked = { false } },
    priority_overrides = {},
    inventory = {
        generation = 1,
        by_id = {
            [99001] = {
                dualInstance("dual:a", 1),
                dualInstance("dual:b", 2),
            },
        },
    },
};
local twoInstances = dualResolver:resolve(
    twoInstanceState,
    "BLU",
    "engaged",
    dualPolicy
);
assert(twoInstances.set.Main ~= nil);
assert(twoInstances.set.Sub ~= nil);
assert(twoInstances.set.Main.instance_key ~= twoInstances.set.Sub.instance_key);

local partialLockState = {
    player = { effective_level = 75 },
    ui = { weapons_locked = { true } },
    priority_overrides = {},
    inventory = { generation = 1, by_id = {} },
};
local partialLockBaseline = dualResolver:resolve(
    partialLockState,
    "BLU",
    "engaged",
    dualPolicy
);
local dualUpgrade = Upgrade.new(
    dualConfig,
    dualCatalog,
    dualResolver,
    dualDiagnostics
);
local dualRecommendations = dualUpgrade:recommend(
    partialLockState,
    partialLockBaseline,
    "BLU",
    "engaged",
    dualPolicy
);
assert(#dualRecommendations == 1);
assert(dualRecommendations[1].slot == "Sub");

-- Force Swap pins are fixed inputs to the same optimizer.  The remaining
-- slots still use formula scoring, one physical instance cannot be duplicated,
-- and unverified manual gear contributes no invented stats.
local ringItems = {
    {
        id = 99101,
        name = "Formula Ring",
        slots = { "Ring" },
        required_level = 1,
        jobs = { "BLU" },
        stats = { accuracy = 10 },
        verification = "Verified",
        source_id = "TEST",
    },
    {
        id = 99102,
        name = "Preference Ring",
        slots = { "Ring" },
        required_level = 1,
        jobs = { "BLU" },
        stats = { accuracy = 1 },
        verification = "Verified",
        source_id = "TEST",
    },
    {
        id = 99103,
        name = "Unknown Stats Ring",
        slots = { "Ring" },
        required_level = nil,
        jobs = {},
        stats = { accuracy = 999 },
        verification = "Partial",
        source_id = "TEST",
    },
    {
        id = 99104,
        name = "Overlevel Ring",
        slots = { "Ring" },
        required_level = 80,
        jobs = { "BLU" },
        stats = { accuracy = 20 },
        verification = "Verified",
        source_id = "TEST",
    },
    {
        id = 99105,
        name = "Unowned Upgrade Ring",
        slots = { "Ring" },
        required_level = 1,
        jobs = { "BLU" },
        stats = { accuracy = 50 },
        verification = "Verified",
        source_id = "TEST",
    },
};
local ringCatalog = { items = ringItems, by_id = {} };
for _,item in ipairs(ringItems) do
    ringCatalog.by_id[item.id] = item;
end
local pinConfig = {
    verified_item_policy = "Verified",
    beam_width = 64,
    manual_slots = { Main = true, Sub = true, Range = true, Ammo = true },
    upgrade_candidate_limit = 20,
    upgrade_result_limit = 10,
};
local ringEffects = { by_item = {} };
local pinDiagnostics = Diagnostics.new();
local pins = GearPins.new(pinConfig, ringCatalog, ringEffects, pinDiagnostics);
local pinResolver = Resolver.new(
    pinConfig,
    ringCatalog,
    ringEffects,
    pinDiagnostics,
    pins
);
local pinPolicy = {
    label = "Accuracy",
    profile_key = "accuracy",
    profile_label = "Accuracy",
    required_tags = {},
    objectives = {
        { stat = "accuracy", label = "Accuracy", direction = "max" },
    },
};
local function ringInstance(itemId, index, requiredLevel)
    return {
        item_id = itemId,
        bag = 0,
        index = index,
        instance_key = string.format("ring:%d:%d", index, itemId),
        resource = {
            Flags = 0x800,
            Jobs = math.pow(2, 16),
            Slots = slotMasks.Ring1 + slotMasks.Ring2,
            Level = requiredLevel or 1,
            Name = ringCatalog.by_id[itemId].name,
        },
    };
end
local function pinState(pinRows, includeUnknown, includeOverlevel)
    local byId = {
        [99101] = { ringInstance(99101, 1, 1) },
        [99102] = { ringInstance(99102, 2, 1) },
    };
    if includeUnknown then
        byId[99103] = { ringInstance(99103, 3, 1) };
    end
    if includeOverlevel then
        byId[99104] = { ringInstance(99104, 4, 80) };
    end
    return {
        player = { effective_level = 75 },
        ui = { weapons_locked = { false } },
        priority_overrides = {},
        gear_pins = {
            [GearPins.key("BLU", "engaged", "accuracy")] = pinRows,
        },
        inventory = { generation = 1, by_id = byId },
    };
end

local manualState = pinState({ Ring1 = { item_id = 99102 } });
local manualResult = pinResolver:resolve(
    manualState,
    "BLU",
    "engaged",
    pinPolicy
);
assert(manualResult.set.Ring1.item_id == 99102);
assert(manualResult.set.Ring1.selection_source == "manual");
assert(manualResult.set.Ring2.item_id == 99101);
assert(manualResult.set.Ring2.selection_source == "formula");
assert(manualResult.stats.accuracy == 11);
assert(manualResult.pins.Ring1.status == "active");
local manualPlan = EquipPlan.fromResult(manualResult, pinConfig.manual_slots);
assert(manualPlan.slots.Ring1.selection_source == "manual");
assert(manualPlan.slots.Ring2.selection_source == "formula");

local duplicatePinState = pinState({
    Ring1 = { item_id = 99102 },
    Ring2 = { item_id = 99102 },
});
local duplicatePinResult = pinResolver:resolve(
    duplicatePinState,
    "BLU",
    "engaged",
    pinPolicy
);
assert(duplicatePinResult.set.Ring1.item_id == 99102);
assert(duplicatePinResult.pins.Ring2.reason == "instance_conflict");
assert(duplicatePinResult.set.Ring2.item_id == 99101);

local missingPinState = pinState({ Ring1 = { item_id = 99999 } });
local missingPinResult = pinResolver:resolve(
    missingPinState,
    "BLU",
    "engaged",
    pinPolicy
);
assert(missingPinResult.pins.Ring1.reason == "not_owned");
assert(missingPinResult.set.Ring1.selection_source == "formula");

local unknownPinState = pinState(
    { Ring1 = { item_id = 99103 } },
    true,
    false
);
local unknownPinResult = pinResolver:resolve(
    unknownPinState,
    "BLU",
    "engaged",
    pinPolicy
);
assert(unknownPinResult.set.Ring1.item_id == 99103);
assert(unknownPinResult.set.Ring1.stats_trusted == false);
assert(unknownPinResult.stats.accuracy == 10);
local unknownPinPlan = EquipPlan.fromResult(
    unknownPinResult,
    pinConfig.manual_slots
);
assert(unknownPinPlan.slots.Ring1.stats_trusted == false);
assert(unknownPinPlan.warnings[1].kind == "manual_pin_unverified_stats");
local unknownOptions = pins:options(
    unknownPinState,
    require("data.schema").normalizeSlot("Ring1"),
    "BLU",
    75
);
local foundUnknownOption = false;
for _,option in ipairs(unknownOptions) do
    if option.item_id == 99103 then
        foundUnknownOption = true;
        assert(option.stats_trusted == false);
    end
end
assert(foundUnknownOption == true);

local overlevelPinState = pinState(
    { Ring1 = { item_id = 99104 } },
    false,
    true
);
local overlevelPinResult = pinResolver:resolve(
    overlevelPinState,
    "BLU",
    "engaged",
    pinPolicy
);
assert(overlevelPinResult.pins.Ring1.reason == "level");
assert(overlevelPinResult.set.Ring1.selection_source == "formula");

local allPinnedState = pinState({
    Ring1 = { item_id = 99102 },
    Ring2 = { item_id = 99101 },
});
local allPinnedBaseline = pinResolver:resolve(
    allPinnedState,
    "BLU",
    "engaged",
    pinPolicy
);
local pinUpgrade = Upgrade.new(
    pinConfig,
    ringCatalog,
    pinResolver,
    pinDiagnostics
);
assert(#pinUpgrade:recommend(
    allPinnedState,
    allPinnedBaseline,
    "BLU",
    "engaged",
    pinPolicy
) == 0);

local weaponPins = GearPins.new(
    dualConfig,
    dualCatalog,
    { by_item = {} },
    dualDiagnostics
);
local weaponPinResolver = Resolver.new(
    dualConfig,
    dualCatalog,
    { by_item = {} },
    dualDiagnostics,
    weaponPins
);
local weaponPinState = {
    player = { effective_level = 75 },
    ui = { weapons_locked = { true } },
    priority_overrides = {},
    gear_pins = {
        [GearPins.key("BLU", "engaged", "accuracy")] = {
            Main = { item_id = 99001 },
        },
    },
    inventory = {
        generation = 1,
        by_id = { [99001] = { dualInstance("dual:pin", 1) } },
    },
};
local weaponPinResult = weaponPinResolver:resolve(
    weaponPinState,
    "BLU",
    "engaged",
    pinPolicy
);
assert(weaponPinResult.locked.Main == true);
assert(weaponPinResult.pins.Main.status == "inactive");
assert(weaponPinResult.pins.Main.reason == "weapon_lock");

local engaged = resolver:resolve(
    state,
    "BLU",
    "engaged",
    policy:get("BLU", "engaged", state)
);
assert(engaged.set.Hands.name == "Akinji Bazubands");

local learning = resolver:resolve(
    state,
    "BLU",
    "learning",
    policy:get("BLU", "learning", state)
);
assert(learning.set.Hands.name == "Magus Bazubands");
assert(learning.tags.learn_blue_magic == true);

state.player.effective_level = 55;
local synced = resolver:resolve(
    state,
    "BLU",
    "engaged",
    policy:get("BLU", "engaged", state)
);
assert(synced.set.Hands.name == "Akinji Bazubands");
assert(synced.set.Body == nil);
assert(synced.set.Head == nil);

local plan = EquipPlan.fromResult(engaged, config.manual_slots);
assert(plan.read_only == true);
assert(plan.executable == false);
assert(plan.locked.Main == "manual_lock");
assert(plan.slots.Hands.name == "Akinji Bazubands");
assert(EquipPlan.countSelected(plan) == 5);

local explanation = Preview.explain(
    engaged,
    policy:get("BLU", "engaged", state)
);
assert(explanation.totals.accuracy == engaged.stats.accuracy);
assert(#explanation.objectives == #engaged.objectives);

local changed = {
    stats = { accuracy = (engaged.stats.accuracy or 0) + 2 },
    set = {
        Hands = {
            name = "Replacement Hands",
            instance_key = "replacement",
        },
    },
};
local delta = Preview.delta(engaged, changed);
assert(delta.stats.accuracy == 2);
assert(delta.slots.Hands.after == "Replacement Hands");

state.ui.blm_nuke_balance[1] = 0;
state.priority_overrides["BLM:nuke"] = {
    "mp", "magic_accuracy", "magic_attack_bonus",
    "int", "elemental_magic_skill",
};
local manuallyOrderedNuke = policy:get("BLM", "nuke", state);
assert(manuallyOrderedNuke.objectives[1].stat == "mp");

local profileState = {
    action_context = { known = false },
    priority_overrides = {},
    policy_revision = 0,
    dirty_result = false,
    ui = { blm_nuke_balance = { 50 } },
};
local defaultEngagedProfile = policy:get("BLU", "engaged", profileState);
assert(defaultEngagedProfile.profile_key == "haste");
assert(policy:normalizeProfile("BLU", "engaged", "Accuracy") == "accuracy");
assert(policy:activateProfile(
    "BLU",
    "engaged",
    profileState,
    "accuracy"
) == true);
assert(policy:get("BLU", "engaged", profileState).profile_key == "accuracy");

local storedPreferences = nil;
local preferenceBackend = {};
function preferenceBackend:load(defaults)
    return storedPreferences or defaults;
end
function preferenceBackend:save(document)
    storedPreferences = document;
end

local preferenceState = {
    selected_job = "AUTO",
    selected_context = { BLU = "engaged", BLM = "nuke" },
    priority_overrides = {},
    policy_revision = 0,
    pin_revision = 0,
    gear_pins = {},
    dirty_result = false,
    ui = {
        weapons_locked = { true },
        learn_plan = { false },
        evasion_plan = { false },
        chain_plan = { false },
        burst_plan = { false },
        blm_nuke_balance = { 50 },
        hud = { true },
        open = { true },
    },
};
local preferences = Persistence.new(
    Diagnostics.new(),
    preferenceBackend
);
assert(preferences:load(preferenceState, policy) == true);
preferenceState.selected_job = "BLM";
preferenceState.selected_context.BLM = "nuke";
preferenceState.priority_overrides["BLM:nuke"] = { "mp", "magic_accuracy" };
preferenceState.gear_pins["BLU:engaged:accuracy"] = {
    Ring1 = { item_id = 99102, mode = "force" },
};
preferenceState.ui.weapons_locked[1] = false;
preferenceState.ui.blm_nuke_balance[1] = 73;
preferenceState.ui.hud[1] = false;
assert(preferences:save(preferenceState, policy) == true);

preferenceState.selected_job = "AUTO";
preferenceState.priority_overrides = {};
preferenceState.gear_pins = {};
preferenceState.ui.weapons_locked[1] = true;
preferenceState.ui.blm_nuke_balance[1] = 50;
preferenceState.ui.hud[1] = true;
local reloaded = Persistence.new(Diagnostics.new(), preferenceBackend);
assert(reloaded:load(preferenceState, policy) == true);
assert(preferenceState.selected_job == "BLM");
assert(preferenceState.priority_overrides["BLM:nuke"][1] == "mp");
assert(preferenceState.gear_pins["BLU:engaged:accuracy"].Ring1.item_id == 99102);
assert(preferenceState.ui.weapons_locked[1] == false);
assert(preferenceState.ui.blm_nuke_balance[1] == 73);
assert(preferenceState.ui.hud[1] == false);

storedPreferences = {
    schema_version = 1,
    selected_job = "NOT_A_JOB",
    selected_context = { BLU = "not_a_context" },
    priority_overrides = {
        ["BLU:not_a_context"] = { "fake_stat" },
    },
    gear_pins = {
        ["BLU:engaged:accuracy"] = {
            Ring1 = { item_id = 99102 },
        },
    },
    ui = {
        blm_nuke_balance = 999,
        weapons_locked = "unsafe",
    },
};
preferenceState.selected_job = "AUTO";
preferenceState.selected_context = { BLU = "engaged", BLM = "nuke" };
preferenceState.priority_overrides = {};
preferenceState.gear_pins = {};
preferenceState.ui.weapons_locked[1] = true;
preferenceState.ui.blm_nuke_balance[1] = 50;
assert(reloaded:load(preferenceState, policy) == true);
assert(preferenceState.selected_job == "AUTO");
assert(preferenceState.selected_context.BLU == "engaged");
assert(preferenceState.priority_overrides["BLU:not_a_context"] == nil);
assert(next(preferenceState.gear_pins) == nil);
assert(preferenceState.ui.weapons_locked[1] == true);
assert(preferenceState.ui.blm_nuke_balance[1] == 100);

storedPreferences = {
    schema_version = 2,
    selected_job = "BLU",
    selected_context = { BLU = "engaged", BLM = "nuke" },
    priority_overrides = {},
    gear_pins = {
        ["BLU:engaged:accuracy"] = {
            Ring1 = { item_id = 99102 },
            NotASlot = { item_id = 99101 },
            Ring2 = { item_id = 99101.5 },
        },
        ["BLU:engaged:not_a_profile"] = {
            Head = { item_id = 14928 },
        },
    },
    ui = {},
};
preferenceState.gear_pins = {};
assert(reloaded:load(preferenceState, policy) == true);
assert(preferenceState.gear_pins["BLU:engaged:accuracy"].Ring1.item_id == 99102);
assert(preferenceState.gear_pins["BLU:engaged:accuracy"].Ring2 == nil);
assert(preferenceState.gear_pins["BLU:engaged:accuracy"].NotASlot == nil);
assert(preferenceState.gear_pins["BLU:engaged:not_a_profile"] == nil);

local actionDiagnostics = Diagnostics.new();
local actions = ActionContext.new({
    {
        id = 1001,
        name = "Disseverment",
        job = "BLU",
        category = "physical",
        context = "physical",
        skill = "Blue Magic",
        hit_count = 5,
        wsc = { STR = 0.3, DEX = 0.3 },
        chain_behavior = "tp_accuracy",
        flags = { multi_hit_accuracy = true },
    },
    {
        id = 1002,
        name = "Magic Hammer",
        job = "BLU",
        category = "drain",
        context = "debuff",
        skill = "Blue Magic",
        element = "Light",
        burst_behavior = "magic_burst",
    },
    {
        id = 1003,
        name = "Broken Metadata",
        job = "BLU",
        category = "not_a_category",
        context = "physical",
    },
    {
        id = 1001,
        name = "Duplicate Metadata",
        job = "BLU",
        category = "physical",
        context = "physical",
    },
}, actionDiagnostics);
assert(actions:count() == 2);
assert(#actions.rejected == 2);

local affinityState = {
    buffs = { chainaffinity = true },
    ui = { chain_plan = { false }, burst_plan = { false } },
    player = { tp = 3000 },
};
local physicalAction = actions:resolve(1001, affinityState);
assert(physicalAction.known == true);
assert(physicalAction.context_key == "physical");
assert(physicalAction.hit_count == 5);
assert(physicalAction.multi_hit == true);
assert(physicalAction.wsc.str == 0.3);
assert(physicalAction.chain_active == true);
assert(physicalAction.affinity_source.chain == "active_buff");

local noAffinityState = {
    buffs = {},
    ui = { chain_plan = { false }, burst_plan = { false } },
    player = { tp = 3000 },
};
local noAffinity = actions:resolve("Disseverment", noAffinityState);
assert(noAffinity.chain_active == false);
assert(noAffinity.chain_requested == false);
assert(noAffinity.signature ~= nil);

local verifiedRegistry = ActionContext.new(
    actionData.actions,
    Diagnostics.new(),
    {
        metadata_version = actionData.data_version,
        require_verified = true,
    }
);
assert(verifiedRegistry:count() == 106);
assert(#verifiedRegistry.rejected == 7);
for _,rejected in ipairs(verifiedRegistry.rejected) do
    assert(rejected.reason == "action_not_verified");
end
local mechanicsRegistry = ActionMechanics.new(
    mechanicsData,
    Diagnostics.new()
);
assert(mechanicsRegistry:count() == 4);
assert(#mechanicsRegistry.rejected == 0);
local sandspinMechanics = mechanicsRegistry:resolve(524);
assert(sandspinMechanics.known == true);
assert(sandspinMechanics.by_type.landing.status == "qualitative");
assert(sandspinMechanics.by_type.duration.status == "unknown");
assert(#sandspinMechanics.by_type.duration.drivers == 0);
local unknownMechanics = mechanicsRegistry:resolve(999999);
assert(unknownMechanics.known == false);
assert(unknownMechanics.by_type.potency.status == "unknown");
local rejectedMechanics = ActionMechanics.new({
    schema_version = 1,
    data_version = 1,
    server_scope = "HorizonXI",
    mechanics = {
        {
            action_id = 9999,
            verification = "Partial",
            confidence = "low",
            last_verified = "2026-09-25",
            source_ids = { "TEST" },
            outcomes = {
                {
                    type = "landing",
                    status = "unknown",
                    drivers = {
                        { kind = "stat", key = "int", role = "invented" },
                    },
                    notes = "Invalid assertion fixture",
                },
                { type = "potency", status = "unknown", drivers = {}, notes = "Unknown" },
                { type = "duration", status = "unknown", drivers = {}, notes = "Unknown" },
                { type = "utility", status = "unknown", drivers = {}, notes = "Unknown" },
            },
        },
    },
}, Diagnostics.new());
assert(rejectedMechanics:count() == 0);
assert(rejectedMechanics.rejected[1].reason == "unsupported_driver_assertion");
local annotatedAction = mechanicsRegistry:annotate(
    verifiedRegistry:resolve("Cannonball", noAffinityState)
);
assert(annotatedAction.mechanics.known == true);
assert(annotatedAction.mechanics.by_type.potency.status == "qualitative");
local breathAction = verifiedRegistry:resolve("Poison Breath", noAffinityState);
assert(breathAction.known == true);
assert(breathAction.context_key == "breath");
assert(breathAction.metadata_flags.hp_sensitive == true);
assert(breathAction.required_level == 22);
assert(breathAction.verification == "Verified");
assert(breathAction.metadata_version == actionData.data_version);
local level18Actions = verifiedRegistry:list("BLU", 18);
assert(#level18Actions == 18);
assert(level18Actions[1].name == "Foot Kick");
assert(level18Actions[2].name == "Pollen");
assert(level18Actions[3].name == "Sandspin");
assert(level18Actions[16].name == "Blastbomb");
assert(level18Actions[17].name == "Bludgeon");
assert(level18Actions[18].name == "Cursed Sphere");
local horizonAction = verifiedRegistry:resolve("Winds of Promy.", noAffinityState);
assert(horizonAction.known == true);
assert(horizonAction.action_name == "Winds of Promyvion");
assert(horizonAction.required_level == 54);
assert(horizonAction.context_key == "buff");
assert(horizonAction.horizon_verification == "Horizon change");
local quadAction = verifiedRegistry:resolve("Quad. Continuum", noAffinityState);
assert(quadAction.hit_count == 4);
assert(quadAction.multi_hit == true);
assert(quadAction.dominant_stats[1] == "str");
local level75Actions = verifiedRegistry:list("BLU", 75);
assert(#level75Actions == 106);
local pendingAction = verifiedRegistry:resolve("Spiral Spin", noAffinityState);
assert(pendingAction.known == false);
local plasmaAction = verifiedRegistry:resolve("Plasma Charge", noAffinityState);
assert(plasmaAction.known == true);
assert(plasmaAction.element == "Lightning");
assert(plasmaAction.verification == "Verified");
local cannonAction = verifiedRegistry:resolve("Cannonball", noAffinityState);
assert(cannonAction.known == true);
assert(cannonAction.dominant_stats[1] == "str");
assert(cannonAction.dominant_stats[2] == "defense");
assert(cannonAction.best_use == "Defense-scaled blunt damage");

local actionFocusState = {
    action_context = cannonAction,
    priority_overrides = {},
    ui = { blm_nuke_balance = { 50 } },
};
local cannonPolicy = policy:get("BLU", "physical", actionFocusState);
assert(cannonPolicy.objectives[1].stat == "blue_magic_skill");
assert(cannonPolicy.objectives[2].stat == "accuracy");
assert(cannonPolicy.objectives[3].stat == "str");
assert(cannonPolicy.objectives[4].stat == "defense");

local capturedAction = nil;
local commandApp = {
    previewAction = function(_, value)
        capturedAction = value;
        return true;
    end,
};
local commandEvent = {
    command = "/gb action Poison Breath",
    blocked = false,
};
assert(Commands.handle(commandApp, commandEvent) == true);
assert(commandEvent.blocked == true);
assert(capturedAction == "Poison Breath");

local capturedPin = nil;
local capturedMessage = nil;
local pinCommandApp = {
    activePinScope = function()
        return "BLU", "engaged", "accuracy";
    end,
    setGearPin = function(_, job, contextKey, profileKey, slotName, itemId)
        capturedPin = { job, contextKey, profileKey, slotName, itemId };
        return true;
    end,
    clearGearPin = function(_, job, contextKey, profileKey, slotName)
        capturedPin = { job, contextKey, profileKey, slotName, "auto" };
        return true;
    end,
    message = function(_, value)
        capturedMessage = value;
    end,
};
local pinCommand = { command = "/gb pin Ring1 99102", blocked = false };
assert(Commands.handle(pinCommandApp, pinCommand) == true);
assert(pinCommand.blocked == true);
assert(capturedPin[1] == "BLU");
assert(capturedPin[2] == "engaged");
assert(capturedPin[3] == "accuracy");
assert(capturedPin[4] == "Ring1");
assert(capturedPin[5] == 99102);
assert(capturedMessage ~= nil);
local explicitPinCommand = {
    command = "/gb pin physical accuracy Ring2 auto",
    blocked = false,
};
assert(Commands.handle(pinCommandApp, explicitPinCommand) == true);
assert(capturedPin[2] == "physical");
assert(capturedPin[3] == "accuracy");
assert(capturedPin[4] == "Ring2");
assert(capturedPin[5] == "auto");

local selfTestVerbose = nil;
local approvalReportCalls = 0;
local approvalCommandApp = {
    runSelfTest = function(_, verbose)
        selfTestVerbose = verbose;
    end,
    printApprovalReport = function()
        approvalReportCalls = approvalReportCalls + 1;
    end,
};
local selfTestCommand = {
    command = "/gb selftest verbose",
    blocked = false,
};
assert(Commands.handle(approvalCommandApp, selfTestCommand) == true);
assert(selfTestCommand.blocked == true);
assert(selfTestVerbose == true);
local reportCommand = { command = "/gb report", blocked = false };
assert(Commands.handle(approvalCommandApp, reportCommand) == true);
assert(reportCommand.blocked == true);
assert(approvalReportCalls == 1);

local quarantinedRegistry = ActionContext.new({
    {
        id = 9998,
        name = "Unverified Test Action",
        job = "BLU",
        category = "physical",
        context = "physical",
        required_level = 1,
        verification = "Pending",
        confidence = "unknown",
        source_id = "TEST",
    },
}, Diagnostics.new(), { require_verified = true });
assert(quarantinedRegistry:count() == 0);
assert(quarantinedRegistry.rejected[1].reason == "action_not_verified");

noAffinityState.ui.chain_plan[1] = true;
local plannedAffinity = actions:resolve("Disseverment", noAffinityState);
assert(plannedAffinity.chain_active == false);
assert(plannedAffinity.chain_requested == true);
assert(plannedAffinity.affinity_source.chain == "manual_plan");

local unknownAction = actions:resolve(9999, noAffinityState);
assert(unknownAction.known == false);
assert(unknownAction.context_key == nil);

local boundedCache = ResolvedCache.new(2);
boundedCache:put("a", { value = 1 });
boundedCache:put("b", { value = 2 });
assert(boundedCache:get("a").value == 1);
boundedCache:put("c", { value = 3 });
assert(boundedCache:get("b") == nil);
assert(boundedCache:get("a").value == 1);
assert(boundedCache:get("c").value == 3);

local upgradeState = {
    player = { effective_level = 60 },
    ui = { weapons_locked = { true } },
    priority_overrides = {},
    inventory = {
        generation = 1,
        by_id = { [14939] = state.inventory.by_id[14939] },
    },
};
local upgradePolicy = policy:get("BLU", "engaged", upgradeState);
local upgradeBaseline = resolver:resolve(
    upgradeState,
    "BLU",
    "engaged",
    upgradePolicy
);
local planner = Upgrade.new(config, catalog, resolver, Diagnostics.new());
local recommendations = planner:recommend(
    upgradeState,
    upgradeBaseline,
    "BLU",
    "engaged",
    upgradePolicy
);
assert(#recommendations > 0);
assert(recommendations[1].ownership == "unowned");
assert(recommendations[1].full_set == true);
assert(recommendations[1].deltas.stats ~= nil);
for _,recommendation in ipairs(recommendations) do
    assert(recommendation.slot ~= "Main");
    assert(recommendation.slot ~= "Sub");
    assert(recommendation.slot ~= "Range");
    assert(recommendation.slot ~= "Ammo");
end

-- Compatibility probes observe manager availability and cached state without
-- enumerating a bag or mutating the plan.
local bagEnumerationCalls = 0;
local fakeMemory = {
    GetPlayer = function() return {}; end,
    GetParty = function() return {}; end,
    GetInventory = function()
        return {
            GetContainerCountMax = function()
                bagEnumerationCalls = bagEnumerationCalls + 1;
                return 0;
            end,
        };
    end,
};
local fakeRuntime = {
    AshitaCore = {
        GetMemoryManager = function() return fakeMemory; end,
        GetResourceManager = function() return {}; end,
    },
    ashita = {
        events = { register = function() end },
    },
};
local selfTestResource = {
    Flags = 0x800,
    Jobs = math.pow(2, 16),
    Slots = slotMasks.Head,
    Level = 1,
};
local selfTestState = {
    player = {
        live_job = "BLU",
        effective_level = 60,
    },
    inventory = {
        generation = 1,
        refresh_count = 1,
        refresh_history = {
            { generation = 1, at = 1, reason = "test" },
        },
        items = {
            {
                item_id = 14928,
                bag = 0,
                index = 1,
                instance_key = "00:01:14928",
                resource = selfTestResource,
            },
        },
        by_id = {},
        total_items = 1,
        catalog_matches = 1,
        last_reason = "test",
    },
    result = {
        equip_plan = { read_only = true, executable = false },
    },
};
local selfTestApp = {
    state = selfTestState,
    persistence = { backend = {} },
    action_context = verifiedRegistry,
    action_mechanics = mechanicsRegistry,
};
local compatibility = SelfTest.new(config, Diagnostics.new());
local compatibilityReport = compatibility:run(selfTestApp, fakeRuntime);
assert(compatibilityReport.status == "pass");
assert(compatibilityReport.counts.fail == 0);
assert(bagEnumerationCalls == 0);
assert(#SelfTest.format(compatibilityReport, false) == 1);
assert(#SelfTest.format(compatibilityReport, true) == #compatibilityReport.checks + 1);

selfTestState.result.equip_plan.executable = true;
local unsafeReport = compatibility:run(selfTestApp, fakeRuntime);
assert(unsafeReport.status == "fail");
assert(unsafeReport.counts.fail == 1);
selfTestState.result.equip_plan.executable = false;

-- Inventory refreshes retain a bounded, reasoned scan history while replacing
-- the immutable cache generation.
local previousAshitaCore = rawget(_G, "AshitaCore");
local fixtureResource = {
    Flags = 0x800,
    Jobs = math.pow(2, 16),
    Slots = slotMasks.Head,
    Level = 1,
};
local fixtureInventory = {
    GetContainerCountMax = function(_, bag)
        assert(bag == 0);
        return 1;
    end,
    GetContainerItem = function(_, bag, index)
        assert(bag == 0 and index == 1);
        return { Id = 14928, Count = 1, Flags = 0 };
    end,
};
_G.AshitaCore = {
    GetMemoryManager = function()
        return { GetInventory = function() return fixtureInventory; end };
    end,
    GetResourceManager = function()
        return { GetItemById = function() return fixtureResource; end };
    end,
};
local inventoryFixtureConfig = {
    inventory_bags = { 0 },
    inventory_history_limit = 2,
};
local inventoryFixtureState = {
    inventory = {
        generation = 0,
        refresh_count = 0,
        refresh_history = {},
    },
};
local inventoryFixture = InventoryIndex.new(
    inventoryFixtureConfig,
    catalog,
    Diagnostics.new()
);
assert(inventoryFixture:refresh(inventoryFixtureState, "first") == true);
assert(inventoryFixture:refresh(inventoryFixtureState, "second") == true);
assert(inventoryFixture:refresh(inventoryFixtureState, "third") == true);
assert(inventoryFixtureState.inventory.generation == 3);
assert(inventoryFixtureState.inventory.refresh_count == 3);
assert(#inventoryFixtureState.inventory.refresh_history == 2);
assert(inventoryFixtureState.inventory.refresh_history[1].reason == "second");
assert(inventoryFixtureState.inventory.refresh_history[2].reason == "third");
assert(inventoryFixtureState.inventory.total_items == 1);
_G.AshitaCore = previousAshitaCore;

print("Lua resolver smoke test passed.");
