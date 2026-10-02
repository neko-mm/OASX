part of 'window_service.dart';

extension WindowServiceRestartX on WindowService {
  /// Lets the launcher wait until this process exits before starting OASX.
  Future<void> restartViaLauncher() async {
    if (!PlatformUtils.isWindows) {
      throw const FormatException('重启功能目前仅支持 Windows');
    }
    final installDirectory = File(Platform.resolvedExecutable).parent.path;
    final launcher = File('$installDirectory${Platform.pathSeparator}'
        'OASX.Launcher.exe');
    if (!await launcher.exists()) {
      throw const FormatException('找不到 OASX 启动器');
    }
    await Process.start(
      launcher.path,
      ['--wait-for-pid', '$pid'],
      workingDirectory: installDirectory,
      mode: ProcessStartMode.detached,
    );
    await windowManager.setPreventClose(false);
    await windowManager.close();
  }
}
