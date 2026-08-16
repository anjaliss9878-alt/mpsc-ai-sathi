import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Firestore rejects arrays that contain arrays (`List<List<…>>`).
/// Maps may contain arrays, and arrays may contain maps — just not arrays
/// nested directly inside arrays.
///
/// [flattenFirestoreValue] converts any nested array into a list of maps
/// (`{cells: [...]}`) so `set()` / `add()` succeed.

dynamic flattenFirestoreValue(dynamic value) {
  if (value is Map) {
    return <String, dynamic>{
      for (final e in value.entries)
        e.key.toString(): flattenFirestoreValue(e.value),
    };
  }
  if (value is List) {
    final items = [for (final e in value) flattenFirestoreValue(e)];
    if (items.any((e) => e is List)) {
      return [
        for (var i = 0; i < items.length; i++) _wrapNestedListItem(items[i], i),
      ];
    }
    return items;
  }
  return value;
}

Map<String, dynamic> _wrapNestedListItem(dynamic item, int index) {
  if (item is Map<String, dynamic>) return item;
  if (item is Map) return Map<String, dynamic>.from(item);
  if (item is List) {
    return <String, dynamic>{'index': index, 'cells': item};
  }
  return <String, dynamic>{'index': index, 'value': item};
}

/// Returns a JSON-path to the first nested array, or null if the payload is
/// Firestore-safe.
String? findNestedArrayPath(dynamic value, [String path = r'$']) {
  if (value is Map) {
    for (final e in value.entries) {
      final found = findNestedArrayPath(e.value, '$path.${e.key}');
      if (found != null) return found;
    }
  } else if (value is List) {
    for (var i = 0; i < value.length; i++) {
      final item = value[i];
      if (item is List) return '$path[$i]';
      final found = findNestedArrayPath(item, '$path[$i]');
      if (found != null) return found;
    }
  }
  return null;
}

bool hasNestedArrays(dynamic value) => findNestedArrayPath(value) != null;

/// Flatten, validate, and log a note document before `setDoc` / `add`.
Map<String, dynamic> prepareFirestoreNotePayload(Map<String, dynamic> data) {
  final flattened = flattenFirestoreValue(data);
  if (flattened is! Map<String, dynamic>) {
    throw StateError('Firestore note payload must be a Map.');
  }

  final nestedPath = findNestedArrayPath(flattened);
  if (nestedPath != null) {
    throw ArgumentError(
      'Nested arrays are not supported at $nestedPath. '
      'Flatten List<List<dynamic>> into List<Map> or Map before setDoc().',
    );
  }

  try {
    debugPrint(
      '[NotesRepository] Firestore payload:\n'
      '${const JsonEncoder.withIndent('  ').convert(flattened)}',
    );
  } catch (e) {
    debugPrint('[NotesRepository] Firestore payload (raw): $flattened');
    debugPrint('[NotesRepository] JSON encode failed: $e');
  }

  return flattened;
}
