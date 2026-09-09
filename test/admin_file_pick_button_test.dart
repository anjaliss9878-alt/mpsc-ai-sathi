import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_file_pick_button.dart';

void main() {
  test('adminFileInputAccept formats extensions for HTML accept', () {
    expect(adminFileInputAccept(const ['pdf']), '.pdf');
    expect(adminFileInputAccept(const ['.PDF', 'jpg']), '.pdf,.jpg');
  });

  test('adminFileNameMatchesExtensions', () {
    expect(adminFileNameMatchesExtensions('MPSCAI_VERIFY_NOTE_20260908.pdf', const ['pdf']), isTrue);
    expect(adminFileNameMatchesExtensions('notes.PDF', const ['pdf']), isTrue);
    expect(adminFileNameMatchesExtensions('notes.docx', const ['pdf']), isFalse);
  });

  testWidgets('Upload PDF button is visible', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AdminFilePickButton(
            label: 'Upload PDF',
            icon: Icons.picture_as_pdf_rounded,
            allowedExtensions: ['pdf'],
            onPicked: _unused,
          ),
        ),
      ),
    );
    expect(find.text('Upload PDF'), findsOneWidget);
  });
}

void _unused(AdminPickedLocalFile _) {}
