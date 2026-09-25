local cache = {};
cache.__index = cache;

local function touch(self, key)
    for index,value in ipairs(self.order) do
        if value == key then
            table.remove(self.order, index);
            break;
        end
    end
    table.insert(self.order, key);
end

function cache.new(maxEntries)
    return setmetatable({
        values = {},
        order = {},
        max_entries = maxEntries or 128,
        hits = 0,
        misses = 0,
    }, cache);
end

function cache:get(key)
    local value = self.values[key];
    if value ~= nil then
        self.hits = self.hits + 1;
        touch(self, key);
    else
        self.misses = self.misses + 1;
    end
    return value;
end

function cache:put(key, value)
    touch(self, key);
    self.values[key] = value;
    while #self.order > self.max_entries do
        local oldest = table.remove(self.order, 1);
        self.values[oldest] = nil;
    end
end

function cache:clear()
    self.values = {};
    self.order = {};
end

return cache;
