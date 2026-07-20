/// Detailed notes for a chapter, stored in Firestore at `notes/{id}`.
///
/// Kept as two bullet-point lists (matching the existing student UI in
/// `NotesDetailScreen`) rather than free-form rich text, so the Admin Panel
/// form can stay a simple, reliable "one bullet per line" editor.
class NoteItem {
  const NoteItem({
    required this.id,
    required this.subjectId,
    required this.chapterId,
    required this.importantPoints,
    required this.revisionSummary,
  });

  final String id;
  final String subjectId;
  final String chapterId;
  final List<String> importantPoints;
  final List<String> revisionSummary;

  factory NoteItem.fromMap(Map<String, dynamic> map, String id) {
    return NoteItem(
      id: id,
      subjectId: map['subjectId'] as String? ?? '',
      chapterId: map['chapterId'] as String? ?? '',
      importantPoints: List<String>.from(
        map['importantPoints'] as List? ?? const [],
      ),
      revisionSummary: List<String>.from(
        map['revisionSummary'] as List? ?? const [],
      ),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'subjectId': subjectId,
      'chapterId': chapterId,
      'importantPoints': importantPoints,
      'revisionSummary': revisionSummary,
      'updatedAt': DateTime.now().toIso8601String(),
    };
  }
}
