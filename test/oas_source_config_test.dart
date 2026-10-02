import 'package:flutter_test/flutter_test.dart';
import 'package:oasx/modules/server/models/oas_source_config.dart';

void main() {
  const source = "Deploy:\r\n"
      "  Git:\r\n"
      "    Repository: 'https://github.com/old/OAS.git' # 当前仓库\r\n"
      "    Branch: 'master'\r\n"
      "    AutoUpdate: true\r\n"
      "  Python:\r\n"
      "    Executable: ./toolkit/python.exe\r\n";

  test('reads only the nested Git source', () {
    final config = OasSourceConfig.read(source);
    expect(config.repository, 'https://github.com/old/OAS.git');
    expect(config.branch, 'master');
  });

  test('preserves comments, other settings, quoting and line endings', () {
    final updated = OasSourceConfig.update(
      source,
      repository: 'https://github.com/neko-mm/OnmyojiAutoScript.git',
      branch: 'mine',
    );
    expect(updated, source
        .replaceFirst('https://github.com/old/OAS.git',
            'https://github.com/neko-mm/OnmyojiAutoScript.git')
        .replaceFirst("Branch: 'master'", "Branch: 'mine'"));
  });

  test('rejects missing Git keys and malformed values', () {
    expect(() => OasSourceConfig.read('Deploy:\n  Git:\n    Branch: mine'),
        throwsFormatException);
    expect(
      () => OasSourceConfig.update(source,
          repository: 'https://github.com/a/b.git\nAutoUpdate: false',
          branch: 'mine'),
      throwsFormatException,
    );
  });
}
