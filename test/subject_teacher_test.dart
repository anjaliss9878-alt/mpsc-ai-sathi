import 'package:flutter_test/flutter_test.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/subject_teacher.dart';

void main() {
  test('detects Polity, History, Geography, Economics and Science from topic text', () {
    expect(
      detectMpscTeachingSubject('मूलभूत अधिकार कलम १४'),
      MpscTeachingSubject.polity,
    );
    expect(
      detectMpscTeachingSubject('छत्रपती शिवाजी महाराज १६७४'),
      MpscTeachingSubject.history,
    );
    expect(
      detectMpscTeachingSubject('गोदावरी नदी महाराष्ट्राचा भूगोल'),
      MpscTeachingSubject.geography,
    );
    expect(
      detectMpscTeachingSubject('चलनवाढ आणि आर बी आय रेपो दर'),
      MpscTeachingSubject.economics,
    );
    expect(
      detectMpscTeachingSubject('प्रकाशसंश्लेषण आणि पेशी'),
      MpscTeachingSubject.science,
    );
    expect(detectMpscTeachingSubject('sansad'), MpscTeachingSubject.polity);
    expect(detectMpscTeachingSubject('संसद'), MpscTeachingSubject.polity);
    expect(detectMpscTeachingSubject('मान्सून'), MpscTeachingSubject.geography);
    expect(detectMpscTeachingSubject('1857 चा उठाव'), MpscTeachingSubject.history);
    expect(
      detectMpscTeachingSubject('Coding Decoding'),
      MpscTeachingSubject.science,
    );
    expect(
      detectMpscTeachingSubject(
        'Blood relations',
        hint: 'Intelligence Test & Arithmetic',
      ),
      MpscTeachingSubject.science,
    );
    expect(
      detectMpscTeachingSubject('An unclassified MPSC factoid xyz'),
      MpscTeachingSubject.science,
    );
  });

  test('subject teachers keep distinct Marathi classroom styles', () {
    expect(
      MpscTeachingSubject.polity.classroomHook,
      isNot(MpscTeachingSubject.economics.classroomHook),
    );
    expect(
      MpscTeachingSubject.history.classroomHook,
      isNot(MpscTeachingSubject.polity.classroomHook),
    );
    expect(lessonSystemPrompt(MpscTeachingSubject.polity), contains('POLITY'));
    expect(lessonSystemPrompt(MpscTeachingSubject.history), contains('HISTORY'));
    expect(
      lessonSystemPrompt(MpscTeachingSubject.geography),
      contains('GEOGRAPHY'),
    );
    expect(
      lessonSystemPrompt(MpscTeachingSubject.economics),
      contains('ECONOMICS'),
    );
    expect(
      lessonSystemPrompt(MpscTeachingSubject.science),
      contains('SCIENCE'),
    );
  });
}
