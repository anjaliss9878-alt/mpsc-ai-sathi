import 'dart:convert';

import 'package:mpsc_combine_ai/models/chat_message.dart';
import 'package:mpsc_combine_ai/models/study_plan.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_service.dart';
import 'package:mpsc_combine_ai/utils/json_list.dart';

/// Builds / parses weekly MPSC study plans via the shared Gemini teacher service.
class StudyPlannerService {
  StudyPlannerService({AiTeacherService? ai}) : _ai = ai ?? aiTeacherService;

  final AiTeacherService _ai;

  Future<StudyPlan> generateWeeklyPlan({
    String targetExam = 'MPSC Combine',
    int dailyHours = 4,
  }) async {
    final weekKey = StudyPlan.weekKeyFor();
    final prompt = '''
Create a practical 7-day MPSC Combine study timetable as JSON only (no markdown fences).
Target exam: $targetExam
Daily available study hours: $dailyHours

Return exactly this JSON shape:
{
  "title": "string",
  "summary": "1-2 sentence overview",
  "weeklyGoals": ["goal1", "goal2", "goal3"],
  "revisionReminders": ["reminder1", "reminder2"],
  "dailySlots": [
    {"dayLabel": "Monday", "slots": ["06:30-07:30 Polity notes", "19:00-20:00 MCQ Practice"]}
  ]
}

Cover: History, Geography, Polity, Economy, Science, Environment, Current Affairs, Marathi, English, Reasoning.
Include revision + one mock/test slot in the week. Keep slots realistic for $dailyHours hours/day.
''';

    try {
      final raw = await _ai.sendMessage(
        history: const <ChatMessage>[],
        userMessage: prompt,
      );
      final parsed = _parsePlanJson(raw, weekKey);
      if (parsed != null) return parsed;
    } catch (_) {
      // Fall through to deterministic offline plan.
    }
    return _fallbackPlan(weekKey, dailyHours);
  }

  StudyPlan? _parsePlanJson(String raw, String weekKey) {
    final start = raw.indexOf('{');
    final end = raw.lastIndexOf('}');
    if (start < 0 || end <= start) return null;
    try {
      final map = jsonDecode(raw.substring(start, end + 1)) as Map<String, dynamic>;
      final days = asMapList(map['dailySlots'])
          .map(StudyPlanDay.fromMap)
          .where((d) => d.dayLabel.isNotEmpty)
          .toList();
      if (days.isEmpty) return null;
      return StudyPlan(
        weekKey: weekKey,
        title: map['title'] as String? ?? 'MPSC Weekly Plan',
        summary: map['summary'] as String? ?? '',
        dailySlots: days,
        weeklyGoals: asStringList(map['weeklyGoals']),
        revisionReminders: asStringList(map['revisionReminders']),
        generatedAt: DateTime.now(),
      );
    } catch (_) {
      return null;
    }
  }

  StudyPlan _fallbackPlan(String weekKey, int dailyHours) {
    const subjects = [
      ('Monday', 'Polity — Constitution basics + Fundamental Rights'),
      ('Tuesday', 'History — Modern Maharashtra + Freedom struggle'),
      ('Wednesday', 'Geography — Maharashtra physical + resources'),
      ('Thursday', 'Economy — Budget, schemes, Maharashtra economy'),
      ('Friday', 'Science & Environment — ecology + tech current'),
      ('Saturday', 'Current Affairs digest + Marathi/English grammar'),
      ('Sunday', 'Full revision + Reasoning + timed mock test'),
    ];
    return StudyPlan(
      weekKey: weekKey,
      title: 'MPSC Combine — $dailyHours hr/day plan',
      summary:
          'Balanced weekly timetable covering core GS subjects, language, reasoning, and one mock.',
      dailySlots: [
        for (final s in subjects)
          StudyPlanDay(
            dayLabel: s.$1,
            slots: [
              'Morning: ${s.$2}',
              'Evening: 45 min MCQ / flashcard revision',
            ],
          ),
      ],
      weeklyGoals: const [
        'Finish 5 chapter note blocks',
        'Attempt 150+ MCQs',
        'Complete 1 timed mock + wrong-answer review',
      ],
      revisionReminders: const [
        'Revise yesterday notes for 20 minutes before new study',
        'Bookmark weak MCQs and retry on Sunday',
      ],
      generatedAt: DateTime.now(),
    );
  }
}

final StudyPlannerService studyPlannerService = StudyPlannerService();
