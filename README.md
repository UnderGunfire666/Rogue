# 余烬之路 · 单人 MVP

Godot 4.7.2 的 2D 固定俯视像素风原型。项目概念与长期约束以 [统一设计决策](docs/DESIGN_DECISIONS.md) 为准。

## 开始试玩

在 Godot 中导入本目录的 `project.godot`，等待资源导入后按 **F5**。入口是 `scenes/app/title_screen.tscn`。

流程：开始 → 选择旅人 → 同一界面选择右手武器和遗物 → 地图营地 → 普通战斗 → 商店 → 在相邻格子间选择奖励、事件、精英战斗或前往 BOSS → 旅程结算。失败可返回开始界面开启新 Run。

地图沿上下左右相邻格移动。已完成的格子可以返回，内容不会重复触发。初始事件仅显示一段文字。

## 操作

| 操作 | 按键 |
| --- | --- |
| 移动 | WASD 或方向键 |
| 武器攻击 | 自动选取射程内目标并攻击 |
| 主动技能选区 / 切换 | Q，由装备或遗物提供 |
| 确认技能 | 选区状态下点击左键 |
| 取消技能选区 | 右键，或 Esc |
| 暂停 / 继续 | 未处于技能选区状态时按 Esc |
| 菜单和地图 | 鼠标；按钮也可使用键盘焦点 |

移动、自动武器攻击与技能瞄准相互独立。战斗中获得的升级选择在战斗结束后依次结算。

## 当前内容

- 旅人与十二个参考角色；角色选择界面显示全部主属性及角色特性。默认旅人生命 100，显示移速 5，实际 180 像素/秒。
- 两个玩家装备槽，开局只装备右手；商店或奖励可获得左手装备。
- 六把玩家武器：猎针/裂石斧（突刺/挥砍近战）、余烬手枪/燧火霰弹枪（单弹/散弹远程）、紫晶法杖/群星魔典（单体/群体必中法术）。裂石斧提供圆形爆破技能。
- 普通 / 精英 / Boss 分类；三种普通敌人行为、一个精英配置、一名首领。
- 普通战斗生成 3 次初始敌人组，每次 5 近战、2 远程、1 治疗，按计时生成并允许重叠。
- BOSS 示例战斗在前 2 组清空后出 BOSS，之后敌人持续按间隔生成；时间到即胜利，击败 BOSS 才获得巨大宝箱。
- 五类不同文字颜色的 Map Cell：普通战斗、精英战斗、BOSS 战斗、奖励、事件。
- 共用装备 / 遗物基础系统：玩家双装备槽与无限遗物；敌人单装备槽和单遗物槽，具体物品不通用。
- 敌人采用固定像素速度：赤牙/队长基础 144，射手/施法医师/BOSS 基础 108；自身遗物可修正，玩家移速变化不影响它们。

当前为单人版本，使用可替换的占位像素素材及系统中文字体。本地多人、营救、Steam 联机和存档位于后续阶段。

## 敌人整合编辑器

打开 Godot 顶部 **Enemy Editor** 工作区，或通过 **项目 → 工具 → 敌人编辑器 / Enemy Editor** 进入。插件已在项目中启用；若关闭过，可到项目设置的 Plugins 页启用 Enemy Editor。

左侧搜索、筛选并选择敌人，右侧三个标签页分别编辑基础属性与外观、装备与攻击、遗物与被动。工具栏提供新建、复制、保存、放弃修改、查看引用、删除和刷新。全部编辑使用自定义界面，无需进入 Inspector。

在敌人页面从已保存的敌人装备和遗物中选择；装备必选，遗物可不携带。敌人页面展示所选物品的效果，可以打开 Equipment Editor 或 Relic Editor 创建、编辑物品并刷新选择列表。装备可包含多个近战、远程和施法配置；治疗是施法效果。保持距离行为采用第一个远程配置的射程。每个敌人独立设置“撤退时发起攻击”，默认关闭；治疗和被动回血在移动中继续。

