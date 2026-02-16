# PR-10 计划：EPUB AI 翻译（内联显示 + 导出翻译版 EPUB）（参考 epub-translator）

> 范围：**只做 EPUB**（不做 PDF）。
>
> 目标：把 Anx Reader 的“选中翻译”和“全文翻译”拆成两个明确的产品与工程路径：
> - **选中翻译（划线翻译 / Translation & Reference）**：保持现状，继续使用原来的 AI prompt（`AiPrompts.translate`），输出可包含讲解/词汇/注释。
> - **全文翻译（EPUB 内联）**：输出必须是 **纯译文**，禁止出现解释/标题/词典结构/Markdown 列表，否则会污染正文。
> - **导出翻译版 EPUB**：把整本书翻译后导出为新的 EPUB，支持两种“提交模式”（对齐 epub-translator）：
>   - `SubmitKind.REPLACE`：导出“仅译文”版（替换原文）
>   - `SubmitKind.APPEND_BLOCK`：导出“双语”版（原文 + 块级译文）
>
> 参考项目：`oomol-lab/epub-translator`（MIT）
> - 借鉴点（不复用代码）：
>   - 提交模式（REPLACE / APPEND_BLOCK）
>   - 限制每组规模（max_group_tokens）
>   - 并发控制（concurrency）
>   - 缓存/断点恢复（cache_path）
>   - 翻译提示词可自定义（user_prompt）
>   - 允许为“翻译任务”指定专用模型/配置

---

## 0. 背景：现状与关键改动点

### 0.1 现有实现路径（Anx Reader）
- EPUB 全文翻译（内联显示）由 `foliate-js` 实现：`assets/foliate-js/src/translator.js`
  - JS 调用 Flutter：`window.flutter_inappwebview.callHandler('translateText', text)`
- Flutter handler：`lib/page/book_player/epub_player.dart`（`translateText` handler）
  - 调用：`Prefs().fullTextTranslateService.provider.translateTextOnly(text, from, to)`
- AI 翻译 provider：`lib/service/translate/ai.dart`
  - 使用 prompt：`AiPrompts.translate`

### 0.2 你提出的增强需求（本 PR 的“约束”）
1) 选中翻译继续用原来的（学习型输出不变）。
2) 全文翻译：要支持“仅显示翻译”和“双语显示”。
   - 这件事 **已经在 foliate-js 里通过 TranslationMode 支持**（`TRANSLATION_ONLY` / `BILINGUAL`），我们要保证全文翻译返回的字符串是“干净译文”。
3) 提交模式（导出时）：`SubmitKind.REPLACE` / `SubmitKind.APPEND_BLOCK` **可选**。
4) 翻译结果要 **可缓存且可复用**（至少跨 session 的持久缓存）。
5) 做完“全量翻译”后可 **导出** 成翻译好的 EPUB。
6) 翻译提示词要可自定义。
7) 模型要能单独指定“翻译专用模型”（不影响聊天默认模型）。

---

## 1. Definition of Done（验收标准）

### 1.1 全文内联翻译（EPUB 阅读器）
- 当 Full-text Translation Service 选择 AI 时：
  - 输出严格为“纯译文”，不包含解释/词汇表/标题/编号/Markdown。
  - 保留换行（段落结构）尽量接近原文。
- 有并发控制（防止快速滚动导致 API 风暴）。
- 有持久缓存：同样的文本块再次出现时不会再次请求。

### 1.2 导出翻译版 EPUB
- 支持两种导出：
  - REPLACE：导出仅译文版本
  - APPEND_BLOCK：导出双语版本（原文 + 译文 block）
- 导出过程可展示进度，可取消，失败可恢复/重试（最小可行：失败提示 + 下次重来；增强：断点恢复）。

### 1.3 配置能力
- 有一个明确的位置配置“翻译专用 AI provider + model”。
- 翻译提示词可编辑（至少 fulltext prompt 可编辑；可选：加一个 user_prompt 追加指令）。
- 缓存可开关、可清理。

---

## 2. 设计总览（架构）

我们拆成两条 pipeline：

### 2.1 Pipeline A：选中翻译（保持现状）
- 继续走 `TranslateService.ai` → `AiTranslateProvider` → `AiPrompts.translate`
- 不引入新模式，避免破坏现有体验。

