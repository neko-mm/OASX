import 'package:flutter/material.dart';
import 'package:oasx/service/ai_analysis/ai_analysis_service.dart';
import 'package:oasx/service/ai_analysis/ai_log_analysis.dart';
import 'package:oasx/service/ai_analysis/ai_provider.dart';

/// On-demand, text-only analysis of the selected OAS configuration's logs.
class AiAnalysisPanel extends StatefulWidget {
  const AiAnalysisPanel({super.key, required this.scriptName});

  final String scriptName;

  @override
  State<AiAnalysisPanel> createState() => _AiAnalysisPanelState();
}

class _AiAnalysisPanelState extends State<AiAnalysisPanel> {
  final _service = AiAnalysisService();
  final _settings = AiProviderSettings();
  String _summary = '';
  String _result = '';
  String _status = '';
  bool _busy = false;

  @override
  void didUpdateWidget(covariant AiAnalysisPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scriptName != widget.scriptName) {
      _summary = '';
      _result = '';
      _status = '';
    }
  }

  Future<void> _analyze() async {
    if (_busy || widget.scriptName.trim().isEmpty) return;
    final scriptName = widget.scriptName;
    setState(() {
      _busy = true;
      _status = '正在读取日志';
    });
    try {
      final draft = await _service.loadCurrentRun(scriptName);
      if (!mounted || widget.scriptName != scriptName) return;
      final summary = AiLogAnalysis.localSummary(
        draft.text,
        partial: draft.partial,
      );
      setState(() {
        _summary = summary;
        _result = '';
        _status = draft.partial ? '只取得部分日志' : '';
      });
      if (draft.text.isEmpty) return;

      final provider = _settings.selected;
      final apiKey = await _settings.keyFor(provider);
      if (!mounted || widget.scriptName != scriptName) return;
      if (apiKey == null || apiKey.isEmpty) {
        setState(() => _status = '未设置 API 密钥；已完成本地分析');
        return;
      }

      final textToSend = await _confirmText(draft, provider);
      if (!mounted || widget.scriptName != scriptName || textToSend == null) {
        return;
      }
      if (textToSend.trim().isEmpty) {
        setState(() => _status = '没有可发送的日志');
        return;
      }
      setState(() => _status = '正在分析日志');
      final result = await _service.analyze(
        provider: provider,
        model: _settings.modelFor(provider),
        apiKey: apiKey,
        logText: textToSend,
      );
      if (!mounted || widget.scriptName != scriptName) return;
      setState(() {
        _result = result;
        _status = draft.partial ? '基于部分日志分析' : '分析完成';
      });
    } catch (error) {
      if (mounted && widget.scriptName == scriptName) {
        setState(() => _status = error is StateError
            ? error.message.toString()
            : '分析失败，请稍后重试');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _confirmText(AiLogDraft draft, AiProvider provider) async {
    final editor = TextEditingController(text: draft.text);
    try {
      return await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('发送给 ${provider.label}'),
          content: SizedBox(
            width: 680,
            height: 440,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${draft.lineCount} 行文字日志${draft.partial ? ' · 记录不完整' : ''}。'
                  '请检查并删除可能包含账号的信息；不会发送截图。',
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: TextField(
                    controller: editor,
                    expands: true,
                    maxLines: null,
                    minLines: null,
                    keyboardType: TextInputType.multiline,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: '将发送的文字（可编辑）',
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('仅看本地判断'),
            ),
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(editor.text),
              child: const Text('确认发送'),
            ),
          ],
        ),
      );
    } finally {
      // The dialog may still be disposing its field during the current frame.
      WidgetsBinding.instance.addPostFrameCallback((_) => editor.dispose());
    }
  }

  void _showFullResult() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('AI 日志分析'),
        content: SizedBox(
          width: 650,
          height: 430,
          child: SingleChildScrollView(child: SelectableText(_result)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 146,
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 6),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome_outlined,
                  color: theme.colorScheme.primary, size: 18),
              const SizedBox(width: 8),
              Text('AI 助手', style: theme.textTheme.titleSmall),
              const Spacer(),
              TextButton(
                onPressed: _busy || widget.scriptName.trim().isEmpty
                    ? null
                    : _analyze,
                child: Text(_busy ? '分析中' : '分析本轮'),
              ),
            ],
          ),
          if (_status.isNotEmpty)
            Text(_status, style: theme.textTheme.bodySmall),
          const SizedBox(height: 4),
          if (_summary.isNotEmpty)
            Text(
              _summary,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
          if (_result.isNotEmpty) ...[
            const SizedBox(height: 4),
            Expanded(
              child: InkWell(
                onTap: _showFullResult,
                child: Text(
                  _result,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
