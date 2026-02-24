import 'dart:convert';
import 'dart:io';

import 'package:anx_reader/utils/get_path/get_cache_dir.dart';

/// Persistent cache for inline full-text translation.
///
/// Design goals:
/// - Per-book namespace (easy "clear this book" action)
/// - File-based (no DB migration)
/// - Metadata-light (good enough for first iteration)
class FullTextTranslateCache {
  static const _dirName = 'fulltext_translate_cache';

  static Future<Directory> _ensureDir() async {
    final cacheDir = await getAnxCacheDir();
    final dir = Directory('${cacheDir.path}/$_dirName');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static Future<File> _fileForBook(int bookId) async {
    final dir = await _ensureDir();
    return File('${dir.path}/book_$bookId.json');
  }

  static Future<Map<String, dynamic>> _readBook(int bookId) async {
    final file = await _fileForBook(bookId);
    if (!await file.exists()) return {};

    try {
      final content = await file.readAsString();
      final decoded = jsonDecode(content);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) {
        return decoded.map((k, v) => MapEntry(k.toString(), v));
      }
      return {};
    } catch (_) {
      // Corrupted cache: best-effort reset.
      try {
        await file.delete();
      } catch (_) {}
      return {};
    }
  }

  static Future<void> _writeBook(int bookId, Map<String, dynamic> json) async {
    final file = await _fileForBook(bookId);
    await file.writeAsString(jsonEncode(json), mode: FileMode.writeOnly);
  }

  /// Read cached translation by hash key.
  static Future<String?> get(int bookId, String key) async {
    final json = await _readBook(bookId);
    final entry = json[key];
    if (entry is String) {
      return entry;
    }
    if (entry is Map) {
      final text = entry['text'];
      if (text is String) return text;
    }
    return null;
  }

  /// Store cached translation.
  static Future<void> set(
    int bookId,
    String key,
    String translatedText,
  ) async {
    final json = await _readBook(bookId);
    json[key] = {
      'text': translatedText,
      'ts': DateTime.now().millisecondsSinceEpoch,
    };
    await _writeBook(bookId, json);
  }

  static Future<void> clearBook(int bookId) async {
    final file = await _fileForBook(bookId);
    if (await file.exists()) {
      await file.delete();
    }
  }
}