### 2.2 Pipeline B：全文翻译（内联显示 + 导出）
新增一个专门的“全文纯翻译”服务：
- 新 `TranslateService.aiFullText`（名称建议：**AI (Translate Only)**）
- Provider：`AiFullTextTranslateProvider`
  - prompt：`AiPrompts.translate_fulltext`（或类似新枚举）
  - 支持：chunking + 并发 + 缓存 +（导出时）整书遍历

**核心原则：同一个翻译引擎，两个入口：**
- 在线内联：单块 translateText handler 调用
- 离线导出：遍历整本 EPUB 内容文档，批量调用

---

## 3. 数据模型与存储

### 3.1 配置（Prefs）
建议新增一组“翻译专用”配置（避免污染聊天的 provider 配置）：
- `aiFullTextTranslateProviderId`：从 Provider Center 选择一个启用的 provider（不在 provider list 的则回退 openai）
- `aiFullTextTranslateModelOverride`：翻译专用 model（可选；为空则用 provider config 的 model）
- `aiFullTextTranslateUserPrompt`：用户自定义翻译指令（可选，作为 prompt 末尾的附加规则）
- `aiFullTextTranslateCacheEnabled`：是否启用缓存
- `aiFullTextTranslateConcurrency`：并发数（默认 **4**，你已确认）
- `aiFullTextTranslateMaxChunkChars`：chunking 上限（默认 1200；实际实现以“段落/句子边界优先”的 chunker 为准，不允许硬切破坏语义）
- `aiFullTextExportSubmitKind`：导出默认模式（REPLACE/APPEND_BLOCK）

> 备注：这些配置属于“AI 设置”，但更贴近“翻译设置页”，建议放在 TranslateSetting 的 service config 表单里。

### 3.2 缓存（持久）
参考 epub-translator 的 cache_path 思路，但在移动端我们做轻量实现：
- 存储位置：`getAnxCacheDir()` 下单独的 cache 文件或 sqlite 表。
- key 设计（必须能稳定复用）：
  - `hash(providerId + model + fromLang + toLang + promptVersion + normalizedText)`
- value：`translatedText` + `timestamp` + `hitCount`（可选）

清理策略：
- 最大条目数 or 最大文件大小（例如 2万条 / 50MB）
- LRU 淘汰（按 lastUsed）

> 关键：缓存 **不参与 WebDAV sync / backup**（避免体积与隐私问题），仅本机。

---

## 4. Chunking/分段策略（为何必须“按段落/句子”而不是硬切）

你提到的点非常关键：**硬切会显著降低翻译准确性**（主谓宾断裂、指代丢失、上下文丢失）。

### 4.1 epub-translator 是怎么做的（可借鉴）
`epub-translator` 并不是“按句子 split”，它走的是更强的 **结构化切分 + token 预算分组**：
- 先把 XHTML/XML 解析成一系列 `TextSegment`（按 DOM 文本节点与 tail 分割）
- 再把它们组装成 `InlineSegment`（保持 inline tag 结构与相对顺序）
- 用 `tiktoken` 计算每个 segment 的 token/score，再用 `resource_segmentation.split(...)` 按 `max_group_score` 分组
- 组内渲染 source text 时，会用 `\n\n` 作为段落分隔（见 `XMLTranslator._render_source_text_parts`）

这套做法的本质是：**优先按“DOM 的自然段落/块级结构”切分**，只有在 token 预算不够时，才会在结构边界上进一步裁剪（而不是随便截断字符）。

### 4.2 Anx Reader 里我们怎么落地（移动端可实现版本）
我们在 Anx Reader 分两种场景处理：

A) 阅读器内联翻译（translator.js 单块请求）
- 默认以“段落/块级元素”为单位翻译（这是最接近语义的边界）
- 只有当块文本超出阈值时，才启动句子级 split（`。！？.!?` + 换行）
- 绝不做“任意字符硬切”

B) 导出翻译 EPUB（批量）
- 我们直接在 XHTML DOM 层面做分段：
  - 以 block-level element 为主（p/div/li/h1..h6/blockquote 等）
  - 对超长 block 采用句子边界 split
- 同时引入“token/长度预算”的分组思想（Dart 侧先用字符近似，后续可选接入 token 计数器）

---

## 5. EPUB 导出翻译版：算法与实现策略

### 4.1 输入与输出
- 输入：书库中某本 EPUB 的原始文件路径
- 输出：一个新 EPUB 文件（用户通过 Files 选择保存位置）

