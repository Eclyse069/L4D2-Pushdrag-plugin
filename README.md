L4D2-Pushdrag-plugin
This is L4D2 Grab plugin for Pushdrag Ultimate FIX, you can grab teammate and item or prop. add many function.
admin can grab special infected. and can be use grab in spectators mode.

这是抓取插件的终极修复版，能让玩家抓取队友与各种物品，新增多种功能。
管理员可以抓取特感，甚至能在旁观者模式使用抓取功能。

How to play:
Double click "R" = Grab; Hold +speed Double click "R" = Super Grab; click "R" agin drop.
Right-click = Throw; Hold +speed = Rocket launch.
Middle-click = Reset mode.
if someone grab you, you can press jump to break free.

spectators mode: E = Throw, F = Reset mode

按键：双击 R = 普通抓取（240）；按住 +speed 双击 R = 超远抓取（1000）；
持握中右键 = 投掷；持握中按住 +speed + 右键 = 大力投掷。
持握中单击 R = 放下；被抓玩家按空格 = 挣脱；按狙击瞄准键 = 回正模式。
旁观者（team 1）也可抓物件；生还者可抓敌方特感；均由cvar控制。

旁观者投掷是E，回正模式是F

Original author: Pan Xiaohai
https://forums.alliedmods.net/showthread.php?p=1325370

由Deepseek V4.1 Flash全全修改

# Push And Drag 更新日志

**当前版本：2.4.0**  
**适用游戏：** Left 4 Dead 1 / Left 4 Dead 2  
**编译环境：** SourceMod 1.12.0.7220（语法兼容 1.10–1.12）  
**运行依赖：** SDKHooks（v2.0 起不再需要 DHooks；v2.4 起硬直取消需要 `gamedata/l4_pushdrag.txt`，来自核心 SDKCall，不需要额外扩展）  
**文件：** `l4d_pushdrag_v24.sp`、`l4d_pushdrag_v24.smx`、`l4_pushdrag.txt`（gamedata）、`l4d_pushdrag.phrases.txt`、`l4d_pushdrag.cfg`

---

## 一、版本历史

### v2.4.0

- **旁观者回正键改为 F（手电筒）**：L4D2 客户端默认 `bind "f" "impulse 100"`，F 走 usercmd 的 impulse 字段，观测者模式下按键位可能被过滤、但 impulse 仍会发送。现在旁观者持握物件按 F 切换回正，聊天框有开关提示；Ctrl 作为第二键保留，`!pdlevel` 仍可兜底。抓取/回正逻辑抽成 `ToggleLevelMode()` 供三个入口共用。
- **硬直特感真正可抓**：新增 `gamedata/l4_pushdrag.txt`（签名来自 Left4DHooks v1.159 在用的 `CTerrorPlayer::CancelStagger`），用核心 `SDKCall` 在抓到客户端目标的瞬间调用引擎取消硬直；旧的“压制 stagger 字段 + 每帧强制位置”保留为兜底。签名缺失/失效时只写日志，不崩溃；可用 `l4d_pushdrag_cancel_stagger 0` 关闭。
- **被特感控制时禁止抓取**：新增 `l4d_pushdrag_block_when_controlled`（默认 1），检测 `m_pounceAttacker` / `m_tongueOwner` / `m_jockeyAttacker` / `m_pummelAttacker`；被 Hunter/Smoker/Jockey/Charger 控制时无法抓取，已持握的物件会被放下并提示 `ControlledBlocked`。
- **诊断增强**：新增 `!pddebug`（开关诊断，无需改 cfg/换图）、`!pdver`（版本 + CancelStagger 是否就绪 + 队伍/持握状态）；debug 会打印旁观者 `impulse` 与 `cancel stagger`、`grab blocked: controlled`。
- cvar 总数：**51**（新增 `block_when_controlled`、`cancel_stagger`）。

### v2.3.0

