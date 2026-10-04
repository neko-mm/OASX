import 'package:flutter/material.dart';
import 'package:oasx/modules/settings/widgets/setting_card.dart';
import 'package:oasx/service/ai_analysis/ai_analysis_service.dart';
import 'package:oasx/service/ai_analysis/ai_provider.dart';

class AiSettingsCard extends StatefulWidget {
  const AiSettingsCard({super.key});

  @override
  State<AiSettingsCard> createState() => _AiSettingsCardState();
}

class _AiSettingsCardState extends State<AiSettingsCard> {
  final _settings = AiProviderSettings();
  final _service = AiAnalysisService();
  final _model = TextEditingController();
  final _key = TextEditingController();
  late AiProvider _provider;
  bool _hasSavedKey = false;
  bool _busy = false;
  String _status = '';

  @override
  void initState() {
    super.initState();
    _provider = _settings.selected;
    _model.text = _settings.modelFor(_provider);
    _readSavedKey();
  }

  @override
  void dispose() {
    _model.dispose();
    _key.dispose();
    super.dispose();
  }

  Future<void> _readSavedKey() async {
    final provider = _provider;
    try {
      final key = await _settings.keyFor(provider);
      if (mounted && provider == _provider) {
        setState(() => _hasSavedKey = key != null && key.isNotEmpty);
      }
    } catch (_) {
      if (mounted) setState(() => _status = '无法读取已保存的密钥');
    }
  }

  void _switch(AiProvider provider) {
    setState(() {
      _provider = provider;
      _model.text = _settings.modelFor(provider);
      _key.clear();
      _hasSavedKey = false;
      _status = '';
    });
    _readSavedKey();
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (_key.text.trim().isEmpty && !_hasSavedKey) {
        throw StateError('请填写 API 密钥');
      }
      await _settings.save(_provider, _model.text, newKey: _key.text);
      _key.clear();
      if (mounted) {
        setState(() {
          _hasSavedKey = true;
          _status = '已保存 ${_provider.label} 配置';
        });
      }
    } catch (error) {
      if (mounted) setState(() => _status = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _test() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = '正在测试连接';
    });
    try {
      final key = _key.text.trim().isNotEmpty
          ? _key.text.trim()
          : await _settings.keyFor(_provider) ?? '';
      await _service.testConnection(
        provider: _provider,
        model: _model.text.trim(),
        apiKey: key,
      );
      if (mounted) setState(() => _status = '连接成功');
    } catch (error) {
      if (mounted) setState(() => _status = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _message(Object error) => error is StateError
      ? error.message.toString()
      : error is ArgumentError
          ? error.message.toString()
          : '操作失败，请稍后重试';

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(borderRadius: BorderRadius.circular(2));
    return SettingCard(
      title: 'AI 日志分析',
      items: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<AiProvider>(
                key: ValueKey(_provider),
                initialValue: _provider,
                decoration: InputDecoration(labelText: 'AI 服务', border: border),
                items: AiProvider.values
                    .map((provider) => DropdownMenuItem(
                          value: provider,
                          child: Text(provider.label),
                        ))
                    .toList(),
                onChanged: _busy
                    ? null
                    : (provider) {
                        if (provider != null) _switch(provider);
                      },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _model,
                decoration: InputDecoration(labelText: '模型', border: border),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _key,
                obscureText: true,
                enableSuggestions: false,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: 'API 密钥',
                  hintText: _hasSavedKey ? '已保存；留空则保持原密钥' : '输入密钥',
                  border: border,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: _busy ? null : _save,
                    child: const Text('保存'),
                  ),
                  TextButton(
                    onPressed: _busy ? null : _test,
                    child: const Text('测试连接'),
                  ),
                  if (_hasSavedKey)
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () async {
                              await _settings.deleteKey(_provider);
                              if (mounted) {
                                setState(() {
                                  _hasSavedKey = false;
                                  _status = '密钥已清除';
                                });
                              }
                            },
                      child: const Text('清除密钥'),
                    ),
                ],
              ),
              if (_status.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(_status, style: Theme.of(context).textTheme.bodySmall),
              ],
              const SizedBox(height: 4),
              Text(
                '只在确认发送后请求 AI；不同服务的密钥分别保存在本机。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
