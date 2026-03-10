# {{$PROJECT_NAME}} AI Collaboration Guide

本仓库支持人类开发者与多种 AI 工具协作开发。`.saitec/AI_COLLABORATION.md` 是唯一主规范；如果 `Skills.md`、工具专属文件与本文件表述不一致，以本文件为准。

## 1. 协作目标
- 用 AI 提升信息检索、代码修改、测试补全、文档撰写与重构效率。
- 保持仓库规范统一，不因工具差异产生多套行为标准。
- 所有 AI 产出都必须经过人工复核后再进入主分支。

## 2. 工作方式
AI 在开始修改前应先：
- 阅读当前任务相关代码、配置与文档，不凭空假设系统结构。
- 明确目标、约束、验收标准与影响范围。
- 优先做最小必要变更，避免无依据的架构重写。

AI 在提交结果时应说明：
- 改了什么。
- 为什么这样改。
- 做了哪些验证；如果没验证，要明确写出原因。
- 仍然存在的风险、假设或待确认点。

## 3. 代码与文档约束
- 不要伪造接口、依赖、命令、测试结果或线上状态。
- 不要无依据删除用户已有逻辑、配置或注释。
- 修改前优先复用仓库既有模式、命名与目录结构。
- 新增脚本、模板或自动化时，应尽量幂等并支持重复执行。
- 如变更行为、接口或运维流程，同时更新对应文档。

## 4. Git 协作要求
- 不直接向 `main` push，通过分支和 Pull Request 合并。
- PR 描述中标注 AI 参与范围、人工复核点和验证结果。
- 评审责任仍由人承担；AI 不能替代 reviewer 审批。

## 5. Skills 约定
- `.saitec/Skills.md` 是 Git 协作技能清单，聚焦分支命名、提交前校验、PR 合并路径和结果说明。
- AI 在处理 Git 协作相关任务时，应先阅读本文件，再阅读 `.saitec/Skills.md`。
- `Skills.md` 只补充执行层要求，不替代本文件的主规范地位。

## 6. 多工具适配约定
- `AGENTS.md`：仓库级 agent 入口说明。
- `.saitec/Skills.md`：Git 协作技能清单。
- `.github/copilot-instructions.md`：GitHub Copilot 指令适配文件。
- `.cursor/rules/`：Cursor 规则目录。
- `.claude/CLAUDE.md`：Claude Code 协作说明。
- `.codex/AGENTS.md`：Codex / CLI agent 协作说明。
- `.trae/AGENTS.md`：Trae 协作说明。

这些文件只负责把主规范映射到各工具可识别的入口，不重复维护规则正文。

除 `.github/copilot-instructions.md` 等仓库级协作文件外，`.cursor/`、`.claude/`、`.codex/`、`.trae/` 等本地工具目录可视为派生产物：
- 团队共享与评审时，以 `.saitec/AI_COLLABORATION.md` 和 `AGENTS.md` 为准。
- 本地工具目录可以通过初始化脚本按需重建，不要求长期纳入版本控制。
- 新成员 clone 仓库后，如需恢复本地 AI 工具入口，可执行 `install.sh init --non-interactive .`。
- `.saitec/Skills.md` 由初始化脚本同步生成，建议纳入版本控制，确保 AI 始终可发现该入口。
