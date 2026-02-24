# P1：OpenAI-compatible Thinking（思考内容）— 仅展示供应商提供的数据（无兜底捏造）

> 你明确的产品原则：
>
> - **不做提示词兜底**：不通过 prompt 让模型“编一个思考摘要”。
> - **只展示供应商返回的思考数据**：供应商不给（无 `reasoning_content` / 无 thoughts）就不显示。
> - thinkingMode=off：**不主动请求**思考/推理；但如果后端仍返回 `reasoning_content`，则 **照样展示**。

本文将把这个原则落到工程可执行的实现计划与测试计划。

---

## 1. 术语与数据源（Sources）

### 1.1 OpenAI-compatible（Chat Completions 兼容）

我们认可/使用的“思考数据”来源只有两类（均为供应商返回）：

- **Source A：`reasoning_content`**
  - 非流式：`message.reasoning_content`
  - 流式：`delta.reasoning_content`
- **Source B：`reasoning`**（部分兼容实现可能用这个字段）

> 重要：无论 thinkingMode 如何，只要响应里出现上述字段，就展示。

### 1.2 Gemini / Anthropic

- Gemini：由供应商 SDK/包装器返回 thoughts（若 includeThoughts 开启且模型支持）
- Anthropic：由 SDK thinking block 返回（若开启 extended thinking）

这两类同样遵循“只展示供应商提供的数据”。

---

## 2. thinkingMode 的工程语义（不等于 UI 是否展示）

我们把 `AiThinkingMode` 定义为：

- **请求侧（Request）**：是否/以何种强度向模型请求“推理能力/推理预算”。
- **展示侧（Display）**：是否展示由供应商返回的 reasoning 内容。

你指定的规则是：

- thinkingMode=off：
  - Request：不主动请求（例如 OpenAI 不设置 reasoning effort；Claude 关闭 thinking；Gemini 不额外请求 thoughts）
  - Display：如果响应里仍返回 reasoning_content/thoughts → 仍展示

因此：UI 中“关闭”应理解为“**不主动要**”，而不是“强行隐藏”。

---

## 3. 实施计划（Implementation Plan）

### 3.1 OpenAI-compatible：确保 reasoning_content 透传到 UI

**目标**：当供应商返回 reasoning_content/ reasoning 时，最终能进入 `<think>...</think>` 通道并被 UI 折叠区识别。

实施点（已具备部分基础）：

1) SDK/Schema 支持
- `openai_dart` 已包含 `reasoning_content` 字段（schema 层）

2) LangChain mapper 透传
- `langchain_openai` mapper 需要把 reasoning_content 写入 `ChatResult.metadata`

3) Runner 聚合
- `CancelableLangchainRunner` 在 streaming chunk 中读取 metadata：
  - `reasoning_content` / `reasoning`
  - 聚合到 thinkingSummary
  - 并把 thinkingSummary 包装成 `<think>...</think>` 输出

**验收**：对同一个 OpenAI-compatible provider，只要它返回 reasoning_content，就能在 UI Thinking 区块看到。

### 3.2 thinkingMode=off 的请求侧行为（不主动要）

OpenAI-compatible：
- thinkingMode=off 时，不设置 `reasoningEffort`
- thinkingMode=minimal/low/medium/high 时，设置对应 `reasoningEffort`

Claude：
- thinkingMode=off 时 `thinking.disabled()`
- 其他档位映射预算 tokens

Gemini：
- thinkingMode 仅影响我们对 Gemini 的 thinking config（若实现已支持）
- includeThoughts 仍由开关控制

### 3.3 禁止兜底摘要（明确不做）

- 不新增任何 prompt 指令来强制模型输出 `<think>...</think>`
- 不做二次总结（two-pass）来生成“摘要 thinking”

---

## 4. 测试计划（Test Plan）

### 4.1 单元测试（建议新增）

> 目标：验证“仅展示供应商字段 + thinkingMode=off 不影响展示”。

1) **显示 reasoning_content**
- 输入：模拟 stream chunk，`metadata['reasoning_content'] = 'abc'`
- 期望：输出文本包含 `<think>abc</think>`（或最终解析为 thinking 区块）

2) **显示 reasoning（兼容字段）**
- 输入：`metadata['reasoning'] = 'xyz'`
- 期望：同上

3) **thinkingMode=off 仍展示（Display 不受影响）**
- 输入：thinkingMode=off + metadata reasoning_content 存在
- 期望：仍展示 `<think>`

4) **无字段则不展示**
- 输入：无 reasoning_content / reasoning
- 期望：输出不包含 `<think>`（除非 Gemini/Claude 等供应商返回了 thoughts）

### 4.2 Widget 测试（回归）

- 给 `aiChatProvider` 注入包含 `<think>` 的 assistant message → UI 显示 Thinking 折叠区
- 注入无 `<think>` 的 message → UI 不显示 Thinking 折叠区

### 4.3 真机验收（必须）

准备两类 OpenAI-compatible 端：

- Case 1：会返回 reasoning_content 的模型/网关
  - thinkingMode=off：仍显示 Thinking
  - thinkingMode=high：仍显示 Thinking（可能内容更长/更充分，由供应商决定）

- Case 2：不会返回 reasoning_content 的模型/网关
  - thinkingMode=high：不显示 Thinking（因为供应商不给；符合“没有就没有”）

---

## 5. OpenAI 官方文档核对（结论性摘要）

我已查看 OpenAI 官方文档中的“Reasoning models”说明要点（不贴原文）：

- reasoning effort 是通过 **API 参数**控制（不是靠提示词）。
- 原始 reasoning tokens 不会直接对外暴露（通常不可见）。
- 部分模型/接口支持返回“reasoning summary”（同样是供应商提供的数据）。

> 后续如要支持 OpenAI 官方的 reasoning summary（属于供应商提供、非 prompt 捏造），可以作为 P1.1 扩展评估是否需要切换/兼容 Responses API。
