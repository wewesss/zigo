local type, error, setmetatable = type, error, setmetatable

local M = {}

local methods = {}
local meta = { __index = methods }

function methods.addIssue(self, t)
    if type(t) ~= "table" then
        error("zigo: addIssue() expects a table", 2)
    end
    local message, code, extra = t.message, t.code, t.path
    if message ~= nil and type(message) ~= "string" then
        error("zigo: addIssue() message must be a string", 2)
    end
    if code ~= nil and type(code) ~= "string" then
        error("zigo: addIssue() code must be a string", 2)
    end
    if extra ~= nil and type(extra) ~= "table" then
        error("zigo: addIssue() path must be a list", 2)
    end
    self.count = self.count + 1
    if not self.collect then return end
    local path, depth = self.path, self.depth
    local p = {}
    for i = 1, depth do p[i] = path[i] end
    if extra then
        for i = 1, #extra do p[depth + i] = extra[i] end
    end
    local issues = self.issues
    if not issues then
        issues = {}
        self.issues = issues
    end
    issues[#issues + 1] = { path = p, code = code or "custom", message = message }
end

function M.fast()
    return setmetatable({ collect = false, count = 0, depth = 0 }, meta)
end

function M.collect(path, issues)
    return setmetatable({ collect = true, count = 0, path = path, depth = 0, issues = issues }, meta)
end

return M
