import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:oasx/service/appearance_service.dart';

/// A restrained frosted panel; its fill responds to the appearance slider.
class GlassPanel extends StatelessWidget {
  const GlassPanel({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final appearance = Get.find<AppearanceService>();
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Obx(() {
      final opacity = appearance.panelOpacity.value;
      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Card(
            elevation: 0,
            color: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
              side: BorderSide(
                color: dark
                    ? const Color(0xFFB9C8D1).withValues(alpha: 0.22)
                    : const Color(0xFF687C88).withValues(alpha: 0.28),
              ),
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: dark
                      ? [
                          const Color(0xFF29404C).withValues(alpha: opacity),
                          const Color(0xFF20323D).withValues(alpha: opacity),
                          const Color(0xFF1B2A35).withValues(alpha: opacity),
                        ]
                      : [
                          Colors.white.withValues(alpha: opacity),
                          const Color(0xFFE7F0F4).withValues(alpha: opacity),
                        ],
                ),
              ),
              child: child,
            ),
          ),
        ),
      );
    });
  }
}
