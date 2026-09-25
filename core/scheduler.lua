local scheduler = {};
scheduler.__index = scheduler;

function scheduler.new(defaultDelay, maximumDelay)
    return setmetatable({
        default_delay = defaultDelay or 0.25,
        maximum_delay = maximumDelay or 1.50,
        pending = false,
        first_at = nil,
        due_at = nil,
        reasons = {},
    }, scheduler);
end

function scheduler:request(reason, delay)
    local now = os.clock();
    local requestedDelay = delay or self.default_delay;
    if not self.pending then
        self.pending = true;
        self.first_at = now;
        self.reasons = {};
    end
    self.reasons[reason or "unspecified"] = true;
    local latest = now + requestedDelay;
    local forced = self.first_at + self.maximum_delay;
    self.due_at = math.min(latest, forced);
end

function scheduler:poll()
    if (not self.pending) or (os.clock() < self.due_at) then
        return nil;
    end
    local reasons = {};
    for reason,_ in pairs(self.reasons) do
        table.insert(reasons, reason);
    end
    table.sort(reasons);
    self.pending = false;
    self.first_at = nil;
    self.due_at = nil;
    self.reasons = {};
    return table.concat(reasons, ",");
end

function scheduler:status()
    if not self.pending then
        return "idle";
    end
    return string.format("pending %.2fs", math.max(0, self.due_at - os.clock()));
end

return scheduler;
