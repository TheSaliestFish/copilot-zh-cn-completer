[CmdletBinding()]
param(
  [Parameter(Mandatory = $false)]
  [string]$LanguagePackMainI18n = "",

  [Parameter(Mandatory = $false)]
  [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-VSCodeAppRoot {
  $cmd = Get-Command code.cmd -ErrorAction SilentlyContinue
  if ($null -eq $cmd) { $cmd = Get-Command code -ErrorAction SilentlyContinue }
  if ($null -eq $cmd) {
    throw '未找到 code 或 code.cmd，请确认 VS Code 已安装且可在 PATH 中找到。'
  }

  $codePath = $cmd.Source
  $binDir = Split-Path -Parent $codePath
  $installRoot = Resolve-Path (Join-Path $binDir '..')
  $hashDir = Get-ChildItem -Directory $installRoot | Where-Object { $_.Name -match '^[0-9a-f]{8,}$' } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if ($null -eq $hashDir) {
    throw "无法在 $installRoot 下找到版本目录（形如 hash 的文件夹）。"
  }

  $appRoot = Join-Path $hashDir.FullName 'resources\app'
  if (-not (Test-Path $appRoot)) {
    throw "找不到 VS Code appRoot：$appRoot"
  }
  return $appRoot
}

function Get-VSCodeCoreNlsIndexMap {
  $appRoot = Get-VSCodeAppRoot
  $keysPath = Join-Path $appRoot 'out\nls.keys.json'
  $msgsPath = Join-Path $appRoot 'out\nls.messages.json'
  if (-not (Test-Path $keysPath)) { throw "找不到：$keysPath" }
  if (-not (Test-Path $msgsPath)) { throw "找不到：$msgsPath" }

  $keys = Get-Content -Raw -Encoding UTF8 $keysPath | ConvertFrom-Json
  $msgs = Get-Content -Raw -Encoding UTF8 $msgsPath | ConvertFrom-Json

  $map = @{}
  $i = 0
  foreach ($entry in $keys) {
    $module = $entry[0]
    foreach ($k in $entry[1]) {
      $map["$module::$k"] = [pscustomobject]@{ index = $i; message = $msgs[$i] }
      $i++
    }
  }
  return $map
}

function Get-ActiveClpNlsMessagesPath {
  $lpMapPath = Join-Path $env:APPDATA 'Code\languagepacks.json'
  if (-not (Test-Path $lpMapPath)) {
    return $null
  }

  $lpMap = Get-Content -Raw -Encoding UTF8 $lpMapPath | ConvertFrom-Json
  $zhcn = $lpMap.'zh-cn'
  if ($null -eq $zhcn -or [string]::IsNullOrWhiteSpace($zhcn.hash)) {
    return $null
  }

  $clpRoot = Join-Path $env:APPDATA ("Code\\clp\\{0}.zh-cn" -f $zhcn.hash)
  if (-not (Test-Path $clpRoot)) {
    return $null
  }

  $nls = Get-ChildItem -Path $clpRoot -Recurse -File -Filter 'nls.messages.json' -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($null -eq $nls) {
    return $null
  }
  return $nls.FullName
}

function Get-LatestZhHansLanguagePackMainI18nPath {
  $extensionsRoot = Join-Path $env:USERPROFILE '.vscode\extensions'
  $candidate = Get-ChildItem -Path $extensionsRoot -Directory -Filter 'ms-ceintl.vscode-language-pack-zh-hans-*' -ErrorAction SilentlyContinue |
    Sort-Object -Property LastWriteTime -Descending |
    Select-Object -First 1

  if ($null -eq $candidate) {
    throw "未找到已安装的简体中文语言包目录：$extensionsRoot\ms-ceintl.vscode-language-pack-zh-hans-*"
  }

  $main = Join-Path $candidate.FullName 'translations\main.i18n.json'
  if (-not (Test-Path $main)) {
    throw "找不到语言包文件：$main"
  }
  return $main
}

if ([string]::IsNullOrWhiteSpace($LanguagePackMainI18n)) {
  $LanguagePackMainI18n = Get-LatestZhHansLanguagePackMainI18nPath
}

if (-not (Test-Path $LanguagePackMainI18n)) {
  throw "找不到语言包文件：$LanguagePackMainI18n"
}

$doc = Get-Content -Raw -Encoding UTF8 $LanguagePackMainI18n | ConvertFrom-Json -AsHashtable
$contents = $doc['contents']
if (-not ($contents -is [hashtable])) {
  throw '语言包 contents 类型不正确'
}

function Get-OrCreateModuleTable([hashtable]$contents, [string]$module) {
  $t = $contents[$module]
  if ($null -eq $t) {
    $t = @{}
    $contents[$module] = $t
  }
  if (-not ($t -is [hashtable])) {
    $t = [hashtable]$t
    $contents[$module] = $t
  }
  return $t
}

$patches = @(
  # Tool invocation approvals (buttons)
  @{ module='vs/workbench/contrib/chat/browser/widget/chatContentParts/toolInvocationParts/chatExtensionsInstallToolSubPart'; key='allow'; value='允许' },
  @{ module='vs/workbench/contrib/chat/browser/widget/chatContentParts/toolInvocationParts/chatTerminalToolConfirmationSubPart'; key='tool.allow'; value='允许' },
  @{ module='vs/workbench/contrib/chat/browser/widget/chatContentParts/toolInvocationParts/chatTerminalToolConfirmationSubPart'; key='tool.skip'; value='跳过' },
  @{ module='vs/workbench/contrib/chat/browser/widget/chatContentParts/toolInvocationParts/abstractToolConfirmationSubPart'; key='skip'; value='跳过' },
  @{ module='vs/workbench/contrib/chat/browser/widget/chatContentParts/toolInvocationParts/chatToolConfirmationSubPart'; key='allow'; value='允许' },
  @{ module='vs/workbench/contrib/chat/browser/widget/chatContentParts/toolInvocationParts/chatToolPostExecuteConfirmationPart'; key='allow'; value='允许' },

  # Chat tool actions
  @{ module='vs/workbench/contrib/chat/browser/actions/chatToolActions'; key='chat.skip'; value='跳过' },

  # Chat codeblock content
  @{ module='vs/workbench/contrib/chat/browser/widget/chatContentParts/chatMarkdownContentPart'; key='chat.codeblock.edited'; value='已编辑' },

  # Agent sessions view
  @{ module='vs/workbench/contrib/chat/browser/widgetHosts/viewPane/chatViewPane'; key='sessions'; value='会话' },
  @{ module='vs/workbench/contrib/chat/browser/widgetHosts/viewPane/chatViewPane'; key='newSession'; value='新建会话' },
  @{ module='vs/workbench/contrib/chat/browser/agentSessions/experiments/unifiedQuickAccess'; key='agentSessionsTab'; value='会话' },
  @{ module='vs/workbench/contrib/chat/browser/agentSessions/agentSessionsViewer'; key='agentSessionInProgress'; value='进行中' },
  @{ module='vs/workbench/contrib/chat/browser/agentSessions/agentSessionsViewer'; key='agentSessions.inProgressSection'; value='进行中' },
  @{ module='vs/workbench/contrib/chat/browser/agentSessions/agentSessionHoverWidget'; key='agentSessionInProgress'; value='进行中' },
  @{ module='vs/workbench/contrib/chat/browser/agentSessions/agentSessionsFilter'; key='agentSessionStatus.inProgress'; value='进行中' },
  @{ module='vs/workbench/contrib/editTelemetry/browser/editStats/aiStatsStatusBar'; key='viewBySessions'; value='按会话查看' },

  # Agent sessions context menu
  @{ module='vs/workbench/contrib/chat/browser/agentSessions/agentSessionsActions'; key='chat.openSessionInEditorGroup.label'; value='作为编辑器打开' },
  @{ module='vs/workbench/contrib/chat/browser/agentSessions/agentSessionsActions'; key='chat.openSessionInNewEditorGroup.label'; value='在一侧打开' },
  @{ module='vs/workbench/contrib/chat/browser/agentSessions/agentSessionsActions'; key='chat.openSessionInNewWindow.label'; value='在新窗口中打开' },
  @{ module='vs/workbench/contrib/chat/browser/agentSessions/agentSessionsActions'; key='markUnread'; value='标记为未读' },
  @{ module='vs/workbench/contrib/chat/browser/agentSessions/agentSessionsActions'; key='markAllRead.label'; value='全部标记为已读' },
  @{ module='vs/workbench/contrib/chat/browser/agentSessions/agentSessionsActions'; key='markSectionRead'; value='全部标记为已读' },
  @{ module='vs/workbench/contrib/chat/browser/agentSessions/agentSessionsActions'; key='archive'; value='归档' },
  @{ module='vs/workbench/contrib/chat/browser/agentSessions/agentSessionsActions'; key='archiveAllSessions.archive'; value='归档' },
  @{ module='vs/workbench/contrib/chat/browser/agentSessions/agentSessionsPicker'; key='archiveSession'; value='归档' },
  @{ module='vs/workbench/contrib/chat/browser/agentSessions/agentSessionsActions'; key='rename'; value='重命名...' },
  @{ module='vs/workbench/contrib/chat/browser/agentSessions/agentSessionsActions'; key='delete'; value='删除...' },

  # Chat customization menu
  @{ module='vs/workbench/contrib/chat/browser/actions/chatCustomizationDiagnosticsAction'; key='chat.diagnostics.label'; value='诊断' },
  @{ module='vs/workbench/contrib/chat/browser/actions/chatCustomizationDiagnosticsAction'; key='status.type.skills'; value='技能' },
  @{ module='vs/workbench/contrib/chat/browser/actions/chatCustomizationDiagnosticsAction'; key='status.type.hooks'; value='钩子' },
  @{ module='vs/workbench/contrib/chat/browser/promptSyntax/skillActions'; key='configure-skills.short'; value='配置技能...' },
  @{ module='vs/workbench/contrib/chat/browser/promptSyntax/hookActions'; key='commands.hooks.title'; value='钩子' },
  @{ module='vs/workbench/contrib/chat/browser/promptSyntax/hookActions'; key='configure-hooks.short'; value='配置钩子...' },

  # Agent sessions time group headers + archive
  @{ module='vs/workbench/contrib/chat/browser/agentSessions/agentSessionsViewer'; key='agentSessions.todaySection'; value='今天' },
  @{ module='vs/workbench/contrib/chat/browser/agentSessions/agentSessionsViewer'; key='agentSessions.yesterdaySection'; value='昨天' },
  @{ module='vs/workbench/contrib/chat/browser/agentSessions/agentSessionsViewer'; key='agentSessions.weekSection'; value='过去一周' },
  @{ module='vs/workbench/contrib/chat/browser/agentSessions/agentSessionsViewer'; key='agentSessions.olderSection'; value='更早' },
  @{ module='vs/workbench/contrib/chat/browser/agentSessions/agentSessionsViewer'; key='agentSessions.archivedSection'; value='已归档' },
  @{ module='vs/workbench/contrib/chat/browser/agentSessions/agentSessionsViewer'; key='agentSessions.archivedSectionWithCount'; value='已归档 ({0})' },
  @{ module='vs/workbench/contrib/chat/browser/agentSessions/agentSessionsFilter'; key='agentSessions.filter.archived'; value='已归档' },
  @{ module='vs/workbench/contrib/chat/browser/agentSessions/agentSessionHoverWidget'; key='tooltip.archived'; value='已归档' },

  # Generic date
  @{ module='vs/base/common/date'; key='today'; value='今天' },
  @{ module='vs/base/common/date'; key='yesterday'; value='昨天' },

  # References footer
  @{ module='vs/workbench/contrib/chat/browser/widget/chatContentParts/chatReferencesContentPart'; key='usedReferencesSingular'; value='使用了 {0} 个引用' },
  @{ module='vs/workbench/contrib/chat/browser/widget/chatContentParts/chatReferencesContentPart'; key='usedReferencesPlural'; value='使用了 {0} 个引用' },

  # Working... progress labels
  @{ module='vs/workbench/contrib/chat/browser/widget/chatListRenderer'; key='working'; value='工作中' },
  @{ module='vs/workbench/contrib/chat/browser/agentSessions/agentSessionsViewer'; key='chat.session.status.inProgress'; value='工作中...' },
  @{ module='vs/workbench/contrib/chat/browser/widget/chatContentParts/chatProgressContentPart'; key='workingMessage'; value='工作中...' },
  @{ module='vs/workbench/contrib/chat/browser/widget/chatContentParts/chatThinkingContentPart'; key='chat.thinking.header'; value='工作中...' },
  @{ module='vs/workbench/contrib/inlineChat/browser/inlineChatController'; key='loading'; value='工作中...' },
  @{ module='vs/workbench/contrib/inlineChat/browser/inlineChatOverlayWidget'; key='working'; value='工作中...' },

  # Chat setup progress
  @{ module='vs/workbench/contrib/chat/browser/chatSetup/chatSetupController'; key='setupChatProgress'; value='正在准备聊天...' },
  @{ module='vs/workbench/contrib/chat/browser/chatSetup/chatSetupProviders'; key='waitingChat'; value='正在准备聊天...' },
  @{ module='vs/workbench/contrib/chat/browser/chatSetup/chatSetupProviders'; key='installingChat'; value='正在准备聊天...' },

  # Agent todo list tool messages
  @{ module='vs/workbench/contrib/chat/common/tools/builtinTools/manageTodoListTool'; key='todo.created.single'; value='已创建 1 个待办事项' },
  @{ module='vs/workbench/contrib/chat/common/tools/builtinTools/manageTodoListTool'; key='todo.created.multiple'; value='已创建 {0} 个待办事项' },
  @{ module='vs/workbench/contrib/chat/common/tools/builtinTools/manageTodoListTool'; key='todo.starting'; value='开始：*{0}*（{1}/{2}）' },
  @{ module='vs/workbench/contrib/chat/common/tools/builtinTools/manageTodoListTool'; key='todo.updated'; value='已更新待办事项列表' },
  @{ module='vs/workbench/contrib/chat/common/tools/builtinTools/manageTodoListTool'; key='todo.updatedList'; value='已更新待办事项列表' },

  # Thinking status variants
  @{ module='vs/workbench/contrib/chat/browser/widget/chatContentParts/chatThinkingContentPart'; key='chat.thinking.thinking.3'; value='正在考虑…' },

  # Tool / agent status messages
  @{ module='vs/workbench/contrib/chat/browser/widget/chatContentParts/chatSubagentContentPart'; key='chat.subagent.defaultDescription'; value='正在运行子代理…' },
  @{ module='vs/workbench/contrib/chat/browser/widget/chatContentParts/chatWorkspaceEditContentPart'; key='created'; value='已创建 []({0})' },
  @{ module='vs/workbench/contrib/chat/browser/widget/chatContentParts/toolInvocationParts/chatTerminalToolProgressPart'; key='chat.terminal.running.prefix'; value='正在运行' },

  @{ module='vs/workbench/contrib/terminalContrib/chatAgentTools/browser/tools/task/createAndRunTaskTool'; key='copilotChat.runningTask'; value='正在运行任务 `{0}`' },
  @{ module='vs/workbench/contrib/terminalContrib/chatAgentTools/browser/tools/task/createAndRunTaskTool'; key='createdTask'; value='已创建任务 `{0}`' },
  @{ module='vs/workbench/contrib/terminalContrib/chatAgentTools/browser/tools/task/createAndRunTaskTool'; key='createdTaskPast'; value='已创建任务 `{0}`' },
  @{ module='vs/workbench/contrib/terminalContrib/chatAgentTools/browser/tools/task/runTaskTool'; key='chat.runningTask'; value='正在运行 `{0}`' },

  @{ module='vs/workbench/contrib/testing/common/testingChatAgentTool'; key='runTestTool.confirm.invocation'; value='正在运行测试…' },

  # Terminal await tool status
  @{ module='vs/workbench/contrib/terminalContrib/chatAgentTools/browser/tools/awaitTerminalTool'; key='await.past'; value='已等待终端执行完成' },
  @{ module='vs/workbench/contrib/terminalContrib/chatAgentTools/browser/tools/awaitTerminalTool'; key='await.progressive'; value='正在等待终端执行完成' },

  # Tool confirmation service (allow in session/workspace/global)
  @{ module='vs/workbench/contrib/chat/browser/tools/languageModelToolsConfirmationService'; key='allowSession'; value='在此会话中允许' },
  @{ module='vs/workbench/contrib/chat/browser/tools/languageModelToolsConfirmationService'; key='allowSessionTooltip'; value='允许此工具在此会话中运行而无需确认。' },
  @{ module='vs/workbench/contrib/chat/browser/tools/languageModelToolsConfirmationService'; key='allowWorkspace'; value='在此工作区中允许' },
  @{ module='vs/workbench/contrib/chat/browser/tools/languageModelToolsConfirmationService'; key='allowWorkspaceTooltip'; value='允许此工具在此工作区中运行而无需确认。' },
  @{ module='vs/workbench/contrib/chat/browser/tools/languageModelToolsConfirmationService'; key='allowGlobally'; value='始终允许' },
  @{ module='vs/workbench/contrib/chat/browser/tools/languageModelToolsConfirmationService'; key='allowGloballyTooltip'; value='始终允许此工具运行而无需确认。' },

  @{ module='vs/workbench/contrib/chat/browser/tools/languageModelToolsConfirmationService'; key='allowServerSession'; value='在此会话中允许来自 {0} 的工具' },
  @{ module='vs/workbench/contrib/chat/browser/tools/languageModelToolsConfirmationService'; key='allowServerSessionTooltip'; value='允许此服务器的所有工具在此会话中运行而无需确认。' },
  @{ module='vs/workbench/contrib/chat/browser/tools/languageModelToolsConfirmationService'; key='allowServerWorkspace'; value='在此工作区中允许来自 {0} 的工具' },
  @{ module='vs/workbench/contrib/chat/browser/tools/languageModelToolsConfirmationService'; key='allowServerWorkspaceTooltip'; value='允许此服务器的所有工具在此工作区中运行而无需确认。' },
  @{ module='vs/workbench/contrib/chat/browser/tools/languageModelToolsConfirmationService'; key='allowServerGlobally'; value='始终允许来自 {0} 的工具' },
  @{ module='vs/workbench/contrib/chat/browser/tools/languageModelToolsConfirmationService'; key='allowServerGloballyTooltip'; value='始终允许来自此服务器的所有工具运行而无需确认。' },

  @{ module='vs/workbench/contrib/chat/browser/tools/languageModelToolsConfirmationService'; key='allowSessionPost'; value='在此会话中允许且无需复核' },
  @{ module='vs/workbench/contrib/chat/browser/tools/languageModelToolsConfirmationService'; key='allowSessionPostTooltip'; value='允许在此会话中无需确认就发送此工具的结果。' },
  @{ module='vs/workbench/contrib/chat/browser/tools/languageModelToolsConfirmationService'; key='allowWorkspacePost'; value='在此工作区中允许且无需复核' },
  @{ module='vs/workbench/contrib/chat/browser/tools/languageModelToolsConfirmationService'; key='allowWorkspacePostTooltip'; value='允许在此工作区中无需确认就发送此工具的结果。' },
  @{ module='vs/workbench/contrib/chat/browser/tools/languageModelToolsConfirmationService'; key='allowGloballyPost'; value='始终允许且无需复核' },
  @{ module='vs/workbench/contrib/chat/browser/tools/languageModelToolsConfirmationService'; key='allowGloballyPostTooltip'; value='始终允许在无需确认的情况下发送结果。' },

  @{ module='vs/workbench/contrib/chat/browser/tools/languageModelToolsConfirmationService'; key='allowServerSessionPost'; value='在此会话中允许来自 {0} 的工具且无需复核' },
  @{ module='vs/workbench/contrib/chat/browser/tools/languageModelToolsConfirmationService'; key='allowServerSessionPostTooltip'; value='允许在此会话中无需确认就发送此服务器所有工具的结果。' },
  @{ module='vs/workbench/contrib/chat/browser/tools/languageModelToolsConfirmationService'; key='allowServerWorkspacePost'; value='在此工作区中允许来自 {0} 的工具且无需复核' },
  @{ module='vs/workbench/contrib/chat/browser/tools/languageModelToolsConfirmationService'; key='allowServerWorkspacePostTooltip'; value='允许在此工作区中无需确认就发送此服务器所有工具的结果。' },
  @{ module='vs/workbench/contrib/chat/browser/tools/languageModelToolsConfirmationService'; key='allowServerGloballyPost'; value='始终允许来自 {0} 的工具且无需复核' },
  @{ module='vs/workbench/contrib/chat/browser/tools/languageModelToolsConfirmationService'; key='allowServerGloballyPostTooltip'; value='始终允许在无需确认的情况下发送来自此服务器所有工具的结果。' },

  # Terminal run-in-terminal auto-approve dropdown
  @{ module='vs/workbench/contrib/terminalContrib/chatAgentTools/browser/runInTerminalHelpers'; key='autoApprove.exactCommand1'; value='在此会话中允许完全匹配的命令行' },
  @{ module='vs/workbench/contrib/terminalContrib/chatAgentTools/browser/runInTerminalHelpers'; key='autoApprove.exactCommand2'; value='在此工作区中允许完全匹配的命令行' },
  @{ module='vs/workbench/contrib/terminalContrib/chatAgentTools/browser/runInTerminalHelpers'; key='autoApprove.exactCommand'; value='始终允许完全匹配的命令行' },
  @{ module='vs/workbench/contrib/terminalContrib/chatAgentTools/browser/runInTerminalHelpers'; key='allowSession'; value='允许此会话中的所有命令' },
  @{ module='vs/workbench/contrib/terminalContrib/chatAgentTools/browser/runInTerminalHelpers'; key='allowSessionTooltip'; value='允许此工具在此会话中运行而无需确认。' },
  @{ module='vs/workbench/contrib/terminalContrib/chatAgentTools/browser/runInTerminalHelpers'; key='autoApprove.configure'; value='配置自动审批...' },

  # Chat queue actions (input menu)
  @{ module='vs/workbench/contrib/chat/browser/widget/input/chatQueuePickerActionItem'; key='chat.sendImmediately'; value='停止并发送' },
  @{ module='vs/workbench/contrib/chat/browser/actions/chatQueueActions'; key='chat.queueMessage'; value='加入队列' },
  @{ module='vs/workbench/contrib/chat/browser/actions/chatQueueActions'; key='chat.steerWithMessage'; value='用消息引导' }
)

# Verified publisher strings (Extensions / MCP)
$patches += @(
  @{ module='vs/workbench/contrib/extensions/browser/extensionsViewer'; key='extension.arialabel.verifiedPublisher'; value='已验证发布者 {0}' },
  @{ module='vs/workbench/contrib/extensions/browser/extensionsWidgets'; key='verified publisher'; value='此发布者已验证对 {0} 的所有权' },
  @{ module='vs/workbench/contrib/extensions/browser/extensionsWidgets'; key='publisher verified tooltip'; value='此发布者已验证对 {0} 的所有权' },
  @{ module='vs/workbench/contrib/mcp/browser/mcpServerWidgets'; key='verified publisher'; value='此发布者已验证对 {0} 的所有权' },
  @{ module='vs/workbench/services/extensionManagement/common/extensionManagementService'; key='verifiedPublisherWithName'; value='{0} 已验证对 {1} 的所有权。' },
  @{ module='vs/workbench/services/extensionManagement/common/extensionManagementService'; key='unverifiedPublisherWithName'; value='{0} [**未**验证]({1})。' },
  @{ module='vs/workbench/services/extensionManagement/common/extensionManagementService'; key='unverifiedPublishers'; value='{0} 和 {1} [**未**验证]({2})。' },
  @{ module='vs/workbench/services/extensionManagement/common/extensionManagementService'; key='allUnverifed'; value='所有发布者均[**未**验证]({0})。' }
)

function ConvertTo-NlsNormalizedMessage([string]$s) {
  if ($null -eq $s) { return $null }
  $s = $s -replace '&', ''
  $s = $s -replace '\.\.\.', '…'
  return $s
}

try {
  $indexMapForAuto = Get-VSCodeCoreNlsIndexMap

  $existing = @{}
  foreach ($p in $patches) {
    $existing["$($p.module)::$($p.key)"] = $true
  }

  $autoExactMap = @{
    'Working'        = '工作中'
    'Working…'       = '工作中…'
    'Processing…'    = '处理中…'
    'Evaluating…'    = '评估中…'
    'Thinking'       = '思考中'
    'Thinking…'      = '思考中…'
    'Thinking: {0}'  = '思考中：{0}'
  }

  $autoStatus = @()
  foreach ($id in $indexMapForAuto.Keys) {
    $msg = $indexMapForAuto[$id].message
    $norm = ConvertTo-NlsNormalizedMessage $msg
    $value = $autoExactMap[$norm]
    if ($null -eq $value) { continue }
    if ($existing.ContainsKey($id)) {
      continue
    }

    $parts = $id -split '::', 2
    if ($parts.Count -ne 2) {
      continue
    }

    $autoStatus += @{ module = $parts[0]; key = $parts[1]; value = $value }
    $existing[$id] = $true
  }

  if ($autoStatus.Count -gt 0) {
    $patches += $autoStatus
    Write-Host "Auto patches (status): $($autoStatus.Count)"
  }
} catch {
  Write-Host "Auto patches (status): skipped ($($_.Exception.Message))"
}

$changes = 0
foreach ($p in $patches) {
  $t = Get-OrCreateModuleTable -contents $contents -module $p.module
  $before = $t[$p.key]
  if ($before -ne $p.value) {
    $t[$p.key] = $p.value
    $changes++
  }
}

Write-Host "Language pack: $LanguagePackMainI18n"
Write-Host "Patches applied/updated: $changes"

$clpChanges = 0
$clpPath = Get-ActiveClpNlsMessagesPath
if ($null -ne $clpPath) {
  $indexMap = Get-VSCodeCoreNlsIndexMap
  $clpMessages = Get-Content -Raw -Encoding UTF8 $clpPath | ConvertFrom-Json

  foreach ($p in $patches) {
    $id = "$($p.module)::$($p.key)"
    $info = $indexMap[$id]
    if ($null -eq $info) {
      continue
    }
    $idx = [int]$info.index
    $before = $clpMessages[$idx]
    if ($before -ne $p.value) {
      $clpMessages[$idx] = $p.value
      $clpChanges++
    }
  }

  Write-Host "CLP cache: $clpPath"
  Write-Host "CLP patches applied/updated: $clpChanges"
} else {
  Write-Host 'CLP cache: <not found> (will rely on language pack file only)'
}

if ($DryRun) {
  Write-Host 'DryRun=ON：不写入文件。'
  exit 0
}

$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$bak = "$LanguagePackMainI18n.bak.$timestamp"
Copy-Item -Path $LanguagePackMainI18n -Destination $bak -Force

($doc | ConvertTo-Json -Depth 100) + "`n" | Set-Content -Encoding UTF8 -Path $LanguagePackMainI18n
Write-Host "Wrote: $LanguagePackMainI18n"
Write-Host "Backup: $bak"

if ($null -ne $clpPath -and $clpChanges -gt 0) {
  $timestamp2 = Get-Date -Format 'yyyyMMdd_HHmmss'
  $bak2 = "$clpPath.bak.$timestamp2"
  Copy-Item -Path $clpPath -Destination $bak2 -Force
  ($clpMessages | ConvertTo-Json -Compress) + "`n" | Set-Content -Encoding UTF8 -Path $clpPath
  Write-Host "Wrote: $clpPath"
  Write-Host "Backup: $bak2"
}
