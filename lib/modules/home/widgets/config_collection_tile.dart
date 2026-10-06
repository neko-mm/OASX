import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:oasx/modules/home/controllers/dashboard_controller.dart';
import 'package:oasx/modules/home/models/config_model.dart';
import 'package:oasx/modules/home/widgets/config_collection_script_label.dart';
import 'package:oasx/modules/home/widgets/config_collection_task_preview.dart';
import 'package:oasx/translation/i18n_content.dart';

class ConfigCollectionTile extends StatelessWidget {
  const ConfigCollectionTile({
    super.key,
    required this.controller,
    required this.script,
    required this.onTap,
    required this.onTogglePower,
    required this.onRename,
    required this.onExport,
    required this.onDelete,
  });

  static const _actionSpacing = 8.0;
  static const _compactLayoutThreshold = 200.0;
  final HomeDashboardController controller;
  final ScriptModel script;
  final VoidCallback onTap;
  final VoidCallback onTogglePower;
  final VoidCallback onRename;
  final VoidCallback onExport;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        return Obx(() {
          final isActive = controller.activeScriptName.value == script.name;
          final showLinkCheckbox = controller.isLinkModeEnabled.value;
          final isLinked = controller.isScriptLinked(script.name);
          final isDragCopyLoading = controller.isDragCopyPendingFor(
            script.name,
          );
          final compactThreshold =
              ConfigCollectionTile._compactLayoutThreshold +
              (showLinkCheckbox ? 64 : 0);
          final isCompact = constraints.maxWidth < compactThreshold;
          final rowColor = isActive
              ? theme.colorScheme.primaryContainer.withValues(alpha: 0.18)
              : Colors.transparent;
          final state = controller.scriptCollectionStateFor(script);
          final accentColor = _accentColor(context, state);
          return Material(
            color: rowColor,
            child: InkWell(
              onTap: isDragCopyLoading ? null : onTap,
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: isCompact ? 8 : 10,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (showLinkCheckbox) ...[
                      SizedBox(
                        width: 36,
                        height: 36,
                        child: Checkbox(
                          value: isLinked,
                          onChanged: (value) => controller.setScriptLinked(
                            script.name,
                            value ?? false,
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                      const SizedBox(width: 2),
                    ],
                    Expanded(
                      child: Stack(
                        children: [
                          AbsorbPointer(
                            absorbing: isDragCopyLoading,
                            child: _ScriptMeta(
                              script: script,
                              compact: isCompact,
                              powerButton: _PowerButton(
                                onTogglePower: onTogglePower,
                                state: state,
                                color: accentColor,
                              ),
                              popupButton: _ActionMenuButton(
                                onRename: onRename,
                                onExport: onExport,
                                onDelete: onDelete,
                              ),
                            ),
                          ),
                          if (isDragCopyLoading)
                            const Positioned.fill(
                              child: _DragCopyLoadingMask(),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        });
      },
    );
  }

  Color _accentColor(BuildContext context, HomeScriptStateFilter value) {
    final scheme = Theme.of(context).colorScheme;
    return switch (value) {
      HomeScriptStateFilter.running => Colors.green.shade600,
      HomeScriptStateFilter.stopped => scheme.outline,
      HomeScriptStateFilter.abnormal => Colors.amber.shade600,
      HomeScriptStateFilter.offline => scheme.outline,
      HomeScriptStateFilter.all => scheme.outline,
    };
  }
}

class _ScriptMeta extends StatelessWidget {
  const _ScriptMeta({
    required this.script,
    required this.compact,
    required this.powerButton,
    required this.popupButton,
  });

  final ScriptModel script;
  final bool compact;
  final Widget powerButton;
  final Widget popupButton;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            powerButton,
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ConfigCollectionScriptLabel(script: script, centered: false),
                  const SizedBox(height: 4),
                  ConfigCollectionTaskPreview(script: script),
                ],
              ),
            ),
            popupButton,
          ],
        ),
      );
    }
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          powerButton,
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ConfigCollectionScriptLabel(script: script, centered: false),
                const SizedBox(height: 6),
                ConfigCollectionTaskPreview(script: script),
              ],
            ),
          ),
          const SizedBox(width: ConfigCollectionTile._actionSpacing),
          popupButton,
        ],
      ),
    );
  }
}

class _DragCopyLoadingMask extends StatelessWidget {
  const _DragCopyLoadingMask();

  @override
  Widget build(BuildContext context) {
    return AbsorbPointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.68),
          borderRadius: BorderRadius.circular(3),
        ),
        child: const Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        ),
      ),
    );
  }
}

class _PowerButton extends StatelessWidget {
  const _PowerButton({
    required this.onTogglePower,
    required this.state,
    required this.color,
  });

  final VoidCallback onTogglePower;
  final HomeScriptStateFilter state;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final active = state == HomeScriptStateFilter.running ||
        state == HomeScriptStateFilter.abnormal;
    return IconButton(
      onPressed: onTogglePower,
      tooltip: state == HomeScriptStateFilter.running ? '停止任务' : '启动任务',
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(width: 32, height: 32),
      padding: EdgeInsets.zero,
      iconSize: 23,
      icon: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active ? color.withValues(alpha: 0.13) : Colors.transparent,
          boxShadow: active
              ? [BoxShadow(color: color.withValues(alpha: 0.25), blurRadius: 9)]
              : null,
        ),
        child: Icon(Icons.power_settings_new_rounded, color: color, size: 23),
      ),
    );
  }
}

class _ActionMenuButton extends StatelessWidget {
  const _ActionMenuButton({
    required this.onRename,
    required this.onExport,
    required this.onDelete,
  });

  final VoidCallback onRename;
  final VoidCallback onExport;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 32,
      child: PopupMenuButton<String>(
        padding: EdgeInsets.zero,
        tooltip: '',
        icon: const Icon(Icons.more_vert_rounded, size: 18),
        onSelected: (value) async {
          if (value == 'rename') {
            onRename();
            return;
          }
          if (value == 'export') {
            onExport();
            return;
          }
          onDelete();
        },
        itemBuilder: (context) => [
          PopupMenuItem(value: 'rename', child: Text(I18n.rename.tr)),
          PopupMenuItem(value: 'export', child: Text(I18n.configExport.tr)),
          PopupMenuItem(value: 'delete', child: Text(I18n.delete.tr)),
        ],
      ),
    );
  }
}
