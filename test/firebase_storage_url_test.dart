import 'package:flutter_test/flutter_test.dart';
import 'package:mpsc_combine_ai/models/content_index.dart';
import 'package:mpsc_combine_ai/utils/firebase_storage_url.dart';

void main() {
  test('parses Firebase Storage download URLs to object paths', () {
    const url =
        'https://firebasestorage.googleapis.com/v0/b/mpsc-3f4ef.appspot.com/o/notes%2F1710000000_Polity.pdf?alt=media&token=abc-123';
    expect(isFirebaseStorageUrl(url), isTrue);
    expect(isValidFirebaseDownloadUrl(url), isTrue);
    expect(
      firebaseStorageObjectPath(url),
      'notes/1710000000_Polity.pdf',
    );
  });

  test('parses firebasestorage.app download URLs', () {
    const url =
        'https://firebasestorage.googleapis.com/v0/b/mpsc-3f4ef.firebasestorage.app/o/notes%2Ffile.pdf?alt=media&token=x';
    expect(isValidFirebaseDownloadUrl(url), isTrue);
    expect(firebaseStorageObjectPath(url), 'notes/file.pdf');
  });

  test('parses gs:// and relative Storage paths', () {
    expect(
      firebaseStorageObjectPath('gs://mpsc-3f4ef.appspot.com/notes/a.pdf'),
      'notes/a.pdf',
    );
    expect(firebaseStorageObjectPath('notes/a.pdf'), 'notes/a.pdf');
    expect(isValidFirebaseDownloadUrl('notes/a.pdf'), isTrue);
  });

  test('rejects empty and non-Storage links', () {
    expect(isValidFirebaseDownloadUrl(''), isFalse);
    expect(isValidFirebaseDownloadUrl('https://example.com/a.pdf'), isFalse);
  });

  test('admin RAG label is Pending until indexed', () {
    expect(noteRagStatusAdminLabel(NoteRagStatus.notIndexed), 'Pending');
    expect(noteRagStatusAdminLabel(NoteRagStatus.indexed), 'Indexed');
    expect(noteRagStatusAdminLabel(NoteRagStatus.failed), 'Failed');
    expect(noteRagStatusLabel(NoteRagStatus.notIndexed), 'Not Indexed');
  });
}
