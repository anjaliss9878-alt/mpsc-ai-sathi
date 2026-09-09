import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_select_field.dart';
import 'package:mpsc_combine_ai/models/exam_item.dart';

void main() {
  test('committedSelectId never substitutes the first exam', () {
    expect(
      committedSelectId(kGroupBCombinedExamId, [
        kDefaultExamId,
        kGroupBCombinedExamId,
      ]),
      kGroupBCombinedExamId,
    );
    expect(
      committedSelectId('missing', [kDefaultExamId, kGroupBCombinedExamId]),
      isNull,
    );
    expect(committedSelectId('', [kDefaultExamId]), isNull);
  });

  test('uniqueAdminSelectItems keeps first id only', () {
    final items = uniqueAdminSelectItems(const [
      AdminSelectItem(id: kDefaultExamId, label: 'A'),
      AdminSelectItem(id: kDefaultExamId, label: 'dup'),
      AdminSelectItem(id: kGroupBCombinedExamId, label: 'B'),
    ]);
    expect(items.map((e) => e.id).toList(), [
      kDefaultExamId,
      kGroupBCombinedExamId,
    ]);
  });

  testWidgets('Exam menu item tap commits Group B Combined id', (tester) async {
    String? selected = kDefaultExamId;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return AdminSelectField(
                label: 'Exam',
                value: selected,
                items: [
                  AdminSelectItem(
                    id: kDefaultExamId,
                    label: ExamItem.mpscCombine().title,
                  ),
                  AdminSelectItem(
                    id: kGroupBCombinedExamId,
                    label: ExamItem.groupBCombined().title,
                  ),
                ],
                onChanged: (id) => setState(() => selected = id),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text(ExamItem.mpscCombine().title));
    await tester.pumpAndSettle();
    await tester.tap(find.text(ExamItem.groupBCombined().title).last);
    await tester.pumpAndSettle();

    expect(selected, kGroupBCombinedExamId);
    expect(find.text(ExamItem.groupBCombined().title), findsWidgets);
  });
}
