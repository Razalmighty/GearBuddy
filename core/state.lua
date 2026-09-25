local state = {};

function state.new()
    return {
        loaded = false,
        player = {
            live_job = "Unknown",
            live_job_id = 0,
            effective_level = 0,
            natural_level = 0,
            zone = 0,
        },
        selected_job = "AUTO",
        selected_context = {
            BLU = "engaged",
            BLM = "nuke",
        },
        buffs = {},
        indicators = {
            learn = false,
            chain = false,
            burst = false,
            evasion = false,
        },
        action_context = {
            signature = "none",
            known = false,
        },
        inventory = {
            generation = 0,
            refresh_count = 0,
            last_refresh_at = nil,
            refresh_history = {},
            items = {},
            by_id = {},
            total_items = 0,
            catalog_matches = 0,
            last_reason = "not scanned",
        },
        self_test = {
            status = "not_run",
            checks = {},
            counts = { pass = 0, warn = 0, fail = 0 },
        },
        result = nil,
        result_key = nil,
        policy_revision = 0,
        pin_revision = 0,
        priority_overrides = {},
        gear_pins = {},
        dirty_result = true,
        next_buff_refresh = 0,
        ui = {
            open = { true },
            hud = { true },
            weapons_locked = { true },
            learn_plan = { false },
            evasion_plan = { false },
            chain_plan = { false },
            burst_plan = { false },
            blm_nuke_balance = { 50 },
            force_swap_open = { false },
            force_swap_context = {},
            force_swap_profile = {},
        },
    };
end

return state;
