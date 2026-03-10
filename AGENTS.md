# AGENTS.md

本文件用于约束 Codex 在本仓库（`Slay the Spire 2/mods`）中的默认行为，减少重复沟通。

## 目标

- 维护 `README.md` 的 **mod 清单、数量统计、功能说明**。
- 当目录中新增/删除 mod 时，自动同步 README。
- 在你确认后，直接完成 `commit + push + tag`。

## 默认工作方式

- 用户说“更新了/多了一个 mod/改下 readme”等，助手应：
  1. 扫描当前目录中的 mod 文件夹。
  2. 读取 `mod_manifest.json`（如果存在）提取名称/版本/作者/描述。
  3. 对无 manifest 的 mod：通过目录名、dll 字符串做推断，并在 README 明确标注“推断”。
  4. 直接修改 `README.md`，保持原有表格结构。
- 用户说“直接操作/嗯/push/tag”，助手应直接执行，不再反复确认。

## README 约定

- 标题：`Slay the Spire 2 Mods 清单`
- 必有章节：
  - `统计`（Mod 总数）
  - `已安装 Mod`（表格）
  - `说明`（哪些来源于 manifest，哪些是推断）
- 表格列默认：
  - `# | 目录 | 显示名称 | 主要功能（这个 mod 是干啥的） | 版本 | 作者`
- 功能说明优先级：
  1. 用户明确口述（最高优先级）
  2. `mod_manifest.json` 的 `description`
  3. 基于 DLL/文件名推断（需标注）

## Git 操作约定

- 默认分支：`master`
- 默认远端：`SlayTheSpire2MODS`
- 用户要求“push”：
  - 执行 `git add -A`
  - 使用清晰 commit message 提交
  - `git push SlayTheSpire2MODS master`
- 用户要求“打 tag”：
  - 为当前最新提交创建 annotated tag
  - 命名建议：`mods-update-YYYY-MM-DD[-suffix]`
  - `git push SlayTheSpire2MODS <tag>`

## 沟通偏好

- 用中文，简洁直接。
- 先做事，后汇报结果。
- 对不确定信息只问最小必要问题；能推断就先落地并标注“推断”。

## 安全边界

- 不执行破坏性命令（如 `git reset --hard`、批量删除）除非用户明确要求。
- 不回滚用户已有改动。
