import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:oasx/modules/home/widgets/deploy_stage_panel.dart';
import 'package:oasx/modules/server/controllers/server_controller.dart';
import 'package:oasx/modules/server/models/deploy_progress.dart';
import 'package:oasx/translation/i18n_content.dart';

class AutoDeployOverlay extends StatefulWidget {
  const AutoDeployOverlay({super.key, this.progress, this.onViewLogs});

  final DeployProgress? progress;
  final VoidCallback? onViewLogs;

  @override
  State<AutoDeployOverlay> createState() => _AutoDeployOverlayState();
}

class _AutoDeployOverlayState extends State<AutoDeployOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1700),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _pulse.stop();
      _pulse.value = 1;
    } else {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final server = Get.isRegistered<ServerController>()
        ? Get.find<ServerController>()
        : null;
    if (widget.progress != null) return _content(widget.progress!, server);
    if (server == null) {
      return _content(DeployProgress()..beginAttempt(0), null);
    }
    return Obx(() => _content(server.deployProgress.value, server));
  }

  Widget _content(DeployProgress progress, ServerController? server) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final accent = dark ? const Color(0xFF80D8F3) : const Color(0xFF087C9D);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.7);
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 300);
    void viewLogs() {
      if (widget.onViewLogs != null) {
        widget.onViewLogs!();
      } else if (server != null) {
        showDialog<void>(
          context: context,
          builder: (_) => _DeployLogDialog(server: server),
        );
      }
    }

    return LayoutBuilder(
      builder: (context, viewport) => Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(
            color: dark ? const Color(0xEF0E1921) : const Color(0xF2EAF1F4),
          ),
          CustomPaint(painter: _DeployGridPainter(dark: dark)),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 44, 24, 110),
              child: AnimatedContainer(
                duration: duration,
                curve: Curves.easeInOutCubic,
                width: math.min(
                  viewport.maxWidth - 48,
                  progress.showUpdate ? 1180.0 : 720.0,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: _ActivityRail(animation: _pulse, accent: accent),
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            I18n.homeLoadingAutoDeploying.tr,
                            style: TextStyle(
                              fontSize: viewport.maxWidth < 600 ? 28 : 40,
                              fontWeight: FontWeight.w600,
                              height: 1.2,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Semantics(
                            liveRegion: true,
                            child: Text(
                              progress.summary,
                              style: TextStyle(
                                color: muted,
                                fontSize: 17,
                                height: 1.4,
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          LayoutBuilder(
                            builder: (context, panels) {
                              final startup = DeployStagePanel(
                                title: 'OAS 启动',
                                stages: List.of(progress.startup),
                                attempt: progress.retry,
                                pulse: _pulse,
                                onViewLogs: viewLogs,
                              );
                              final update = DeployStagePanel(
                                title: 'OAS 更新',
                                stages: List.of(progress.update),
                                attempt: progress.retry,
                                pulse: _pulse,
                                onViewLogs: viewLogs,
                              );
                              if (viewport.maxWidth < 820) {
                                return Column(
                                  children: [
                                    startup,
                                    TweenAnimationBuilder<double>(
                                      tween: Tween(
                                        end: progress.showUpdate ? 1 : 0,
                                      ),
                                      duration: duration,
                                      builder: (context, value, child) =>
                                          ClipRect(
                                            child: Align(
                                              alignment: Alignment.topCenter,
                                              heightFactor: value,
                                              child: child,
                                            ),
                                          ),
                                      child: progress.showUpdate
                                          ? Padding(
                                              padding: const EdgeInsets.only(
                                                top: 16,
                                              ),
                                              child: update,
                                            )
                                          : const SizedBox.shrink(),
                                    ),
                                  ],
                                );
                              }
                              final updateWidth = (panels.maxWidth - 16) / 2;
                              return TweenAnimationBuilder<double>(
                                tween: Tween(end: progress.showUpdate ? 1 : 0),
                                duration: duration,
                                curve: Curves.easeInOutCubic,
                                builder: (context, value, child) => Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(child: startup),
                                    SizedBox(width: 16 * value),
                                    ClipRect(
                                      child: SizedBox(
                                        width: updateWidth * value,
                                        height: DeployStagePanel.panelHeight,
                                        child: OverflowBox(
                                          alignment: Alignment.centerLeft,
                                          minWidth: updateWidth,
                                          maxWidth: updateWidth,
                                          child: IgnorePointer(
                                            ignoring: value < 1,
                                            child: ExcludeSemantics(
                                              excluding: !progress.showUpdate,
                                              child: Opacity(
                                                opacity: ((value - 0.3) / 0.7)
                                                    .clamp(0.0, 1.0),
                                                child: progress.showUpdate
                                                    ? update
                                                    : const SizedBox.shrink(),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            right: 26,
            bottom: 22,
            child: TextButton(
              key: const ValueKey('go-deploy-page'),
              style: TextButton.styleFrom(
                shape: const RoundedRectangleBorder(),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),
              ),
              onPressed: () => Get.toNamed('/server'),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 2, height: 24, color: accent),
                  const SizedBox(width: 14),
                  Text(
                    I18n.homeGoDeployPage.tr,
                    style: const TextStyle(fontSize: 16),
                  ),
                  const SizedBox(width: 14),
                  const Icon(Icons.arrow_forward, size: 19),
                ],
              ),
            ),
          ),
          Positioned(
            left: 28,
            bottom: 22,
            child: Container(
              constraints: BoxConstraints(
                maxWidth: math.max(120, math.min(330, viewport.maxWidth - 270)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface.withValues(alpha: 0.65),
                border: Border(left: BorderSide(color: accent, width: 2)),
              ),
              child: Text(
                'OAS 尚未连接\n${progress.summary}',
                maxLines: 3,
                style: TextStyle(color: muted, fontSize: 13, height: 1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DeployLogDialog extends StatefulWidget {
  const _DeployLogDialog({required this.server});
  final ServerController server;

  @override
  State<_DeployLogDialog> createState() => _DeployLogDialogState();
}

class _DeployLogDialogState extends State<_DeployLogDialog> {
  late Future<String> _logs = widget.server.readCompleteDeployLog();

  @override
  Widget build(BuildContext context) => Dialog(
    shape: const RoundedRectangleBorder(),
    child: SizedBox(
      width: 960,
      height: MediaQuery.sizeOf(context).height * 0.75,
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('本次部署完整日志', style: TextStyle(fontSize: 20)),
                ),
                IconButton(
                  tooltip: '刷新',
                  onPressed: () => setState(() {
                    _logs = widget.server.readCompleteDeployLog();
                  }),
                  icon: const Icon(Icons.refresh),
                ),
                IconButton(
                  tooltip: '复制日志',
                  onPressed: () async {
                    await Clipboard.setData(
                      ClipboardData(
                        text: await widget.server.readCompleteDeployLog(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.copy_outlined),
                ),
                IconButton(
                  tooltip: '关闭',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const Divider(),
            Expanded(
              child: FutureBuilder<String>(
                future: _logs,
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  return SingleChildScrollView(
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: SelectableText(
                        snapshot.data!.isEmpty ? '暂无部署日志' : snapshot.data!,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 13,
                          height: 1.5,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ActivityRail extends StatelessWidget {
  const _ActivityRail({required this.animation, required this.accent});
  final Animation<double> animation;
  final Color accent;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 24,
    height: 180,
    child: AnimatedBuilder(
      animation: animation,
      builder: (context, child) => Column(
        children: [
          Container(
            width: 3,
            height: 60,
            decoration: BoxDecoration(
              color: accent,
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: 0.25 + animation.value * 0.2),
                  blurRadius: 12,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < 3; i++) ...[
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accent.withValues(
                  alpha:
                      0.35 +
                      0.65 *
                          ((math.sin(animation.value * math.pi * 2 - i) + 1) /
                              2),
                ),
              ),
            ),
            const SizedBox(height: 13),
          ],
          Expanded(
            child: Container(width: 2, color: accent.withValues(alpha: 0.12)),
          ),
        ],
      ),
    ),
  );
}

class _DeployGridPainter extends CustomPainter {
  const _DeployGridPainter({required this.dark});
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    if (dark) {
      final rect = Offset.zero & size;
      canvas.drawRect(
        rect,
        Paint()
          ..shader = const RadialGradient(
            center: Alignment(0.72, -0.82),
            radius: 1.15,
            colors: [Color(0x1835A8C5), Colors.transparent],
          ).createShader(rect),
      );
    }
    final line = Paint()
      ..color = (dark ? const Color(0xFF85CDE5) : const Color(0xFF28778D))
          .withValues(alpha: 0.045)
      ..strokeWidth = 1;
    for (var x = 80.0; x < size.width; x += 160) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
    }
    for (var y = 90.0; y < size.height; y += 160) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
  }

  @override
  bool shouldRepaint(covariant _DeployGridPainter oldDelegate) =>
      oldDelegate.dark != dark;
}
