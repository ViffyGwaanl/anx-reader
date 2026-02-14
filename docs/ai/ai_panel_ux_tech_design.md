# AI Panel UX Tech Design (iPad-first)

> 本文面向工程实现，尽量可直接转成 PR checklist。

## 1. Goals / Non-goals

### Goals

1. **iPad dock split panel**：分割条触摸友好（大热区 + 可视手柄），支持拖拽调整宽/高，并**持久化**。
2. **iPad optional bottom sheet**：允许在设置中切换为 iPhone 风格 bottom sheet，且 sheet 高度可拖拽，并持久化。
3. **Dock side switch**：iPad dock 模式支持左/右停靠，默认保持右侧。
4. **Gesture conflict**：当 AI 停靠左侧时，避免与左侧 TOC Drawer 的边缘手势冲突（允许 TOC 覆盖 AI 面板）。
5. **AI chat font scale**：AI 面板内字体缩放（Markdown + 输入框），持久化。
6. **Input quick prompts**：输入区快捷提示词 chip 可配置（增删改、排序、启用/禁用）。
7. **User prompt max length**：用户自定义 prompt 长度上限提升至 **20,000**。

### Non-goals

- 不做全书 embeddings/RAG（已确认现阶段不优先）。
- 不通过 WebDAV 同步 API key（安全策略）。

## 2. Current Implementation Summary (fork)

> 这些改动已在分支栈中实现，见 `docs/ai/README.md`。

### 2.1 Dock resize + persistence

- 文件：`lib/page/reading_page.dart`
- Prefs：`aiPanelWidth`, `aiPanelHeight`
- 拖拽分割条：
  - HitTest 行为：`HitTestBehavior.opaque`
  - 热区宽/高：16px
  - 手柄：`Icons.drag_indicator`
  - 触觉反馈：`HapticFeedback.selectionClick()`（drag start）
- 结束拖拽持久化：`Prefs().aiPanelWidth/_Height`

### 2.2 Bottom sheet (fixed large size)

> 早期实现为可拖拽调整高度的 `DraggableScrollableSheet`（见 PR-2），但在真机触摸下“难以精确控制”。
> PR-8 将其收敛为“固定大尺寸 + 系统下滑关闭”的稳定交互。

- 文件：
  - `lib/widgets/ai/ai_chat_bottom_sheet.dart`
  - `lib/page/reading_page.dart`（showAiChat 小屏入口）
- 实现：固定高度 `SizedBox(height: screenHeight * 0.95)`
  - 不提供“按住调大小”的交互
  - 依赖 `showModalBottomSheet` 默认的 **下滑关闭**
- Prefs：
  - 仍保留 `aiSheetInitialSize`（历史兼容；当前 fixed-size 版本不再使用）

### 2.3 iPad panel mode + dock side

- 新增 enums：
  - `lib/enums/ai_pad_panel_mode.dart`（dock/bottomSheet）
  - `lib/enums/ai_dock_side.dart`（left/right）
- Prefs：`aiPadPanelMode`, `aiDockSide`
- 阅读页布局：`_buildMainLayout()` 根据 side 重排 children
- drawer 手势冲突：`drawerEnableOpenDragGesture: false`（dock-left 且 AI 面板显示时）

### 2.4 AI chat font scale

- Prefs：`aiChatFontScale`（默认 1.0）
- UI：AI Chat AppBar 增加 `Icons.text_fields`
  - PR-8：使用 `AlertDialog` 承载 slider（避免在 bottom sheet 内再开 bottom sheet 导致自动消失）
- 应用：`MediaQuery.copyWith(textScaler: TextScaler.linear(scale))`

### 2.5 Configurable input quick prompts

- Model：`lib/models/ai_input_quick_prompt.dart`
- Prefs：`aiInputQuickPrompts`（JSON list；空表示用默认本地化 prompt）
- UI editor：`lib/page/settings_page/ai_quick_prompts_editor.dart`

## 3. UX Specs

### 3.0 Quick entry gesture (bottom sheet mode)

- 目标：在 bottom sheet 模式下，无需先唤出菜单再点击 AI。
- 交互：从阅读页面**中下部区域**向上滑动即可打开 AI bottom sheet。
- 设计约束：
  - 只在 bottom sheet 模式启用（小屏 iPhone / iPad 设置为 bottomSheet）
  - 手势捕获区域建议为屏幕宽度 50%（中间），高度约 120–160px（靠底部），避免干扰阅读/翻页
  - 触发阈值：上滑位移 ~40px 或上滑速度阈值（例如 -500 px/s）


### 3.1 iPad Dock Resize

- Divider hit target: **>= 16pt** (推荐 16–24)
- Resizing overlay: when dragging, show a full-screen transparent layer intercepting touches (already present via `_isResizingAiChat` overlay)
- Clamp:
  - width min: 240
  - height min: 200
  - max: percentage cap (currently width 65%, height 60%) and remaining space cap
- Persistence:
  - Persist on drag end
  - Restore in `initState()`

### 3.2 iPad Dock Side

- Default: right
- When dock-left:
  - AI panel order: `[AI panel][divider][reader]`
  - Drawer edge swipe: disabled to avoid conflicts
  - TOC still opens via button (drawer)

### 3.3 iPad Panel Mode

- Setting key: `aiPadPanelMode` (dock / bottomSheet)
- Behavior:
  - If `bottomSheet`: `showModalBottomSheet` even when `width>=600`
  - If `dock`: use split panel

### 3.4 Font Scale

- Range: 0.8–1.4 (can be adjusted)
- Reset: 1.0

### 3.5 Input Quick Prompts

- Default prompts (localized): 解释/看法/总结/分析/建议
- Custom prompts:
  - reorder
  - enable/disable
  - edit label + text
  - reset to defaults (clear pref)

## 4. Preference Keys

| Key | Type | Default | Notes |
|-----|------|---------|------|
| aiPanelWidth | double | 300 | dock width |
| aiPanelHeight | double | 300 | dock bottom height |
| aiSheetInitialSize | double | 0.6 | sheet initial extent |
| aiPadPanelMode | string | dock | dock/bottomSheet |
| aiDockSide | string | right | left/right |
| aiChatFontScale | double | 1.0 | 0.8–1.4 |
| aiInputQuickPrompts | string(JSON) | unset | empty means use defaults |

## 5. Testing Checklist

- iPad (>=600 width):
  - dock-right resize width persists
  - dock-bottom resize height persists
  - dock-left layout order correct
  - dock-left drawer edge swipe disabled; TOC button works
  - switching `aiPadPanelMode` changes behavior
- iPhone (<600 width):
  - bottom sheet opens at large fixed height (~95%)
  - swipe down dismiss works
  - swipe up from lower-middle area opens AI (no menu tap needed)
- AI chat:
  - font scale slider affects markdown + input
  - custom quick prompts appear in input row
- Regression:
  - no crash when prefs missing

