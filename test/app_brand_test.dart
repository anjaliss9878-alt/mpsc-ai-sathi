import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mpsc_combine_ai/theme/app_brand.dart';

void main() {
  test('product name and high-res logo are wired for live web', () {
    expect(kAppName, 'MPSC AI SATHI');
    expect(File(kAppLogoAsset).existsSync(), isTrue);
    expect(File('web/icons/Icon-512.png').existsSync(), isTrue);
    expect(File('web/favicon.png').existsSync(), isTrue);
    expect(File('web/manifest.json').readAsStringSync(), contains(kAppName));
  });
}
