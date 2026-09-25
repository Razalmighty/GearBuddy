local schema = {};

schema.verification_states = {
    Verified = true,
    Partial = true,
    ["ID Verified"] = true,
    Pending = true,
};

schema.confidence_levels = {
    high = true,
    medium = true,
    low = true,
    unknown = true,
};

schema.action_categories = {
    physical = true,
    magical = true,
    debuff = true,
    healing = true,
    breath = true,
    buff = true,
    drain = true,
    dispel = true,
    status = true,
};

schema.slots = {
    { name = "Main", index = 1, catalog = "Main", weapon = true },
    { name = "Sub", index = 2, catalog = "Sub", weapon = true },
    { name = "Range", index = 3, catalog = "Range", weapon = true },
    { name = "Ammo", index = 4, catalog = "Ammo", weapon = false },
    { name = "Head", index = 5, catalog = "Head", weapon = false },
    { name = "Body", index = 6, catalog = "Body", weapon = false },
    { name = "Hands", index = 7, catalog = "Hands", weapon = false },
    { name = "Legs", index = 8, catalog = "Legs", weapon = false },
    { name = "Feet", index = 9, catalog = "Feet", weapon = false },
    { name = "Neck", index = 10, catalog = "Neck", weapon = false },
    { name = "Waist", index = 11, catalog = "Waist", weapon = false },
    { name = "Ear1", index = 12, catalog = "Ear", weapon = false },
    { name = "Ear2", index = 13, catalog = "Ear", weapon = false },
    { name = "Ring1", index = 14, catalog = "Ring", weapon = false },
    { name = "Ring2", index = 15, catalog = "Ring", weapon = false },
    { name = "Back", index = 16, catalog = "Back", weapon = false },
};

schema.slots_by_name = {};
for _,slot in ipairs(schema.slots) do
    schema.slots_by_name[string.lower(slot.name)] = slot;
end

function schema.normalizeSlot(value)
    local key = string.lower(tostring(value or "")):gsub("[^a-z0-9]", "");
    return schema.slots_by_name[key];
end

schema.context_packets = {
    [0x00A] = "zone",
    [0x01B] = "job_or_sync",
    [0x061] = "job_or_level",
};

schema.inventory_packets = {
    [0x01D] = "inventory_assign",
    [0x01E] = "inventory_update",
    [0x01F] = "inventory_status",
    [0x020] = "inventory_finish",
};

schema.job_ids = {
    WAR = 1, MNK = 2, WHM = 3, BLM = 4, RDM = 5, THF = 6,
    PLD = 7, DRK = 8, BST = 9, BRD = 10, RNG = 11, SAM = 12,
    NIN = 13, DRG = 14, SMN = 15, BLU = 16, COR = 17, PUP = 18,
    DNC = 19, SCH = 20, GEO = 21, RUN = 22,
};

schema.stat_labels = {
    agi = "AGI",
    attack = "Attack",
    accuracy = "Accuracy",
    blue_magic_skill = "Blue Magic Skill",
    cure_potency = "Cure Potency",
    defense = "Defense",
    delay = "Delay",
    dex = "DEX",
    damage = "Damage",
    elemental_magic_skill = "Elemental Magic Skill",
    enmity = "Enmity",
    evasion = "Evasion",
    evasion_skill = "Evasion Skill",
    fast_cast = "Fast Cast",
    haste = "Haste",
    hmp = "hMP",
    hp = "HP",
    int = "INT",
    magic_accuracy = "Magic Accuracy",
    magic_attack_bonus = "Magic Attack Bonus",
    magic_damage_taken = "MDT",
    magic_defense_bonus = "Magic Defense Bonus",
    mnd = "MND",
    mp = "MP",
    parrying_skill = "Parrying Skill",
    physical_damage_taken = "PDT",
    refresh = "Refresh",
    regen = "Regen",
    spell_interruption_down = "Spell Interruption Down",
    store_tp = "Store TP",
    str = "STR",
    vit = "VIT",
};

return schema;
