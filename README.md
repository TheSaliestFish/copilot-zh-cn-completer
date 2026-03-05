# GitHub Copilot Chat 简体中文补全（非官方）

这是一个 VS Code **语言包扩展（Localization Pack）**，用于补全/修正 `github.copilot-chat` 在简体中文界面下的本地化显示。

Unofficial Simplified Chinese localization completer for `github.copilot-chat`.

## 安装

1. 打开 VS Code 命令面板（Windows：`Ctrl+Shift+P`）。
2. 运行 **Configure Display Language**，选择 `zh-cn`，按提示重启 VS Code。
3. 在扩展市场中安装本扩展。
4. 执行一次 **Developer: Reload Window**。

## 验证

- 打开 Copilot Chat/Agent 相关界面（例如侧边栏 Copilot Chat）。
- 若仍看到英文：先确认 VS Code 的显示语言确实为 `zh-cn`，并尝试“完全退出 VS Code 后重新打开”。

## 覆盖范围与限制

- 本扩展仅覆盖 `github.copilot-chat` 扩展自身的可本地化字符串。
- 你在界面里看到的部分英文可能来自 **VS Code 核心**（例如 Chat/Agent/Terminal Agent Tools 等），这类字符串无法通过 Marketplace 上架的语言包扩展直接覆盖。

## 常见问题

- **为什么装了还不生效？**
  - 仅在显示语言为 `zh-cn` 时生效；并且部分内容需要 Reload 或重启后才会刷新。
- **为什么仍有少量英文？**
  - 可能来自 VS Code 核心或其他扩展，不属于本扩展可覆盖范围。

## 可选：修复 VS Code 核心残留英文（本地补丁）

有些英文按钮/菜单/状态提示并不来自 `github.copilot-chat` 扩展，而是来自 **VS Code 核心**（例如 Chat/Agent/Terminal Agent Tools）。这类字符串无法通过 Marketplace 上架的语言包扩展直接覆盖。

本仓库提供“本地补丁脚本”，用于在你的本机上修补简中语言包与 VS Code 缓存，从而改善这些核心英文残留：

- `scripts/apply-copilot-core-patches.ps1`

> 注意：该脚本只在 **GitHub 仓库源码** 中提供，不会包含在 Marketplace 安装的扩展包内。

### 运行指南（推荐 PowerShell 7）

1. 从 GitHub 克隆/下载本仓库源码。
2. 在仓库根目录打开 PowerShell 7（`pwsh`）。
3. 执行：`pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\apply-copilot-core-patches.ps1`
4. 运行完成后，**完全退出并重启 VS Code**（不是 Reload Window），因为缓存可能已被进程加载。

### 回滚与风险

- 脚本写入前会在同目录生成 `.bak.<timestamp>` 备份文件；需要回滚时可用备份覆盖原文件。
- VS Code 或语言包更新后缓存可能重建，可能需要重新运行脚本。

### 反查未汉化条目（可选）

当你在界面里看到仍是英文的核心字符串时，可用辅助脚本反查到 VS Code core 的 `module::key`：

- `scripts/find-core-nls-keys.ps1`

示例：

- 精确匹配：`pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\find-core-nls-keys.ps1 "Working..." "Thinking..." -Normalize`
- 通配符匹配：`pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\find-core-nls-keys.ps1 "Thinking*" -Normalize -UseWildcard`

## 反馈

- 问题反馈/建议：<https://github.com/TheSaliestFish/copilot-zh-cn-completer/issues>

## License

MIT
