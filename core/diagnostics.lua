local diagnostics = {};
diagnostics.__index = diagnostics;

function diagnostics.new(limit)
    return setmetatable({
        limit = limit or 80,
        rows = {},
    }, diagnostics);
end

function diagnostics:add(kind, message)
    table.insert(self.rows, {
        at = os.clock(),
        kind = tostring(kind or "info"),
        message = tostring(message or ""),
    });
    while #self.rows > self.limit do
        table.remove(self.rows, 1);
    end
end

function diagnostics:recent(count)
    local result = {};
    local first = math.max(1, #self.rows - (count or 10) + 1);
    for index = first,#self.rows do
        table.insert(result, self.rows[index]);
    end
    return result;
end

return diagnostics;
