local world = {
    componentCache = nil,
    executor = nil,
    hardware = nil,
    assignment = nil,
    assignments = nil,
    jobPool = nil,
    nodeSensor = nil,
    runtime = nil,
    lastResult = nil,
    lastPhase = nil,
    lastValue = nil,
    lastTable = nil,
    lastError = nil,
    tickCount = 0,
}

function world.reset()
    world.componentCache = nil
    world.executor = nil
    world.hardware = nil
    world.assignment = nil
    world.assignments = nil
    world.jobPool = nil
    world.nodeSensor = nil
    world.runtime = nil
    world.lastResult = nil
    world.lastPhase = nil
    world.lastValue = nil
    world.lastTable = nil
    world.lastError = nil
    world.tickCount = 0
end

return world
