class RagPdfPageImage {
  const RagPdfPageImage({
    required this.pageNumber,
    required this.base64Data,
    this.mimeType = 'image/png',
  });

  final int pageNumber;
  final String mimeType;
  final String base64Data;

  Map<String, dynamic> toJson() => {
        'page': pageNumber,
        'mimeType': mimeType,
        'data': base64Data,
      };

  static RagPdfPageImage? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final data = '${raw['data'] ?? ''}'.trim();
    if (data.isEmpty) return null;
    final pageRaw = raw['page'] ?? raw['pageNumber'];
    final page = pageRaw is num ? pageRaw.toInt() : int.tryParse('$pageRaw') ?? 0;
    if (page < 1) return null;
    final mime = '${raw['mimeType'] ?? raw['mime_type'] ?? 'image/png'}'.trim();
    return RagPdfPageImage(
      pageNumber: page,
      base64Data: data,
      mimeType: mime.isEmpty ? 'image/png' : mime,
    );
  }
}
