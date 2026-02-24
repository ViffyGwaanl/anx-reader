import 'package:anx_reader/models/ai_provider_meta.dart';
import 'package:anx_reader/service/ai/ai_models_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AiModelsService registryIdentifierFor maps types', () {
    expect(
      AiModelsService.registryIdentifierFor(
        AiProviderMeta(
          id: 'x',
          name: 'x',
          type: AiProviderType.openaiCompatible,
          enabled: true,
          isBuiltIn: false,
          createdAt: 0,
          updatedAt: 0,
        ),
      ),
      'openai',
    );
    expect(
      AiModelsService.registryIdentifierFor(
        AiProviderMeta(
          id: 'x',
          name: 'x',
          type: AiProviderType.anthropic,
          enabled: true,
          isBuiltIn: false,
          createdAt: 0,
          updatedAt: 0,
        ),
      ),
      'claude',
    );
    expect(
      AiModelsService.registryIdentifierFor(
        AiProviderMeta(
          id: 'x',
          name: 'x',
          type: AiProviderType.gemini,
          enabled: true,
          isBuiltIn: false,
          createdAt: 0,
          updatedAt: 0,
        ),
      ),
      'gemini',
    );
  });
}
