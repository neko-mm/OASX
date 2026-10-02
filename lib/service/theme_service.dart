import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:oasx/config/theme.dart';
import 'package:oasx/modules/common/models/storage_key.dart';
import 'package:oasx/service/system_tray_service.dart';
import 'package:oasx/utils/platform_utils.dart';

class ThemeService extends GetxService {
  final _storage = GetStorage();
  final _dark = false.obs;
  final _color = ColorSeed.baseColor.color.obs;

  bool get isDarkMode => _dark.value;
  Color get color => _color.value;

  ThemeMode get themeMode => isDarkMode ? ThemeMode.dark : ThemeMode.light;

  @override
  void onInit() {
    // Apply the approved dark design once to existing light-theme installs.
    // Any theme choice made afterward stays under the user's control.
    final visualVersion = _storage.read(StorageKey.visualThemeVersion.name);
    if (PlatformUtils.isWindows &&
        (visualVersion is! int || visualVersion < 1)) {
      _dark.value = true;
      _storage.write(StorageKey.visualThemeVersion.name, 1);
    } else {
      _dark.value = _storage.read(StorageKey.dark.name) ?? true;
    }
    switchTheme(_dark.value);
    super.onInit();
  }

  void switchTheme([bool? dark]) {
    _dark.value = dark ?? !_dark.value;
    _storage.write(StorageKey.dark.name, _dark.value);
    Get.changeThemeMode(themeMode);
    if (Get.isRegistered<SystemTrayService>()) {
      Get.find<SystemTrayService>().syncTrayTheme(_dark.value);
    }
  }
}
