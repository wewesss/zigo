local M = {}

local Error = {}
Error.__index = Error

local function fmtValue(x)
    local t = type(x)
    if t == "string" then return '"' .. x .. '"' end
    if t == "table" then
        local parts = {}
        for i = 1, #x do parts[i] = fmtValue(x[i]) end
        return table.concat(parts, ", ")
    end
    return tostring(x)
end

local function subject(issue)
    if issue.type == "number" or issue.type == "integer" then return "value" end
    return "length"
end

M.messages = {
    invalid_type = function(i)
        return "Expected " .. tostring(i.expected) .. ", got " .. tostring(i.got)
    end,
    too_small = function(i)
        if i.exact then
            return "Expected " .. subject(i) .. " of exactly " .. tostring(i.expected) .. ", got " .. tostring(i.got)
        end
        return "Expected " .. subject(i) .. " of at least " .. tostring(i.expected) .. ", got " .. tostring(i.got)
    end,
    too_big = function(i)
        if i.exact then
            return "Expected " .. subject(i) .. " of exactly " .. tostring(i.expected) .. ", got " .. tostring(i.got)
        end
        return "Expected " .. subject(i) .. " of at most " .. tostring(i.expected) .. ", got " .. tostring(i.got)
    end,
    invalid_literal = function(i)
        return "Expected " .. fmtValue(i.expected) .. ", got " .. fmtValue(i.got)
    end,
    invalid_enum = function(i)
        return "Expected one of: " .. fmtValue(i.expected) .. ", got " .. fmtValue(i.got)
    end,
    invalid_array = function()
        return "Expected a sequence without holes or extra keys"
    end,
    unrecognized_key = function(i)
        if i.got then return "Unrecognized key of type " .. tostring(i.got) end
        return "Unrecognized key"
    end,
    invalid_union = function()
        return "Input matches none of the union variants"
    end,
    invalid_union_discriminator = function(i)
        return "Expected discriminator one of: " .. fmtValue(i.expected) .. ", got " .. fmtValue(i.got)
    end,
    too_deep = function(i)
        return "Nesting deeper than " .. tostring(i.expected) .. " levels"
    end,
    too_many_keys = function(i)
        return "Expected at most " .. tostring(i.expected) .. " keys"
    end,
    custom = function()
        return "Invalid input"
    end,
}

function M.setMessages(tbl)
    for code, handler in pairs(tbl) do
        M.messages[code] = handler
    end
end

local function render(handler, issue)
    if type(handler) == "function" then return handler(issue) end
    return (handler:gsub("{(%w+)}", function(field)
        local x = issue[field]
        if x == nil then return "" end
        if type(x) == "table" then return fmtValue(x) end
        return tostring(x)
    end))
end

function M.messageOf(issue, override)
    if issue.message ~= nil then return issue.message end
    local handler = override and override[issue.code] or M.messages[issue.code]
    if handler == nil then return issue.code end
    return render(handler, issue)
end

local function joinPath(path)
    local s = ""
    for i = 1, #path do
        local p = path[i]
        if type(p) == "string" then
            s = s .. (i > 1 and "." or "") .. p
        else
            s = s .. "[" .. tostring(p) .. "]"
        end
    end
    return s
end

M.pathToString = joinPath

function M.new(issues)
    return setmetatable({ issues = issues or {} }, Error)
end

function M.isError(x)
    return getmetatable(x) == Error
end

function Error:format(override)
    local lines = {}
    local issues = self.issues
    for i = 1, #issues do
        local issue = issues[i]
        local where = joinPath(issue.path)
        if where == "" then where = "<root>" end
        lines[i] = where .. ": " .. M.messageOf(issue, override)
    end
    return table.concat(lines, "\n")
end

function Error:flatten(override)
    local formErrors, fieldErrors = {}, {}
    local issues = self.issues
    for i = 1, #issues do
        local issue = issues[i]
        local msg = M.messageOf(issue, override)
        local where = joinPath(issue.path)
        if where == "" then
            formErrors[#formErrors + 1] = msg
        else
            local list = fieldErrors[where]
            if not list then
                list = {}
                fieldErrors[where] = list
            end
            list[#list + 1] = msg
        end
    end
    return { formErrors = formErrors, fieldErrors = fieldErrors }
end

Error.__tostring = function(self)
    return "ZigoError: " .. #self.issues .. " issue(s)\n" .. self:format()
end

return M
