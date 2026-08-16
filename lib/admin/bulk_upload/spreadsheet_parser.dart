import 'dart:convert';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:excel/excel.dart' as xls;

/// Parses a `.csv` or `.xlsx` file's bytes into a list of rows, each row a
/// map of lower-cased header name to cell value (as a string). Used by the
/// Bulk Upload screen so the rest of the pipeline doesn't care which file
/// format the admin picked.
List<Map<String, String>> parseSpreadsheetBytes(String fileName, Uint8List bytes) {
  final lower = fileName.toLowerCase();
  if (lower.endsWith('.xlsx')) {
    return _parseXlsx(bytes);
  }
  return _parseCsv(bytes);
}

List<Map<String, String>> _parseCsv(Uint8List bytes) {
  final content = utf8.decode(bytes, allowMalformed: true);
  final rows = const CsvToListConverter(eol: '\n', shouldParseNumbers: false)
      .convert(content.replaceAll('\r\n', '\n'));
  if (rows.isEmpty) return [];
  final headers = rows.first.map((h) => h.toString().trim().toLowerCase()).toList();
  return rows.skip(1).where((r) => r.any((c) => c.toString().trim().isNotEmpty)).map((row) {
    final map = <String, String>{};
    for (var i = 0; i < headers.length && i < row.length; i++) {
      map[headers[i]] = row[i].toString();
    }
    return map;
  }).toList();
}

List<Map<String, String>> _parseXlsx(Uint8List bytes) {
  final workbook = xls.Excel.decodeBytes(bytes);
  if (workbook.sheets.isEmpty) return [];
  final sheet = workbook.sheets.values.first;
  final rows = sheet.rows;
  if (rows.isEmpty) return [];
  final headers = rows.first
      .map((cell) => (cell?.value?.toString() ?? '').trim().toLowerCase())
      .toList();
  return rows.skip(1).where((r) => r.any((c) => (c?.value?.toString() ?? '').trim().isNotEmpty)).map((row) {
    final map = <String, String>{};
    for (var i = 0; i < headers.length && i < row.length; i++) {
      map[headers[i]] = row[i]?.value?.toString() ?? '';
    }
    return map;
  }).toList();
}
