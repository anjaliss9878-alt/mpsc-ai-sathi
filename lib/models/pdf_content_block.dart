import 'package:mpsc_combine_ai/utils/json_list.dart';

/// Typed content extracted from a Topic PDF without flattening into one blob.
enum PdfBlockType {
  heading,
  paragraph,
  bullets,
  table,
  timeline,
  flowchart,
  diagram,
  chart,
  other,
}

PdfBlockType pdfBlockTypeFromString(String? value) {
  switch ((value ?? '').trim().toLowerCase()) {
    case 'heading':
    case 'title':
    case 'h1':
    case 'h2':
    case 'h3':
      return PdfBlockType.heading;
    case 'paragraph':
    case 'text':
    case 'body':
      return PdfBlockType.paragraph;
    case 'bullets':
    case 'bullet':
    case 'list':
    case 'points':
      return PdfBlockType.bullets;
    case 'table':
    case 'comparison':
      return PdfBlockType.table;
    case 'timeline':
    case 'chronology':
      return PdfBlockType.timeline;
    case 'flowchart':
    case 'process':
    case 'flow':
      return PdfBlockType.flowchart;
    case 'diagram':
    case 'mindmap':
    case 'figure':
      return PdfBlockType.diagram;
    case 'chart':
    case 'graph':
    case 'bar':
    case 'pie':
      return PdfBlockType.chart;
    default:
      return PdfBlockType.other;
  }
}

String pdfBlockTypeToString(PdfBlockType type) {
  switch (type) {
    case PdfBlockType.heading:
      return 'heading';
    case PdfBlockType.paragraph:
      return 'paragraph';
    case PdfBlockType.bullets:
      return 'bullets';
    case PdfBlockType.table:
      return 'table';
    case PdfBlockType.timeline:
      return 'timeline';
    case PdfBlockType.flowchart:
      return 'flowchart';
    case PdfBlockType.diagram:
      return 'diagram';
    case PdfBlockType.chart:
      return 'chart';
    case PdfBlockType.other:
      return 'other';
  }
}

/// One structural unit from a Topic PDF (heading, table, flowchart, …).
///
/// Kept as discrete blocks so AI Classroom and Notes UI never collapse the
/// PDF into a single paragraph.
class PdfContentBlock {
  const PdfContentBlock({
    required this.type,
    this.title = '',
    this.text = '',
    this.bullets = const [],
    this.tableHeaders = const [],
    this.tableRows = const [],
    this.timeline = const [],
    this.flowchart = const [],
    this.chartLabels = const [],
    this.chartValues = const [],
    this.caption = '',
    this.pageHint = 0,
  });

  final PdfBlockType type;
  final String title;
  final String text;
  final List<String> bullets;
  final List<String> tableHeaders;
  final List<List<String>> tableRows;

  /// Timeline entries as `{year, label}` maps.
  final List<Map<String, String>> timeline;

  /// Flowchart nodes as `{id, label, nextIds}` maps.
  final List<Map<String, dynamic>> flowchart;

  final List<String> chartLabels;
  final List<double> chartValues;
  final String caption;
  final int pageHint;

  factory PdfContentBlock.fromMap(Map<String, dynamic> map) {
    final timeline = <Map<String, String>>[];
    for (final e in asDynamicList(map['timeline'] ?? map['events'])) {
      if (e is Map) {
        timeline.add({
          'year': (e['year'] ?? e['time'] ?? '').toString(),
          'label': (e['label'] ?? e['text'] ?? e['event'] ?? '').toString(),
        });
      } else if (e != null) {
        timeline.add({'year': '', 'label': e.toString()});
      }
    }

    final flowchart = <Map<String, dynamic>>[];
    for (final e in asDynamicList(map['flowchart'] ?? map['nodes'])) {
      if (e is! Map) continue;
      final m = Map<String, dynamic>.from(e);
      flowchart.add({
        'id': (m['id'] ?? '').toString(),
        'label': (m['label'] ?? m['text'] ?? '').toString(),
        'nextIds': asStringList(m['nextIds'] ?? m['next']),
      });
    }

    final chartValues = <double>[];
    for (final e in asDynamicList(map['chartValues'] ?? map['values'])) {
      if (e is num) {
        chartValues.add(e.toDouble());
      } else if (e != null) {
        final parsed = double.tryParse(e.toString());
        if (parsed != null) chartValues.add(parsed);
      }
    }

    return PdfContentBlock(
      type: pdfBlockTypeFromString(map['type'] as String?),
      title: (map['title'] as String?)?.trim() ?? '',
      text: (map['text'] as String?)?.trim() ??
          (map['content'] as String?)?.trim() ??
          '',
      bullets: asStringList(map['bullets'] ?? map['items'] ?? map['points']),
      tableHeaders: asStringList(map['tableHeaders'] ?? map['headers'], keepEmpty: true),
      tableRows: asStringTable(map['tableRows'] ?? map['rows']),
      timeline: timeline,
      flowchart: flowchart,
      chartLabels: asStringList(map['chartLabels'] ?? map['labels']),
      chartValues: chartValues,
      caption: (map['caption'] as String?)?.trim() ?? '',
      pageHint: (map['pageHint'] as num?)?.toInt() ??
          (map['page'] as num?)?.toInt() ??
          0,
    );
  }

