import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:oasx/service/appearance_service.dart';
import 'package:oasx/utils/platform_utils.dart';

/// The low-contrast background underneath translucent panels.
class AppBackground extends StatelessWidget {
  const AppBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final appearance = Get.find<AppearanceService>();
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: dark
                  ? const [
                      Color(0xFF29424F),
                      Color(0xFF1B303C),
                      Color(0xFF111F2A),
                    ]
                  : const [Color(0xFFE2E8EC), Color(0xFFD3DDE3), Color(0xFFC8D7DD)],
            ),
          ),
        ),
        Obx(() {
          final path = appearance.backgroundImagePath.value;
          if (!PlatformUtils.isDesktop || path.isEmpty) {
            return const SizedBox.shrink();
          }
          final file = File(path);
          if (!file.existsSync()) return const SizedBox.shrink();
          return ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
            child: Image.file(
              file,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          );
        }),
        ColoredBox(
          color: dark
              ? const Color(0xFF101A22).withValues(alpha: 0.30)
              : Colors.white.withValues(alpha: 0.18),
        ),
        if (dark) ...[
          const IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0.72, -0.82),
                  radius: 1.15,
                  colors: [Color(0x6635A8C5), Colors.transparent],
                  stops: [0, 1],
                ),
              ),
            ),
          ),
          const IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(-0.90, 0.85),
                  radius: 1.10,
                  colors: [Color(0x50406B9E), Colors.transparent],
                  stops: [0, 1],
                ),
              ),
            ),
          ),
        ],
        child,
      ],
    );
  }
}
