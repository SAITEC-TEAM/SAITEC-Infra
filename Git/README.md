# SAITEC Infra Git

这个仓库现在提供一个统一的 Bash 入口：[`install.sh`](/ai/dataset/workspace/SAITEC/SAITEC-Infra/Git/install.sh)。

本地源码模式：

```bash
bash install.sh init /path/to/repo
bash install.sh validate /path/to/repo
bash install.sh doctor /path/to/repo
bash install.sh version
```

远程单文件模式：

```bash
bash <(curl -fsSL https://<internal-host>/saitec/git/install.sh) \
  --dist-base-url https://<internal-host>/saitec/git/releases \
  --version 0.2.0 \
  init /path/to/repo
```

`install.sh` 在源码仓库内会直接调用本地实现；以远程单文件执行时会下载对应版本的 release artifact。

`init` 支持：

```bash
bash install.sh init --non-interactive --config .saitec/config.toml --dry-run .
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

给发布链路打包 artifact：

```bash
bash src/shells/build-release.sh
```

直接发布到 GitHub Release：

```bash
export GITHUB_TOKEN=xxxx
bash src/shells/publish-release.sh --version 0.2.0
```

脚本会：

- 生成 `dist/saitec-git-<version>.tar.gz`
- 创建并推送同名 tag
- 创建或更新 GitHub Release
- 上传 `install.sh`、artifact、`.sha256`