  Map<String, dynamic> toMap() => {
        'type': pdfBlockTypeToString(type),
        'title': title,
        'text': text,
        'bullets': bullets,
        'tableHeaders': tableHeaders,
        // Firestore forbids nested arrays. Each row is a map with a flat
        // `cells` list — never List<List<String>> on the wire.
        'tableRows': [
          for (var i = 0; i < tableRows.length; i++)
            <String, dynamic>{
              'index': i,
              'cells': tableRows[i],
            },
        ],
        'timeline': timeline,
        'flowchart': [
          for (final n in flowchart)
            <String, dynamic>{
              'id': (n['id'] ?? '').toString(),
              'label': (n['label'] ?? '').toString(),
              'nextIds': asStringList(n['nextIds'] ?? n['next']),
            },
        ],
        'chartLabels': chartLabels,
        'chartValues': chartValues,
        'caption': caption,
        'pageHint': pageHint,
      };

  /// Structured Markdown for one block (never a flattened paragraph dump).
  String toStructuredMarkdown() {
    final out = StringBuffer();
    switch (type) {
      case PdfBlockType.heading:
        final h = title.trim().isNotEmpty ? title.trim() : text.trim();
        if (h.isNotEmpty) out.writeln('## $h');
        break;
      case PdfBlockType.paragraph:
        if (title.trim().isNotEmpty) out.writeln('### ${title.trim()}');
        if (text.trim().isNotEmpty) out.writeln(text.trim());
        break;
      case PdfBlockType.bullets:
        if (title.trim().isNotEmpty) out.writeln('### ${title.trim()}');
        for (final b in bullets) {
          if (b.trim().isNotEmpty) out.writeln('- ${b.trim()}');
        }
        if (bullets.isEmpty && text.trim().isNotEmpty) {
          out.writeln('- ${text.trim()}');
        }
        break;
      case PdfBlockType.table:
        if (title.trim().isNotEmpty) out.writeln('### ${title.trim()}');
        final headers = tableHeaders.isNotEmpty
            ? tableHeaders
            : (tableRows.isNotEmpty
                ? List.generate(tableRows.first.length, (i) => 'स्तंभ ${i + 1}')
                : const <String>[]);
        if (headers.isNotEmpty) {
          out.writeln('| ${headers.join(' | ')} |');
          out.writeln('| ${headers.map((_) => '---').join(' | ')} |');
          for (final row in tableRows) {
            final cells = [
              for (var i = 0; i < headers.length; i++)
                i < row.length ? row[i] : '',
            ];
            out.writeln('| ${cells.join(' | ')} |');
          }
        }
        break;
      case PdfBlockType.timeline:
        if (title.trim().isNotEmpty) out.writeln('### ${title.trim()}');
        out.writeln('Timeline:');
        for (final e in timeline) {
          final year = (e['year'] ?? '').trim();
          final label = (e['label'] ?? '').trim();
          if (year.isEmpty && label.isEmpty) continue;
          out.writeln(year.isEmpty ? '- $label' : '- **$year** — $label');
        }
        break;
      case PdfBlockType.flowchart:
        if (title.trim().isNotEmpty) out.writeln('### ${title.trim()}');
        out.writeln('Flowchart:');
        for (final n in flowchart) {
          final id = (n['id'] ?? '').toString();
          final label = (n['label'] ?? '').toString();
          final next = asStringList(n['nextIds']);
          out.writeln(
            '- [$id] $label'
            '${next.isEmpty ? '' : ' → ${next.join(', ')}'}',
          );
        }
        break;
      case PdfBlockType.diagram:
        if (title.trim().isNotEmpty) out.writeln('### ${title.trim()}');
        out.writeln('Diagram: ${caption.isNotEmpty ? caption : text}');
        for (final b in bullets) {
          if (b.trim().isNotEmpty) out.writeln('- ${b.trim()}');
        }
        break;
      case PdfBlockType.chart:
        if (title.trim().isNotEmpty) out.writeln('### ${title.trim()}');
        out.writeln('Chart:');
        for (var i = 0; i < chartLabels.length; i++) {
          final v = i < chartValues.length ? chartValues[i].toString() : '';
          out.writeln('- ${chartLabels[i]}: $v');
        }
        break;
      case PdfBlockType.other:
        if (title.trim().isNotEmpty) out.writeln('### ${title.trim()}');
        if (text.trim().isNotEmpty) out.writeln(text.trim());
        for (final b in bullets) {
          if (b.trim().isNotEmpty) out.writeln('- ${b.trim()}');
        }
        break;
    }
    if (caption.trim().isNotEmpty &&
        type != PdfBlockType.diagram &&
        type != PdfBlockType.chart) {
      out.writeln('_${caption.trim()}_');
    }
    return out.toString().trimRight();
  }
}

/// Joins blocks into a structured syllabus document for lesson prompts.
String pdfBlocksToStructuredDocument(List<PdfContentBlock> blocks) {
  if (blocks.isEmpty) return '';
  final out = StringBuffer()
    ..writeln('PDF STRUCTURED CONTENT (preserve types — do NOT flatten):');
  for (var i = 0; i < blocks.length; i++) {
    final b = blocks[i];
    out
      ..writeln()
      ..writeln('--- block ${i + 1} [${pdfBlockTypeToString(b.type)}] ---')
      ..writeln(b.toStructuredMarkdown());
  }
  return out.toString().trimRight();
}
