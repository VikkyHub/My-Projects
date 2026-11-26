import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class CachedResponse {
  const CachedResponse(this.body, this.etag, this.savedAt);
  final String body;
  final String? etag;
  final DateTime savedAt;
}

/// Offline-first cache for GET responses (catalog, product listings, shop lists).
///
/// The app shows the cached copy instantly, revalidates with `If-None-Match`, and falls back to the
/// cache when there's no network — important on patchy 3G/4G. Bounded to [maxEntries] (LRU by savedAt).
abstract class ResponseCache {
  Future<CachedResponse?> get(String key);
  Future<void> put(String key, String body, String? etag);
  Future<void> touch(String key);
}

class SqfliteResponseCache implements ResponseCache {
  SqfliteResponseCache._(this._db);
  final Database _db;
  static const maxEntries = 300;

  static Future<SqfliteResponseCache> open(String name) async {
    final db = await openDatabase(
      p.join(await getDatabasesPath(), '$name.db'),
      version: 1,
      onCreate: (db, _) => db.execute(
        'CREATE TABLE responses (key TEXT PRIMARY KEY, body TEXT NOT NULL, etag TEXT, saved_at INTEGER NOT NULL)',
      ),
    );
    return SqfliteResponseCache._(db);
  }

  @override
  Future<CachedResponse?> get(String key) async {
    final rows = await _db.query('responses', where: 'key = ?', whereArgs: [key], limit: 1);
    if (rows.isEmpty) return null;
    final r = rows.first;
    return CachedResponse(r['body'] as String, r['etag'] as String?, DateTime.fromMillisecondsSinceEpoch(r['saved_at'] as int));
  }

  @override
  Future<void> put(String key, String body, String? etag) async {
    await _db.insert('responses', {'key': key, 'body': body, 'etag': etag, 'saved_at': DateTime.now().millisecondsSinceEpoch},
        conflictAlgorithm: ConflictAlgorithm.replace);
    await _db.execute(
        'DELETE FROM responses WHERE key NOT IN (SELECT key FROM responses ORDER BY saved_at DESC LIMIT $maxEntries)');
  }

  @override
  Future<void> touch(String key) =>
      _db.update('responses', {'saved_at': DateTime.now().millisecondsSinceEpoch}, where: 'key = ?', whereArgs: [key]);
}

class MemoryResponseCache implements ResponseCache {
  final _m = <String, CachedResponse>{};
  @override
  Future<CachedResponse?> get(String key) async => _m[key];
  @override
  Future<void> put(String key, String body, String? etag) async => _m[key] = CachedResponse(body, etag, DateTime.now());
  @override
  Future<void> touch(String key) async {
    final c = _m[key];
    if (c != null) _m[key] = CachedResponse(c.body, c.etag, DateTime.now());
  }
}
