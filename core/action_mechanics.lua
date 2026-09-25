-- Versioned, fail-closed action-mechanics boundary.
--
-- This registry reports independent landing, potency, duration, and utility
-- evidence.  Alpha.7 does not convert qualitative rows into numeric scoring;
-- unknown or partially known relationships remain visible and inert.

local actionMechanics = {};
actionMechanics.__index = actionMechanics;

local outcomeOrder = { "landing", "potency", "duration", "utility" };
local allowedOutcome = {
    landing = true,
    potency = true,
    duration = true,
    utility = true,
};
local allowedStatus = {
    not_applicable = true,
    qualitative = true,
    unknown = true,
    verified_numeric = true,
};
local allowedVerification = { Verified = true, Partial = true };
local allowedConfidence = { high = true, medium = true, low = true };
local allowedDriverKind = {
    stat = true,
    state = true,
    model = true,
    property = true,
};

local allowedFormulaNode = { constant = true, input = true, operator = true };
local allowedFormulaOperator = {
    add = true, subtract = true, multiply = true, divide = true,
    minimum = true, maximum = true, floor = true, ceiling = true, clamp = true,
};
local allowedRounding = { none = true, floor = true, ceiling = true, nearest = true };

local function validFormulaNode(node, depth)
    depth = depth or 0;
    if depth > 24 or type(node) ~= "table" or not allowedFormulaNode[node.type] then
        return false;
    end
    if node.type == "constant" then
        return type(node.value) == "number" and type(node.unit) == "string" and node.unit ~= "";
    end
    if node.type == "input" then
        return type(node.key) == "string" and node.key ~= ""
            and type(node.unit) == "string" and node.unit ~= "";
    end
    if not allowedFormulaOperator[node.operator] or type(node.args) ~= "table" then
        return false;
    end
    local count = #node.args;
    if (node.operator == "subtract" or node.operator == "divide") and count ~= 2 then
        return false;
    end
    if (node.operator == "floor" or node.operator == "ceiling") and count ~= 1 then
        return false;
    end
    if node.operator == "clamp" and count ~= 3 then
        return false;
    end
    if (node.operator == "add" or node.operator == "multiply"
        or node.operator == "minimum" or node.operator == "maximum") and count < 2 then
        return false;
    end
    for _,child in ipairs(node.args) do
        if not validFormulaNode(child, depth + 1) then
            return false;
        end
    end
    return true;
end

local function validFormula(formula)
    return type(formula) == "table"
        and type(formula.id) == "string" and formula.id ~= ""
        and type(formula.output) == "table"
        and type(formula.output.key) == "string" and formula.output.key ~= ""
        and type(formula.output.unit) == "string" and formula.output.unit ~= ""
        and allowedRounding[formula.rounding]
        and validFormulaNode(formula.expression, 0);
end

local function copy(value)
    if type(value) ~= "table" then
        return value;
    end
    local result = {};
    for key,item in pairs(value) do
        result[key] = copy(item);
    end
    return result;
end

local function unknownOutcome(kind)
    return {
        type = kind,
        status = "unknown",
        drivers = {},
        notes = "No reviewed Horizon mechanics row is available.",
    };
end

