import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get_storage/get_storage.dart';

enum AiProvider { openai, gemini, deepseek }

extension AiProviderInfo on AiProvider {
  String get label => switch (this) {
        AiProvider.openai => 'OpenAI',
        AiProvider.gemini => 'Gemini',
        AiProvider.deepseek => 'DeepSeek',
      };

  String get defaultModel => switch (this) {
        AiProvider.openai => 'gpt-5-mini',
        AiProvider.gemini => 'gemini-3.8-flash',
        AiProvider.deepseek => 'deepseek-flash',
      };

  String get endpoint => switch (this) {
        AiProvider.openai => 'https://api.openai.com/v1/chat/completions',
        AiProvider.gemini =>
          'https://generativelanguage.googleapis.com/v1beta/openai/chat/completions',
        AiProvider.deepseek => 'https://api.deepseek.com/chat/completions',
      };
}

/// Non-secret choices use app storage; keys never enter GetStorage or deploy.yaml.
class AiProviderSettings {
  AiProviderSettings({GetStorage? storage, FlutterSecureStorage? secrets})
      : _storage = storage ?? GetStorage(),
        _secrets = secrets ?? const FlutterSecureStorage();

  static const selectedKey = 'ai_analysis_provider';
  final GetStorage _storage;
  final FlutterSecureStorage _secrets;

  AiProvider get selected {
    final value = _storage.read<String>(selectedKey);
    for (final provider in AiProvider.values) {
      if (provider.name == value) return provider;
    }
    return AiProvider.openai;
  }

  String modelFor(AiProvider provider) {
    final value = _storage.read<String>('ai_analysis_model_${provider.name}');
    return value == null || value.trim().isEmpty
        ? provider.defaultModel
        : value.trim();
  }

  Future<String?> keyFor(AiProvider provider) =>
      _secrets.read(key: 'oasx_ai_${provider.name}_api_key');

  Future<void> save(AiProvider provider, String model, {String? newKey}) async {
    final trimmedModel = model.trim();
    if (trimmedModel.isEmpty) throw ArgumentError('模型不能为空');
    if (newKey != null && newKey.trim().isNotEmpty) {
      await _secrets.write(
        key: 'oasx_ai_${provider.name}_api_key',
        value: newKey.trim(),
      );
    }
    await _storage.write('ai_analysis_model_${provider.name}', trimmedModel);
    await _storage.write(selectedKey, provider.name);
  }

  Future<void> deleteKey(AiProvider provider) =>
      _secrets.delete(key: 'oasx_ai_${provider.name}_api_key');
}
