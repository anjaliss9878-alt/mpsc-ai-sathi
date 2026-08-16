import 'package:mpsc_combine_ai/utils/json_list.dart';

/// One slide inside a [TeachingSlideDeckItem] — either an uploaded image or
/// a PDF page/deck link.
class TeachingSlide {
  const TeachingSlide({required this.url, required this.type, this.caption = ''});

  final String url;

  /// `image` or `pdf`.
  final String type;
  final String caption;

  factory TeachingSlide.fromMap(Map<String, dynamic> map) {
    return TeachingSlide(
      url: map['url'] as String? ?? '',
      type: map['type'] as String? ?? 'image',
      caption: map['caption'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() => {'url': url, 'type': type, 'caption': caption};
}

/// An ordered deck of teaching slides for a subject/chapter, stored in
/// Firestore at `teachingSlides/{id}` with the slide list embedded directly
/// (same pattern as [TestItem.questions]).
class TeachingSlideDeckItem {
  const TeachingSlideDeckItem({
    required this.id,
    required this.title,
    required this.subjectId,
    required this.chapterId,
    required this.slides,
    required this.order,
  });

  final String id;
  final String title;
  final String subjectId;
  final String chapterId;
  final List<TeachingSlide> slides;
  final int order;

  factory TeachingSlideDeckItem.fromMap(Map<String, dynamic> map, String id) {
    return TeachingSlideDeckItem(
      id: id,
      title: map['title'] as String? ?? '',
      subjectId: map['subjectId'] as String? ?? '',
      chapterId: map['chapterId'] as String? ?? '',
      slides: asMapList(map['slides']).map(TeachingSlide.fromMap).toList(),
      order: (map['order'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'subjectId': subjectId,
      'chapterId': chapterId,
      'slides': slides.map((s) => s.toMap()).toList(),
      'order': order,
      'updatedAt': DateTime.now().toIso8601String(),
    };
  }
}
