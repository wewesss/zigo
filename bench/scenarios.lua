return function(z, b)
    local core = assert(loadfile("bench/core.lua"))()
    core(z, b)
    local union = assert(loadfile("bench/union.lua"))()
    union(z, b)
end
