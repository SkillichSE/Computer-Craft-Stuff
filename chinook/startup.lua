local bridge = peripheral.find("redstone_link_bridge")
if not bridge then
    error("redstone_link_bridge not found")
end

local JOY_FWD_F1,   JOY_FWD_F2   = "offroad:wheel_mount", "rocketnautics:thruster_mount"
local JOY_BACK_F1,  JOY_BACK_F2  = "rocketnautics:thruster_mount", "offroad:wheel_mount"
local JOY_LEFT_F1,  JOY_LEFT_F2  = "copycats:copycat_board", "copycats:copycat_layer"
local JOY_RIGHT_F1, JOY_RIGHT_F2 = "copycats:copycat_layer", "copycats:copycat_board"
local YAW_LEFT_F1,  YAW_LEFT_F2  = "offroad:wheel_mount", "offroad:wheel_mount"
local YAW_RIGHT_F1, YAW_RIGHT_F2 = "rocketnautics:thruster_mount", "rocketnautics:thruster_mount"

local ROTORS = {
    front = {
        pitchFwd  = { "create:light_gray_postbox", "create:light_gray_postbox" },
        pitchBack = { "minecraft:cyan_wool", "minecraft:cyan_wool" },
        rollLeft  = { "create:light_gray_postbox", "minecraft:cyan_wool" },
        rollRight = { "minecraft:cyan_wool", "create:light_gray_postbox" },
    },
    rear = {
        pitchFwd  = { "rocketnautics:space_helmet", "rocketnautics:space_helmet" },
        pitchBack = { "rocketnautics:sputnik", "rocketnautics:sputnik" },
        rollLeft  = { "rocketnautics:space_helmet", "rocketnautics:sputnik" },
        rollRight = { "rocketnautics:sputnik", "rocketnautics:space_helmet" },
    },
}

local LEVEL_KP = 3.0
local MAX_TILT = 15
local MAX_YAW_TILT = 8

local function readLink(f1, f2)
    local ok, v = pcall(bridge.getLinkSignal, f1, f2)
    if not ok or not v then return 0 end
    return v
end

local function readJoystick()
    local fwd, back, left, right, yl, yr = 0, 0, 0, 0, 0, 0

    parallel.waitForAll(
        function() fwd   = readLink(JOY_FWD_F1, JOY_FWD_F2) end,
        function() back  = readLink(JOY_BACK_F1, JOY_BACK_F2) end,
        function() left  = readLink(JOY_LEFT_F1, JOY_LEFT_F2) end,
        function() right = readLink(JOY_RIGHT_F1, JOY_RIGHT_F2) end,
        function() yl    = readLink(YAW_LEFT_F1, YAW_LEFT_F2) end,
        function() yr    = readLink(YAW_RIGHT_F1, YAW_RIGHT_F2) end
    )

    local joyX = (right - left) / 15
    local joyY = (fwd - back) / 15
    local yawCmd = ((yr - yl) / 15) * MAX_YAW_TILT

    return joyX, joyY, yawCmd
end

local function queueAxis(tasks, negLink, posLink, value)
    local v = value
    if v > MAX_TILT then v = MAX_TILT end
    if v < -MAX_TILT then v = -MAX_TILT end

    local negOut, posOut = 0, 0
    if v >= 0 then
        posOut = math.floor(v + 0.5)
    else
        negOut = math.floor(-v + 0.5)
    end

    table.insert(tasks, function() pcall(bridge.sendLinkSignal, negLink[1], negLink[2], negOut) end)
    table.insert(tasks, function() pcall(bridge.sendLinkSignal, posLink[1], posLink[2], posOut) end)
end

local function flush(tasks)
    if #tasks > 0 then
        parallel.waitForAll(table.unpack(tasks))
    end
end

local function zeroRotors()
    local tasks = {}
    for _, r in pairs(ROTORS) do
        table.insert(tasks, function() pcall(bridge.sendLinkSignal, r.pitchFwd[1], r.pitchFwd[2], 0) end)
        table.insert(tasks, function() pcall(bridge.sendLinkSignal, r.pitchBack[1], r.pitchBack[2], 0) end)
        table.insert(tasks, function() pcall(bridge.sendLinkSignal, r.rollLeft[1], r.rollLeft[2], 0) end)
        table.insert(tasks, function() pcall(bridge.sendLinkSignal, r.rollRight[1], r.rollRight[2], 0) end)
    end
    flush(tasks)
end

local function updateAttitude(pitch, roll)
    local joyX, joyY, yawCmd = readJoystick()

    local pitchCmd = joyY * MAX_TILT - pitch * LEVEL_KP
    local rollCmd  = joyX * MAX_TILT - roll  * LEVEL_KP

    local tasks = {}
    queueAxis(tasks, ROTORS.front.pitchBack, ROTORS.front.pitchFwd, pitchCmd)
    queueAxis(tasks, ROTORS.front.rollLeft,  ROTORS.front.rollRight, rollCmd + yawCmd)
    queueAxis(tasks, ROTORS.rear.pitchBack, ROTORS.rear.pitchFwd, pitchCmd)
    queueAxis(tasks, ROTORS.rear.rollLeft,  ROTORS.rear.rollRight, rollCmd - yawCmd)
    flush(tasks)
end

while true do
    local onShip = sublevel ~= nil and sublevel.isInPlotGrid and sublevel.isInPlotGrid()

    if onShip then
        local ok, pose = pcall(sublevel.getLogicalPose)
        if ok and pose and pose.orientation and pose.orientation.toEuler then
            local pitch, yaw, roll = pose.orientation:toEuler()
            updateAttitude(pitch, roll)
        else
            zeroRotors()
        end
    else
        zeroRotors()
    end

    sleep(0.05)
end