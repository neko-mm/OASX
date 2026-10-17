import 'dart:async';

import 'package:flutter/material.dart';
import 'package:oasx/modules/server/models/deploy_progress.dart';

class DeployStagePanel extends StatelessWidget {
  static const panelHeight = 420.0;
  const DeployStagePanel({
    super.key,
    required this.title,
    required this.stages,
    required this.attempt,
    required this.pulse,
    required this.onViewLogs,
  });

  final String title;
  final List<DeployStage> stages;
  final int attempt;
  final Animation<double> pulse;
  final VoidCallback onViewLogs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.brightness == Brightness.dark
        ? const Color(0xFF80D8F3)
        : const Color(0xFF087C9D);
    final failed = stages.any(
      (stage) => stage.status == DeployStageStatus.failed,
    );
    final done =
        stages.isNotEmpty &&
        stages.every((stage) => stage.status == DeployStageStatus.done);
    final status = failed
        ? '未完成'
        : done
        ? '已完成'
        : '进行中';
    return Container(
      height: panelHeight,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.55),
        border: Border.all(color: accent.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  status,
                  style: TextStyle(
                    fontSize: 13,
                    color: failed
                        ? const Color(0xFFE4B85F)
                        : done
                        ? const Color(0xFF69C594)
                        : accent,
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: accent.withValues(alpha: 0.16)),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 8),
              child: _StageTimeline(
                key: ValueKey('$title-$attempt'),
                stages: stages,
                pulse: pulse,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Divider(height: 1, color: accent.withValues(alpha: 0.16)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: TextButton.icon(
              style: TextButton.styleFrom(
                shape: const RoundedRectangleBorder(),
              ),
              onPressed: onViewLogs,
              icon: Icon(Icons.arrow_forward, size: 18, color: accent),
              iconAlignment: IconAlignment.end,
              label: Text(
                '查看完整日志',
                style: TextStyle(color: accent, fontSize: 15),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StageTimeline extends StatefulWidget {
  const _StageTimeline({super.key, required this.stages, required this.pulse});
  final List<DeployStage> stages;
  final Animation<double> pulse;

  @override
  State<_StageTimeline> createState() => _StageTimelineState();
}

class _StageTimelineState extends State<_StageTimeline> {
  final _listKey = GlobalKey<AnimatedListState>();
  final _visible = <String>[];
  Timer? _reveal;
  bool _scheduled = false;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(covariant _StageTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);
    _schedule();
  }

  void _schedule() {
    if (_scheduled ||
        _reveal != null ||
        _visible.length >= widget.stages.length) {
      return;
    }
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      _showNext();
    });
  }

  void _showNext() {
    if (!mounted || _visible.length >= widget.stages.length) return;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final next = widget.stages.firstWhere(
      (stage) => !_visible.contains(stage.id),
    );
    _visible.add(next.id);
    _listKey.currentState?.insertItem(
      _visible.length - 1,
      duration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 280),
    );
    _reveal = Timer(
      reduceMotion ? Duration.zero : const Duration(milliseconds: 320),
      () {
        _reveal = null;
        _showNext();
      },
    );
  }

  @override
  void dispose() {
    _reveal?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedList(
      key: _listKey,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      initialItemCount: 0,
      itemBuilder: (context, index, animation) {
        final stage = widget.stages.firstWhere(
          (stage) => stage.id == _visible[index],
        );
        final eased = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return SizeTransition(
          sizeFactor: eased,
          axisAlignment: -1,
          child: FadeTransition(
            opacity: eased,
            child: SlideTransition(
              position: Tween(
                begin: const Offset(0, 0.12),
                end: Offset.zero,
              ).animate(eased),
              child: _StageRow(
                stage: stage,
                pulse: widget.pulse,
                last: index == widget.stages.length - 1,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _StageRow extends StatelessWidget {
  const _StageRow({
    required this.stage,
    required this.pulse,
    required this.last,
  });
  final DeployStage stage;
  final Animation<double> pulse;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = stage.status == DeployStageStatus.active;
    final failed = stage.status == DeployStageStatus.failed;
    final accent = theme.brightness == Brightness.dark
        ? const Color(0xFF80D8F3)
        : const Color(0xFF087C9D);
    final color = failed
        ? const Color(0xFFE4B85F)
        : active
        ? accent
        : theme.colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              AnimatedBuilder(
                animation: pulse,
                builder: (context, child) => Opacity(
                  opacity: active ? 0.65 + pulse.value * 0.35 : 1,
                  child: Icon(
                    failed
                        ? Icons.error_outline
                        : active
                        ? Icons.radio_button_checked
                        : Icons.check_circle_outline,
                    color: color,
                    size: 24,
                  ),
                ),
              ),
              if (!last)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Container(
                    width: 1,
                    height: 22,
                    color: accent.withValues(alpha: 0.35),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        stage.title,
                        style: TextStyle(
                          color: color,
                          fontSize: active ? 19 : 17,
                          height: 1.4,
                          fontWeight: active
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                    if (stage.percent != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 12),
                        child: Text(
                          '${stage.percent}%',
                          style: TextStyle(
                            color: accent,
                            fontSize: 28,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
                if (stage.percent != null) ...[
                  const SizedBox(height: 10),
                  LinearProgressIndicator(
                    value: stage.percent! / 100,
                    minHeight: 4,
                    semanticsLabel: stage.title,
                    semanticsValue: '${stage.percent}%',
                  ),
                ],
                if (stage.detail.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      stage.detail,
                      style: TextStyle(
                        color: color.withValues(alpha: 0.8),
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
