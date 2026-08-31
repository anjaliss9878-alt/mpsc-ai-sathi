import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:mpsc_combine_ai/models/chat_message.dart';
import 'package:mpsc_combine_ai/services/ai_backend_base.dart';
import 'package:mpsc_combine_ai/services/backend_request_headers.dart';
import 'package:mpsc_combine_ai/utils/json_list.dart';

/// Thrown whenever the AI Teacher service cannot produce a reply — missing
/// configuration, a network failure, a non-200 response, or an unexpected
/// response shape. The [message] is safe to show directly to the student.
class AiServiceException implements Exception {
  const AiServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// System instruction that turns the model into an MPSC exam tutor.
///
/// Kept as a standalone constant so it can be reused or extended later
/// (e.g. by [AiTeacherService.sendMessage]'s `extraContext` parameter) once
/// Notes/MCQ/PYQ content is wired in as additional grounding context.
const String kAiTeacherSystemPrompt = '''
You are "AI Teacher" inside the MPSC COMBINE AI app — an expert, patient tutor
for the Maharashtra Public Service Commission (MPSC) Combine examination.

Rules you must always follow:
- Explain concepts as simply and clearly as possible, suitable for exam preparation.
- If the student asks in Marathi, reply in Marathi. If the student asks in English, reply in English.
- Stay focused strictly on the MPSC exam syllabus (Polity, Economy, Geography, History,
  Science & Technology, Current Affairs, and related exam topics) and give exam-oriented,
  concise explanations rather than generic essays.
- Never invent facts, dates, numbers, or figures. If you are not certain about something,
  clearly say so instead of guessing.
- Keep answers well-structured (short paragraphs or bullet points) so they are easy to revise from.
- Format your answer using Markdown: use **bold** for key terms, bullet/numbered lists for
  enumerations, and a Markdown table whenever you compare multiple items (e.g. articles,
  acts, dates, schemes) side by side — this renders directly in the app's chat.
''';

/// Abstraction over "send a chat message, get a reply" so the concrete AI
/// provider can be swapped later without touching the UI.
///
/// [extraContext] is intentionally unused today — it is the seam for later
/// connecting Notes/MCQ/PYQ repository content (e.g. the current chapter's
/// notes) as extra grounding context for the model, without changing this
/// interface or any calling code.
abstract class AiTeacherService {
  Future<String> sendMessage({
    required List<ChatMessage> history,
    required String userMessage,
    String? extraContext,
  });
}

/// [AiTeacherService] implementation backed by the Google Gemini
/// `generateContent` REST API.
///
/// Configuration is supplied entirely via compile-time environment values
/// (`--dart-define`) — no key is hardcoded and none is bundled with the app:
///
/// ```
/// flutter run -d chrome --dart-define=AI_API_KEY=your_gemini_api_key
/// ```
///
/// Optionally override the model with `--dart-define=AI_MODEL=gemini-2.0-flash`.
class GeminiAiTeacherService implements AiTeacherService {
  GeminiAiTeacherService({http.Client? client, String? apiKey})
      : _client = client ?? http.Client(),
        _apiKey = (apiKey ?? _envKey).trim();

  final http.Client _client;
  final String _apiKey;

  static const String _envKey = String.fromEnvironment('AI_API_KEY');
  static const String _model = String.fromEnvironment(
    'AI_MODEL',
    defaultValue: 'gemini-flash-latest',
  );
  static const String _baseUrl =
      'https://generativelanguage.googleapis.com/v1beta/models';

  String get _workerBase => aiBackendBase();

  @override
  Future<String> sendMessage({
    required List<ChatMessage> history,
    required String userMessage,
    String? extraContext,
  }) async {
    if (_apiKey.isEmpty) {
      return _sendViaBackend(
        history: history,
        userMessage: userMessage,
        extraContext: extraContext,
      );
    }

    final uri = Uri.parse('$_baseUrl/$_model:generateContent');

    final systemInstruction = extraContext == null || extraContext.trim().isEmpty
        ? kAiTeacherSystemPrompt
        : '$kAiTeacherSystemPrompt\n\nRelevant study material context:\n$extraContext';

    final contents = [
      ...history.map(
        (message) => {
          'role': message.isUser ? 'user' : 'model',
          'parts': [
            {'text': message.content},
          ],
        },
      ),
      {
        'role': 'user',
        'parts': [
          {'text': userMessage},
        ],
      },
    ];

    final body = jsonEncode({
      'systemInstruction': {
        'parts': [
          {'text': systemInstruction},
        ],
      },
      'contents': contents,
    });

    http.Response response;
    try {
      response = await _client
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'x-goog-api-key': _apiKey,
            },
            body: body,
          )
          .timeout(const Duration(seconds: 30));
    } catch (_) {
      throw const AiServiceException(
        'AI सेवेशी संपर्क होऊ शकला नाही. कृपया इंटरनेट कनेक्शन तपासा आणि पुन्हा प्रयत्न करा.\n'
        '(Could not reach the AI service. Please check your connection and retry.)',
      );
    }

    if (response.statusCode != 200) {
      throw const AiServiceException(
        'उत्तर मिळाले नाही. कृपया पुन्हा प्रयत्न करा.',
      );
    }

