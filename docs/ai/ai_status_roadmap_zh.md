# AI 改造（fork）— 当前已完成 & 路线图（中文）

> 本文是面向 **真实实现** 的“项目状态 + 路线图”汇总，便于你随时对齐：哪些已经做完、哪些还在计划、下一步怎么验收。
>
> 集成验收分支：`feat/ai-all-in-one`

---

## 1. 背景与目标（范围边界）

核心目标：在 Anx Reader 的基础上，围绕“阅读场景中的 AI 对话面板”做 **iPad 优先** 的 UX、配置、同步与可靠性增强，并引入 Cherry 风格的 Provider Center / 对话编辑与回滚能力。

关键约束（持续有效）：

- 仅修改 Anx Reader（MIT）；Cherry Studio（AGPL）仅做 UX 灵感，禁止代码复用。
- WebDAV **不**同步 `api_key`。
- 备份：明文备份永不包含 `api_key`；只有“手动备份 + 加密”才允许携带。
- Prompt 长度上限目标：20,000 chars。

---

## 2. 已完成（按模块）

### 2.1 阅读页 AI 面板 UX（iPad / iPhone）

**iPad Dock 分屏面板**
- 分隔条可用手指拖拽调整（热区扩大、可视化手柄、触觉反馈）。
- 宽/高持久化：重新进入阅读页保持上次尺寸。
- Dock 侧边切换：支持左/右停靠（默认右侧）。
- 手势冲突治理：当 AI dock-left 且可见时，禁用 TOC drawer 左边缘滑出手势，仍可用按钮打开目录。

**Bottom Sheet 模式（iPhone + iPad 可选）**
- 使用 `DraggableScrollableSheet` 支持：
  - 可拖拽调整高度、支持 snap 点。
  - 可最小化为 bar（继续阅读）。
  - 阅读页打开默认展开（接近 95%）。

**滚动策略**
- 打开对话面板不再强制滚到底。
- streaming 期间：仅当用户处于“贴底”状态才自动跟随滚动。

---

### 2.2 关键根治：把 streaming 从 UI 迁移到 Provider（架构可靠性修复）

**问题根因（已解决）**
- 旧实现由 UI Widget 持有 `StreamSubscription`，在 bottom sheet 缩放/最小化/重建、scrollController swap、路由变化时，容易因生命周期/异常导致断流。

**根治方案（已落地）**
- streaming 由 `aiChatProvider`（keepAlive）持有订阅与状态；UI 仅渲染 provider state。
- 新增 streaming 状态 provider：`aiChatStreamingProvider`。
- 对外 API（核心语义）：
  - `startStreaming(...)`：开始生成并逐 chunk 更新会话树/消息列表。
  - `cancelStreaming()`：停止生成（调用 runner cancel + subscription cancel）。

工程收益：
- 最小化/关闭对话面板（不退出阅读页）不会打断生成。
- UI 层即使发生 rebuild，也不会直接影响流的订阅生命周期。

---

### 2.3 Provider Center（Cherry 风格，Flutter 原生实现）

- Provider Center 作为设置里的顶层入口（与 AI Settings 平级）。
- 内置 provider + 自定义 provider：支持 enable/disable、详情编辑、应用为当前 provider。
- Provider 元信息与 secret 配置分离存储：
  - `aiProvidersV1`：非敏感（可同步/可备份）。
  - `aiConfig_<providerId>`：包含本地 secrets（`api_key` 不走 WebDAV）。
  - `aiModelsCacheV1_<providerId>`：模型列表缓存（local-only，排除备份）。

---

### 2.4 Cherry 风格聊天能力（对话编辑/回滚/变体）

- In-chat provider + model 切换。
- Thinking 档位（灯泡 UI）与 Gemini `includeThoughts` 开关。
- Thinking/Answer/Tools 可折叠分区展示。
- 编辑任意 user turn + 从任意 user turn regenerate。
- assistant 变体（variants）存储与左右切换。
- **Conversation Tree v2**（`conversationV2`）持久化：支持“回滚到旧版本并保留后续分支”。

---

### 2.5 配置 / 同步 / 备份

