# CC-T-CBC-FireContorl
使用CC:T CC:VS 控制学等 和别人边玩边写的火控 还加了一些简单的预判

`n`为发射药药量 * 2
`k`从炮口到炮台上方的长度（包含两端）
`player_name`射线检测时，从哪个玩家那射出射线
`cannon_world_offset`为火炮相对于物理结构重心的偏移量
`channel`伺服电机和关节电机所在的频道
`control_yaw_motor_name`控制偏航的伺服电机的外设接口的名
`control_pitch_motor_name`控制俯仰的关节电机的外设接口的名
`target_player_name`要射击的目标名（可以是玩家也可以是瓦尔基里实体）
`target_velocity_scale`对速度向量的缩放
`target_is_ship`如果目标是瓦尔基里实体，将此改为true
`offset_x`,`offset_y`,`offset_z`对目标点坐标的偏移量
`offset_pitch`,`offset_yaw`如果炮管的方向反了，就调这个偏移量，单位度

---
参考资料
<https://www.bilibili.com/video/BV1QUWre9Ex1/?share_source=copy_web&vd_source=39c04f8819e2d629ad53de88a4bb5cd4>
<https://www.mcmod.cn/post/2983.html>
<https://www.mcmod.cn/class/13226.html>
<https://github.com/KallenKas024/Metaphysics/wiki>
<https://github.com/Rew1nd-dev/Control-Craft/tree/1.20.1-vs-2.3.0-beta5/doc/cc-peripherals>
