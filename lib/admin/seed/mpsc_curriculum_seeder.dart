import 'package:mpsc_combine_ai/data/subject_notes_data.dart';
import 'package:mpsc_combine_ai/models/chapter_item.dart';
import 'package:mpsc_combine_ai/models/subject_item.dart';
import 'package:mpsc_combine_ai/services/notes_repository.dart';

/// Seeds the full MPSC Combine curriculum into Firestore:
/// 10 subjects × every listed topic as `chapters`.
///
/// Idempotent by [SubjectItem.slug] / [ChapterItem.slug] — safe to re-run.
/// Does **not** overwrite Admin-authored PDF/summary/MCQ content on existing
/// chapters (upsert preserves non-empty content fields).
Future<String> seedMpscCurriculumStructure({
  NotesRepository? repository,
}) async {
  final repo = repository ?? notesRepository;
  var subjectsCreated = 0;
  var subjectsUpdated = 0;
  var chaptersCreated = 0;
  var chaptersUpdated = 0;

  for (var i = 0; i < subjectNotesCatalog.length; i++) {
    final catalog = subjectNotesCatalog[i];
    final existingSubject = await repo.findSubjectBySlug(catalog.slug);
    final subjectId = await repo.upsertSubjectBySlug(
      SubjectItem(
        id: '',
        title: catalog.title,
        subtitle: catalog.subtitle,
        iconName: _iconNameForCatalog(catalog),
        order: i,
        slug: catalog.slug,
        nameEn: catalog.titleEn,
        published: true,
      ),
    );
    if (existingSubject == null) {
      subjectsCreated++;
    } else {
      subjectsUpdated++;
    }

    for (var j = 0; j < catalog.topics.length; j++) {
      final topicTitle = catalog.topics[j];
      final slug = topicSlug(catalog.slug, topicTitle, j);
      final existingChapter = await repo.findChapterBySlug(
        subjectId: subjectId,
        slug: slug,
      );
      await repo.upsertChapterBySlug(
        ChapterItem(
          id: '',
          subjectId: subjectId,
          title: topicTitle,
          order: j,
          slug: slug,
          published: true,
          tags: [catalog.title, catalog.titleEn],
        ),
      );
      if (existingChapter == null) {
        chaptersCreated++;
      } else {
        chaptersUpdated++;
      }
    }
  }

  return 'MPSC रचना: '
      '$mpscCurriculumSubjectCount विषय '
      '(+$subjectsCreated / ~$subjectsUpdated), '
      '$mpscCurriculumTopicCount टॉपिक '
      '(+$chaptersCreated / ~$chaptersUpdated).';
}

String _iconNameForCatalog(SubjectNotesData catalog) {
  switch (catalog.id) {
    case 'rajyashastra':
      return 'account_balance';
    case 'bhugol':
      return 'public';
    case 'arthavyavastha':
      return 'trending_up';
    case 'itihas':
      return 'history';
    case 'chalu_ghadamodi':
      return 'newspaper';
    case 'ankganit':
      return 'calculate';
    case 'buddhibatta':
      return 'psychology';
    case 'samanya_vigyan':
      return 'science';
    case 'marathi':
      return 'translate';
    case 'english':
      return 'menu_book';
    default:
      return 'menu_book';
  }
}
