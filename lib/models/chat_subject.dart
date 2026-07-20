import 'package:flutter/material.dart';

/// MPSC syllabus subject a chat session is auto-categorized under, based on
/// its first message. Used to badge chats in the history drawer.
enum ChatSubject {
  polity,
  economy,
  geography,
  history,
  science,
  currentAffairs,
  csat,
  general,
}

extension ChatSubjectX on ChatSubject {
  String get label {
    switch (this) {
      case ChatSubject.polity:
        return 'राज्यव्यवस्था';
      case ChatSubject.economy:
        return 'अर्थव्यवस्था';
      case ChatSubject.geography:
        return 'भूगोल';
      case ChatSubject.history:
        return 'इतिहास';
      case ChatSubject.science:
        return 'विज्ञान व तंत्रज्ञान';
      case ChatSubject.currentAffairs:
        return 'चालू घडामोडी';
      case ChatSubject.csat:
        return 'CSAT';
      case ChatSubject.general:
        return 'सामान्य';
    }
  }

  IconData get icon {
    switch (this) {
      case ChatSubject.polity:
        return Icons.account_balance_rounded;
      case ChatSubject.economy:
        return Icons.trending_up_rounded;
      case ChatSubject.geography:
        return Icons.public_rounded;
      case ChatSubject.history:
        return Icons.history_edu_rounded;
      case ChatSubject.science:
        return Icons.science_rounded;
      case ChatSubject.currentAffairs:
        return Icons.newspaper_rounded;
      case ChatSubject.csat:
        return Icons.psychology_alt_rounded;
      case ChatSubject.general:
        return Icons.chat_bubble_outline_rounded;
    }
  }

  Color get color {
    switch (this) {
      case ChatSubject.polity:
        return const Color(0xFF3F51B5);
      case ChatSubject.economy:
        return const Color(0xFF2E7D32);
      case ChatSubject.geography:
        return const Color(0xFF00838F);
      case ChatSubject.history:
        return const Color(0xFF8D6E63);
      case ChatSubject.science:
        return const Color(0xFF6A1B9A);
      case ChatSubject.currentAffairs:
        return const Color(0xFFD84315);
      case ChatSubject.csat:
        return const Color(0xFF1565C0);
      case ChatSubject.general:
        return const Color(0xFF5A6B85);
    }
  }

  static ChatSubject fromName(String? name) {
    return ChatSubject.values.firstWhere(
      (s) => s.name == name,
      orElse: () => ChatSubject.general,
    );
  }
}
