# SAITEC Infra Git

`SAITEC-Infra/Git` 用于初始化和校验项目仓库的基础工程规范、Git 治理规则和 AI 协作入口。

对团队用户来说，这个仓库的标准使用方式不是 `git clone` 源码仓，而是直接使用 GitHub Release 中发布的 `install.sh` 和版本化 artifact。

## Quick Start

在目标项目仓库中执行初始化：

```bash
bash <(curl -fsSL https://github.com/SAITEC-TEAM/SAITEC-Infra/releases/download/0.2.0/install.sh) \
  --artifact-url https://github.com/SAITEC-TEAM/SAITEC-Infra/releases/download/0.2.0/saitec-git-0.2.0.tar.gz \
  init .
```

如果只想预览将要写入的内容：

```bash
bash <(curl -fsSL https://github.com/SAITEC-TEAM/SAITEC-Infra/releases/download/0.2.0/install.sh) \
  --artifact-url https://github.com/SAITEC-TEAM/SAITEC-Infra/releases/download/0.2.0/saitec-git-0.2.0.tar.gz \
  init --dry-run .
```

如果想固定到其他版本，只需要把上面 URL 里的 `0.2.0` 替换成目标 release tag。

## Commands

统一入口是 `install.sh`，支持 4 个子命令。

### `init`

初始化或增量应用仓库规范。

它会根据当前参数和模板资产，生成或更新以下内容：

- `pyproject.toml`
- `.pre-commit-config.yaml`
- `.gitignore`
- `.gitattributes`
- `.README.md`
- `.saitec/hooks/enforce-branch-law.sh`
- `.vscode/settings.json`
- `.saitec/config.toml`
- AI 协作文件，例如 `AI_COLLABORATION.md`、`AGENTS.md`、`.github/copilot-instructions.md`、`.codex/AGENTS.md` 等

常用参数：

- `--dry-run`：只显示将执行的动作，不写入文件
- `--non-interactive`：非交互模式，适合批量初始化或 CI
- `--config <file>`：从配置文件读取初始化参数
- `--force`：覆盖已存在文件
- `--install-hooks`：安装 `pre-commit` 和 Git hooks
- `--no-install-hooks`：跳过 `pre-commit` 和 Git hooks 安装

示例：

```bash
bash <(curl -fsSL https://github.com/SAITEC-TEAM/SAITEC-Infra/releases/download/0.2.0/install.sh) \
  --artifact-url https://github.com/SAITEC-TEAM/SAITEC-Infra/releases/download/0.2.0/saitec-git-0.2.0.tar.gz \
  init --non-interactive --config ./saitec.toml .
```

配置文件示例：

```toml
project_name = "demo-service"
project_version = "0.1.0"
python_version = ">=3.11"
mypy_strict = true
install_hooks = false
ai_collaboration = true
ai_github = true
ai_cursor = true
ai_claude = false
ai_codex = true
ai_trae = false
```

### `validate`

校验目标仓库是否已经具备 AI 协作主规范和至少一个工具适配入口。

当前检查项包括：

- `AI_COLLABORATION.md`
- `AGENTS.md`
- 至少一个工具适配文件：
  - `.github/copilot-instructions.md`
  - `.cursor/rules/ai-collaboration.mdc`
  - `.claude/CLAUDE.md`
  - `.codex/AGENTS.md`
  - `.trae/AGENTS.md`

示例：

```bash
bash <(curl -fsSL https://github.com/SAITEC-TEAM/SAITEC-Infra/releases/download/0.2.0/install.sh) \
  --artifact-url https://github.com/SAITEC-TEAM/SAITEC-Infra/releases/download/0.2.0/saitec-git-0.2.0.tar.gz \
  validate .
```

### `doctor`

诊断当前环境和目标目录是否具备运行条件。

当前会检查：

- `bash`、`git`、`cp`、`mktemp`、`tar`
- `curl` 或 `wget`
- `python + pip`
- `pre-commit` 是否存在
- 目标目录是否存在、是否可写
- 目标目录是否位于 Git 仓库中
- 是否已存在 `.saitec/config.toml`

示例：

```bash
bash <(curl -fsSL https://github.com/SAITEC-TEAM/SAITEC-Infra/releases/download/0.2.0/install.sh) \
  --artifact-url https://github.com/SAITEC-TEAM/SAITEC-Infra/releases/download/0.2.0/saitec-git-0.2.0.tar.gz \
  doctor .
```

### `version`

输出当前使用的 Infra 版本，便于排障和沟通。

示例：

```bash
bash <(curl -fsSL https://github.com/SAITEC-TEAM/SAITEC-Infra/releases/download/0.2.0/install.sh) \
  --artifact-url https://github.com/SAITEC-TEAM/SAITEC-Infra/releases/download/0.2.0/saitec-git-0.2.0.tar.gz \
  version
```

## Local Source Usage

如果你是这个 Infra 仓库的维护者，也可以在源码目录里直接执行本地入口：

```bash
bash install.sh init /path/to/repo
bash install.sh validate /path/to/repo
bash install.sh doctor /path/to/repo
bash install.sh version
```

源码模式主要用于开发、调试和发布，不是团队用户的标准接入方式。

## Release Flow

先构建发布 artifact：

```bash
bash src/shells/build-release.sh
```

再发布到 GitHub Release：

```bash
export GITHUB_TOKEN=xxxx
bash src/shells/publish-release.sh --version 0.2.0
```

发布脚本会：

- 生成 `dist/saitec-git-<version>.tar.gz`
- 生成 `dist/saitec-git-<version>.tar.gz.sha256`
- 创建并推送同名 Git tag
- 创建或更新 GitHub Release
- 上传 `install.sh`、artifact 和 checksum
