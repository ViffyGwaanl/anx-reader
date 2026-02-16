# PR-10 计划：AI 翻译体验重做（参考 epub-translator）

> 目标：把 Anx Reader 的“选中翻译”和“全文（内联）翻译”拆成两个清晰的产品形态：
> - **选中翻译**：保留“翻译 + 讲解/词汇/注释”的学习型体验（当前 `AiPrompts.translate` 更适合这里）。
> - **全文翻译（EPUB 内联）**：输出必须是 **纯译文**，禁止出现解释/标题/词典结构，否则会污染正文排版。
>
> 参考项目：`oomol-lab/epub-translator`（MIT）
> - 核心思路：**翻译任务与结构填充/呈现解耦**、控制并发（concurrency）、限制每组输入规模（max_group_tokens）、缓存进度（cache_path）、并提供 REPLACE/APPEND 等提交模式。

---

## 0. 背景：现状与问题

### 0.1 现有实现路径（Anx Reader）
- EPUB 全文翻译由 `foliate-js` 实现：`assets/foliate-js/src/translator.js`
  - JS 通过 `window.flutter_inappwebview.callHandler('translateText', text)` 调 Flutter
- Flutter 侧 handler：`lib/page/book_player/epub_player.dart`（`translateText` handler）
  - 调用：`Prefs().fullTextTranslateService.provider.translateTextOnly(...)`
- AI 翻译 provider：`lib/service/translate/ai.dart`
  - 使用 prompt：`AiPrompts.translate`

### 0.2 现存问题
1) **全文翻译输出“像讲解”**
- 当前 `AiPrompts.translate` 设计为“Translation & Reference（翻译 + 讲解 + glossary + encyclopedia）”。
- 在 EPUB 内联翻译里会把分析块插入正文 → 观感非常差。

2) **请求过长 & 失败率高**
- 章节/段落较长时，AI provider 更容易 timeout 或触发网关限制。

3) **并发与限流风险**
- IntersectionObserver 会触发很多元素翻译；如果没有并发控制，会产生爆发式请求，易 429。

---

## 1. 目标（PR-10 DoD）

### 必须达成（P0）
- EPUB 全文翻译（内联）在 AI 模式下：**只输出译文**（不出现“解释/词汇表/标题/编号/markdown”）。
- 选中翻译（划线翻译）保持现有“学习型翻译”体验。
- 对长文本有可控的 chunking 策略（防超时/失败）。
- 有并发控制（避免快速翻页/滚动导致 API 风暴）。

### 期望达成（P1）
- 基于输入文本的缓存（减少重复请求；scroll/回到上一页时更稳）。
- 失败重试与降级：失败时不污染正文（例如返回空串/简短错误），并可在日志中定位。

---

## 2. 参考 epub-translator 的可迁移设计点

（不复用代码，只借鉴工程结构）

1) **提交模式（SubmitKind）**
- epub-translator 有 REPLACE / APPEND_TEXT / APPEND_BLOCK。
- Anx Reader `translator.js` 已有类似的显示模式：
  - OFF / ORIGINAL_ONLY / TRANSLATION_ONLY / BILINGUAL
- 对应策略：全文翻译场景使用“append block”（译文单独成块）最清晰；但要求译文本身必须干净。

2) **限制每次处理规模（max_group_tokens）**
- 我们用 `maxChunkChars` 近似（不引入 token 计数器），并按段落/句子切分。

3) **并发控制（concurrency）**
- epub-translator 显式控制并发。
- 我们需要在 Flutter handler 层做队列/信号量，保证同一时刻最多 N 个 translateTextOnly 在跑。

4) **缓存（cache_path）与恢复**
- epub-translator 用 cache 保障中断可恢复。
- 我们至少做：
  - 内存 LRU（本章/本页有效）
  - 可选：磁盘 cache（按书 id + 语言对 + hash，后续再做）

---

## 3. 方案选型（建议）

### 方案 A：一个 AI TranslateService + 通过“调用方”决定 prompt
- 问题：`TranslateServiceProvider.translateTextOnly(...)` 的签名无法识别调用方（选中翻译 vs 全文翻译）。
- 不建议：会引入隐式依赖（靠全局 Prefs/状态推断），长期可维护性差。