- 输入区 quick prompt chips 可配置（增删改、排序、启用）。
- prompt 编辑器 maxLength 提升到 **20,000**。

**WebDAV 同步（已完成）**
- `anx/config/ai_settings.json`
- 冲突策略：整文件 `updatedAt` newer-wins（Phase 1）。
- 明确排除：`api_key`。

**手动备份/恢复（已完成）**
- v4 zip + manifest。
- 可选：加密携带 `api_key`（密码派生 + AES-GCM）。
- 导入具备回滚保护（避免半恢复状态）。

---

### 2.6 OpenAI-compatible “思考内容”展示兼容

- 若后端/网关返回 `reasoning_content`（或 `reasoning`），会映射到 `<think>...</think>`，从而进入 Thinking 区块展示。

---

## 3. 仍需验证（建议作为验收任务）

这些是“工程上必须用真机/真实网络压力验证”的点：

1) 阅读页：生成中最小化/展开/翻页/开关目录等操作，生成是否持续、是否有 UI 卡顿。
2) iOS 前后台切换：系统可能挂起网络/定时器；需要明确“预期行为”（继续/暂停/恢复）。
3) Provider Center 快速导航压力：是否还会触发 Flutter 依赖断言类 crash。
4) conversation tree v2：复杂分支回滚场景下，持久化一致性与 UI 同步是否稳定。

---

## 4. 未来计划（按优先级拆解）

### P0：稳定性与可观测性

- 为 streaming session 增加更明确的可观测 UI（例如 minimized bar 上的 generating 状态、可停止入口、错误提示）。
- 增加 1 个关键 widget test：验证 edit+regen 生成分支后切回旧 variant 会恢复旧子树。

### P1：OpenAI-compatible Thinking 的“兜底模式”

背景：很多 OpenAI-compatible 提供方不会返回 `reasoning_content`。

- 增加可选“thinking summary”模式：
  - 输出的是短摘要（非 chain-of-thought），安全且可控。
  - 仍走 `<think>...</think>` 展示。

### P1：AI 翻译体验（EPUB/PDF）

来自既有设计文档（仍有效）：

- 选中翻译：保留“翻译 + 讲解/词汇/注释”。
- 全文翻译：新增 `translate_fulltext` prompt，严格“只输出译文”。
- 长文本 chunking/长度上限，降低超时与失败率。
- PDF：默认引导用户用选中翻译；必要时对全文翻译加提示或默认关闭。

### P2：PDF 章节化与 OCR（MinerU）

- PDF outline 存在时：按 outline item 的页范围组合“章节内容”（多页拼接 + maxChars 截断）。
- outline 缺失时：采用 page-window（当前页 ±N 页）作为“chapter-like context”。
- 扫描版 PDF：集成 MinerU OCR，做缓存与状态机（not_started/processing/ready/failed），文本层不足时自动 fallback。

---

## 5. 分支策略（为何分这么多分支，以及后续建议）

当前策略是典型的“PR 栈 + 集成分支验收”：

- 小分支：每个分支只做一个可 review、可回滚的变更面（降低风险、降低冲突）。
- 集成分支：`feat/ai-all-in-one` 汇总所有 AI 改动用于真机安装与验收。

后续建议（工程治理）：

- docs-only 的历史分支：建议统一归档到 `archive/docs/*` 或打 tag，避免“commit 在但 ref 不在”的追溯困难。

---

## 6. 开发者注意事项

- repo 忽略生成文件（`*.g.dart`, `*.freezed.dart`, `lib/gen/` 等），切分支后必须：

```bash
flutter pub get
flutter gen-l10n
dart run build_runner build --delete-conflicting-outputs
```

---

## 7. 推荐验收清单（最小闭环）

1) 阅读页：生成中最小化 → 翻页阅读 → 展开 → 生成不断。
2) stop 按钮：立即停止（不会假停）。
3) edit+regen：生成新分支，切回旧 1/N 能回滚。
4) WebDAV sync：A 改 url/model/quickprompts → B 同步成功且 B 的 api_key 不变。
5) 备份：明文导出不含 api_key；加密导入输入正确密码可恢复。
