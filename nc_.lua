transmitter = peripheral.find("transmitter")
local monitor = peripheral.find("monitor")

monitor.setTextScale(0.5)

transmitter.setProtocol(channel)


-- n: 火炮装药量 * 2，初始速度 = n * 20，k: 火炮炮口到炮尾的长度
local n = 8
local k = 6

-- 玩家名和火炮世界坐标偏移量
local player_name = "Condou"
local cannon_world_offset = { x = 0, y = 2, z = 0 }

-- 频道，用于控制偏航的外设接口名和控制俯仰的外设接口名
local channel = 0
local control_yaw_motor_name = "yaw"
local control_pitch_motor_name = "pitch"

local setTargetValue_func_name = "setTargetValue"

local target_player_name = "LV114"

local target_velocity_scale = 1.2

local target_is_ship = false -- 目标是否为瓦尔基里物理结构

local offset_x = 0
local offset_y = 0
local offset_z = 0

local offset_pitch = -90
local offset_yaw = 0


local mode_1 = "ray"
local mode_2 = "target"
-- 模式
local mode = mode_1

local screen_w, screen_h = monitor.getSize()



-- 默认滚动条
local default_scroll_bar = {
    begin_y = 1,
    end_y = -1,

    current_line = 1,
    max_lines = -1,
}




-- ========= 四元数 =========
-- 四元数 a * b
local function quat_mul(a, b)
    return {
        w = a.w*b.w - a.x*b.x - a.y*b.y - a.z*b.z,
        x = a.w*b.x + a.x*b.w + a.y*b.z - a.z*b.y,
        y = a.w*b.y - a.x*b.z + a.y*b.w + a.z*b.x,
        z = a.w*b.z + a.x*b.y - a.y*b.x + a.z*b.w
    }
end

-- 四元数取逆
local function quat_inv(q)
    local norm = q.w*q.w + q.x*q.x + q.y*q.y + q.z*q.z
    return {
        w =  q.w / norm,
        x = -q.x / norm,
        y = -q.y / norm,
        z = -q.z / norm
    }
end

-- 计算 res = q * (0 + v) * q^{-1}
local function quat_rotate(q, v)
    local qv = { w = 0, x = v.x, y = v.y, z = v.z }
    local q_inv = quat_inv(q)
    local tmp = quat_mul(q, qv)
    local res = quat_mul(tmp, q_inv)
    return { x = res.x, y = res.y, z = res.z }
end

-- 将角度规范到 (-180, 180]
local function normalizeAngleDeg(a)
    a = a % 360
    if a > 180 then a = a - 360 end
    return a
end

local function toAngle(rad)
    return math.deg(rad)
end

local function toRad(deg)
    return math.rad(deg)
end




-- metaphysic API（获取玩家视点并 raycast）
-- 从 coordinate.getEntities(-1) 里找到玩家位置和 raw_euler（视线方向）
function getPlayerPosRot(name)
    local player_data = nil
    if target_is_ship and mode == mode_2 then
        player_data = coordinate.getShipsAll(512)
    else
        player_data = coordinate.getEntitiesAll(-1)
    end
    if player_data ~= nil then
        for key, value in pairs(player_data) do

            local _name = nil
            if target_is_ship and mode == mode_2 then
                _name = value.slug
            else
                _name = value.name
            end

            if _name == name then
                return { x = value.x, y = value.y, z = value.z },
                       { x = value.raw_euler_x, y = value.raw_euler_y, z = value.raw_euler_z }
            end
        end
    end
    return { x = 0, y = 0, z = 0 }, { x = 0, y = 0, z = 0 }
end

function getPlayerPos(name)
    local player_pos, _ = getPlayerPosRot(name)
    return player_pos.x, player_pos.y, player_pos.z
end


local rayScale = 1.0
local rayDistance = 256

-- 简单射线投射：沿玩家视线每次加一，直到碰到非空气方块或达到最大步数
function rayCast(name)
    local player_pos, player_rot = getPlayerPosRot(name)
    -- 把起始点抬一点（玩家眼睛高度等）
    for i = 1, rayDistance, 1 do
        player_pos.x = player_pos.x + (player_rot.x * rayScale)
        player_pos.y = player_pos.y + (player_rot.y * rayScale)
        player_pos.z = player_pos.z + (player_rot.z * rayScale)

        local block = coordinate.getBlock(player_pos.x, player_pos.y + 1, player_pos.z)
        if (block ~= "minecraft:air" and block ~= "minecraft:cave_air" and block ~= "minecraft:void_air") or i == 319 then
            return player_pos.x, player_pos.y + 1, player_pos.z
        end
    end

    return player_pos.x, player_pos.y, player_pos.z