- **先解决“改了没反应”的排查问题**：插件启动时在服务端控制台/日志打印 `[Push And Drag] v2.3.0 loaded`；新增 `l4d_pushdrag_debug`（默认 0），打开后在聊天框/控制台打印旁观者按键位、回正切换、原点拖拽、投掷命中计数。**升级后请确认 `sm plugins list` 里只有一个 pushdrag**；旧版与新版本同时加载会让所有功能表现异常。
- **旁观者 Ctrl 回正**：按键来源改为 `原始 usercmd | 服务端按键` 双路合并；回正切换对旁观者**额外发聊天提示**（HintText 在旁观 HUD 下常常不显示，容易误判为没生效）；另提供 `!pdlevel` / `sm_pdlevel` 命令兜底（不依赖按键位）。
- **普通感染者投掷伤害**：投掷者从“仅生还者”放宽为“生还者或旁观者”（感染者自己扔的不加伤）；最低触发速度 400 → **200**，普通右键投掷也能触发；对普通感染者若 `DMG_CRUSH` 没造成实际掉血，自动用 `DMG_CLUB` 重试一次；debug 会打印 `si/common` 命中数。
- **硬直特感抓取**：回退检测从 1 秒缩短到 **0.2 秒**，并改为“有没有朝持握点靠近”判定；新增 `InterruptStagger()`，在抓取瞬间和原点拖拽每帧把 `m_staggerStart` 钉在当前原点、清零 `m_staggerDir` / `m_staggerDist`，压制硬直位移；原点拖拽每帧强制位置并清速度，硬直期间不再“空抓”。
- cvar 总数：**49**（新增诊断开关）。

### v2.2.0

- **Witch 可抓取**：Witch 没有 VPhysics，写速度会被她的 idle 逻辑每帧清零，所以之前只提示“抓住了某物”却纹丝不动。现在对 Witch 使用**原点拖拽**（每帧把她的原点朝持握点移动，并用玩家包围盒扫掠截断墙/地面，避免传进墙里），可以吸到面前、拖着走、扔出去；扔出改用**轻量模拟弹道**（重力 + 包围盒截断，速度上限 900）。
- **修复特感硬直/动画锁定时抓不起来**：硬直中的特感位置由 stagger 根运动驱动，同样无视速度写入。现在抓取后 1 秒若目标仍在持握半径 40 单位外，自动切换为原点拖拽，之后每 0.5 秒复查；正常玩家/队友 1 秒内已收敛，不会误切换。
- **投掷伤害对普通感染者生效**：`l4d_pushdrag_thrown_prop_damage_scale` 现在同时作用于 `infected`（普通感染者），伤害公式与特感一致，击杀计给投掷者；并且一次扫掠可命中多个目标（不再只打第一个）。
- **旁观者回正键改为 Ctrl**（`IN_DUCK`）：旁观者持握时按 Ctrl 切换回正模式，狙击瞄准键不再触发；其他玩家仍用狙击瞄准键（`IN_ZOOM`）。
- cvar 总数不变：**48**（无新增）。

### v2.1.0

- **旁观者投掷键改为 E**（`IN_USE`）：旁观时右键是切换观战，所以持握中按 E 投掷、按住 +speed + E 大力投掷；其他玩家仍是右键投掷。
- 新增**仅管理员**开关：`l4d_pushdrag_admin_only_far_grab`（超远抓取）、`l4d_pushdrag_admin_only_strong_throw`（大力投掷），默认 0。非管理员用远抓时降级为普通距离并提示“该功能仅管理员可用”，强投降级为普通投掷。
- **修复“物理击杀归属 cvar 不生效”**，原因有三：① 旧 cfg 里 `physics_attacker` 默认就是 0（功能根本没开）；② `attacker_time` 只有 1.5 秒，短于物件飞行时间；③ `AutoExecConfig` 不会覆盖已经存在的 cfg。现在：`physics_attacker` 默认 1、`attacker_time` 默认 5.0（引擎 `HasPhysicsAttacker` 判定窗口就是 5 秒）、额外写 `m_hLastAttacker`，并新增 **`OnTakeDamage` 归属兜底**——即使 `physics_attacker 0`，投掷物造成的击杀也会记到投掷者头上。
- **生还者投出的物件可以伤害感染者**：新增 `l4d_pushdrag_thrown_prop_damage_scale`（默认 0.05，0=关闭），伤害 = 物件速度 × 系数（上限 150）。用线段扫掠判定，避免高速物件穿过目标；每个物件 0.35 秒内只打一个目标，且引擎原生已经造成伤害时不会重复叠加。
- **生还者抓取投掷敌方特感时，该特感会吃摔伤**：新增 `l4d_pushdrag_thrown_si_fall_damage_scale`（默认 0.02，0=关闭），伤害 = 投掷力 × 系数（5–150）。团队 2 投出团队 3 时**不再给摔伤保护**；落地时若引擎没算摔伤，插件补一次 `DMG_FALL`（被过滤时用 `DMG_CLUB` 兜底）。
- `l4d_pushdrag_player_fall_protect` 默认值 3.0 → **0.3**（松手后基本立即恢复摔伤）。
- cvar 总数：**48**。

