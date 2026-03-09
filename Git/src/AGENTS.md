# SAITEC-Git 项目管理 Infra

## 1. 项目概述
本项目用于快速规范化 Git 仓库中的工程配置、Git 治理与 AI 协作流程。当前通过脚本与模板资产，为目标仓库初始化 Python 项目配置、代码质量检查、编辑器设置、多 AI 工具协作说明以及 GitHub 协作模板。最终所有对外接口都暴露在 `SAITEC-Infra/Git/src/shells` 中。

## 2. 接口功能
1. `initial.sh`
   交互式初始化脚本，负责生成 `pyproject.toml`、复制 `.pre-commit-config.yaml` / `.gitignore` / `.gitattributes` / `.README.md`、创建编辑器目录、写入 VS Code `settings.json`，并按需生成 `AI_COLLABORATION.md`、`AGENTS.md`、Copilot / Cursor / Claude Code / Codex / Trae 适配文件，以及 GitHub PR / Issue 模板。
2. `validate_ai_collaboration.sh`
   轻量检查脚本，用于验证目标仓库是否具备 AI 协作主规范与至少一个工具适配入口，适合接入手工检查、CI 或示例仓库验收。

## 3. 模板设计原则
- `AI_COLLABORATION.md` 是 AI 协作唯一主规范。
- 各工具专属文件只做格式适配，不重复维护规则正文。
- 初始化脚本必须支持重复执行，已有文件沿用覆盖确认逻辑。