end





-- 计算俯仰角
local function solvePitchForDistance(w, dy)
    -- w 是水平距离，dy 是目标 y 相对火炮（在船坐标里）
    local cannonPitch = nil
    local error_pitch = 0.2
    repeat
        for i = 60, -30, -0.1 do
            local seci = 1 / math.cos(math.rad(i))
            local tani = math.tan(math.rad(i))
            local y_ccl = (5 * seci / n + tani) * w + 500 * math.log(1 - (w * seci - k) / (100 * n)) - 5 * k / n

            if math.abs(y_ccl - dy) < error_pitch and error_pitch < 2 then
                cannonPitch = i
                break
            elseif error_pitch >= 2 then
                cannonPitch = "no solution"
                break
            end
        end
        error_pitch = error_pitch + 0.2
    until cannonPitch ~= nil

    -- 默认炮口朝前，俯仰角为 0
    return cannonPitch
end


local function getTargetGeometry(target_x, target_y, target_z)
    local ship_pos = ship.getWorldspacePosition()
    local cannon_pos = {
        x = ship_pos.x + cannon_world_offset.x,
        y = ship_pos.y + cannon_world_offset.y,
        z = ship_pos.z + cannon_world_offset.z
    }

    local delta_world = {
        x = target_x - cannon_pos.x,
        y = target_y - cannon_pos.y,
        z = target_z - cannon_pos.z
    }

    local shipQuat = ship.getQuaternion()
    if shipQuat.w == nil and shipQuat[4] ~= nil then
        shipQuat.w = shipQuat[4]
    end

    local delta_ship = quat_rotate(quat_inv(shipQuat), delta_world)

    local w  = math.sqrt(delta_ship.x^2 + delta_ship.z^2)
    local dy = delta_ship.y

    return delta_ship, w, dy
end


local function cannonAiming(target_x, target_y, target_z)
    local needed_angle = { yaw = 0, pitch = 0 }


    -- 计算根据物理结构姿态将目标点转换后的坐标，距离，高度差
    local delta_ship, w, dy = getTargetGeometry(target_x, target_y, target_z)

    -- 求俯仰角（degree）
    local cannonPitch = solvePitchForDistance(w, dy)

    if cannonPitch ~= nil and cannonPitch ~= "no solution" then
        needed_angle.pitch = cannonPitch
    end


    -- 计算偏航角（degree）

    local cannonYaw = math.deg(math.atan2(delta_ship.z, delta_ship.x)) + 180 -- [-180,180]

    local cannonYaw = normalizeAngleDeg(cannonYaw)

    needed_angle.yaw = cannonYaw

    

    return needed_angle
end



local last_target_x = 0
local last_target_y = 0
local last_target_z = 0

-- 计算目标速度
local function getTargetVelocity(player_name, delta_time, scale)
    local target_pos_x, target_pos_y, target_pos_z = getPlayerPos(player_name)
    if delta_time == 0 then
        return 0, 0, 0
    end

    if target_pos_x == last_target_x and target_pos_y == last_target_y and target_pos_z == last_target_z then
        return 0, 0, 0
    end

    local velocity = {
        x = (target_pos_x - last_target_x) / delta_time * scale,
        y = (target_pos_y - last_target_y) / delta_time * scale,
        z = (target_pos_z - last_target_z) / delta_time * scale
    }

    last_target_x = target_pos_x
    last_target_y = target_pos_y
    last_target_z = target_pos_z

    return velocity.x, velocity.y, velocity.z
end

local last_current_ship_x = 0
local last_current_ship_y = 0
local last_current_ship_z = 0

