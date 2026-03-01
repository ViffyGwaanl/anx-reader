# PR-10（内联全文翻译）工程计划（专业版）

> 本文聚焦：**阅读页内联全文翻译**（当页 + 下页），只显示不改 EPUB，并具备持久缓存与按书清理。
>
> 对比参考：
> - Anx Reader 现状：`assets/foliate-js/src/translator.js` + Flutter `translateText` handler
> - `old-immersive-translate`：网页沉浸式翻译的“内容选取 + 视口增量翻译”体系
> - `epub-translator`：导出翻译 EPUB 的“结构化分段 + token 预算分组 + 回填/提交”体系

---

## 1. 问题定义（Problem Statement）

我们要把“全文翻译”做成一个**可控范围、可恢复、不会污染原文**的阅读增强功能。

### 1.1 关键约束（必须满足）
- **范围限制**：仅翻译 **当页 + 下页**（不做多屏预取）。
- **显示-only**：只在 DOM 中追加/覆盖显示，不修改 EPUB 文件，不写回章节内容。
- **原文隔离**：AI 提问/工具获取的章节内容必须是**原文**，不得包含 `.translated-text`。
- **提示词隔离**：
  - 划线/选中翻译使用现有 `AiPrompts.translate`（允许解释/词汇）。
  - 内联全文翻译使用新 `AiPrompts.translate_fulltext`（严格纯译文）。
- **持久缓存**：退出 App/重进后可命中缓存恢复；并提供**按书清除缓存**。

### 1.2 评价维度（我们如何判断做得好）
- 翻译质量稳定：段落边界优先，避免硬切。
- 性能可控：请求并发受限、可去重、缓存命中率高。
- 阅读器稳定：不破坏 CFI/标注/选择/搜索等既有能力。
- 可维护/可测试：明确层次、可单测关键逻辑。

---

## 2. 方案对比结论（Why：借鉴谁的什么）

### 2.1 Anx Reader（foliate-js translator.js）
- **优点**：DOM 改动保守（append `.translated-text`），更适合 EPUB 阅读器场景。
- **短板**：
  - 单元素单请求，滚动触发易产生 API 风暴。
  - `getChapterContent()` 目前会把译文混入原文（必须修）。

### 2.2 old-immersive-translate（网页扩展）
- **优点**：视口驱动的增量翻译调度成熟，可自然实现“只翻译当前屏幕附近”。
- **短板**：对 DOM 的替换/克隆更激进；直接照搬到 EPUB 可能影响 CFI/标注。

### 2.3 epub-translator（导出 EPUB）
- **优点**：结构化切分 + token 预算分组 + 回填校验，非常适合导出 pipeline。
- **短板**：过重，不适合阅读页“实时显示”。

### 2.4 组合策略（最终选择）
- **调度策略**：借鉴 `old-immersive-translate` 的“视口增量翻译”（范围严格可控）。
- **DOM 写入策略**：保持 Anx Reader 的 `.translated-text` overlay 思路（安全、可逆）。
- **分段/预算思想**：借鉴 `epub-translator` 的“结构边界优先 + 预算控制”，在移动端做轻量实现。

---

## 3. 目标架构（What：模块划分）

### 3.1 分层（强制清晰）
1) **JS 调度层（foliate-js）**
- 负责：
  - 识别“当页 + 下页”的候选元素
  - 控制 IntersectionObserver 的 rootMargin/阈值
  - 避免多屏预取

2) **Flutter handler 层（WebView JS handler：`translateText`）**
- 负责：
  - 并发控制（semaphore/pool）
  - inflight 去重（同 key 共享 Future）
  - 持久缓存读取/写入
  - 调用真实翻译 Provider

3) **翻译 Provider 层（TranslateServiceProvider）**
- 负责：
  - 内联全文翻译的 AI prompt（`translate_fulltext`）
  - 选择翻译的 AI prompt（`translate`）

4) **原文提取层（foliate-js book.js）**
- 负责：
  - `getChapterContent()` / `getPreviousContent()` 等必须过滤 `.translated-text`

