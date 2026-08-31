import 'package:mpsc_combine_ai/utils/json_list.dart';

/// Admin-authored recruitment / exam alert at `jobAlerts/{id}`.
///
/// Students only see [published] documents. Status is derived from dates,
/// never stored as a fake feed.
enum JobAlertLifecycle { draft, newlyPosted, active, closingSoon, closed }

class JobAlert {
  const JobAlert({
    required this.id,
    required this.examName,
    required this.organization,
    required this.post,
    required this.eligibility,
    required this.description,
    required this.applicationUrl,
    required this.published,
    this.importantDates = '',
    this.applicationStartDate = '',
    this.lastDate = '',
    this.createdAt,
    this.updatedAt,
  });

  final String id;

  /// Exam / recruitment name.
  final String examName;
  final String organization;
  final String post;
  final String eligibility;
  final String description;
  final String importantDates;

  /// `yyyy-MM-dd` when set.
  final String applicationStartDate;

  /// Application last date as `yyyy-MM-dd`.
  final String lastDate;
  final String applicationUrl;
  final bool published;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  String get title => examName.trim().isNotEmpty ? examName.trim() : post;

  DateTime? get lastDateTime => DateTime.tryParse(lastDate.trim());
  DateTime? get startDateTime => DateTime.tryParse(applicationStartDate.trim());

  JobAlertLifecycle lifecycle([DateTime? now]) {
    if (!published) return JobAlertLifecycle.draft;
    final clock = now ?? DateTime.now();
    final today = DateTime(clock.year, clock.month, clock.day);
    final close = lastDateTime;
    if (close != null) {
      final closeDay = DateTime(close.year, close.month, close.day);
      if (closeDay.isBefore(today)) return JobAlertLifecycle.closed;
      final daysLeft = closeDay.difference(today).inDays;
      if (daysLeft <= 7) return JobAlertLifecycle.closingSoon;
    }
    final created = createdAt;
    if (created != null && today.difference(DateTime(created.year, created.month, created.day)).inDays <= 7) {
      return JobAlertLifecycle.newlyPosted;
    }
    return JobAlertLifecycle.active;
  }

  String get statusLabel => lifecycle().label;

  Map<String, dynamic> toMap() => {
        'examName': examName,
        'organization': organization,
        'post': post,
        'eligibility': eligibility,
        'description': description,
        'importantDates': importantDates,
        'applicationStartDate': applicationStartDate,
        'lastDate': lastDate,
        'applicationUrl': applicationUrl,
        'published': published,
        'createdAt': (createdAt ?? DateTime.now()).toIso8601String(),
        'updatedAt': DateTime.now().toIso8601String(),
      };

  factory JobAlert.fromMap(Map<String, dynamic> map, String id) {
    return JobAlert(
      id: id,
      examName: map['examName'] as String? ?? map['title'] as String? ?? '',
      organization: map['organization'] as String? ?? '',
      post: map['post'] as String? ?? '',
      eligibility: map['eligibility'] as String? ?? '',
      description: map['description'] as String? ?? '',
      importantDates: map['importantDates'] as String? ?? '',
      applicationStartDate: map['applicationStartDate'] as String? ?? '',
      lastDate: map['lastDate'] as String? ?? '',
      applicationUrl: map['applicationUrl'] as String? ?? map['url'] as String? ?? '',
      published: asBool(map['published'], defaultValue: true),
      createdAt: DateTime.tryParse(map['createdAt'] as String? ?? ''),
      updatedAt: DateTime.tryParse(map['updatedAt'] as String? ?? ''),
    );
  }

  JobAlert copyWith({
    String? examName,
    String? organization,
    String? post,
    String? eligibility,
    String? description,
    String? importantDates,
    String? applicationStartDate,
    String? lastDate,
    String? applicationUrl,
    bool? published,
  }) {
    return JobAlert(
      id: id,
      examName: examName ?? this.examName,
      organization: organization ?? this.organization,
      post: post ?? this.post,
      eligibility: eligibility ?? this.eligibility,
      description: description ?? this.description,
      importantDates: importantDates ?? this.importantDates,
      applicationStartDate: applicationStartDate ?? this.applicationStartDate,
      lastDate: lastDate ?? this.lastDate,
      applicationUrl: applicationUrl ?? this.applicationUrl,
      published: published ?? this.published,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}

extension JobAlertLifecycleX on JobAlertLifecycle {
  String get label => switch (this) {
        JobAlertLifecycle.draft => 'Draft',
        JobAlertLifecycle.newlyPosted => 'New',
        JobAlertLifecycle.active => 'Active',
        JobAlertLifecycle.closingSoon => 'Closing Soon',
        JobAlertLifecycle.closed => 'Closed',
      };
}
