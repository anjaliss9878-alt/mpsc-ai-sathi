import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mpsc_combine_ai/rag/rag_extract_quality.dart';
import 'package:mpsc_combine_ai/rag/rag_pdf_extract_pipeline.dart';
import 'package:mpsc_combine_ai/rag/rag_pdf_page_image.dart';
import 'package:mpsc_combine_ai/rag/rag_pdf_raster_cache_io.dart';
import 'package:mpsc_combine_ai/rag/rag_text.dart';
import 'package:pdfrx/pdfrx.dart';

void main() {
  test('िज्यघटना is corrupted; निवड निज संविधान are not', () {
    expect(ragExtractedTextLooksCorrupted('िज्यघटना'), isTrue);
    expect(ragExtractedTextLooksCorrupted('िज्य'), isTrue);
    expect(ragExtractedTextLooksCorrupted('निवड'), isFalse);
    expect(ragExtractedTextLooksCorrupted('निज'), isFalse);
    expect(
      ragExtractedTextLooksCorrupted(
        'भारतीय संविधानातील संसद ही द्विसदनी आहे. लोकसभा आणि राज्यसभा. निवड.',
      ),
      isFalse,
    );
  });

  test('CID token with low Devanagari is corrupted', () {
    expect(ragExtractedTextLooksCorrupted('9D0fjYpn'), isTrue);
    expect(ragExtractedTextLooksCorrupted('9DUlj : बा.'), isTrue);
  });

  test('good Unicode Marathi stays on the PDF-bytes path', () async {
    const good =
        'भारतीय संविधानातील संसद ही द्विसदनी आहे. लोकसभा आणि राज्यसभा.';
    expect(ragExtractedTextLooksCorrupted(good), isFalse);
    expect(
      ragExtractedPagesLookCorrupted([
        const RagExtractedPage(pageNumber: 1, text: good),
      ]),
      isFalse,
    );

    var pdfCalls = 0;
    var rasterCalls = 0;
    var imageCalls = 0;
    final result = await extractPdfWithCorruptionFallback(
      extractFromPdfBytes: () async {
        pdfCalls++;
        return {
          'pages': [
            {'page': 1, 'text': good},
          ],
        };
      },
      rasterizePages: ({required Set<int> pageNumbers}) async {
        rasterCalls++;
        return const [];
      },
      extractFromPageImages: (images) async {
        imageCalls++;
        return {'pages': []};
      },
    );
    expect(pdfCalls, 1);
    expect(rasterCalls, 0);
    expect(imageCalls, 0);
    expect(result['pages'], [
      {'page': 1, 'text': good},
    ]);
  });

  test('English PDF stays on the PDF-bytes path', () async {
    const english =
        'Parliament is bicameral. Article 14 guarantees equality before law.';
    expect(ragExtractedTextLooksCorrupted(english), isFalse);

    var rasterCalls = 0;
    await extractPdfWithCorruptionFallback(
      extractFromPdfBytes: () async {
        return {
          'pages': [
            {'page': 1, 'text': english},
          ],
        };
      },
      rasterizePages: ({required Set<int> pageNumbers}) async {
        rasterCalls++;
        return const [];
      },
      extractFromPageImages: (images) async {
        fail('image OCR must not run for English');
        return {'pages': []};
      },
    );
    expect(rasterCalls, 0);
  });

  test('mixed Marathi-English Unicode stays on the PDF-bytes path', () {
    const mixed =
        'भारतीय संविधानातील Article 14 equality before law. समानता.';
    expect(ragExtractedTextLooksCorrupted(mixed), isFalse);
  });

  test('joined CID page plus Marathi page is corrupted', () {
    expect(
      ragExtractedPagesLookCorrupted([
        const RagExtractedPage(pageNumber: 1, text: '9D0fjYpn'),
        const RagExtractedPage(
          pageNumber: 2,
          text: 'भारतीय संविधानातील संसद ही द्विसदनी आहे.',
        ),
      ]),
      isTrue,
    );
  });

  test('corrupted Devanagari extract triggers image fallback', () async {
    const broken = 'िज्यघटना भारतीय संविधान लोकसभा राज्यसभा';
    expect(ragExtractedTextLooksCorrupted(broken), isTrue);

    var pdfCalls = 0;
    var rasterCalls = 0;
    Set<int>? requestedPages;
    var imageCalls = 0;
    const recovered = 'भारतीय संविधानातील संसद ही द्विसदनी आहे.';
    String? path;
    final result = await extractPdfWithCorruptionFallback(
      extractFromPdfBytes: () async {
        pdfCalls++;
        return {
          'pages': [
            {'page': 2, 'text': broken},
          ],
        };
      },
      rasterizePages: ({required Set<int> pageNumbers}) async {
        rasterCalls++;
        requestedPages = pageNumbers;
        return const [
          RagPdfPageImage(pageNumber: 2, base64Data: 'aaa'),
        ];
      },
      extractFromPageImages: (images) async {
        imageCalls++;
        expect(images.single.pageNumber, 2);
        return {
          'pages': [
            {'page': 2, 'text': recovered},
          ],
        };
      },
      onTrace: (t) => path = t.path,
    );
    expect(pdfCalls, 1);
    expect(rasterCalls, 1);
    expect(imageCalls, 1);
    expect(requestedPages, {2});
    expect(path, 'image-ocr');
    expect(result['pages'], [
      {'page': 2, 'text': recovered},
    ]);
  });

  test('rasterization failure returns a clear extraction error', () async {
    const broken = 'िज्यघटना भारतीय संविधान लोकसभा राज्यसभा';
    await expectLater(
      extractPdfWithCorruptionFallback(
        extractFromPdfBytes: () async {
          return {
            'pages': [
              {'page': 1, 'text': broken},
            ],
          };
        },
        rasterizePages: ({required Set<int> pageNumbers}) async {
          throw StateError('pdfium unavailable');
        },
        extractFromPageImages: (images) async {
          fail('must not OCR after rasterize failure');
          return {'pages': []};
        },
      ),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('page-image OCR'),
        ),
      ),
    );
  });

  test('empty rasterization returns a clear extraction error', () async {
    const broken = 'िज्यघटना भारतीय संविधान लोकसभा राज्यसभा';
    await expectLater(
      extractPdfWithCorruptionFallback(
        extractFromPdfBytes: () async {
          return {
            'pages': [
              {'page': 1, 'text': broken},
            ],
          };
        },
        rasterizePages: ({required Set<int> pageNumbers}) async {
          return const [];
        },
        extractFromPageImages: (images) async {
          fail('must not OCR when rasterize returned no images');
          return {'pages': []};
        },
      ),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('no page images'),
        ),
      ),
    );
  });

  test('truncated Gemini JSON uses image OCR instead of failing immediately',
      () async {
    var rasterCalls = 0;
    var imageCalls = 0;
    const recovered = 'भारतीय संविधानातील संसद ही द्विसदनी आहे.';
    final result = await extractPdfWithCorruptionFallback(
      extractFromPdfBytes: () async {
        throw StateError('response parsing error');
      },
      rasterizePages: ({required Set<int> pageNumbers}) async {
        rasterCalls++;
        expect(pageNumbers, isEmpty);
        return const [
          RagPdfPageImage(pageNumber: 1, base64Data: 'aaa'),
        ];
      },
      extractFromPageImages: (images) async {
        imageCalls++;
        expect(images, hasLength(1));
        return {
          'pages': [
            {'page': 1, 'text': recovered},
          ],
        };
      },
    );
    expect(rasterCalls, 1);
    expect(imageCalls, 1);
    expect(result['pages'], [
      {'page': 1, 'text': recovered},
    ]);
  });

  test(
      'truncated JSON plus failed OCR returns a clear error, not invented text',
      () async {
    await expectLater(
      extractPdfWithCorruptionFallback(
        extractFromPdfBytes: () async {
          throw StateError('finishReason=MAX_TOKENS response parsing error');
        },
        rasterizePages: ({required Set<int> pageNumbers}) async {
          return const [];
        },
        extractFromPageImages: (images) async {
          fail('must not OCR when rasterize returned no images');
          return {'pages': []};
        },
      ),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('page-image OCR'),
        ),
      ),
    );
  });

  test('non-parse PDF extract errors are not swallowed', () async {
    await expectLater(
      extractPdfWithCorruptionFallback(
        extractFromPdfBytes: () async {
          throw StateError('PDF extraction failed: download HTTP 404');
        },
        rasterizePages: ({required Set<int> pageNumbers}) async {
          fail('must not rasterize on download failure');
          return const [];
        },
        extractFromPageImages: (images) async {
          fail('must not OCR on download failure');
          return {'pages': []};
        },
      ),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('download HTTP 404'),
        ),
      ),
    );
  });

  test('ragMapLimited keeps order with a concurrency cap', () async {
    final started = <int>[];
    var inFlight = 0;
    var maxInFlight = 0;
    final out = await ragMapLimited<int>(5, 2, (i) async {
      started.add(i);
      inFlight++;
      if (inFlight > maxInFlight) maxInFlight = inFlight;
      await Future<void>.delayed(Duration(milliseconds: 20 - i));
      inFlight--;
      return i * 10;
    });
    expect(out, [0, 10, 20, 30, 40]);
    expect(started, [0, 1, 2, 3, 4]);
    expect(maxInFlight, lessThanOrEqualTo(2));
    expect(kRagPageOcrConcurrency, 3);
  });

  test('native raster cache uses Directory.systemTemp', () {
    final previous = Pdfrx.cacheDirectoryPath;
    Pdfrx.cacheDirectoryPath = null;
    ensureRagPdfRasterCacheDirectory();
    expect(Pdfrx.cacheDirectoryPath, Directory.systemTemp.path);
    Pdfrx.cacheDirectoryPath = previous;
  });
}
