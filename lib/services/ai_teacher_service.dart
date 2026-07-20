import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:mpsc_combine_ai/models/chat_message.dart';

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
  GeminiAiTeacherService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const String _apiKey = String.fromEnvironment('AI_API_KEY');
  static const String _model = String.fromEnvironment(
    'AI_MODEL',
    defaultValue: 'gemini-2.0-flash',
  );
  static const String _baseUrl =
      'https://generativelanguage.googleapis.com/v1beta/models';

  @override
  Future<String> sendMessage({
    required List<ChatMessage> history,
    required String userMessage,
    String? extraContext,
  }) async {
    if (_apiKey.isEmpty) {
      throw const AiServiceException(
        'AI सेवा अद्याप कॉन्फिगर केलेली नाही. कृपया AI_API_KEY सेट करा.\n'
        '(AI service is not configured yet. Please set the AI_API_KEY '
        'environment variable and restart the app.)',
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
      throw AiServiceException(
        'AI सेवेकडून उत्तर मिळाले नाही (कोड ${response.statusCode}). कृपया पुन्हा प्रयत्न करा.\n'
        '(AI service returned an error, code ${response.statusCode}. Please retry.)',
      );
    }

    try {
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final candidates = decoded['candidates'] as List<dynamic>?;
      final firstCandidate = candidates?.isNotEmpty == true
          ? candidates!.first as Map<String, dynamic>
          : null;
      final content = firstCandidate?['content'] as Map<String, dynamic>?;
      final parts = content?['parts'] as List<dynamic>?;
      final text = parts?.isNotEmpty == true
          ? (parts!.first as Map<String, dynamic>)['text'] as String?
          : null;

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
}

/// Shared instance used by the AI Teacher screen. Swap this single line for
/// a different [AiTeacherService] implementation if the provider changes.
final AiTeacherService aiTeacherService = GeminiAiTeacherService();
