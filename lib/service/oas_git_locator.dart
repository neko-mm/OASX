import 'dart:io';

/// 将 OAS 根目录提供给先于 Flutter 启动的更新器。
class OasGitLocator {
  static const rootFileName = 'oasx-oas-root.txt';

  static void sync(String? root, {String? installDirectory}) {
    if (!Platform.isWindows) return;
    final directory =
        installDirectory ?? File(Platform.resolvedExecutable).parent.path;
    final file = File('$directory${Platform.pathSeparator}$rootFileName');
    final git = root == null || root.trim().isEmpty
        ? null
        : File('${root.trim()}${Platform.pathSeparator}toolkit'
            '${Platform.pathSeparator}Git${Platform.pathSeparator}mingw64'
            '${Platform.pathSeparator}bin${Platform.pathSeparator}git.exe');
    try {
      if (git != null && git.existsSync()) {
        file.writeAsStringSync(root!.trim(), flush: true);
      } else if (file.existsSync()) {
        file.deleteSync();
      }
    } on FileSystemException {
      // 路径缓存写入失败不影响 OASX 启动。
    }
  }
}