### v2.0.0

- **删除 v1.7 的 DHooks `PhysicsDamage` 补丁**：弹飞的真正原因是“投掷力残留在物件上”，v1.9 的投掷落地清理已经解决，旧补丁不再需要。
- 删除 `gamedata/l4d_pushdrag.txt`；插件不再依赖 DHooks。
- 摔伤保护从“3 秒开关”改为**秒数 cvar**：`l4d_pushdrag_player_fall_protect`，默认 3.0，0 = 关闭。
- 新增旁观者抓玩家/特感：`l4d_pushdrag_spectator_grab_players`（默认 1）。
- 翻译补**繁体中文 `zho`**，并新增回正模式提示 `LevelModeOn` / `LevelModeOff`。
- 删除 `l4d_pushdrag_player_keep_gravity`，玩家目标恢复**旧版“抓队友悬浮”**手感（3D 速度弹簧）；随之删除无用的 `l4d_pushdrag_player_max_speed`。
- 回正从“按一下回正”改为**模式切换**：按下瞄准键开启并持续保持回正，再按关闭。
- cvar 总数：**44**。

### v1.9.0

- **真正修复投掷后踩物件弹飞**：投掷物停下后清零速度/角速度、重新同步原点（`l4d_pushdrag_throw_settle`），避免投掷力残留在物件上。
- 修复翻译占位符：带名字的 phrase 增加 `"#format" "{1:N}"`，代码改传客户端索引，不再显示 `{1}`。
- **禁止抓取机关类实体**：`func_*`、`trigger_*`、`logic_*`、`info_*`、`env_*`、`point_*`、`ambient_*`、`sky_*`、`water*`、`prop_dynamic`、`prop_static`；修复“抓电梯导致所有玩家被排斥”的问题。
- 移除 v1.8 错误的电梯 Z 轴夹紧思路及 `elevator_*` 两项 cvar。

### v1.8.0

- 使用原始 usercmd 按钮（`OnPlayerRunCmdPre`），修复**倒地时右键投掷无效**；新增倒地左键投掷兜底 `l4d_pushdrag_incap_attack_throw`。
- 释放玩家后摔伤保护（当时为 3 秒开关）+ 清 `m_flFallVelocity`，修复“从下抓上面的玩家导致摔死”。
- 倒地抓取射线跳过敌方玩家，修复“倒地后只能抓一次队友 / 第二次提示敌方”。
- 新增瞄准键回正、特感悬停距离 `hold_dist_special`、持握免伤 `no_held_damage`。
- 新增屏幕提示：空格挣脱、大力抛射、回正；提示接入 translations（en / ru / chi）。
- 电梯 Z 轴夹紧（v1.9 已移除）。

### v1.7.0

- 使用 DHooks 预挂钩 `PhysicsDamage::operator()` 防弹飞（v2.0 已删除）。
- 旁观者射线忽略玩家，修复“不能抓取敌方”提示。
- 持握中单击 R 放下；被抓玩家按空格挣脱。
- 新增管理员权限三开关：总功能 / 抓特感 / 旁观者抓取。

### v1.6.0

- 清理 `m_hPhysicsAttacker` / `m_flLastPhysicsInfluenceTime`，新增 `release_settle`。
- 生还者可以抓敌方特感；旁观者可以抓物件。
- 修复释放后速度残留、实体索引复用等问题。

### v1.5.0

- 强投改为“持握中 +speed + 右键”，普通右键保持普通投掷。
- “+speed + 双击 R”改为**超远距离抓取**（默认 1000，`far_grab_range`）。
- 远抓增加独立的断开距离上限，避免抓到远处立刻自动松手。

### v1.4.0

- 增加总开关 `l4d_pushdrag_enable`。
- 全部数值 cvar 化（距离、时长、力、投掷、双击窗口等）。
- 释放路径统一清理、entref 校验、重力修复、现代 SourcePawn 语法。

### 社区评论版 v1.3

