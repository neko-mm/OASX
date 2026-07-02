import 'package:flutter_test/flutter_test.dart';
import 'package:oasx/config/constants.dart';

void main() {
  test('personal builds use the fork release feed', () {
    expect(
      updateUrlGithub,
      'https://api.github.com/repos/neko-mm/OASX/releases/latest',
    );
    expect(oasxRelease, 'https://github.com/neko-mm/OASX/releases');
  });
}
