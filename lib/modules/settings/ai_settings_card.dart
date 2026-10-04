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
    const fieldWidth = 360.0;
    const fieldDecoration = InputDecoration(
      isDense: true,
      border: UnderlineInputBorder(),
      contentPadding: EdgeInsets.symmetric(vertical: 9),
    );
    return SizedBox(
      width: double.infinity,
      child: SettingCard(
        title: 'AI 日志分析',
        items: [
          _AiSettingRow(
            label: 'AI 服务',
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: fieldWidth),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<AiProvider>(
                  value: _provider,
                  isExpanded: true,
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
              ),
            ),
          ),
          _AiSettingRow(
            label: '模型',
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: fieldWidth),
              child: TextField(
                controller: _model,
                decoration: fieldDecoration.copyWith(hintText: '模型名称'),
              ),
            ),
          ),
          _AiSettingRow(
            label: 'API 密钥',
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: fieldWidth),
              child: TextField(
                controller: _key,
                obscureText: true,
                enableSuggestions: false,
                autocorrect: false,
                decoration: fieldDecoration.copyWith(
                  hintText: _hasSavedKey ? '已保存 · 留空不修改' : '输入密钥',
                ),
              ),
            ),
          ),
          _AiSettingRow(
            label: '连接',
            child: Wrap(
              alignment: WrapAlignment.end,
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
          ),
          if (_status.isNotEmpty)
            _AiSettingRow(
              label: '状态',
              child: Text(_status, style: Theme.of(context).textTheme.bodySmall),
            ),
        ],
      ),
    );
  }
}

class _AiSettingRow extends StatelessWidget {
  const _AiSettingRow({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 520;
        if (narrow) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label),
                const SizedBox(height: 4),
                Align(alignment: Alignment.centerRight, child: child),
              ],
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Text(label),
              const Spacer(),
              child,
            ],
          ),
        );
      },
    );
  }
}