### 3.2 数据流（内联翻译一次调用）
`IntersectionObserver hit` → `translator.#translateElement(element)` → `callHandler('translateText', text)` → Flutter:
- build cacheKey(bookId + service + lang + promptVersion + normalizedText)
- if cache hit → return
- else acquire semaphore → call provider.translateTextOnly → persist cache → return
→ JS append `.translated-text` wrapper

---

## 4. 关键算法设计（How：可实现且可解释）

### 4.1 范围：只翻当页 + 下页
- IntersectionObserver `rootMargin` 设为：bottom = `100%`（一屏），top = `0`。
- 打开翻译模式时 `forceTranslateVisibleElements()` 只处理：
  - viewport 内 + viewport 下方一屏内

> 目标：用户向下阅读时，下页提前翻好；向上回看时，旧内容进入 viewport 才翻。

### 4.2 分段（避免硬切）
内联翻译单元优先级：
1) block-level 元素（p/li/blockquote/heading 等）
2) 对超长 block：按句子边界 split（`。！？.!?` + 换行）
3) 仍超限再做最后兜底（慎用）：按空白/标点附近裁剪（绝不在单词中间硬切）

> 第一版可先保持“element 粒度翻译”，但必须预留分段扩展点；第二版上分段。

### 4.3 持久缓存（按书）
- 存储位置：`getAnxCacheDir()`
- 文件布局建议：
  - `fulltext_translate_cache/book_<bookId>.json`（或 sqlite）
- key 组成（强制包含 bookId）：
  - `sha1(service + providerId + model + from + to + promptVersion + normalizedText)`
- value：translatedText + timestamp + lastUsed
- 清理：LRU + size/count 上限

### 4.4 原文隔离（必须修）
- `book.js getChapterContent()` 不能直接 `body.textContent`。
- 改为 TreeWalker：过滤 `.translated-text`（与 `text-walker.js` 一致思想）。

---

## 5. 交付拆分（PR Stack）

### PR-10.1（基础正确性）
- [ ] 新增 `AiPrompts.translate_fulltext`
- [ ] 新增 `TranslateService.aiFullText`（仅用于内联全文翻译的 service 列表）
- [ ] `translateText` handler 加：并发限制 + inflight 去重（先不做持久缓存也可，但建议一起做骨架）
- [ ] foliate-js：IntersectionObserver 调整为当页+下页
- [ ] foliate-js：修 `getChapterContent/getPreviousContent` 过滤 `.translated-text`
- [ ] 单测：
  - cacheKey 规范化（空白/换行处理）
  - 原文提取过滤函数（JS 侧可用最小单测或 Dart 侧 snapshot）

### PR-10.2（持久缓存 + 按书清理）
- [ ] 实现 `FullTextTranslateCache`（按书文件）
- [ ] Settings/书籍菜单增加“清除本书全文翻译缓存”
- [ ] 缓存上限策略（默认值）

### PR-10.3（分段质量增强）
- [ ] 引入句子边界 split + 组合策略
- [ ] 针对极端长段落的稳定性（避免 20k prompt/超长输入）

### PR-10.4（导出 EPUB pipeline：另文档/另模块）
- 不在本计划内详述，主要参考 `epub-translator`。

---

## 6. 风险与对策（Engineering Risks）
- **CFI/标注/选择文本受影响**：坚持 overlay（append）而不是 replace/clone。
- **请求风暴/限流**：并发=4 + 去重 + 缓存 + 范围限制。
- **译文污染原文提取**：TreeWalker 过滤 `.translated-text`，并加回归测试。
- **缓存膨胀**：按书拆分 + LRU + 上限。

---

## 7. 验收清单（DoD）
- 阅读页打开内联翻译：仅当页+下页出现译文。
- 快速滚动：不会出现明显卡顿/爆发式请求；日志可看到并发受控。
- 退出重进：已翻译段落命中缓存立即显示（不走网络）。
- AI 提问：获取到的是原文（不包含译文）。
- 每本书可清理缓存，清理后重新触发会重新请求。
