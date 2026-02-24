# AI Panel UX Tech Design (iPad-first)

> 本文面向工程实现，尽量可直接转成 PR checklist。

## 1. Goals / Non-goals

### Goals

1. **iPad dock split panel**：分割条触摸友好（大热区 + 可视手柄），支持拖拽调整宽/高，并**持久化**。
2. **iPad optional bottom sheet**：允许在设置中切换为 iPhone 风格 bottom sheet，且可最小化为 bar（继续阅读）。
3. **Dock side switch**：iPad dock 模式支持左/右停靠，默认保持右侧。
4. **Gesture conflict**：当 AI 停靠左侧时，避免与左侧 TOC Drawer 的边缘手势冲突（允许 TOC 覆盖 AI 面板）。
5. **AI chat font scale**：AI 面板内字体缩放（Markdown + 输入框），持久化。
6. **Input quick prompts**：输入区快捷提示词 chip 可配置（增删改、排序、启用/禁用）。
7. **User prompt max length**：用户自定义 prompt 长度上限提升至 **20,000**。
8. **Streaming reliability**：阅读页 bottom sheet 最小化/关闭时，流式生成不应被 UI 生命周期打断。

### Non-goals

- 不做全书 embeddings/RAG（已确认现阶段不优先）。
- 不通过 WebDAV 同步 API key（安全策略）。

## 2. Current Implementation Summary (fork)

### 2.1 Dock resize + persistence

- 文件：`lib/page/reading_page.dart`
- Prefs：`aiPanelWidth`, `aiPanelHeight`
- 拖拽分割条：
  - 热区：16px+
  - 手柄：`Icons.drag_indicator`
  - 触觉反馈：`HapticFeedback.selectionClick()`（drag start）
- 结束拖拽持久化：`Prefs().aiPanelWidth/_Height`

### 2.2 Bottom sheet (resizable + minimizable)

- 文件：
  - `lib/widgets/ai/ai_chat_bottom_sheet.dart`
  - `lib/page/reading_page.dart`（reading page 入口）
- 实现：`DraggableScrollableSheet`
  - `minChildSize = 0.12`（最小化 bar）
  - `maxChildSize = 0.95`
  - snapSizes: `[0.12, 0.35, 0.6, 0.9, 0.95]`
  - reading page 默认打开为展开（0.95）

### 2.3 Provider-managed streaming (root-cause fix)

> 这是为了解决“缩小 bottom sheet 会断流”的根因。

- 旧架构：streaming 由 UI widget 持有 `StreamSubscription` → UI rebuild/dispose 时容易中断。
- 新架构：streaming 由 `aiChatProvider` (keepAlive) 持有订阅，并逐 chunk 更新 provider state。
- UI（`AiChatStream`）只负责渲染 provider state。

关键入口：

- `lib/providers/ai_chat.dart`
  - `startStreaming(...)`
  - `cancelStreaming()`
  - `aiChatStreamingProvider`

### 2.4 iPad panel mode + dock side

- Enums：
  - `lib/enums/ai_pad_panel_mode.dart`（dock/bottomSheet）
  - `lib/enums/ai_dock_side.dart`（left/right）
- Prefs：`aiPadPanelMode`, `aiDockSide`
- drawer 手势冲突：`drawerEnableOpenDragGesture: false`（dock-left 且 AI 面板显示时）

### 2.5 Font Scale

- Prefs：`aiChatFontScale`（默认 1.0）
- 应用：`MediaQuery.copyWith(textScaler: TextScaler.linear(scale))`

### 2.6 Input quick prompts

- Prefs：`aiInputQuickPrompts`（JSON list；空表示用默认本地化 prompt）
- UI editor：`lib/page/settings_page/ai_quick_prompts_editor.dart`

## 3. UX Specs

### 3.1 Quick entry + minimize

- reading page bottom sheet 模式：
  - 打开后可拖到最小 bar，继续阅读
  - bar 状态下依然可再次拖回展开

### 3.2 Auto-scroll policy

- 打开面板不自动跳到底
- streaming 时仅当用户处于“贴底”状态才自动滚动

## 4. Preference Keys

| Key | Type | Default | Notes |
|-----|------|---------|------|
| aiPanelWidth | double | 300 | dock width |
| aiPanelHeight | double | 300 | dock bottom height |
| aiSheetInitialSize | double | 0.6 | (legacy) sheet initial extent; reading page opens expanded |
| aiPadPanelMode | string | dock | dock/bottomSheet |
| aiDockSide | string | right | left/right |
| aiChatFontScale | double | 1.0 | 0.8–1.4 |
| aiInputQuickPrompts | string(JSON) | unset | empty means use defaults |

## 5. Testing Checklist (high priority)

- iPad dock:
  - resize persists
  - dock-left drawer edge swipe disabled
- bottom sheet:
  - minimize/expand works
  - minimize does **not** interrupt streaming
  - close sheet does **not** interrupt streaming (provider-owned)
