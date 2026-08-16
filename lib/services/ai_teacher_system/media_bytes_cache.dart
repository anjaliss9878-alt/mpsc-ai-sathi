import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

/// In-memory LRU for PDF / audio / thumbnail bytes. Video is skipped when huge.
class MediaBytesCache {
  MediaBytesCache._();

  static final MediaBytesCache instance = MediaBytesCache._();

  static const int maxEntries = 10;
  static const int maxBytes = 12 * 1024 * 1024;

  final Map<String, Uint8List> _data = <String, Uint8List>{};
  final List<String> _order = <String>[];

  String keyFor(String stored) {
    final material = stored.trim().toLowerCase();
    return sha256.convert(utf8.encode(material)).toString().substring(0, 24);
  }

  Uint8List? read(String stored) {
    final key = keyFor(stored);
    final hit = _data[key];
    if (hit == null) return null;
    _order.remove(key);
    _order.add(key);
    return hit;
  }

  void write(String stored, Uint8List bytes) {
    if (bytes.isEmpty || bytes.length > maxBytes) return;
    final key = keyFor(stored);
    _data[key] = bytes;
    _order.remove(key);
    _order.add(key);
    while (_order.length > maxEntries) {
      final evict = _order.removeAt(0);
      _data.remove(evict);
    }
  }
}

final MediaBytesCache mediaBytesCache = MediaBytesCache.instance;
