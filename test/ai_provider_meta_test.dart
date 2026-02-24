import 'package:anx_reader/models/ai_provider_meta.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AiProviderMeta encodes/decodes list', () {
    final now = DateTime.now().millisecondsSinceEpoch;
    final providers = [
      AiProviderMeta(
        id: 'openai',
        name: 'OpenAI',
        type: AiProviderType.openaiCompatible,
        enabled: true,
        isBuiltIn: true,
        createdAt: now,
        updatedAt: now,
        logoKey: 'assets/images/openai.png',
      ),
      AiProviderMeta(
        id: 'claude',
        name: 'Claude',
        type: AiProviderType.anthropic,
        enabled: false,
        isBuiltIn: true,
        createdAt: now,
        updatedAt: now,
      ),
    ];

    final encoded = AiProviderMeta.encodeList(providers);
    final decoded = AiProviderMeta.decodeList(encoded);

    expect(decoded.length, providers.length);
    expect(decoded[0].id, 'openai');
    expect(decoded[0].type, AiProviderType.openaiCompatible);
    expect(decoded[1].type, AiProviderType.anthropic);
  });

  test('AiProviderType parser is resilient', () {
    expect(aiProviderTypeFromString('openai'), AiProviderType.openaiCompatible);
    expect(aiProviderTypeFromString('openai-compatible'),
        AiProviderType.openaiCompatible);
    expect(aiProviderTypeFromString('claude'), AiProviderType.anthropic);
    expect(aiProviderTypeFromString('anthropic'), AiProviderType.anthropic);
    expect(aiProviderTypeFromString('gemini'), AiProviderType.gemini);
    expect(aiProviderTypeFromString('unknown'), AiProviderType.openaiCompatible);
  });
}