    try {
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final candidates = asMapList(decoded['candidates']);
      final firstCandidate = candidates.isNotEmpty ? candidates.first : null;
      final content = firstCandidate?['content'];
      final contentMap =
          content is Map ? Map<String, dynamic>.from(content) : null;
      final parts = asMapList(contentMap?['parts']);
      final text = parts.isNotEmpty ? parts.first['text'] as String? : null;

      if (text == null || text.trim().isEmpty) {
        throw const AiServiceException(
          'AI कडून रिकामे उत्तर मिळाले. कृपया पुन्हा प्रयत्न करा.\n'
          '(Received an empty response from the AI. Please retry.)',
        );
      }
      return text.trim();
    } on AiServiceException {
      rethrow;
    } catch (_) {
      throw const AiServiceException(
        'AI चे उत्तर वाचता आले नाही. कृपया पुन्हा प्रयत्न करा.\n'
        '(Could not parse the AI response. Please retry.)',
      );
    }
  }

  Future<String> _sendViaBackend({
    required List<ChatMessage> history,
    required String userMessage,
    String? extraContext,
  }) async {
    final uri = Uri.parse('$_workerBase/ai/doubt');
    http.Response response;
    try {
      response = await _client
          .post(
            uri,
            headers: await backendJsonHeaders(),
            body: jsonEncode({
              'message': userMessage,
              'extraContext': extraContext ?? '',
              'history': history
                  .map(
                    (m) => {
                      'role': m.isUser ? 'user' : 'model',
                      'content': m.content,
                    },
                  )
                  .toList(),
            }),
          )
          .timeout(const Duration(seconds: 60));
    } catch (_) {
      throw const AiServiceException(
        'उत्तर मिळाले नाही. कृपया पुन्हा प्रयत्न करा.',
      );
    }
    if (response.statusCode != 200) {
      throw const AiServiceException(
        'उत्तर मिळाले नाही. कृपया पुन्हा प्रयत्न करा.',
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw const AiServiceException(
        'उत्तर मिळाले नाही. कृपया पुन्हा प्रयत्न करा.',
      );
    }
    final text = '${decoded['reply'] ?? ''}'.trim();
    if (text.isEmpty) {
      throw const AiServiceException(
        'उत्तर मिळाले नाही. कृपया पुन्हा प्रयत्न करा.',
      );
    }
    return text;
  }
}

/// [AiTeacherService] implementation that returns canned, clearly-labelled
/// placeholder replies instead of calling any real backend.
///
/// Lets the entire AI Teacher flow — loading state, error state, and chat
/// history persistence in [chatRepository] — be built, run, and tested end
/// to end with zero external dependency and zero API key, since
/// [AiTeacherScreen] only ever talks to the [AiTeacherService] interface
/// and has no idea which implementation is actually behind it.
class MockAiTeacherService implements AiTeacherService {
  /// Trigger phrases (checked case-insensitively) that make the mock throw
  /// an [AiServiceException] on purpose, so the chat's error state (retry
  /// button, error bubble, etc.) can be exercised without a real failure.
  static const List<String> _errorTriggers = [
    'simulate error',
    'trigger error',
    'test error',
  ];

  @override
  Future<String> sendMessage({
    required List<ChatMessage> history,
    required String userMessage,
    String? extraContext,
  }) async {
    // Simulated network latency so the UI's loading indicator is genuinely
    // exercised rather than resolving instantly.
    await Future.delayed(const Duration(milliseconds: 900));

    final normalized = userMessage.trim().toLowerCase();
    if (_errorTriggers.any(normalized.contains)) {
      throw const AiServiceException(
        'ही एक चाचणी त्रुटी आहे (मॉक सेवा). कृपया पुन्हा प्रयत्न करा.\n'
        '(This is a simulated test error from the mock AI service. Please retry.)',
      );
    }

    final isMarathi = RegExp(r'[\u0900-\u097F]').hasMatch(userMessage);
    return _buildReply(userMessage.trim(), marathi: isMarathi, turnNumber: history.length + 1);
  }

  String _buildReply(String question, {required bool marathi, required int turnNumber}) {
    if (marathi) {
      return '''
🧪 **(मॉक उत्तर — खरी Gemini API अद्याप जोडलेली नाही)**

तुम्ही विचारले: _"$question"_

- हे एक तात्पुरते उदाहरण उत्तर आहे, जे कोणत्याही खऱ्या AI मॉडेलशिवाय तयार केले आहे.
- खरे, अचूक आणि परीक्षा-केंद्रित उत्तर मिळवण्यासाठी `AI_API_KEY` कॉन्फिगर करा — कोड किंवा UI मध्ये कोणताही बदल न करता.
- तोपर्यंत लोडिंग, चॅट इतिहास आणि त्रुटी हाताळणी पूर्णपणे कार्यरत आहे हे तपासण्यासाठी हे उत्तर वापरा.

_(संदेश क्रमांक: $turnNumber)_
''';
    }
    return '''
🧪 **(Mock reply — real Gemini API not connected yet)**

You asked: _"$question"_

- This is a placeholder answer generated without calling any real AI model.
- Configure `AI_API_KEY` to switch to real, exam-focused Gemini answers — no code or UI change required.
- Until then, use this reply to verify the chat flow end to end: loading state, history, and error handling.

_(Turn number: $turnNumber)_
''';
  }
}

// --- Single configuration point ------------------------------------------
//
// Set `AI_API_KEY` via `--dart-define=AI_API_KEY=your_gemini_api_key` (see
// [GeminiAiTeacherService]'s doc comment for the full command) to switch
// the whole app over to the real Gemini backend.
//
// Leave it unset — the default — to keep using [MockAiTeacherService].
// Nothing else needs to change either way: [AiTeacherScreen] only ever
// depends on the [AiTeacherService] interface below, never on a concrete
// implementation.
final AiTeacherService aiTeacherService = GeminiAiTeacherService();
