import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mpsc_combine_ai/admin/widgets/confirm_delete_dialog.dart';

void main() {
  test('formatAdminError surfaces permission-denied with deploy hint', () {
    final text = formatAdminError(
      FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
        message: 'Missing or insufficient permissions.',
      ),
    );
    expect(text, contains('permission-denied'));
    expect(text, contains('firestore.rules'));
    expect(text, contains('Missing or insufficient permissions.'));
  });

  test('formatAdminError falls back to toString for plain errors', () {
    expect(formatAdminError(StateError('boom')), contains('boom'));
  });
}