-- 计算当前物理结构的速度
local function getCurrentShipVelocity(delta_time)
    local ship_pos = ship.getWorldspacePosition()
    if delta_time == 0 then
        return 0, 0, 0
    end

    if ship_pos.x == last_current_ship_x and ship_pos.y == last_current_ship_y and ship_pos.z == last_current_ship_z then
        return 0, 0, 0
    end

    local velocity = {
        x = (ship_pos.x - last_current_ship_x) / delta_time,
        y = (ship_pos.y - last_current_ship_y) / delta_time,
        z = (ship_pos.z - last_current_ship_z) / delta_time
    }


    last_current_ship_x = ship_pos.x
    last_current_ship_y = ship_pos.y
    last_current_ship_z = ship_pos.z

    return velocity.x, velocity.y, velocity.z
end



-- 计算飞行时间
local function estimateFlightTime(w, pitch)
    if pitch == nil or pitch == "no solution" then
        return 0
    end

    if w <= 50 then
    
        local pitch_rad = math.rad(pitch)
        local v_h = (n * 14) * math.cos(pitch_rad)

        if v_h < 0.1 then return 0 end
        return w / v_h
    end


    local theta = math.rad(pitch)
    local sec = 1 / math.cos(theta)

    local x = (w * sec - k) / (100 * n)

    if x >= 1 then
        return nil
    end

    return -5 * math.log(1 - x)
    
end




local function padStr(str, length)
    if length == -1 then
        length = screen_w - 1
    end
    if string.len(str) < length then
        return str .. string.rep(" ", length - string.len(str))
    else
        return string.sub(str, 1, length)
    end
end

-- 清空屏幕
local function clearScreen()
    local old_bg_color = monitor.getTextColor()

    monitor.setBackgroundColor(colors.black)
    monitor.clear()
    
    monitor.setBackgroundColor(old_bg_color)
end



-- 获取点击事件
local function onClickEvent()
    local event, side, x, y = os.pullEvent("monitor_touch")
    return x, y
end

-- 绘制文本
local function drawText(text, x, y, color, scroll_bar)

    local current_line = 0
    if (scroll_bar ~= nil) then
        current_line = scroll_bar.current_line - 1
    end

    local old_color = monitor.getTextColor()

    local dy = y - current_line
    if dy >= 1 and dy <= screen_h then
        monitor.setTextColor(color)
        monitor.setCursorPos(x, y - current_line)
        monitor.write(text)
    end

    monitor.setTextColor(old_color)
end

-- 绘制矩形
local function drawRect(x, y, w, h, color, scroll_bar)

    local current_line = 0
    if (scroll_bar ~= nil) then
        current_line = scroll_bar.current_line - 1
    end

    local old_color = monitor.getBackgroundColor()

    monitor.setBackgroundColor(color)
    
    for i = 1, h do
        local dy = y + i - 1 - current_line
        if dy >= 1 and dy <= screen_h then
            monitor.setCursorPos(x, dy)
            monitor.write(string.rep(" ", w))
        end
    end

    monitor.setBackgroundColor(old_color)
end


-- 按钮列表
local button_list = {}


