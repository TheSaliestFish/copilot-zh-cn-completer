# GitHub Copilot Chat zh-CN Completer (Unofficial)

Unofficial Simplified Chinese localization completer for `github.copilot-chat`.

—

## GitHub Copilot Chat 简体中文语言包（非官方）

这是一个 VS Code **语言包扩展（Localization Pack）**，为 `github.copilot-chat` 提供简体中文本地化补全/修正。

- 语言：`zh-cn`
- 覆盖范围：`github.copilot-chat`
- 翻译条目：`package` 389 条 + `bundle` 805 条（当前仓库内已全部非空）

> 说明：部分你在界面里看到的英文并不来自 Copilot Chat 扩展，而是来自 **VS Code 核心工作台（Chat/Agent/Terminal Agent Tools）**。这些字符串**不能**通过 Marketplace 上架的普通扩展直接覆盖。

> Note: Some English UI strings are from **VS Code core** (Chat/Agent/Terminal Agent Tools). Those cannot be overridden by a Marketplace localization pack alone.

## 安装与验证（语言包扩展）

1. 在 VS Code 中确保显示语言为简体中文：命令面板运行 **Configure Display Language** → 选择 `zh-cn`。
2. 安装本扩展后执行一次 **Developer: Reload Window**。

## 可选：本地补丁（修复 VS Code 核心英文按钮/下拉/状态提示）

如果你遇到例如：

- 工具确认 UI 的按钮/下拉仍为英文（Allow/Skip/Always Allow…）
- Agent Sessions 的分组标题（TODAY/LAST WEEK/OLDER/ARCHIVED…）
- “Working…/Getting chat ready…/Used {0} references/Created {0} todos…” 等状态提示

这些通常来自 VS Code 核心 NLS/缓存，**不在 Marketplace 语言包扩展的可覆盖范围内**。

仓库提供了一个本地补丁脚本：

- `scripts/apply-copilot-core-patches.ps1`

它会在本机写入：

- 简中语言包的 `main.i18n.json`
- VS Code 用户数据目录的 clp 缓存 `nls.messages.json`

并自动生成 `.bak.<timestamp>` 备份。

### 运行方式

在本仓库目录执行：

- `pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts/apply-copilot-core-patches.ps1`

运行后必须 **完全退出并重启 VS Code**（不是 Reload Window），因为 clp 缓存会被进程加载到内存。

### 回滚

脚本每次写入都会生成备份文件（同目录下 `.bak.<timestamp>`）。

- 需要回滚时，把对应的 `.bak.*` 覆盖回原文件即可。

### 风险提示

- VS Code 或语言包更新后，clp 缓存可能会重建，需要重新运行脚本。
- 这是“本地补丁”方案，不适合打包上架；建议只在 GitHub 仓库中作为可选手段提供。

## 发布到 Marketplace（你需要改的字段）

发布前请修改：

- `package.json` 的 `publisher`

发布（推荐）：

- 在 [VS Code Marketplace 管理页](https://marketplace.visualstudio.com/manage) 创建 Publisher
- 在 Azure DevOps 创建 **Personal Access Token (PAT)**（用于 VS Code Marketplace 发布）
- 本机登录：`vsce login <你的PublisherID>`
- 发布：`vsce publish`

打包：

- `npm i -g @vscode/vsce`
- `vsce package`

本地重新加载测试：

- `vsce package`
- `code.cmd --install-extension .\copilot-zh-cn-completer-0.1.0.vsix --force`
- 执行一次 **Developer: Reload Window**

> 本仓库已通过 `.vscodeignore` 排除 `scripts/`、`node_modules/`、`*.vsix`，确保上架包只包含语言包必要内容。
