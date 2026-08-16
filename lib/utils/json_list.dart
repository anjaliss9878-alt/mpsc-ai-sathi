// Null-safe coercion of Firestore/JSON values that *should* be lists.
//
// Real-world data sometimes stores a Map where a List is expected (single
// object, map-of-items, or index-keyed map like `{"0": ...}`). These helpers
// never throw on wrong shape — they return empty or best-effort lists.

/// Raw list coercion: null → [], List → copy, Map → ordered values or wrap,
/// scalar → single-element list.
List<dynamic> asDynamicList(dynamic value) {
  if (value == null) return const [];
  if (value is List) return List<dynamic>.from(value);
  if (value is Map) {
    final map = Map<dynamic, dynamic>.from(value);
    if (map.isEmpty) return const [];
    final ordered = _orderedMapValues(map);
    // Index-keyed or map-of-items → use values. Otherwise treat as one item.
    if (_looksLikeIndexedOrItemMap(map)) {
      return ordered;
    }
    return [map];
  }
  return [value];
}

/// String list: accepts null, List, single String, or Map (values / wrap).
List<String> asStringList(dynamic value, {bool keepEmpty = false}) {
  if (value == null) return const [];
  if (value is String) {
    final t = value.trim();
    if (t.isEmpty) return keepEmpty ? [value] : const [];
    // Multi-line blobs (admin textarea leftovers) → one entry per line.
    if (t.contains('\n')) {
      return t
          .split(RegExp(r'\r?\n'))
          .map((e) => e.trim())
          .where((e) => keepEmpty || e.isNotEmpty)
          .toList();
    }
    return [t];
  }
  final out = <String>[];
  for (final e in asDynamicList(value)) {
    if (e == null) {
      if (keepEmpty) out.add('');
      continue;
    }
    if (e is Map || e is List) continue;
    final s = e.toString();
    if (keepEmpty || s.trim().isNotEmpty) out.add(s);
  }
  return out;
}

/// List of maps: accepts null, List&lt;Map&gt;, single Map, or Map-of-maps.
List<Map<String, dynamic>> asMapList(dynamic value) {
  if (value == null) return const [];
  if (value is Map) {
    final map = Map<dynamic, dynamic>.from(value);
    if (map.isEmpty) return const [];
    final ordered = _orderedMapValues(map);
    if (ordered.isNotEmpty && ordered.every((e) => e is Map)) {
      return [
        for (final e in ordered) Map<String, dynamic>.from(e as Map),
      ];
    }
    return [Map<String, dynamic>.from(map)];
  }
  final out = <Map<String, dynamic>>[];
  for (final e in asDynamicList(value)) {
    if (e is Map) {
      out.add(Map<String, dynamic>.from(e));
    }
  }
  return out;
}

/// Nested string table (e.g. `tableRows`).
///
/// Accepts:
/// - `List<List>` (in-memory / Gemini extract)
/// - `List<Map>` with `cells` / `values` / `row` (Firestore-safe write shape)
/// - `List<Map>` of column-keyed or index-keyed cells
List<List<String>> asStringTable(dynamic value) {
  final rows = <List<String>>[];
  for (final row in asDynamicList(value)) {
    if (row is List) {
      rows.add(asStringList(row, keepEmpty: true));
    } else if (row is Map) {
      final map = Map<String, dynamic>.from(row);
      if (map.containsKey('cells')) {
        rows.add(asStringList(map['cells'], keepEmpty: true));
      } else if (map.containsKey('values')) {
        rows.add(asStringList(map['values'], keepEmpty: true));
      } else if (map.containsKey('row')) {
        rows.add(asStringList(map['row'], keepEmpty: true));
      } else {
        final withoutMeta = Map<String, dynamic>.from(map)..remove('index');
        rows.add(asStringList(withoutMeta, keepEmpty: true));
      }
    } else if (row != null) {
      rows.add([row.toString()]);
    }
  }
  return rows;
}

/// Bool coercion for Firestore fields that may be bool, string, or 0/1.
/// [defaultValue] is used when the value is null / unrecognized.
bool asBool(dynamic value, {bool defaultValue = true}) {
  if (value == null) return defaultValue;
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final t = value.trim().toLowerCase();
    if (t == 'true' || t == '1' || t == 'yes') return true;
    if (t == 'false' || t == '0' || t == 'no') return false;
  }
  return defaultValue;
}

/// Int coercion for order / minutes fields that may be num or string.
int asInt(dynamic value, {int defaultValue = 0}) {
  if (value == null) return defaultValue;
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim()) ?? defaultValue;
  return defaultValue;
}

/// Numeric list (e.g. graph values).
List<double> asDoubleList(dynamic value) {
  final out = <double>[];
  for (final e in asDynamicList(value)) {
    if (e is num) {
      out.add(e.toDouble());
    } else if (e != null) {
      final parsed = double.tryParse(e.toString());
      if (parsed != null) out.add(parsed);
    }
  }
  return out;
}

bool _looksLikeIndexedOrItemMap(Map<dynamic, dynamic> map) {
  if (map.isEmpty) return false;
  final keys = map.keys.toList();
  final allNumeric = keys.every(_isNumericKey);
  if (allNumeric) return true;
  final values = map.values;
  // Map-of-entities: every value is itself a Map (attachments/mcqs/slides…).
  if (values.isNotEmpty && values.every((v) => v is Map)) return true;
  // Map of scalars keyed arbitrarily (options/tags stored as object).
  if (values.isNotEmpty && values.every((v) => v is! Map && v is! List)) {
    return true;
  }
  return false;
}

bool _isNumericKey(dynamic key) {
  if (key is int) return true;
  if (key is num) return true;
  if (key is String) return int.tryParse(key) != null;
  return false;
}

int _numericKeyOrder(dynamic key) {
  if (key is int) return key;
  if (key is num) return key.toInt();
  return int.tryParse(key.toString()) ?? 0;
}

List<dynamic> _orderedMapValues(Map<dynamic, dynamic> map) {
  final keys = map.keys.toList();
  if (keys.every(_isNumericKey)) {
    keys.sort((a, b) => _numericKeyOrder(a).compareTo(_numericKeyOrder(b)));
  }
  return [for (final k in keys) map[k]];
}
