# Slay the Spire 2 Mods 清单

## 统计

- Mod 总数：**13**

## 已安装 Mod

| # | 目录 | 显示名称 | 主要功能（这个 mod 是干啥的） | 版本 | 作者 |
|---|---|---|---|---|---|
| 1 | `BaseLib.0.2.1` | BaseLib | Mod 开发基础库，供其他 Mod 依赖使用（如 The Watcher）。 | v0.2.1 | Alchyr |
| 2 | `BetterSpire2-2-1-68-1774378697` | BetterSpire2 | QoL 整合包：玩家/宠物头顶受击伤害统计；多段伤害合计标注；手牌查看器；长按 `R` 快速重置本轮；跳过启动画面；多人踢出/人数缩放。 | v1.68 | jdr |
| 3 | `DamageMeter` | Skada: Damage Meter | 谁尽力？谁犯罪？伤害、格挡、助攻、卡牌效率等 17 类战斗统计，数据仪表盘一键复盘，多人联机通用。 | 1.9.1 | 皮一下就很凡@Bilibili |
| 4 | `Math is Hard-79-0-2-0-1773829700` | Math | 战斗数学覆盖层，辅助计算战斗中的数值。 | v0.2.0 | Ling Samuel |
| 5 | `ModConfig` | ModConfig | 通用模组配置框架：在设置中嵌入「模组配置」标签页，支持开关、滑条、下拉框、快捷键绑定、文本输入、按钮、颜色选择器等控件。 | 0.2.1 | 皮一下就很凡@Bilibili |
| 6 | `QuickRestart-4-1-0-7-1773792467` | Quick Restart | 按 `F5` 立即从头重开当前战斗或事件。 | 1.0.0 | JiesiLuo |
| 7 | `RelicRarityDisplay` | Relic Rarity Display | 按稀有度为遗物上色显示。 | 1.1 | Aiadan |
| 8 | `RouteSuggest-v1.8.0.zip-54-1-8-0-1773998529` | RouteSuggest | 推荐最佳路线（默认金色安全、红色激进，可配置）。 | 1.8.0（推断） | Jiajie Chen @jiegec（推断） |
| 9 | `StsSpeak` | Sts2Speak | 聊天输入增强：可以打字聊天。 | 未提供 | 未提供 |
| 10 | `The Watcher - 1.2.1 - Slay the Spire 2 - v0.101.0-46-1-2-1-1774625779` | The Watcher | 将原版守望者角色移植到 STS2，含平静/神圣/愤怒三姿态，依赖 BaseLib。 | v1.2.1 | lamali |
| 11 | `UndoAndRedo-16-1-1-1-1773792413` | UndoAndRedo | 按左/右方向键撤销/重做战斗操作。 | 1.0.0 | JiesiLuo |
| 12 | `UnifiedSavePaths-6-1-0-3-1773792441` | UnifiedSavePath | Mod 版与原版使用同一存档路径。 | 1.0.3（推断） | 未提供 |

## 说明

- `BaseLib`、`BetterSpire2`、`Skada: Damage Meter`、`Math`、`ModConfig`、`Quick Restart`、`Relic Rarity Display`、`The Watcher`、`UndoAndRedo` 的名称/版本/作者/描述来自 `mod_manifest.json` 或目录内 `.json` 配置文件。
- `RouteSuggest`、`StsSpeak`、`UnifiedSavePath` 无 `mod_manifest.json`，按目录名和 DLL 名推断，并在表格中标注"推断"。

## BetterSpire2 存档与安装备注

- 原版（Unmodded）存档：
  `%APPDATA%\\SlayTheSpire2\\steam<STEAM_ID>\\profile1\\saves\\`
- 模组版（Modded）存档：
  `%APPDATA%\\SlayTheSpire2\\steam<STEAM_ID>\\modded\\profile1\\saves\\`
- 首次安装模组后若进度未继承，请把原版存档文件复制到模组存档目录（建议复制，不要移动）。
- 安装位置：`STEAM\\Install\\steamapps\\common\\Slay the Spire 2\\mods`（若无 `mods` 文件夹则手动创建）。
