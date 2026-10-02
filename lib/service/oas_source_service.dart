import 'dart:io';
import 'dart:async';

import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:oasx/modules/common/models/storage_key.dart';
import 'package:oasx/modules/server/controllers/server_controller.dart';
import 'package:oasx/modules/server/models/deploy_git_config.dart';
import 'package:oasx/modules/server/models/oas_source_config.dart';
import 'package:oasx/service/window_service.dart';

/// Reads and changes the two Git values in the selected OAS deploy.yaml.
class OasSourceService extends GetxService {
  final _storage = GetStorage();
  final path = ''.obs;
  final branch = ''.obs;

  @override
  void onInit() {
    path.value = _storage.read(StorageKey.oasDeployYamlPath.name) ?? '';
    if (path.value.isEmpty) {
      final root = _storage.read(StorageKey.rootPathServer.name);
      if (root is String && root.isNotEmpty) {
        final candidate = File('$root${Platform.pathSeparator}config'
            '${Platform.pathSeparator}deploy.yaml');
        if (candidate.existsSync()) path.value = candidate.path;
      }
    }
    if (path.value.isNotEmpty) {
      unawaited(read(path.value).catchError((Object _) {
        return const OasSourceConfig(repository: '', branch: '');
      }));
    }
    super.onInit();
  }

  Future<OasSourceConfig> read(String filePath) async {
    final file = File(filePath);
    if (file.uri.pathSegments.last.toLowerCase() != 'deploy.yaml' ||
        !await file.exists()) {
      throw const FormatException('请选择 OAS 的 deploy.yaml');
    }
    final config = OasSourceConfig.read(await file.readAsString());
    if (path.value == filePath) branch.value = config.branch;
    return config;
  }

  Future<void> save(
    String filePath, {
    required String repository,
    required String branch,
  }) async {
    final file = File(filePath);
    final original = await file.readAsString();
    final updated = OasSourceConfig.update(
      original,
      repository: repository,
      branch: branch,
    );
    if (updated != original) {
      final backup = File('$filePath.oasx-backup-'
          '${DateTime.now().microsecondsSinceEpoch}');
      await backup.writeAsString(original, flush: true);
      var canRemoveBackup = false;
      try {
        await file.writeAsString(updated, flush: true);
        OasSourceConfig.read(await file.readAsString());
        canRemoveBackup = true;
      } catch (_) {
        await file.writeAsString(original, flush: true);
        canRemoveBackup = true;
        rethrow;
      } finally {
        if (canRemoveBackup && await backup.exists()) await backup.delete();
      }
    }
    path.value = filePath;
    this.branch.value = branch.trim();
    await _storage.write(StorageKey.oasDeployYamlPath.name, filePath);
  }

  /// Runs the existing OAS installer/start routine, then relaunches OASX.
  Future<bool> restartBoth(String filePath) async {
    final root = File(filePath).parent.parent.path;
    final server = Get.isRegistered<ServerController>()
        ? Get.find<ServerController>()
        : Get.put(ServerController(), permanent: true);
    if (!server.authenticatePath(root)) {
      throw const FormatException('无法识别 OAS 安装目录');
    }
    if (!DeployGitConfig.read(root).autoUpdate) {
      throw const FormatException('请先在 deploy.yaml 中开启 AutoUpdate');
    }
    server.updateRootPathServer(root);
    final started = await server.run();
    if (!started) return false;
    await Get.find<WindowService>().restartViaLauncher();
    return true;
  }
}