敌人保存对所选装备和遗物资源的引用。同一物品可供多个敌人使用；在对应物品编辑器修改后，所有引用它的敌人都会使用更新后的配置。旧内嵌配置可在敌人页面先存入物品库，再保存敌人建立引用。创建敌人后还需加入 Enemy Group 或 Boss Encounter 才会进入战斗。

保存前检查必填项、数值、使用者限制、ID 冲突及类别变更对现有组/战斗的影响。删除检查整个项目内已保存场景和资源的直接、间接引用，有引用时阻止删除并显示位置。外部文件修改冲突也会阻止覆盖。详细说明见 [MVP_GUIDE](docs/MVP_GUIDE.md)。

## 装备与遗物整合编辑器

Godot 顶部新增 **Equipment Editor** 与 **Relic Editor**，也可从项目工具菜单打开。二者均已启用，支持玩家/敌人分别创建、复制、完整属性编辑、搜索筛选、保存重开、查看引用和删除保护，无需 Inspector。

装备编辑器可配置攻击类型、攻击力、发动范围、间隔，以及近战/施法的对象数、群体半径，或远程的投射物数、弹速、散射角。敌人装备可组合多个攻击配置。遗物编辑器可组合回血、近战攻速、移速与伤害加成。

近战武器按突刺或挥砍轨迹移动并命中路径上的敌人；法术采用即时判定。远程武器自动瞄准最近的射程内敌人，子弹可继续命中范围外目标，不按寿命或距离销毁。开局从四个随机一级遗物中选择一件；商店使用保存的玩家装备与遗物，敌人物品可在 Enemy Editor 选择并引用。

## 其他数据配置入口

| 内容 | 资源位置 |
| --- | --- |
| 玩家角色与技能 | `resources/characters/`、`resources/skills/` |
| 玩家武器 / 遗物 | `resources/weapons/`、`resources/relics/` |
| 敌人类别、基础属性、行为、固定配装 | `resources/enemies/` |
| 敌人专用装备及攻击 / 治疗配置 | `resources/enemy_equipment/` |
| 敌人专用遗物 | `resources/enemy_relics/` |
| Enemy Group 组成及组内进场速度 | `resources/groups/` |
| 生成位置：边界或固定坐标 | `resources/spawns/` |
| 生成计划、重复次数、间隔、BOSS 与出现时机 | `resources/encounters/` |
| 地图整数坐标、格子类型、奖励和事件 | `resources/maps/ember_map.tres` |

编辑 `training.tres` 的 schedules → repetitions / interval / location 可以改变整场战斗的刷新；编辑其 group 引用中的 entries 可以改变敌人组成。BOSS 不允许放入 Enemy Group，应编辑 Boss Encounter 的 boss 与 boss_after_group_count。

目标事件规则支持个人与全队选项；战斗选项仅出现在全队事件中。当前实现与目标的差异见 [MVP_GUIDE](docs/MVP_GUIDE.md)，完整目标规则见 [统一设计决策](docs/DESIGN_DECISIONS.md)。

## 验证

检查脚本为 `tests/mvp_smoke.gd`，覆盖真实场景、原生计时器、物理命中、重叠组、BOSS 阈值、共用槽位与事件返回。运行：

```powershell
godot --headless --fixed-fps 60 --path . --script res://tests/mvp_smoke.gd
godot --headless --path . --script res://tests/enemy_editor_smoke.gd
godot --headless --fixed-fps 60 --path . --script res://tests/content_editors_smoke.gd
```

流程检查会主动清理敌人以验证衔接；难度和操作手感仍以实际试玩为准。结果见现有 [VALIDATION.md](docs/VALIDATION.md)。

`tools/capture_previews.gd`、`tools/capture_enemy_editor.gd` 与 `tools/capture_content_editors.gd` 使用实际渲染生成截图至被忽略的 `.godot/qa/`。检查与截图工具不参与正式游戏流程。

玩家主属性、遗物和技能规则见 [MVP 指南](docs/MVP_GUIDE.md)。战斗暂停菜单可以查看角色属性。

Godot 顶部 **Character Editor** 可新建、复制、编辑、保存及删除玩家角色。装备和遗物编辑器可配置各自的主动技能。
