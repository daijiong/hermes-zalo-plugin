# Repository Guidelines

## 项目结构与模块组织

本仓库是 `hermes-zalo-plugin`：Node.js ESM 桥接服务连接 Zalo/zca-js 与 Hermes Agent。核心入口在 `server.js`，Zalo 客户端封装在 `zaloClient.js`，动作权限表在 `permissions.js`，运行时路径集中在 `paths.js`。`bin/cli.mjs` 提供 npm CLI；`login.mjs`、`install.mjs`、`uninstall.mjs` 和 `install.ps1`/`install.sh` 负责登录、安装和卸载。`hermes-plugin/` 存放 Hermes 侧 Python adapter 与 `plugin.yaml`，`assets/` 存放 README 使用的 SVG，`.github/workflows/` 存放 CI 与发布流程。

## 构建、测试与开发命令

- `npm ci`：按 `package-lock.json` 安装依赖，CI 与本地复现优先使用。
- `npm start`：运行本地桥接服务，即 `node server.js`。
- `node login.mjs`：执行 QR 登录；需要重扫时使用 `node login.mjs --force`。
- `.\install.ps1 --no-service`：Windows 下安装依赖并登录，但不创建计划任务。
- `node bin/cli.mjs help` / `node bin/cli.mjs status`：验证 CLI 帮助与本地服务状态。
- `npm pack --dry-run`：发布前检查包内容，确认未包含凭证、日志或运行时数据。

## 编码风格与命名约定

JavaScript 使用 ESM、双引号、分号和 2 空格缩进；函数与变量用 `camelCase`，环境变量常量用 `UPPER_SNAKE_CASE`。Python adapter 保持 4 空格缩进和类型提示风格。修改时贴近现有文件风格，不做无关重排或抽象。

## 测试指南

当前没有独立单元测试框架。提交前至少对改动过的 JS 文件运行 `node --check <file>`；涉及 CLI 时运行 `node bin/cli.mjs help` 和 `node bin/cli.mjs status`；涉及打包、安装或文件列表时运行 `npm pack --dry-run`。真机 Zalo/Hermes 验证需要本地账号和环境变量，结果记录在 PR 描述中，禁止提交 `data/`、`.hermes-zalo/`、`credentials.json`、`qr*.png` 或 `*.log`。

## Commit 与 Pull Request 规范

Git 历史采用 Conventional Commits，例如 `fix(zalo): keep session alive`、`docs(readme): add setup-flow`、`chore(release): 1.0.8`。PR 应说明目的、影响范围、运行过的命令，以及相关 issue；改动安装器或后台服务时注明已验证的平台。涉及截图、日志或账号标识时必须脱敏。

## 安全与配置提示

默认保持 `ZALO_PLUGIN_HOST=127.0.0.1`，只有在明确处理 TLS 与访问控制后才暴露到外网。权限相关变更必须同时考虑 `permissions.js` 与 `hermes-plugin/adapter.py` 中的映射同步。