local function normalize(row)
    if type(row) ~= "table"
        or type(row.action_id) ~= "number"
        or row.action_id < 1
        or row.action_id ~= math.floor(row.action_id) then
        return nil, "invalid_action_id";
    end
    if not allowedVerification[row.verification]
        or not allowedConfidence[row.confidence]
        or type(row.source_ids) ~= "table"
        or #row.source_ids == 0
        or type(row.last_verified) ~= "string"
        or row.last_verified == "" then
        return nil, "invalid_provenance";
    end
    if type(row.outcomes) ~= "table" or #row.outcomes ~= #outcomeOrder then
        return nil, "incomplete_outcomes";
    end
    local byType = {};
    for _,outcome in ipairs(row.outcomes or {}) do
        if type(outcome) ~= "table"
            or not allowedOutcome[outcome.type]
            or not allowedStatus[outcome.status] then
            return nil, "invalid_outcome";
        end
        if byType[outcome.type] ~= nil
            or type(outcome.drivers) ~= "table"
            or type(outcome.notes) ~= "string"
            or outcome.notes == "" then
            return nil, "invalid_outcome";
        end
        if (outcome.status == "unknown" or outcome.status == "not_applicable")
            and #outcome.drivers > 0 then
            return nil, "unsupported_driver_assertion";
        end
        if outcome.status == "verified_numeric" then
            if row.verification ~= "Verified"
                or not validFormula(outcome.formula) then
                return nil, "unverified_numeric_formula";
            end
        elseif outcome.formula ~= nil then
            return nil, "unverified_numeric_formula";
        end
        for _,driver in ipairs(outcome.drivers) do
            if type(driver) ~= "table"
                or not allowedDriverKind[driver.kind]
                or type(driver.key) ~= "string"
                or driver.key == ""
                or type(driver.role) ~= "string"
                or driver.role == ""
                or driver.coefficient ~= nil
                or driver.multiplier ~= nil
                or driver.value ~= nil
                or driver.weight ~= nil then
                return nil, "invalid_driver";
            end
        end
        byType[outcome.type] = copy(outcome);
    end
    local result = copy(row);
    result.outcomes = {};
    result.by_type = {};
    for _,kind in ipairs(outcomeOrder) do
        local outcome = byType[kind] or unknownOutcome(kind);
        table.insert(result.outcomes, outcome);
        result.by_type[kind] = outcome;
    end
    return result;
end

function actionMechanics.new(data, diagnostics)
    data = type(data) == "table" and data or {};
    local instance = setmetatable({
        diagnostics = diagnostics,
        schema_version = data.schema_version or 0,
        data_version = data.data_version or 0,
        server_scope = data.server_scope,
        by_action = {},
        rejected = {},
    }, actionMechanics);
    local contract = data.formula_contract;
    if data.schema_version ~= 2
        or type(data.data_version) ~= "number"
        or data.data_version < 1
        or data.server_scope ~= "HorizonXI"
        or type(contract) ~= "table"
        or contract.schema_version ~= 1
        or contract.representation ~= "typed_expression_tree"
        or contract.unknown_policy ~= "omit_not_zero"
        or contract.execution_policy ~= "report_only" then
        table.insert(instance.rejected, {
            action_id = nil,
            reason = "invalid_registry_header",
        });
        if diagnostics ~= nil then
            diagnostics:add("action_mechanics", "rejected invalid_registry_header");
        end
        return instance;
    end
    for _,row in ipairs(data.mechanics or {}) do
        local normalized,reason = normalize(row);
        if normalized == nil or instance.by_action[normalized.action_id] ~= nil then
            table.insert(instance.rejected, {
                action_id = row and row.action_id or nil,
                reason = normalized == nil and reason or "duplicate_action_id",
            });
            if diagnostics ~= nil then
                diagnostics:add("action_mechanics", "rejected " .. tostring(
                    normalized == nil and reason or "duplicate_action_id"
                ));
            end
        else
            instance.by_action[normalized.action_id] = normalized;
        end
    end
    return instance;
end

function actionMechanics:resolve(actionId)
    local row = self.by_action[actionId];
    if row == nil then
        local outcomes = {};
        local byType = {};
        for _,kind in ipairs(outcomeOrder) do
            local outcome = unknownOutcome(kind);
            table.insert(outcomes, outcome);
            byType[kind] = outcome;
        end
        return {
            known = false,
            action_id = actionId,
            verification = "Pending",
            confidence = "unknown",
            outcomes = outcomes,
            by_type = byType,
            data_version = self.data_version,
        };
    end
    local result = copy(row);
    result.known = true;
    result.data_version = self.data_version;
    return result;
end

function actionMechanics:annotate(action)
    action.mechanics = self:resolve(action.action_id);
    action.mechanics_version = self.data_version;
    return action;
end

function actionMechanics:count()
    local count = 0;
    for _,_ in pairs(self.by_action) do
        count = count + 1;
    end
    return count;
end

return actionMechanics;