- 作为基线：双击 R 抓取、右键投掷、+speed 单击 R 强投；无总开关、数值硬编码。Cvar失效。

### 原版 v1.2

- 作为基线：双击 E 抓取、右键投掷；无总开关、数值硬编码。Cvar失效。

---

## 二、弹飞问题排查时间线

| 阶段 | 做法 | 结果 |
|---|---|---|
| v1.4 | 释放时清人工速度、entref 校验 | 解决部分“松手后继续飞”，但踩上去仍会弹 |
| v1.6 | 清 `m_hPhysicsAttacker` / 物理归属时间戳，新增 settle | 对 R 放下有效 |
| v1.7 | DHooks 跳过 `PhysicsDamage::operator()` | 对 R 放下有效，对投掷无效 |
| v1.9 | 发现真正原因：**投掷力残留在物件上**，落地后清速度/角速度/重同步 | 投掷、强投、放下都不再弹飞 |
| v2.0 | 删除 DHooks 补丁与 gamedata | 去掉无效依赖，保留落地清理 |

---

## 三、当前 cvar 一览（44 项）

### 总开关与模式（10）

| cvar | 默认 | 说明 |
|---|---|---|
| `l4d_pushdrag_enable` | 1 | 总开关；0 关闭并释放所有持握 |
| `l4d_pushdrag_versus_survivor` | 3 | 对抗模式生还者：0 禁用 / 1 物件 / 2 队友 / 3 全部 |
| `l4d_pushdrag_versus_infected` | 2 | 对抗模式感染者：0/1/2/3 |
| `l4d_pushdrag_player_grab` | 1 | 是否允许抓玩家（总闸） |
| `l4d_pushdrag_spectator_grab` | 1 | 旁观者（team 1）可抓物件 |
| `l4d_pushdrag_spectator_grab_players` | 1 | 旁观者也可抓玩家/特感 |
| `l4d_pushdrag_survivor_grab_special` | 1 | 生还者可抓敌方特感（含 Tank） |
| `l4d_pushdrag_admin_only` | 0 | 抓取总功能仅管理员 |
| `l4d_pushdrag_admin_only_special` | 0 | 抓特感仅管理员 |
| `l4d_pushdrag_admin_only_spectator` | 0 | 旁观者抓取仅管理员 |

### 抓取距离（8）

| cvar | 默认 | 说明 |
|---|---|---|
| `l4d_pushdrag_grab_range` | 240.0 | 普通抓取最大距离 |
| `l4d_pushdrag_far_grab_range` | 1000.0 | +speed 双击 R 远抓距离 |
| `l4d_pushdrag_hold_dist_object` | 120.0 | `prop_*` 悬停距离 |
| `l4d_pushdrag_hold_dist_car` | 200.0 | 车辆类悬停距离 |
| `l4d_pushdrag_hold_dist_weapon` | 50.0 | `weapon_*` 悬停距离 |
| `l4d_pushdrag_hold_dist_player` | 70.0 | 玩家悬停距离 |
| `l4d_pushdrag_hold_dist_special` | 180.0 | 生还者抓敌方特感的悬停距离 |
| `l4d_pushdrag_hold_dist_default` | 100.0 | 其他实体默认悬停距离 |

### 持握时长（5）

| cvar | 默认 |
|---|---|
| `l4d_pushdrag_hold_time_object` | 15.0 |
| `l4d_pushdrag_hold_time_car` | 10.0 |
| `l4d_pushdrag_hold_time_weapon` | 30.0 |
| `l4d_pushdrag_hold_time_player` | 15.0 |
| `l4d_pushdrag_hold_time_default` | 10.0 |

### 持握物理与修复（12）

| cvar | 默认 | 说明 |
|---|---|---|
| `l4d_pushdrag_hold_force` | 0.2 | 拉力系数：速度 = 系数 × 距离² |
| `l4d_pushdrag_hold_force_dist` | 100.0 | 拉力距离截断 |
| `l4d_pushdrag_hold_max_speed` | 2000.0 | 物件最大速度 |
| `l4d_pushdrag_break_dist` | 350.0 | 超过距离自动松手 |
| `l4d_pushdrag_release_stop` | 1 | 松手清人工速度 |
| `l4d_pushdrag_latency_comp` | 4.0 | 延迟补偿系数 |
| `l4d_pushdrag_release_settle` | 1 | 放下时清角速度/同步原点 |
| `l4d_pushdrag_no_held_damage` | 1 | 持握中的物件不造成碰撞伤害 |
| `l4d_pushdrag_player_fall_protect` | 3.0 | 释放玩家后免摔伤秒数（0=关闭） |
| `l4d_pushdrag_throw_settle` | 1 | 投掷物停下后清投掷力 |
| `l4d_pushdrag_physics_attacker` | 0 | 是否写物理击杀归属 |
| `l4d_pushdrag_attacker_time` | 1.5 | 投掷后归属保留秒数 |

