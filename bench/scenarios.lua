return function(z, b)
    local union = assert(loadfile("bench/union.lua"))()
    union(z, b)
end
