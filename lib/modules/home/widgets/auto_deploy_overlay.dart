import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:oasx/modules/server/controllers/server_controller.dart';
import 'package:oasx/translation/i18n_content.dart';

/// 启动部署页展示实时日志，不使用写死的步骤或百分比。
class AutoDeployOverlay extends StatefulWidget {
  const AutoDeployOverlay({super.key});

  @override
  State<AutoDeployOverlay> createState() => _AutoDeployOverlayState();
}

class _AutoDeployOverlayState extends State<AutoDeployOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1700),
  )..repeat();
  final ScrollController _logScroll = ScrollController();

  @override
  void dispose() {
    _pulse.dispose();
    _logScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final accent = dark ? const Color(0xFF80D8F3) : const Color(0xFF087C9D);
    final foreground = dark ? Colors.white : const Color(0xFF172C37);
    final muted = dark ? const Color(0xFFA7BAC4) : const Color(0xFF536975);
    final server = Get.isRegistered<ServerController>()
        ? Get.find<ServerController>()
        : null;

    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(
          color: dark
              ? const Color(0xEF0E1921)
              : const Color(0xF2EAF1F4),
        ),
        CustomPaint(painter: _DeployGridPainter(dark: dark)),
        Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 36),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 950),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: _ActivityRail(animation: _pulse, accent: accent),
                  ),
                  const SizedBox(width: 28),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          I18n.homeLoadingAutoDeploying.tr,
                          style: TextStyle(
                            color: foreground,
                            fontSize: 38,
                            fontWeight: FontWeight.w600,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Obx(() => Text(
                              (server?.deployPhase.value ??
                                      I18n.homeDeployPreparing)
                                  .tr,
                              style: TextStyle(
                                color: muted,
                                fontSize: 18,
                                height: 1.35,
                              ),
                            )),
                        const SizedBox(height: 22),
                        _DeployLogPanel(
                          server: server,
                          scrollController: _logScroll,
                          dark: dark,
                          accent: accent,
                          muted: muted,
                        ),
                        const SizedBox(height: 14),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Semantics(
                            button: true,
                            label: I18n.homeGoDeployPage.tr,
                            child: InkWell(
                              onTap: () => Get.toNamed('/server'),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 12,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 2,
                                      height: 24,
                                      color: accent,
                                    ),
                                    const SizedBox(width: 15),
                                    Text(
                                      I18n.homeGoDeployPage.tr,
                                      style: TextStyle(
                                        color: accent,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Icon(
                                      Icons.arrow_forward_rounded,
                                      size: 19,
                                      color: accent,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
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
          left: 32,
          bottom: 20,
          child: Semantics(
            liveRegion: true,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 360),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: dark
                    ? const Color(0xDD12232D)
                    : const Color(0xE8EAF3F6),
                border: Border(left: BorderSide(color: accent, width: 2)),
              ),
              child: Text(
                I18n.homeDeployConnectionPending.tr,
                style: TextStyle(color: muted, fontSize: 13),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DeployLogPanel extends StatelessWidget {
  const _DeployLogPanel({
    required this.server,
    required this.scrollController,
    required this.dark,
    required this.accent,
    required this.muted,
  });

  final ServerController? server;
  final ScrollController scrollController;
  final bool dark;
  final Color accent;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 360,
      decoration: BoxDecoration(
        color: dark
            ? const Color(0x881A2A34)
            : const Color(0xB8FFFFFF),
        border: Border.all(
          color: accent.withValues(alpha: dark ? 0.14 : 0.22),
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Obx(() {
        final entries = server?.deployLogEntries.toList(growable: false) ??
            const <DeployLogEntry>[];
        if (entries.isEmpty) {
          return Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Text(
                I18n.homeDeployWaitingLog.tr,
                style: TextStyle(color: muted, fontSize: 14),
              ),
            ),
          );
        }
        return Scrollbar(
          controller: scrollController,
          thumbVisibility: entries.length > 9,
          child: ListView.builder(
            controller: scrollController,
            reverse: true,
            itemCount: entries.length,
            itemExtent: 37,
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
            itemBuilder: (context, index) {
              final entry = entries[entries.length - index - 1];
              return _DeployLogRow(
                entry: entry,
                newest: index == 0,
                accent: accent,
                muted: muted,
              );
            },
          ),
        );
      }),
    );
  }
}

class _DeployLogRow extends StatelessWidget {
  const _DeployLogRow({
    required this.entry,
    required this.newest,
    required this.accent,
    required this.muted,
  });

  final DeployLogEntry entry;
  final bool newest;
  final Color accent;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    final raw = entry.line.trim().replaceAll(RegExp(r'\s+'), ' ');
    final match = RegExp(r'^(INFO|WARNING|ERROR):?\s*', caseSensitive: false)
        .firstMatch(raw);
    final level = match?.group(1)?.toUpperCase() ?? 'INFO';
    final message = raw.substring(match?.end ?? 0);
    final severityColor = level == 'ERROR'
        ? Theme.of(context).colorScheme.error
        : newest
            ? accent
            : muted;
    final time = entry.time;
    final clock = '${_twoDigits(time.hour)}:${_twoDigits(time.minute)}:'
        '${_twoDigits(time.second)}';
    return Row(
      children: [
        SizedBox(
          width: 92,
          child: Text(
            clock,
            style: TextStyle(
              color: newest ? accent : muted.withValues(alpha: 0.8),
              fontSize: 14,
              fontFamily: 'monospace',
            ),
          ),
        ),
        SizedBox(
          width: 94,
          child: Text(
            '[$level]',
            style: TextStyle(
              color: severityColor,
              fontSize: 14,
              fontFamily: 'monospace',
            ),
          ),
        ),
        Expanded(
          child: Tooltip(
            message: message,
            child: Text(
              message,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: severityColor,
                fontSize: 15,
                fontWeight: newest ? FontWeight.w500 : FontWeight.w400,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

String _twoDigits(int value) => value.toString().padLeft(2, '0');

class _ActivityRail extends StatelessWidget {
  const _ActivityRail({required this.animation, required this.accent});

  final Animation<double> animation;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 30,
      height: 180,
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, child) {
          final brightness = 0.68 + 0.32 *
              math.sin(animation.value * math.pi * 2).abs();
          return Column(
            children: [
              Container(
                width: 3,
                height: 60,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: brightness),
                  borderRadius: BorderRadius.circular(2),
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(alpha: brightness * 0.45),
                      blurRadius: 10,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 13),
              for (var i = 0; i < 3; i++) ...[
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: accent.withValues(
                      alpha: 0.3 + 0.7 *
                          ((math.sin(animation.value * math.pi * 2 - i) + 1) /
                              2),
                    ),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(height: 13),
              ],
              Expanded(
                child: Container(
                  width: 2,
                  color: accent.withValues(alpha: 0.1),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DeployGridPainter extends CustomPainter {
  const _DeployGridPainter({required this.dark});

  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = dark
          ? const Color(0xFF85CDE5).withValues(alpha: 0.045)
          : const Color(0xFF28778D).withValues(alpha: 0.045)
      ..strokeWidth = 1;
    const spacing = 160.0;
    for (var x = 80.0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
    }
    for (var y = 90.0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
  }

  @override
  bool shouldRepaint(covariant _DeployGridPainter oldDelegate) =>
      oldDelegate.dark != dark;
}