### 4.2 解析与修改
- 使用 `archive` 解压 epub（zip）到临时目录
- 遍历 `content.opf` 找到 spine 中的 XHTML 文档（或直接遍历 OEBPS/*.xhtml）
- 对每个文档：
  - 解析 DOM
  - 找到“可翻译块”列表（近似复用 translator.js 的 walkTextNodes 策略：跳过 pre/code/math/style/script，跳过已翻译节点）
  - 对每个块：
    - 用 chunker 控制长度
    - 查缓存 → 没命中才请求

### 4.3 SubmitKind 的落地语义
- **APPEND_BLOCK**（推荐）：
  - 在原块后插入一个块级译文节点（如 `<p class="anx-translated">...</p>` 或 `<span class="translated-text" style="display:block">...</span>`）
  - 译文节点打标 `data-translation-mark="1"`，方便后续识别/再处理。

- **REPLACE**（单语版）：
  - 将块的文本内容替换为译文
  - 风险：如果块内存在复杂 inline markup（em/strong/a/span），替换可能损伤格式。
  - 策略：
    1) 第一版：对“无子元素”或“简单结构”的节点执行 replace；复杂结构 fallback 为 append（并在导出日志里记录）。
    2) 后续增强：做更精细的 text node 替换（工程量更大）。

### 4.4 并发与进度
- 采用任务队列：最多 `concurrency` 个并发请求
- 进度 = 已完成块数 / 总块数（按文档累计）
- 可取消：取消时停止队列，写入一个 job state（可选）

### 4.5 断点恢复（可选 P1）
- 把每个块的翻译结果写入缓存后即可恢复：
  - 下次导出时命中缓存 → 继续
- 额外保存 job manifest（当前处理到哪个文档/块索引）可更快恢复

---

## 5. UI/UX 设计

### 5.1 翻译设置页（TranslateSetting）
在“FullTextTranslationConfig”里，当选择 `AI (Translate Only)` 时额外显示：
- 翻译专用 Provider（来自 Provider Center 的启用 providers，下拉选择）
- 翻译专用 Model（输入框/下拉，复用 models cache）
- 自定义翻译指令（可选，多行文本）
- SubmitKind（导出默认模式：REPLACE / APPEND_BLOCK）
- 缓存开关 + 清理按钮
- 并发数、maxChunkChars

### 5.2 导出入口
建议两个入口（二选一，或都做）：
1) Book detail / more menu：`导出翻译版 EPUB...`
2) 阅读页菜单：`翻译 -> 导出翻译版 EPUB...`

导出页（wizard）：
- 选择模式：REPLACE / APPEND_BLOCK
- 选择目标语言（使用 fullTextTranslateTo）
- 展示进度条 + 取消
- 完成后弹出“保存到 Files/分享”

---

## 6. 工程拆分（PR stack）

### PR-10.1：全文翻译专用服务（内联）
- 新增 `TranslateService.aiFullText` + `AiFullTextTranslateProvider`
- 新增 `AiPrompts.translate_fulltext`
- 支持翻译专用 providerId + model override + user_prompt
- **保证返回纯译文**

### PR-10.2：chunking + 并发控制 + 持久缓存
- chunker：段落/句子边界优先
- 队列：concurrency 默认 2
- TranslationCache：文件/表 + LRU 清理

### PR-10.3：导出翻译版 EPUB（APPEND_BLOCK）
- 实现解压、遍历、插入译文 block、重新打包
- UI：导出页 + 保存

### PR-10.4：导出 REPLACE（最小可行版）
- 对简单节点 replace；复杂节点 fallback append 并记录

### PR-10.5：测试与回归
- 单测：chunker、cache key、submit kind 插入
- 真机脚本：iPad 长时间滚动、整书导出

---

## 7. 测试计划（最小闭环）

### 7.1 内联显示
- 选择全文翻译服务为 `AI (Translate Only)`
- 阅读器切到：TRANSLATION_ONLY / BILINGUAL
- 快速滚动/翻页：
  - 不出现“解释型输出”
  - 不出现明显 429 风暴（必要时启用 AI 调试日志）

### 7.2 导出
- 同一本 EPUB：
  - 导出 APPEND_BLOCK：译文在原文后，结构不崩
  - 导出 REPLACE：正文变为译文（允许少量格式损伤但不应破坏可读性）

---

## 8. 已确认的默认值 & 仍待确认项

### 8.1 已确认
- 并发默认值：**4**

### 8.2 仍待确认（我建议的默认）
1) `maxChunkChars`：建议 1200（实际按“段落/句子边界优先”的 chunker 切；不是硬切）
2) REPLACE 的“复杂结构 fallback append”第一版策略：是否接受（我建议接受，先把功能可靠跑通）
