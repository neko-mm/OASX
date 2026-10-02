import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:oasx/modules/settings/widgets/setting_card.dart';
import 'package:oasx/service/appearance_service.dart';
import 'package:oasx/translation/i18n_content.dart';
import 'package:oasx/utils/platform_utils.dart';

class AppearanceSettingsCard extends StatelessWidget {
  const AppearanceSettingsCard({super.key});

  Future<void> _chooseImage(AppearanceService service) async {
    final selected = await FilePicker.platform.pickFiles(type: FileType.image);
    final path = selected?.files.single.path;
    if (path != null) await service.setBackgroundImage(path);
  }

  @override
  Widget build(BuildContext context) {
    final service = Get.find<AppearanceService>();
    return SettingCard(
      title: I18n.appearance.tr,
      items: [
        if (PlatformUtils.isDesktop) _AppearanceItem(
          label: I18n.backgroundImage.tr,
          child: Obx(() => Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              Text(
                service.backgroundImagePath.value.isEmpty
                    ? I18n.defaultBackground.tr
                    : service.backgroundImagePath.value.split(RegExp(r'[/\\]')).last,
                overflow: TextOverflow.ellipsis,
              ),
              OutlinedButton(
                onPressed: () => _chooseImage(service),
                child: Text(I18n.chooseImage.tr),
              ),
              if (service.backgroundImagePath.value.isNotEmpty)
                IconButton(
                  tooltip: I18n.clearImage.tr,
                  onPressed: () => service.setBackgroundImage(''),
                  icon: const Icon(Icons.close_rounded),
                ),
            ],
          )),
        ),
        _AppearanceItem(
          label: I18n.panelOpacity.tr,
          child: Obx(() => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 180,
                child: Slider(
                  min: 0.45,
                  max: 0.95,
                  divisions: 10,
                  value: service.panelOpacity.value,
                  onChanged: service.setPanelOpacity,
                  onChangeEnd: (_) => service.persistPanelOpacity(),
                ),
              ),
              SizedBox(
                width: 42,
                child: Text('${(service.panelOpacity.value * 100).round()}%'),
              ),
            ],
          )),
        ),
      ],
    );
  }
}

class _AppearanceItem extends StatelessWidget {
  const _AppearanceItem({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final narrow = constraints.maxWidth < 420;
      if (narrow) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [Text(label), const SizedBox(height: 8), child],
          ),
        );
      }
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            SizedBox(width: 150, child: Text(label)),
            Expanded(child: Align(alignment: Alignment.centerRight, child: child)),
          ],
        ),
      );
    });
  }
}
