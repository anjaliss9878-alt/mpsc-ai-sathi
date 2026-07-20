import 'package:flutter/material.dart';

/// A subject/topic area (e.g. Polity, Economy) stored in Firestore at
/// `subjects/{id}`. Chapters and notes reference it via `subjectId`.
class SubjectItem {
  const SubjectItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.iconName,
    required this.order,
  });

  final String id;
  final String title;
  final String subtitle;
  final String iconName;
  final int order;

  IconData get icon => iconForName(iconName);

  factory SubjectItem.fromMap(Map<String, dynamic> map, String id) {
    return SubjectItem(
      id: id,
      title: map['title'] as String? ?? '',
      subtitle: map['subtitle'] as String? ?? '',
      iconName: map['iconName'] as String? ?? 'menu_book',
      order: (map['order'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'subtitle': subtitle,
      'iconName': iconName,
      'order': order,
      'updatedAt': DateTime.now().toIso8601String(),
    };
  }

  SubjectItem copyWith({
    String? title,
    String? subtitle,
    String? iconName,
    int? order,
  }) {
    return SubjectItem(
      id: id,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      iconName: iconName ?? this.iconName,
      order: order ?? this.order,
    );
  }
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
};