### 方案 B（推荐）：增加一个新的 TranslateService：AI（全文纯翻译）
- 新增 `TranslateService.aiFullText`（或 `aiTranslateOnly`）
  - provider 使用新 prompt `translate_fulltext`（严格纯译文）
- 原 `TranslateService.ai` 保持“翻译+讲解”给选中翻译使用。

**优点**：调用链明确、配置可分离、回归风险更小。

---

## 4. PR-10 详细实施计划（按提交拆解）

### PR-10.1：Prompt 拆分 + 路由
- 新增 `AiPrompts.translate_fulltext`（仅全文翻译使用）
  - 默认 prompt 要求：只输出译文；保留换行；禁止解释；禁止 markdown 列表/标题。
- 新增 prompt 生成函数：`generatePromptTranslateFullText(...)`
- 新增 provider：`AiFullTextTranslateProvider`
- 新增 TranslateService：`aiFullText`（或命名更直观）
- Settings：
  - AI Settings 页面新增“全文翻译 prompt”编辑入口
  - 翻译设置页：FullTextTranslateServicePicker 里可选 `AI (translate only)`

### PR-10.2：Chunking（长度上限）
- 在 `AiFullTextTranslateProvider.translateTextOnly(...)` 内实现：
  - `maxChunkChars`（默认 800~1500，可配置为常量；后续可做成配置项）
  - 分割优先级：空行段落 > 单行换行 > 句号/问号/感叹号边界 > 兜底硬切
  - 拼接时保留原有换行结构（至少段落间保留 `\n`）

### PR-10.3：并发控制（concurrency）
- 在 `EpubPlayer` 的 `translateText` handler 层增加一个 per-webview 的队列/信号量：
  - 同时最多 N（建议默认 2）个翻译请求
  - 同一文本重复请求去重（inflight map）
- 目的：避免 IntersectionObserver 触发大量并发导致 429。

### PR-10.4：缓存与可观测性
- 内存缓存：LRU（例如 500 条）
  - key = hash(text + from + to + serviceId + model)
  - value = translation
- 与现有“AI 调试日志开关”对齐：
  - 开启后记录 chunking/队列耗时/429 重试次数

### PR-10.5：测试与验收
- 单元测试：
  - chunker 的分割与拼接（长度控制 + 换行保留）
  - provider 确认不会输出多余结构（至少通过 prompt 的 contract + golden snippet）
- 真机验收脚本（iPad）：
  1) FullTextTranslateService 选 `AI (translate only)`
  2) Reader 翻译模式切到 BILINGUAL
  3) 快速滚动/翻页 1-2 分钟，确认不卡顿、无明显 429、译文不夹带解释

---

## 5. 接口与改动点清单（工程影响评估）

### 必改文件（预计）
- `lib/service/translate/index.dart`
  - `TranslateService` enum 增加 `aiFullText`
- `lib/service/translate/ai.dart`
  - 保持为选中翻译（学习型）
- 新增 `lib/service/translate/ai_fulltext.dart`
  - 纯翻译 provider + chunking +（可选）缓存
- `lib/enums/ai_prompts.dart` + `lib/service/ai/prompt_generate.dart`
  - 新增 `translate_fulltext` prompt + generator
- `assets/foliate-js/src/translator.js`
  - 尽量不改（当前 append block 逻辑 OK），只在必要时改错误处理

### 风险点
- 引入新 TranslateService 可能影响设置页展示与旧配置迁移
  - 处理方式：旧用户不受影响；只有当用户把 FullTextTranslateService 改为 AI FullText 才启用。
- AI provider 的输出仍可能“跑偏”
  - 处理方式：prompt 强约束 + chunking + 失败时返回空/短错误而不是长解释

---

## 6. 里程碑与交付物

- 交付物 1：PR-10（代码 + docs）
- 交付物 2：真机验收 checklist（附带“开启 AI 调试日志”定位方法）

---

## 7. 开工前需要你确认的 2 个选择
1) **新 TranslateService 的名字**：
   - 选项：`AI (Full Text)` / `AI (Translate Only)` / `AI Inline`
2) **并发默认值 N**：
   - 建议：2（更稳）
   - 你如果更追求速度：4（可能更易触发限流）
