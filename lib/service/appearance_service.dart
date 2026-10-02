import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:oasx/modules/common/models/storage_key.dart';

/// Persists the desktop background and the opacity of content panels.
class AppearanceService extends GetxService {
  final _storage = GetStorage();
  final panelOpacity = 0.74.obs;
  final backgroundImagePath = ''.obs;

  @override
  void onInit() {
    final savedOpacity = _storage.read(StorageKey.appearancePanelOpacity.name);
    if (savedOpacity is num) {
      panelOpacity.value = savedOpacity.toDouble().clamp(0.45, 0.95).toDouble();
    }
    backgroundImagePath.value =
        _storage.read(StorageKey.appearanceBackgroundImage.name) ?? '';
    super.onInit();
  }

  void setPanelOpacity(double value) {
    panelOpacity.value = value.clamp(0.45, 0.95).toDouble();
  }

  Future<void> persistPanelOpacity() =>
      _storage.write(StorageKey.appearancePanelOpacity.name, panelOpacity.value);

  Future<void> setBackgroundImage(String path) async {
    backgroundImagePath.value = path;
    await _storage.write(StorageKey.appearanceBackgroundImage.name, path);
  }
}
