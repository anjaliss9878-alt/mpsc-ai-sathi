/// Typed RAG failures with messages safe to show in Admin / student UI.
class RagException implements Exception {
  const RagException(this.code, this.message);

  /// Stable machine code (used in tests and logs).
  final String code;
  final String message;

  @override
  String toString() => message;

  static const String pdfExtractionFailed = 'pdf_extraction_failed';
  static const String emptyDocument = 'empty_document';
  static const String embeddingFailed = 'embedding_failed';
  static const String vectorSearchFailed = 'vector_search_failed';
  static const String permissionDenied = 'permission_denied';
  static const String geminiFailed = 'gemini_failed';
  static const String networkFailed = 'network_failed';
  static const String processingFailed = 'processing_failed';
  static const String emptyQuery = 'empty_query';

  factory RagException.pdfExtraction([String detail = '']) {
    return RagException(
      pdfExtractionFailed,
      _join(
        'PDF मधून मजकूर काढता आला नाही. फाइल खराब किंवा संरक्षित असू शकते.',
        'Could not extract text from the PDF. The file may be damaged or protected.',
        detail,
      ),
    );
  }

  factory RagException.emptyDoc([String detail = '']) {
    return RagException(
      emptyDocument,
      _join(
        'दस्तऐवज रिकामा आहे — प्रक्रिया पूर्ण झाली नाही.',
        'The document is empty, so processing did not complete.',
        detail,
      ),
    );
  }

  factory RagException.embedding([String detail = '']) {
    return RagException(
      embeddingFailed,
      _join(
        'एंबेडिंग तयार करता आली नाही. स्रोत Ready म्हणून चिन्हांकित केला नाही.',
        'Embedding generation failed. The source was not marked Ready.',
        detail,
      ),
    );
  }

  factory RagException.vectorSearch([String detail = '']) {
    return RagException(
      vectorSearchFailed,
      _join(
        'समानता शोध अयशस्वी झाला. कृपया पुन्हा प्रयत्न करा.',
        'Vector search failed. Please retry.',
        detail,
      ),
    );
  }

  factory RagException.permission([String detail = '']) {
    return RagException(
      permissionDenied,
      _join(
        'परवानगी नाकारली. Admin म्हणून साइन इन आहे का आणि Firestore नियम डिप्लॉय आहेत का ते तपासा.',
        'Permission denied. Confirm you are signed in as an admin and that firestore.rules are deployed.',
        detail,
      ),
    );
  }

  factory RagException.gemini([String detail = '']) {
    return RagException(
      geminiFailed,
      _join(
        'Gemini/API विनंती अयशस्वी झाली.',
        'The Gemini/API request failed.',
        detail,
      ),
    );
  }

  factory RagException.network([String detail = '']) {
    return RagException(
      networkFailed,
      _join(
        'नेटवर्क त्रुटी. कनेक्शन तपासा आणि पुन्हा प्रयत्न करा.',
        'Network error. Check your connection and retry.',
        detail,
      ),
    );
  }

  factory RagException.emptyQuestion([String detail = '']) {
    return RagException(
      emptyQuery,
      _join(
        'कृपया प्रश्न लिहा.',
        'Please enter a question.',
        detail,
      ),
    );
  }

  factory RagException.processing([String detail = '']) {
    return RagException(
      processingFailed,
      _join(
        'स्रोत प्रक्रिया अयशस्वी झाली.',
        'Source processing failed.',
        detail,
      ),
    );
  }

  static RagException fromError(Object error) {
    if (error is RagException) return error;
    final raw = '$error'.trim();
    final lower = raw.toLowerCase();
    if (lower.contains('permission-denied') ||
        lower.contains('permission denied') ||
        lower.contains('missing or insufficient permissions')) {
      return RagException.permission(raw);
    }
    if (lower.contains('socket') ||
        lower.contains('network') ||
        lower.contains('failed host') ||
        lower.contains('failed to fetch') ||
        lower.contains('timed out') ||
        lower.contains('timeout') ||
        lower.contains('cors') ||
        lower.contains('xmlhttprequest') ||
        lower.contains('clientexception')) {
      return RagException.network(raw);
    }
    if (lower.contains('quota') ||
        lower.contains('unauthorized') ||
        lower.contains('api_key') ||
        lower.contains('gemini')) {
      return RagException.gemini(raw);
    }
    if (lower.contains('embed')) {
      return RagException.embedding(raw);
    }
    if (lower.contains('extract') || lower.contains('pdf')) {
      return RagException.pdfExtraction(raw);
    }
    return RagException.processing(raw);
  }
}

String _join(String mr, String en, String detail) {
  final d = detail.trim();
  if (d.isEmpty) return '$mr\n($en)';
  return '$mr\n($en)\n$d';
}
