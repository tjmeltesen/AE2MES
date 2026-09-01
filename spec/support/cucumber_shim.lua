local shim = {
    steps = {},
    before = {},
}

local unpack = unpack or table.unpack

function shim.Before(fn)
    table.insert(shim.before, fn)
end

function shim.Given(pattern, fn)
    table.insert(shim.steps, { pattern = pattern, fn = fn })
end

shim.When = shim.Given
shim.Then = shim.Given

function shim.run_before()
    for _, fn in ipairs(shim.before) do
        fn()
    end
end

function shim.step(text)
    for _, entry in ipairs(shim.steps) do
        local anchored = "^" .. entry.pattern .. "$"
        if string.match(text, anchored) then
            local captures = { string.match(text, anchored) }
            if captures[1] == nil then
                entry.fn()
            else
                entry.fn(unpack(captures))
            end
            return
        end
    end
    error("no step definition for: " .. text)
end

return shim
