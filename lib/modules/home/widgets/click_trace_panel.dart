import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:oasx/api/api_client.dart';
import 'package:oasx/api/sse_client.dart';
import 'package:oasx/modules/home/models/click_trace_models.dart';
import 'package:oasx/modules/log/log_browser_models.dart';
import 'package:oasx/translation/i18n_content.dart';

/// Shows the coordinates OAS actually clicked during the latest scheduler run.
class ClickTracePanel extends StatefulWidget {
  const ClickTracePanel({super.key, required this.scriptName});

  final String scriptName;

  @override
  State<ClickTracePanel> createState() => _ClickTracePanelState();
}

class _ClickTracePanelState extends State<ClickTracePanel> {
  static const int _pageSize = 2000;
  static const int _maxHistoryPages = 50;

  ClickTraceAccumulator _trace = ClickTraceAccumulator();
  final Set<String> _seenLineKeys = <String>{};
  ApiSseClient? _stream;
  bool _loading = true;
  bool _truncated = false;
  String _error = '';
  String? _selectedTask;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant ClickTracePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scriptName != widget.scriptName) {
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    _generation++;
    unawaited(_stream?.dispose());
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    final previousStream = _stream;
    _stream = null;
    if (previousStream != null) {
      unawaited(previousStream.dispose());
    }
    setState(() {
      _trace = ClickTraceAccumulator();
      _seenLineKeys.clear();
      _loading = true;
      _truncated = false;
      _error = '';
      _selectedTask = null;
    });

    try {
      final pages = <List<ScriptLogLine>>[];
      String? olderCursor;
      String liveCursor = '';
      bool foundRunStart = false;
      bool hasOlder = false;

      for (var page = 0; page < _maxHistoryPages; page++) {
        final window = await ApiClient().getScriptLogWindow(
          widget.scriptName,
          cursor: olderCursor,
          limitLines: _pageSize,
          limitBytes: 1048576,
        );
        if (!mounted || generation != _generation) return;
        if (page == 0) liveCursor = window.liveCursor;
        final relevant = window.lines
            .where(ClickTraceAccumulator.isRelevant)
            .toList(growable: false);
        pages.add(relevant);
        foundRunStart = relevant.any(ClickTraceAccumulator.isRunStart);
        hasOlder = window.hasOlder;
        if (foundRunStart || !hasOlder || window.olderCursor == null) break;
        olderCursor = window.olderCursor;
      }

      final trace = ClickTraceAccumulator();
      final seenKeys = <String>{};
      for (final page in pages.reversed) {
        for (final line in page) {
          if (seenKeys.add(line.key)) trace.add(line);
        }
      }
      if (!mounted || generation != _generation) return;
      setState(() {
        _trace = trace;
        _seenLineKeys.addAll(seenKeys);
        _loading = false;
        _truncated = !foundRunStart && trace.entries.isNotEmpty;
      });
      _startStream(liveCursor, generation);
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  void _startStream(String cursor, int generation) {
    final client = ApiSseClient(
      url: ApiClient().buildScriptLogStreamUri(
        widget.scriptName,
        cursor: cursor,
      ),
      onEvent: (event) => _handleEvent(event, generation),
      onStateChanged: (state, message) {
        if (!mounted || generation != _generation) return;
        if (state == ApiSseConnectionState.error && message != null) {
          setState(() => _error = message);
        } else if (state == ApiSseConnectionState.connected &&
            _error.isNotEmpty) {
          setState(() => _error = '');
        }
      },
    );
    _stream = client;
    unawaited(client.connect());
  }

  void _handleEvent(ApiSseEvent event, int generation) {
    if (!mounted || generation != _generation) return;
    if (event.name == 'error') {
      setState(() => _error = event.data);
      return;
    }
    if (event.name != 'append' || event.data.trim().isEmpty) return;
    try {
      final data = jsonDecode(event.data) as Map<String, dynamic>;
      final rawLines = data['lines'] as List? ?? const [];
      bool changed = false;
      bool startedNewRun = false;
      for (final raw in rawLines.whereType<Map>()) {
        final line = ScriptLogLine.fromJson(raw.cast<String, dynamic>());
        if (!ClickTraceAccumulator.isRelevant(line) ||
            !_seenLineKeys.add(line.key)) {
          continue;
        }
        startedNewRun = ClickTraceAccumulator.isRunStart(line) || startedNewRun;
        changed = _trace.add(line) || changed;
      }
      if (changed) {
        setState(() {
          if (startedNewRun) {
            _truncated = false;
            _selectedTask = null;
          }
        });
      }
    } catch (error) {
      setState(() => _error = error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = _trace.entries;
    final colorScheme = Theme.of(context).colorScheme;
    final colors = <String, Color>{};
    for (final entry in entries) {
      colors.putIfAbsent(entry.taskName, () {
        final hue = (colors.length * 137.508) % 360;
        return HSVColor.fromAHSV(1, hue, 0.72, 0.88).toColor();
      });
    }
    final visibleEntries = _selectedTask == null
        ? entries
        : entries.where((entry) => entry.taskName == _selectedTask).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '${I18n.homeClicksTab.tr} ${visibleEntries.length}/${entries.length}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const Spacer(),
            IconButton(
              tooltip: I18n.homeClicksRefresh.tr,
              onPressed: _loading ? null : () => unawaited(_load()),
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        if (_truncated)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              I18n.homeClicksTruncated.tr,
              style: TextStyle(color: colorScheme.error),
            ),
          ),
        if (_error.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              _error,
              style: TextStyle(color: colorScheme.error),
            ),
          ),
        if (!_loading && entries.isNotEmpty) ...[
          Text(
            I18n.homeClicksMap.tr,
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: CustomPaint(
                painter: _ClickTraceMapPainter(
                  entries: visibleEntries,
                  colors: colors,
                  background: colorScheme.surfaceContainerLow,
                  grid: colorScheme.outlineVariant,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              ChoiceChip(
                label: Text(I18n.homeClicksAll.tr),
                selected: _selectedTask == null,
                onSelected: (_) => setState(() => _selectedTask = null),
              ),
              for (final taskName in colors.keys)
                ChoiceChip(
                  avatar: CircleAvatar(
                    radius: 6,
                    backgroundColor: colors[taskName],
                  ),
                  label: Text(
                    taskName.isEmpty
                        ? I18n.homeClicksUnknownTask.tr
                        : taskName.tr,
                  ),
                  selected: _selectedTask == taskName,
                  onSelected: (_) => setState(() => _selectedTask = taskName),
                ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        Expanded(
          child: _loading
              ? Center(child: Text(I18n.homeClicksLoading.tr))
              : visibleEntries.isEmpty
                  ? Center(child: Text(I18n.homeClicksEmpty.tr))
                  : ListView.builder(
                      itemCount: visibleEntries.length,
                      itemBuilder: (context, index) {
                        final entry =
                            visibleEntries[visibleEntries.length - index - 1];
                        final taskName = entry.taskName.isEmpty
                            ? I18n.homeClicksUnknownTask.tr
                            : entry.taskName.tr;
                        return ListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 4,
                          ),
                          title: SelectableText(
                            '(${entry.x}, ${entry.y})',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(fontFamily: 'monospace'),
                          ),
                          subtitle: Text(
                            '$taskName · ${entry.targetName}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Text(entry.time),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}

class _ClickTraceMapPainter extends CustomPainter {
  const _ClickTraceMapPainter({
    required this.entries,
    required this.colors,
    required this.background,
    required this.grid,
  });

  final List<ClickTraceEntry> entries;
  final Map<String, Color> colors;
  final Color background;
  final Color grid;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = background);
    final gridPaint = Paint()
      ..color = grid.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    for (var part = 1; part < 4; part++) {
      final fraction = part / 4;
      canvas.drawLine(
        Offset(size.width * fraction, 0),
        Offset(size.width * fraction, size.height),
        gridPaint,
      );
      canvas.drawLine(
        Offset(0, size.height * fraction),
        Offset(size.width, size.height * fraction),
        gridPaint,
      );
    }
    for (final entry in entries) {
      final x = (entry.x / 1280 * size.width).clamp(0.0, size.width).toDouble();
      final y = (entry.y / 720 * size.height).clamp(0.0, size.height).toDouble();
      canvas.drawCircle(
        Offset(x, y),
        3.2,
        Paint()
          ..color = (colors[entry.taskName] ?? grid).withValues(alpha: 0.68),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ClickTraceMapPainter oldDelegate) => true;
}
