import 'package:flutter_test/flutter_test.dart';

import 'package:mpsc_combine_ai/main.dart';

void main() {
  testWidgets('Home screen renders app title', (WidgetTester tester) async {
    await tester.pumpWidget(const MpscCombineApp());
    await tester.pump(const Duration(seconds: 1));

    expect(find.textContaining('MPSC'), findsWidgets);
  });
}