-- 添加按钮
local function addButton(text, x, y, w, h, color, bg_color, id)
    button_list[#button_list + 1] =
    {
        text = text,
        x = x,
        y = y,
        w = w,
        h = h,
        color = color,
        bg_color = bg_color,
        id = id
    }
end

-- 绘制按钮
local function drawButton(scroll_bar)
    local current_line = 0
    if (scroll_bar ~= nil) then
        current_line = scroll_bar.current_line - 1
    end

    local old_bg_color = monitor.getBackgroundColor()
    local old_color = monitor.getTextColor()

    for i, button in ipairs(button_list) do
        monitor.setBackgroundColor(button.bg_color)
        monitor.setTextColor(button.color)
        drawRect(button.x, button.y - current_line, button.w, button.h, button.bg_color)
        drawText(button.text, button.x, button.y - current_line, button.color)
    end

    monitor.setBackgroundColor(old_bg_color)
    monitor.setTextColor(old_color)
end

-- 设置按钮颜色
local function setButtonColor(id, color)
    for i, button in ipairs(button_list) do
        if button.id == id then
            button.color = color
        end
    end
end
-- 设置按钮背景颜色
local function setButtonBgColor(id, bg_color)
    for i, button in ipairs(button_list) do
        if button.id == id then
            button.bg_color = bg_color
        end
    end
end
-- 设置按钮文本
local function setButtonText(id, text)
    for i, button in ipairs(button_list) do
        if button.id == id then
            button.text = text
        end
    end
end

-- 按钮事件处理
local function buttonClicked(id, x, y)
    if id == 1 then
        mode = mode_1
        setButtonBgColor(1, colors.green)
        setButtonBgColor(2, colors.black)
    elseif id == 2 then
        mode = mode_2
        setButtonBgColor(1, colors.black)
        setButtonBgColor(2, colors.green)
    elseif id == 3 then
        if target_velocity_scale > 0.05 then
            target_velocity_scale = target_velocity_scale - 0.05
        end
    elseif id == 4 then
        if target_velocity_scale < 2 then
            target_velocity_scale = target_velocity_scale + 0.05
        end
    elseif id == 5 then
        if rayScale > 0.05 then
            rayScale = rayScale - 0.05
        end
    elseif id == 6 then
        if rayScale < 10 then
            rayScale = rayScale + 0.05
        end
    elseif id == 7 then
        if rayDistance > 1 then
            rayDistance = rayDistance - 1
        end
    elseif id == 8 then
        if rayDistance < 1000 then
            rayDistance = rayDistance + 1
        end
    end
end


-- 检查按钮是否被点击
local function checkButton(x, y, scroll_bar)
    local current_line = 0
    if (scroll_bar ~= nil) then
        current_line = scroll_bar.current_line - 1
    end
    for i, button in ipairs(button_list) do
        if x >= button.x and x <= button.x + button.w and y >= button.y - current_line and y <= button.y + button.h - current_line then

            buttonClicked(button.id, x, y - current_line)

            return button.id
        end
    end
end

-- 绘制滚动条
local function drawScrollBar(scroll_bar)
    local old_color = monitor.getTextColor()
    local old_bg_color = monitor.getBackgroundColor()

    if scroll_bar.end_y == -1 then
        scroll_bar.end_y = screen_h
    end

    monitor.setBackgroundColor(colors.gray)
    for i = scroll_bar.begin_y, scroll_bar.end_y, 1 do
        monitor.setCursorPos(screen_w, i)
        monitor.write(" ")
    end

    monitor.setBackgroundColor(colors.lightBlue)

    if scroll_bar.max_lines > screen_h then
        local content_y = math.floor((scroll_bar.current_line - 1) / (scroll_bar.max_lines) * (scroll_bar.end_y - scroll_bar.begin_y)) + 1 + scroll_bar.begin_y
        monitor.setCursorPos(screen_w, content_y)
        monitor.write(" ")
    end

    monitor.setBackgroundColor(colors.lightGray)
    monitor.setTextColor(colors.black)

    drawText("^", screen_w, scroll_bar.begin_y, colors.black)
    drawText("v", screen_w, scroll_bar.end_y, colors.black)

    monitor.setTextColor(old_color)
    monitor.setBackgroundColor(old_bg_color)
        
end

-- 检查滚动条是否被点击
local function checkScrollBar(x, y, scroll_bar)
    local end_y = scroll_bar.end_y
    if scroll_bar.end_y == -1 then
        end_y = screen_h
    end

    if (x == screen_w and y == scroll_bar.begin_y and scroll_bar.current_line > 1) then
        scroll_bar.current_line = scroll_bar.current_line - 1
        clearScreen()
    elseif (x == screen_w and y == end_y and scroll_bar.current_line < scroll_bar.max_lines) then
        scroll_bar.current_line = scroll_bar.current_line + 1
        clearScreen()
    end

end





local target_x = 0
local target_y = 0
local target_z = 0




addButton("Ray", 7, 1, 3, 1, colors.white, colors.green, 1, default_scroll_bar)
addButton("Tar", 11, 1, 3, 1, colors.white, colors.black, 2, default_scroll_bar)

-- 速度缩放调节按钮
addButton("-", 2, 11, 1, 1, colors.black, colors.red, 3, default_scroll_bar)
addButton("+", 7, 11, 1, 1, colors.black, colors.blue, 4, default_scroll_bar)

-- 射线缩放调节按钮
addButton("-", 2, 13, 1, 1, colors.black, colors.red, 5, default_scroll_bar)
addButton("+", 7, 13, 1, 1, colors.black, colors.blue, 6, default_scroll_bar)

-- 射线距离调节按钮
addButton("-", 2, 15, 1, 1, colors.black, colors.red, 7, default_scroll_bar)
addButton("+", 9, 15, 1, 1, colors.black, colors.blue, 8, default_scroll_bar)

default_scroll_bar.max_lines = 16



local function handleTouch()
    while true do
        -- clearScreen()
        local x, y = onClickEvent()
        checkButton(x, y, default_scroll_bar)
        checkScrollBar(x, y, default_scroll_bar)
    end
end

local last_tick = os.clock()
local function main()
    while true do
        

        local rayCast_func_time_spend = 0
        local cannonAiming_time_spend = 0

        if mode == mode_1 then

            local rayCast_start_time = os.clock()
            target_x, target_y, target_z = rayCast(player_name)
            rayCast_func_time_spend = os.clock() - rayCast_start_time
        else
            local getPlayerPos_start_time = os.clock() -- 记录开始时间
            target_x, target_y, target_z = getPlayerPos(target_player_name) -- 获取目标点坐标
            rayCast_func_time_spend = os.clock() - getPlayerPos_start_time

            target_x = target_x + offset_x
            target_y = target_y + offset_y
            target_z = target_z + offset_z

            local delta_ship, w, dy = getTargetGeometry(target_x, target_y, target_z) -- 计算目标点在船坐标系下的坐标
            local pitch0 = solvePitchForDistance(w, dy)

            local t = estimateFlightTime(w, pitch0) -- 计算飞行时间

            
            local tVel_x, tVel_y, tVel_z = getTargetVelocity(target_player_name, os.clock() - last_tick, target_velocity_scale) -- 计算目标速度
            last_tick = os.clock()

            -- 计算目标点未来的坐标
            target_x = target_x + tVel_x * t
            target_y = target_y + tVel_y * t
            target_z = target_z + tVel_z * t
        end



        monitor.setBackgroundColor(colors.black)

        -- 模式
        drawText(padStr("Mode: ", -1), 1, 1, colors.white, default_scroll_bar)

        -- 目标点位置
        drawText(padStr("Target", -1), 1, 2, colors.white, default_scroll_bar)
        drawButton(default_scroll_bar)

        drawText(padStr("X: ".. target_x, -1), 1, 3, colors.red, default_scroll_bar)
        drawText(padStr("Y: ".. target_y, -1), 1, 4, colors.green, default_scroll_bar)
        drawText(padStr("Z: ".. target_z, -1), 1, 5, colors.blue, default_scroll_bar)




        local cannonAiming_start_time = os.clock()
        local needed_angle = cannonAiming(target_x, target_y, target_z) -- 计算需要的角度
        cannonAiming_time_spend = os.clock() - cannonAiming_start_time

        needed_angle.pitch = normalizeAngleDeg(needed_angle.pitch + offset_pitch) -- 修正俯仰角
        needed_angle.yaw = normalizeAngleDeg(needed_angle.yaw + offset_yaw) -- 修正偏航角






        drawText(padStr("Yaw: ".. needed_angle.yaw, -1), 1, 6, colors.white, default_scroll_bar)
        drawText(padStr("Pitch: ".. needed_angle.pitch, -1), 1, 7, colors.white, default_scroll_bar)

        -- 函数运行时间消耗
        drawText(padStr("RC/GP T: ".. rayCast_func_time_spend, -1), 1, 8, colors.purple, default_scroll_bar)
        drawText(padStr("CA T: ".. cannonAiming_time_spend, -1), 1, 9, colors.purple, default_scroll_bar)

        drawText(padStr("TarVelScale:", -1), 1, 10, colors.yellow, default_scroll_bar)
        drawText(string.format("%.2f", target_velocity_scale), 3, 11, colors.white, default_scroll_bar)

        drawText(padStr("RayScale:", -1), 1, 12, colors.yellow, default_scroll_bar)
        drawText(string.format("%.2f", rayScale), 3, 13, colors.white, default_scroll_bar)

        drawText(padStr("RayDis:", -1), 1, 14, colors.yellow, default_scroll_bar)
        drawText(string.format("%.2f", rayDistance), 3, 15, colors.white, default_scroll_bar)

        -- 显示滚动条
        drawScrollBar(default_scroll_bar)






        -- 控制电机
        transmitter.callRemote(control_yaw_motor_name, setTargetValue_func_name, toRad(needed_angle.yaw))
        transmitter.callRemote(control_pitch_motor_name, setTargetValue_func_name, toRad(needed_angle.pitch))

        os.sleep(0.0001)
    end
end





parallel.waitForAll(handleTouch, main)