### 投掷（4）

| cvar | 默认 | 说明 |
|---|---|---|
| `l4d_pushdrag_throw_force` | 2000.0 | +speed 右键强投 |
| `l4d_pushdrag_throw_force_attack2` | 200.0 | 普通右键投掷 |
| `l4d_pushdrag_throw_force_base` | 200.0 | 最远距离附加力 |
| `l4d_pushdrag_throw_falloff_dist` | 1000.0 | 投掷力衰减距离 |

### 输入与杂项（5）

| cvar | 默认 | 说明 |
|---|---|---|
| `l4d_pushdrag_double_tap_time` | 0.3 | 双击 R 判定窗口（秒） |
| `l4d_pushdrag_player_jump_escape` | 1 | 被抓玩家按空格挣脱 |
| `l4d_pushdrag_incap_attack_throw` | 0 | 倒地时左键也可投掷（兜底） |
| `l4d_pushdrag_level_key` | 1 | 瞄准键切换回正模式 |
| `l4d_pushdrag_sound` | 1 | 抓取音效开关 |

---

## 四、部署 / 升级

1. **只保留一个 pushdrag 插件**：`l4d_pushdrag_v20.smx` 放入 `addons/sourcemod/plugins/`。
2. `l4d_pushdrag.phrases.txt` 放入 `addons/sourcemod/translations/`。
3. `l4d_pushdrag.cfg` 放入 `cfg/sourcemod/`（首次运行也会自动生成）。
4. **不需要** `gamedata/l4d_pushdrag.txt`（v2.0 已删除）。
5. 依赖 **SDKHooks**；不再需要 DHooks。
6. 换图或重启游戏后生效。

### 升级注意

以下旧 cvar 已删除，配置文件里即使保留也不会生效：

- `l4d_pushdrag_prop_launch_fix`
- `l4d_pushdrag_player_keep_gravity`
- `l4d_pushdrag_player_max_speed`
- `l4d_pushdrag_elevator_fix`
- `l4d_pushdrag_elevator_max_z`

`l4d_pushdrag_player_fall_protect` 已从 0/1 改为秒数：原来的 `1` 请改成 `3.0` 之类的秒数，`0` 表示关闭。

---

## 五、已知限制

- 旁观者抓玩家时，会**跳过正在观战的那个人**（相机在它体内），想抓他需要切换观战目标；这样物件抓取不会被挡住。
- 回正模式每帧写角度与角速度；若物件有抖动，可后续改为每 0.1 秒一次。
- 玩家抓取已恢复旧版悬浮手感；释放玩家的摔伤由 `player_fall_protect` 秒数保护，不再有重力保留开关。
- `func_*` / `prop_dynamic` 等机关实体不可抓取，会提示“不能抓取机关或电梯”。
- 翻译语言：`en`（英）、`ru`（俄）、`chi`（简中）、`zho`（繁中）。
- 编译目标为 SourceMod 1.12.0.7220；1.10–1.12 语法兼容。

---

## 六、快速自测BUG修复

- [ ] 抛掷 / 强投 / R 放下后，踩上物件不再弹飞。
- [ ] 摔伤保护：`0` 关闭、`3` 保护 3 秒、`5` 保护 5 秒。
- [ ] 抓队友能像旧版一样悬浮拖动与甩出。
- [ ] 旁观者开启 `spectator_grab_players` 后能抓玩家/特感，关闭后只能抓物件。
- [ ] 简体/繁体/英文/俄文提示正常，名字不再显示 `{1}`。
- [ ] 瞄准键开启回正模式后物件持续保持回正，再按关闭。
- [ ] 抓 `func_movelinear` 电梯会提示“不能抓取机关或电梯”，不再排斥玩家。
- [ ] 倒地连抓、倒地右键投掷、管理员开关、远抓 1000、持握免伤均正常。
