import 'dart:convert';

import 'package:anx_reader/enums/ai_thinking_mode.dart';
import 'package:googleai_dart/googleai_dart.dart' as g;
import 'package:http/http.dart' as http;
import 'package:langchain_core/chat_models.dart';
import 'package:langchain_core/language_models.dart';
import 'package:langchain_core/prompts.dart';
import 'package:langchain_core/tools.dart';
import 'package:langchain_google/langchain_google.dart';
// Internal import: needed for tool calling mappers (toToolList/toToolConfig/toSafetySettings).
// We keep this local wrapper small and do not fork langchain_google.
// If upstream exposes these in public API later, we can remove this import.
import 'package:langchain_google/src/chat_models/google_ai/mappers.dart';
import 'package:uuid/uuid.dart';

/// Prefix used by [CancelableLangchainRunner] to detect thinking chunks.
const String _thinkTag = '<think/>';

/// Gemini chat model with thinking controls.
///
/// Gemini official API supports:
/// - Gemini 3: thinkingLevel
/// - Gemini 2.5: thinkingBudget
/// - includeThoughts: thought summary
/// - thought signatures
///
/// But `langchain_google` doesn't currently expose thinkingConfig.
/// This wrapper keeps the LangChain interface so the existing agent/tool loop
/// can continue to work.
class ChatGoogleGenerativeAIWithThinking
    extends BaseChatModel<ChatGoogleGenerativeAIOptions> {
  ChatGoogleGenerativeAIWithThinking({
    required this.thinkingMode,
    required this.includeThoughts,
    final String? apiKey,
    final String? baseUrl,
    final Map<String, String>? headers,
    final Map<String, String>? queryParams,
    final int retries = 3,
    final http.Client? client,
    super.defaultOptions = const ChatGoogleGenerativeAIOptions(
      model: ChatGoogleGenerativeAI.defaultModel,
    ),
  }) {
    final mergedQueryParams = <String, String>{...?(queryParams)};
    if (apiKey != null && apiKey.trim().isNotEmpty) {
      // Some gateways only accept API key via query param.
      mergedQueryParams.putIfAbsent('key', () => apiKey.trim());
    }

    _client = g.GoogleAIClient(
      config: g.GoogleAIConfig(
        authProvider: apiKey != null && apiKey.trim().isNotEmpty
            ? g.ApiKeyProvider(apiKey.trim())
            : null,
        baseUrl: baseUrl ?? 'https://generativelanguage.googleapis.com',
        defaultHeaders: headers ?? const {},
        defaultQueryParams: mergedQueryParams,
        retryPolicy: g.RetryPolicy(maxRetries: retries),
      ),
      httpClient: client,
    );
  }

  final AiThinkingMode thinkingMode;
  final bool includeThoughts;

  late g.GoogleAIClient _client;
  late final _uuid = const Uuid();

  /// Thought signatures returned by Gemini.
  ///
  /// Gemini docs recommend passing them through unchanged across turns.
  /// We keep them in-memory per model instance (per request stream).
  List<g.ThoughtSignaturePart> _thoughtSignatures = const [];

  @override
  String get modelType => 'chat-google-generative-ai-thinking';

  @override
  Future<ChatResult> invoke(
    final PromptValue input, {
    final ChatGoogleGenerativeAIOptions? options,
  }) async {
    final id = _uuid.v4();
    final messages = input.toChatMessages();
    final model = _getModel(options);

    final request = _buildRequest(messages, model: model, options: options);
    final response = await _client.models.generateContent(
      model: model,
      request: request,
    );

    return _toChatResult(response, id: id, model: model);
  }

  @override
  Stream<ChatResult> stream(
    final PromptValue input, {
    final ChatGoogleGenerativeAIOptions? options,
  }) {
    final id = _uuid.v4();
    final messages = input.toChatMessages();
    final model = _getModel(options);

    final request = _buildRequest(messages, model: model, options: options);

    return _client.models
        .streamGenerateContent(model: model, request: request)
        .map((resp) => _toChatResult(resp, id: id, model: model));
  }

  @override
  Future<List<int>> tokenize(
    final PromptValue promptValue, {
    final ChatGoogleGenerativeAIOptions? options,
  }) {
    throw UnsupportedError(
      'Google AI does not expose a tokenizer; use countTokens instead.',
    );
  }

  @override
  Future<int> countTokens(
    final PromptValue promptValue, {
    final ChatGoogleGenerativeAIOptions? options,
  }) async {
    final messages = promptValue.toChatMessages();
    final model = _getModel(options);

    final result = await _client.models.countTokens(
      model: model,
      request: g.CountTokensRequest(contents: _toContentList(messages)),
    );

    return result.totalTokens;
  }

  @override
  void close() {
    _client.close();
  }

  @override
  Future<List<ModelInfo>> listModels() async {
    final models = <g.Model>[];
    String? pageToken;

    do {
      final response = await _client.models.list(pageToken: pageToken);
      models.addAll(response.models);
      pageToken = response.nextPageToken;
    } while (pageToken != null);

    return models
        .where(_isChatModel)
        .map(
          (m) => ModelInfo(
            id: _extractModelId(m.name),
            displayName: m.displayName,
            description: m.description,
            inputTokenLimit: m.inputTokenLimit,
            outputTokenLimit: m.outputTokenLimit,
          ),
        )
        .toList(growable: false);
  }

  static bool _isChatModel(final g.Model model) {
    return model.supportedGenerationMethods?.contains('generateContent') ??
        false;
  }

  static String _extractModelId(final String name) {
    const prefix = 'models/';
    return name.startsWith(prefix) ? name.substring(prefix.length) : name;
  }

  String _getModel(ChatGoogleGenerativeAIOptions? options) {
    return options?.model ??
        defaultOptions.model ??
        ChatGoogleGenerativeAI.defaultModel;
  }

  g.GenerateContentRequest _buildRequest(
    final List<ChatMessage> messages, {
    required String model,
    required ChatGoogleGenerativeAIOptions? options,
  }) {
    // Extract system instruction if present.
    final systemInstruction = messages.firstOrNull is SystemChatMessage
        ? g.Content(parts: [g.TextPart(messages.firstOrNull!.contentAsString)])
        : null;

    final contents = _injectThoughtSignatures(_toContentList(messages));

    return g.GenerateContentRequest(
      contents: contents,
      systemInstruction: systemInstruction,
      safetySettings: (options?.safetySettings ?? defaultOptions.safetySettings)
          ?.toSafetySettings(),
      generationConfig: g.GenerationConfig(
        candidateCount:
            options?.candidateCount ?? defaultOptions.candidateCount,
        stopSequences: options?.stopSequences ?? defaultOptions.stopSequences,
        maxOutputTokens:
            options?.maxOutputTokens ?? defaultOptions.maxOutputTokens,
        temperature: options?.temperature ?? defaultOptions.temperature,
        topP: options?.topP ?? defaultOptions.topP,
        topK: options?.topK ?? defaultOptions.topK,
        presencePenalty:
            options?.presencePenalty ?? defaultOptions.presencePenalty,
        frequencyPenalty:
            options?.frequencyPenalty ?? defaultOptions.frequencyPenalty,
        responseMimeType:
            options?.responseMimeType ?? defaultOptions.responseMimeType,
        responseSchema:
            options?.responseSchema ?? defaultOptions.responseSchema,
        thinkingConfig: _buildThinkingConfig(model: model),
      ),
      tools: (options?.tools ?? defaultOptions.tools).toToolList(
        enableCodeExecution: options?.enableCodeExecution ??
            defaultOptions.enableCodeExecution ??
            false,
      ),
      toolConfig:
          (options?.toolChoice ?? defaultOptions.toolChoice)?.toToolConfig(),
      cachedContent: options?.cachedContent ?? defaultOptions.cachedContent,
    );
  }

  g.ThinkingConfig? _buildThinkingConfig({required String model}) {
    final lower = model.toLowerCase();

    if (lower.contains('gemini-3')) {
      final level = switch (thinkingMode) {
        AiThinkingMode.off => g.ThinkingLevel.minimal,
        AiThinkingMode.auto => g.ThinkingLevel.unspecified,
        AiThinkingMode.minimal => g.ThinkingLevel.minimal,
        AiThinkingMode.low => g.ThinkingLevel.low,
        AiThinkingMode.medium => g.ThinkingLevel.medium,
        AiThinkingMode.high => g.ThinkingLevel.high,
      };

      // Gemini 3 Pro: minimal/medium unsupported (per docs). Clamp to low.
      final supportsMinimal = !lower.contains('gemini-3-pro');
      final supportsMedium = !lower.contains('gemini-3-pro');
      final clamped = switch (level) {
        g.ThinkingLevel.minimal when !supportsMinimal => g.ThinkingLevel.low,
        g.ThinkingLevel.medium when !supportsMedium => g.ThinkingLevel.low,
        _ => level,
      };

      return g.ThinkingConfig(
        includeThoughts: includeThoughts,
        thinkingLevel: clamped == g.ThinkingLevel.unspecified ? null : clamped,
      );
    }

    if (lower.contains('gemini-2.5')) {
      int budget;
      switch (thinkingMode) {
        case AiThinkingMode.off:
          budget = 0;
          break;
        case AiThinkingMode.auto:
          budget = -1;
          break;
        case AiThinkingMode.minimal:
          budget = 0;
          break;
        case AiThinkingMode.low:
          budget = 1024;
          break;
        case AiThinkingMode.medium:
          budget = 4096;
          break;
        case AiThinkingMode.high:
          budget = 8192;
          break;
      }

      // Gemini 2.5 Pro: cannot disable thinking (per docs). Clamp off->auto.
      if (budget == 0 && lower.contains('gemini-2.5-pro')) {
        budget = -1;
      }

      return g.ThinkingConfig(
        includeThoughts: includeThoughts,
        thinkingBudget: budget,
      );
    }

    if (includeThoughts) {
      return g.ThinkingConfig(includeThoughts: true);
    }

    return null;
  }

  List<g.Content> _injectThoughtSignatures(List<g.Content> contents) {
    if (_thoughtSignatures.isEmpty || contents.isEmpty) {
      return contents;
    }

    final index = contents.lastIndexWhere((c) => (c.role ?? '') == 'model');
    if (index < 0) {
      return contents;
    }

    final last = contents[index];
    final merged = last.copyWith(parts: [...last.parts, ..._thoughtSignatures]);
    final out = List<g.Content>.from(contents);
    out[index] = merged;
    return out;
  }

  List<g.Content> _toContentList(List<ChatMessage> messages) {
    final result = <g.Content>[];

    // NOTE: Gemini can return multiple FunctionCall parts in one model turn.
    // The API expects ONE Content.functionResponses next turn with the same
    // number/order of FunctionResponse parts. So we batch tool responses.
    List<g.FunctionResponsePart>? pendingToolResponses;

    void flushToolResponses() {
      if (pendingToolResponses != null && pendingToolResponses!.isNotEmpty) {
        result.add(g.Content(role: 'user', parts: pendingToolResponses!));
        pendingToolResponses = null;
      }
    }

    for (final message in messages) {
      if (message is SystemChatMessage) {
        continue;
      }

      if (message is ToolChatMessage) {
        pendingToolResponses ??= <g.FunctionResponsePart>[];
        pendingToolResponses!.add(_toolMsgToFunctionResponsePart(message));
        continue;
      }

      flushToolResponses();

      switch (message) {
        case final HumanChatMessage msg:
          result.add(_mapHumanChatMessage(msg));
        case final AIChatMessage msg:
          result.add(_mapAIChatMessage(msg));
        case final CustomChatMessage msg:
          result.add(_mapCustomChatMessage(msg));
        default:
          throw UnsupportedError('Unknown message type: $message');
      }
    }

    flushToolResponses();

    return result;
  }

  g.Content _mapHumanChatMessage(final HumanChatMessage msg) {
    final contentParts = switch (msg.content) {
      final ChatMessageContentText c => [g.TextPart(c.text)],
      final ChatMessageContentImage c => [
          if (c.data.startsWith('http'))
            g.FileDataPart(g.FileData(fileUri: c.data))
          else
            g.InlineDataPart(
              g.Blob.fromBytes(
                  c.mimeType ?? 'image/jpeg', base64Decode(c.data)),
            ),
        ],
      final ChatMessageContentMultiModal c => c.parts
          .map(
            (final p) => switch (p) {
              final ChatMessageContentText c => g.TextPart(c.text),
              final ChatMessageContentImage c => c.data.startsWith('http')
                  ? g.FileDataPart(g.FileData(fileUri: c.data))
                  : g.InlineDataPart(
                      g.Blob.fromBytes(
                        c.mimeType ?? 'image/jpeg',
                        base64Decode(c.data),
                      ),
                    ),
              ChatMessageContentMultiModal() => throw UnsupportedError(
                  'Cannot have multimodal content in multimodal content',
                ),
            },
          )
          .toList(growable: false),
    };

    return g.Content(role: 'user', parts: contentParts);
  }

  g.Content _mapAIChatMessage(final AIChatMessage msg) {
    final contentParts = <g.Part>[
      if (msg.content.isNotEmpty) g.TextPart(msg.content),
      if (msg.toolCalls.isNotEmpty)
        ...msg.toolCalls.map(
          (final call) => g.FunctionCallPart(
            g.FunctionCall(name: call.name, args: call.arguments),
          ),
        ),
    ];
    return g.Content(role: 'model', parts: contentParts);
  }

  g.FunctionResponsePart _toolMsgToFunctionResponsePart(
      final ToolChatMessage msg) {
    Map<String, Object?> response;
    try {
      response = jsonDecode(msg.content) as Map<String, Object?>;
    } catch (_) {
      response = {'result': msg.content};
    }
    return g.FunctionResponsePart(
      g.FunctionResponse(name: msg.toolCallId, response: response),
    );
  }

  g.Content _mapCustomChatMessage(final CustomChatMessage msg) {
    return g.Content(role: msg.role, parts: [g.TextPart(msg.content)]);
  }

  ChatResult _toChatResult(
    g.GenerateContentResponse response, {
    required String id,
    required String model,
  }) {
    final candidate = response.candidates?.first;
    if (candidate == null) {
      throw StateError('No candidates in response');
    }

    final parts = candidate.content?.parts ?? const <g.Part>[];

    final toolCalls = <AIChatMessageToolCall>[];
    final buffer = StringBuffer();

    var isThought = false;
    final signatures = <g.ThoughtSignaturePart>[];

    for (final part in parts) {
      switch (part) {
        case final g.ThoughtPart p:
          isThought = p.thought;
          break;
        case final g.ThoughtSignaturePart p:
          signatures.add(p);
          break;
        case final g.TextPart p:
          if (p.text.isEmpty) break;
          if (isThought) {
            buffer.write('$_thinkTag${p.text}');
          } else {
            buffer.write(p.text);
          }
          break;
        case final g.FunctionCallPart p:
          toolCalls.add(
            AIChatMessageToolCall(
              id: p.functionCall.name,
              name: p.functionCall.name,
              argumentsRaw: jsonEncode(p.functionCall.args ?? {}),
              arguments: p.functionCall.args ?? const {},
            ),
          );
          break;
        default:
          break;
      }
    }

    if (signatures.isNotEmpty) {
      _thoughtSignatures = List<g.ThoughtSignaturePart>.from(signatures);
    }

    return ChatResult(
      id: id,
      output: AIChatMessage(content: buffer.toString(), toolCalls: toolCalls),
      finishReason: FinishReason.unspecified,
      metadata: {
        'model': model,
      },
      usage: LanguageModelUsage(
        promptTokens: response.usageMetadata?.promptTokenCount,
        responseTokens: response.usageMetadata?.candidatesTokenCount,
        totalTokens: response.usageMetadata?.totalTokenCount,
      ),
    );
  }
}

extension _ContentListExt on List<g.Content> {
  int lastIndexWhere(bool Function(g.Content) test) {
    for (var i = length - 1; i >= 0; i--) {
      if (test(this[i])) return i;
    }
    return -1;
  }
}
