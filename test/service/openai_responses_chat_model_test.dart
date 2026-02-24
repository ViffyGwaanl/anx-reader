import 'dart:async';
import 'dart:convert';

import 'package:anx_reader/service/ai/openai_responses_chat_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:langchain_core/chat_models.dart';
import 'package:langchain_core/language_models.dart';
import 'package:langchain_core/prompts.dart';
import 'package:langchain_openai/langchain_openai.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _QueuedStreamClient extends http.BaseClient {
  _QueuedStreamClient(this._queue);

  final List<String> _queue;
  final List<Map<String, dynamic>> sentJsonBodies = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request is http.Request) {
      sentJsonBodies.add(jsonDecode(request.body) as Map<String, dynamic>);
    }

    if (_queue.isEmpty) {
      return http.StreamedResponse(
        Stream.value(utf8.encode('')),
        500,
      );
    }

    final sse = _queue.removeAt(0);
    final bytes = utf8.encode(sse);
    final stream = Stream<List<int>>.fromIterable([bytes]);

    return http.StreamedResponse(
      stream,
      200,
      headers: const {
        'content-type': 'text/event-stream',
      },
    );
  }
}

String _sseEvent(String type, Map<String, dynamic> data) {
  final payload = <String, dynamic>{'type': type, ...data};
  return 'event: $type\n'
      'data: ${jsonEncode(payload)}\n\n';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
  });

  test('streams output_text.delta chunks and aggregates into final content',
      () async {
    final sse = StringBuffer()
      ..write(_sseEvent('response.output_text.delta', {'delta': 'Hi '}))
      ..write(_sseEvent('response.output_text.delta', {'delta': 'there'}))
      ..write(_sseEvent('response.completed', {
        'response': {
          'reasoning': {'summary': null}
        }
      }));

    final client = _QueuedStreamClient([sse.toString()]);

    final model = ChatOpenAIResponses(
      baseUrl: 'https://example.com/v1',
      apiKey: 'k',
      defaultOptions: const ChatOpenAIOptions(model: 'gpt-test'),
      client: client,
    );

    final chunks = await model
        .stream(
          PromptValue.chat([
            ChatMessage.humanText('hello'),
          ]),
        )
        .toList();

    ChatResult? agg;
    for (final c in chunks) {
      agg = agg == null ? c : agg!.concat(c);
    }

    expect(agg, isNotNull);
    expect(agg!.output.content, 'Hi there');
  });

  test('emits reasoning_content metadata for reasoning summary items',
      () async {
    final sse = StringBuffer()
      ..write(_sseEvent('response.output_item.done', {
        'output_index': 0,
        'item': {
          'type': 'reasoning',
          'id': 'rs_1',
          'summary': [
            {'type': 'summary_text', 'text': 'Reasoning summary.'}
          ]
        }
      }))
      ..write(_sseEvent('response.completed', {
        'response': {
          'reasoning': {'summary': null}
        }
      }));

    final client = _QueuedStreamClient([sse.toString()]);

    final model = ChatOpenAIResponses(
      baseUrl: 'https://example.com/v1',
      apiKey: 'k',
      defaultOptions: const ChatOpenAIOptions(model: 'gpt-test'),
      client: client,
    );

    final chunks = await model
        .stream(
          PromptValue.chat([
            ChatMessage.humanText('hello'),
          ]),
        )
        .toList();

    expect(
      chunks.any(
        (c) => (c.metadata['reasoning_content']?.toString() ?? '')
            .contains('Reasoning summary.'),
      ),
      isTrue,
    );
  });

  test(
      'aggregates streamed function_call arguments and emits toolCalls on done',
      () async {
    final sse = StringBuffer()
      ..write(_sseEvent('response.output_item.added', {
        'output_index': 0,
        'item': {
          'type': 'function_call',
          'id': 'fc_1',
          'call_id': 'call_1',
          'name': 'get_weather',
          'arguments': ''
        }
      }))
      ..write(_sseEvent('response.function_call_arguments.delta',
          {'item_id': 'fc_1', 'output_index': 0, 'delta': '{"location":'}))
      ..write(_sseEvent('response.function_call_arguments.delta',
          {'item_id': 'fc_1', 'output_index': 0, 'delta': '"Paris"}'}))
      ..write(_sseEvent('response.function_call_arguments.done', {
        'item_id': 'fc_1',
        'output_index': 0,
        'arguments': '{"location":"Paris"}'
      }))
      ..write(_sseEvent('response.output_item.done', {
        'output_index': 0,
        'item': {
          'type': 'function_call',
          'id': 'fc_1',
          'call_id': 'call_1',
          'name': 'get_weather',
          'arguments': '{"location":"Paris"}'
        }
      }))
      ..write(_sseEvent('response.completed', {
        'response': {
          'reasoning': {'summary': null}
        }
      }));

    final client = _QueuedStreamClient([sse.toString()]);

    final model = ChatOpenAIResponses(
      baseUrl: 'https://example.com/v1',
      apiKey: 'k',
      defaultOptions: const ChatOpenAIOptions(model: 'gpt-test'),
      client: client,
    );

    final chunks = await model
        .stream(
          PromptValue.chat([
            ChatMessage.humanText('hello'),
          ]),
        )
        .toList();

    final last = chunks.isEmpty ? null : chunks.last;
    expect(last, isNotNull);
    expect(last!.finishReason, FinishReason.toolCalls);
    expect(last.output.toolCalls, hasLength(1));
    expect(last.output.toolCalls.first.id, 'call_1');
    expect(last.output.toolCalls.first.name, 'get_weather');
    expect(last.output.toolCalls.first.argumentsRaw, '{"location":"Paris"}');
  });

  test('replays reasoning items when tool outputs are present in next call',
      () async {
    final first = StringBuffer()
      ..write(_sseEvent('response.output_item.done', {
        'output_index': 0,
        'item': {
          'type': 'reasoning',
          'id': 'rs_1',
          'summary': [
            {'type': 'summary_text', 'text': 'R1'}
          ]
        }
      }))
      ..write(_sseEvent('response.output_item.done', {
        'output_index': 1,
        'item': {
          'type': 'function_call',
          'id': 'fc_1',
          'call_id': 'call_1',
          'name': 'get_weather',
          'arguments': '{"location":"Paris"}'
        }
      }))
      ..write(_sseEvent('response.completed', {
        'response': {
          'reasoning': {'summary': null}
        }
      }));

    final second = StringBuffer()
      ..write(_sseEvent('response.output_text.delta', {'delta': 'OK'}))
      ..write(_sseEvent('response.completed', {
        'response': {
          'reasoning': {'summary': null}
        }
      }));

    final client = _QueuedStreamClient([first.toString(), second.toString()]);

    final model = ChatOpenAIResponses(
      baseUrl: 'https://example.com/v1',
      apiKey: 'k',
      defaultOptions: const ChatOpenAIOptions(model: 'gpt-test'),
      client: client,
    );

    // First call: captures reasoning items.
    await model
        .stream(
          PromptValue.chat([
            ChatMessage.humanText('hello'),
          ]),
        )
        .toList();

    // Second call: includes tool output, should replay reasoning items.
    final toolCall = AIChatMessageToolCall(
      id: 'call_1',
      name: 'get_weather',
      argumentsRaw: '{"location":"Paris"}',
      arguments: const {},
    );

    await model
        .stream(
          PromptValue.chat([
            AIChatMessage(content: '', toolCalls: [toolCall]),
            ChatMessage.tool(toolCallId: 'call_1', content: '{"temp":25}'),
          ]),
        )
        .toList();

    expect(client.sentJsonBodies, hasLength(2));
    final secondBody = client.sentJsonBodies[1];
    final input = (secondBody['input'] as List).cast<dynamic>();
    expect(input.isNotEmpty, isTrue);

    // Order should be: function_call (from AI toolCalls), reasoning replay,
    // then function_call_output.
    final types = input
        .map((e) => (e as Map)['type']?.toString())
        .whereType<String>()
        .toList(growable: false);

    final reasoningIndex = types.indexOf('reasoning');
    final outputIndex = types.indexOf('function_call_output');

    expect(reasoningIndex, greaterThanOrEqualTo(0));
    expect(outputIndex, greaterThanOrEqualTo(0));
    expect(reasoningIndex, lessThan(outputIndex));

    final reasoningItem = input[reasoningIndex] as Map;
    expect(reasoningItem['id'], 'rs_1');
  });
}
