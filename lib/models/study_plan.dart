import 'package:mpsc_combine_ai/utils/json_list.dart';

/// AI-generated weekly study plan stored at
/// `students/{uid}/studyPlans/{weekKey}` where weekKey is `yyyy-Www`.
class StudyPlan {
  const StudyPlan({
    required this.weekKey,
    required this.title,
    required this.summary,
    required this.dailySlots,
    required this.weeklyGoals,
    required this.revisionReminders,
    this.generatedAt,
  });

  final String weekKey;
  final String title;
  final String summary;
  final List<StudyPlanDay> dailySlots;
  final List<String> weeklyGoals;
  final List<String> revisionReminders;
  final DateTime? generatedAt;

  Map<String, dynamic> toMap() => {
        'weekKey': weekKey,
        'title': title,
        'summary': summary,
        'dailySlots': dailySlots.map((d) => d.toMap()).toList(),
        'weeklyGoals': weeklyGoals,
        'revisionReminders': revisionReminders,
        'generatedAt': (generatedAt ?? DateTime.now()).toIso8601String(),
      };

  factory StudyPlan.fromMap(Map<String, dynamic> map, String weekKey) {
    return StudyPlan(
      weekKey: map['weekKey'] as String? ?? weekKey,
      title: map['title'] as String? ?? 'Weekly Plan',
      summary: map['summary'] as String? ?? '',
      dailySlots: asMapList(map['dailySlots']).map(StudyPlanDay.fromMap).toList(),
      weeklyGoals: asStringList(map['weeklyGoals']),
      revisionReminders: asStringList(map['revisionReminders']),
      generatedAt: DateTime.tryParse(map['generatedAt'] as String? ?? ''),
    );
  }

  static String weekKeyFor([DateTime? now]) {
    final d = now ?? DateTime.now();
    // ISO-ish week: year + day-of-year bucketed by 7.
    final startOfYear = DateTime(d.year, 1, 1);
    final dayOfYear = d.difference(startOfYear).inDays + 1;
    final week = ((dayOfYear - 1) ~/ 7) + 1;
    return '${d.year}-W${week.toString().padLeft(2, '0')}';
  }
}

class StudyPlanDay {
  const StudyPlanDay({
    required this.dayLabel,
    required this.slots,
  });

  final String dayLabel;
  final List<String> slots;

  Map<String, dynamic> toMap() => {
        'dayLabel': dayLabel,
        'slots': slots,
      };

  factory StudyPlanDay.fromMap(Map<String, dynamic> map) => StudyPlanDay(
        dayLabel: map['dayLabel'] as String? ?? '',
        slots: asStringList(map['slots']),
      );
}

/// Per-video watch progress at `students/{uid}/videoProgress/{videoId}`.
class VideoProgress {
  const VideoProgress({
    required this.videoId,
    required this.title,
    required this.subject,
    required this.progress,
    required this.completed,
    required this.playbackSpeed,
    this.updatedAt,
  });

  final String videoId;
  final String title;
  final String subject;
  final double progress;
  final bool completed;
  final double playbackSpeed;
  final DateTime? updatedAt;

  Map<String, dynamic> toMap() => {
        'videoId': videoId,
        'title': title,
        'subject': subject,
        'progress': progress,
        'completed': completed,
        'playbackSpeed': playbackSpeed,
        'updatedAt': (updatedAt ?? DateTime.now()).toIso8601String(),
      };

  factory VideoProgress.fromMap(Map<String, dynamic> map, String id) =>
      VideoProgress(
        videoId: map['videoId'] as String? ?? id,
        title: map['title'] as String? ?? '',
        subject: map['subject'] as String? ?? '',
        progress: (map['progress'] as num?)?.toDouble() ?? 0,
        completed: map['completed'] as bool? ?? false,
        playbackSpeed: (map['playbackSpeed'] as num?)?.toDouble() ?? 1.0,
        updatedAt: DateTime.tryParse(map['updatedAt'] as String? ?? ''),
      );
}
