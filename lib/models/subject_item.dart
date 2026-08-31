import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/models/exam_item.dart';
import 'package:mpsc_combine_ai/utils/json_list.dart';

/// A subject/topic area (e.g. राज्यशास्त्र) stored in Firestore at
/// `subjects/{id}`. Chapters and notes reference it via `subjectId`.
class SubjectItem {
  const SubjectItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.iconName,
    required this.order,
    this.imageUrl = '',
    this.slug = '',
    this.nameEn = '',
    this.examId = kDefaultExamId,
    this.published = true,
    this.updatedAt,
  });

  final String id;

  /// Primary display name (Marathi). Also written as `nameMr` in Firestore.
  final String title;
  final String subtitle;
  final String iconName;
  final int order;

  /// Optional cover image (uploaded to Firebase Storage from the Admin
  /// Panel). Falls back to [icon] in the student UI when empty.
  final String imageUrl;

  /// Stable English key for idempotent seeding (e.g. `rajyashastra`).
  final String slug;

  /// Optional English label for admin search / internal display.
  final String nameEn;

  /// Parent exam (`exams/{examId}`). Default is MPSC Combine.
  final String examId;

  /// When false, students do not see this subject. Missing field ⇒ published.
  final bool published;

  final DateTime? updatedAt;

  /// Alias for Marathi title (data-model docs / seed helpers).
  String get nameMr => title;

  IconData get icon => iconForName(iconName);

  factory SubjectItem.fromMap(Map<String, dynamic> map, String id) {
    final rawTitle = map['title'] ?? map['nameMr'] ?? map['name'];
    final title = rawTitle is String ? rawTitle.trim() : '';
    final nameMr = (map['nameMr'] as String?)?.trim() ?? '';
    return SubjectItem(
      id: id,
      title: title.isNotEmpty ? title : nameMr,
      subtitle: map['subtitle'] as String? ?? '',
      iconName: map['iconName'] as String? ?? 'menu_book',
      order: asInt(map['order']),
      imageUrl: map['imageUrl'] as String? ?? '',
      slug: map['slug'] as String? ?? '',
      nameEn: map['nameEn'] as String? ?? '',
      examId: (map['examId'] as String?)?.trim().isNotEmpty == true
          ? (map['examId'] as String).trim()
          : kDefaultExamId,
      published: asBool(map['published'], defaultValue: true),
      updatedAt: _parseUpdatedAt(map['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    final now = DateTime.now().toIso8601String();
    return {
      'title': title,
      'nameMr': title,
      'nameEn': nameEn,
      'subtitle': subtitle,
      'iconName': iconName,
      'order': order,
      'imageUrl': imageUrl,
      'slug': slug,
      'examId': examId.isEmpty ? kDefaultExamId : examId,
      'published': published,
      'updatedAt': now,
    };
  }

  SubjectItem copyWith({
    String? title,
    String? subtitle,
    String? iconName,
    int? order,
    String? imageUrl,
    String? slug,
    String? nameEn,
    String? examId,
    bool? published,
    DateTime? updatedAt,
  }) {
    return SubjectItem(
      id: id,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      iconName: iconName ?? this.iconName,
      order: order ?? this.order,
      imageUrl: imageUrl ?? this.imageUrl,
      slug: slug ?? this.slug,
      nameEn: nameEn ?? this.nameEn,
      examId: examId ?? this.examId,
      published: published ?? this.published,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

DateTime? _parseUpdatedAt(dynamic value) {
  if (value is String && value.isNotEmpty) {
    return DateTime.tryParse(value);
  }
  return null;
}

/// Maps a stored icon name (Admin Panel picker) to a concrete [IconData].
/// Extend this map when adding new icon choices to the admin subject form.
IconData iconForName(String name) {
  switch (name) {
    case 'account_balance':
      return Icons.account_balance_rounded;
    case 'trending_up':
      return Icons.trending_up_rounded;
    case 'public':
      return Icons.public_rounded;
    case 'history':
      return Icons.history_rounded;
    case 'science':
      return Icons.science_rounded;
    case 'calculate':
      return Icons.calculate_rounded;
    case 'gavel':
      return Icons.gavel_rounded;
    case 'psychology':
      return Icons.psychology_rounded;
    case 'eco':
      return Icons.eco_rounded;
    case 'newspaper':
      return Icons.newspaper_rounded;
    case 'translate':
      return Icons.translate_rounded;
    case 'menu_book':
    default:
      return Icons.menu_book_rounded;
  }
}

/// Icon choices offered in the Admin Panel's subject form.
const Map<String, IconData> subjectIconChoices = {
  'menu_book': Icons.menu_book_rounded,
  'account_balance': Icons.account_balance_rounded,
  'trending_up': Icons.trending_up_rounded,
  'public': Icons.public_rounded,
  'history': Icons.history_rounded,
  'science': Icons.science_rounded,
  'calculate': Icons.calculate_rounded,
  'gavel': Icons.gavel_rounded,
  'psychology': Icons.psychology_rounded,
  'eco': Icons.eco_rounded,
  'newspaper': Icons.newspaper_rounded,
  'translate': Icons.translate_rounded,
};
