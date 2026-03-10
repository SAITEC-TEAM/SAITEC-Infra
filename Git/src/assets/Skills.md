# SAITEC Git Collaboration Skills

本文件定义 AI 参与 Git 协作时必须遵守的最小技能集，用于约束提交前后的协作流程。

使用方式：
- 开始执行 Git 相关任务前，先阅读 `.saitec/AI_COLLABORATION.md`，再阅读本文件。
- 如本文件与 `.saitec/AI_COLLABORATION.md` 冲突，以 `.saitec/AI_COLLABORATION.md` 为准。
- 本文件只覆盖 Git 协作流程，不扩展为通用开发规范。

## 1. Branch Naming
- 所有开发分支都必须从 `main` 创建。
- 只允许以下命名格式：
  - `feat/<topic>`
  - `fix/<topic>`
  - `new/<topic>`
- `<topic>` 只能包含小写字母、数字、`.`、`_`、`-`。

## 2. Pre-Commit Checks
- 提交前先阅读本次变更涉及的代码、配置和文档，不凭空假设仓库状态。
- 提交前完成仓库既有校验，包括代码规范、格式化、测试或项目内约定的等效检查。
- 只做最小必要改动；如行为、接口或流程发生变化，应同步更新对应文档。
- 不伪造命令执行结果、测试状态、CI 状态或线上状态。

## 3. Pull Request Merge Path
- 不直接向 `main` push。
- 所有变更通过分支和 Pull Request 合并进入 `main`。
- PR 描述中应说明：
  - AI 参与范围
  - 需要人工重点复核的点
  - 已完成的验证结果

## 4. Result Reporting
- AI 在交付结果时必须明确说明：
  - 改了什么
  - 为什么这样改
  - 做了哪些验证；如果未验证，要明确写出原因
  - 仍然存在的风险、假设或待确认项
