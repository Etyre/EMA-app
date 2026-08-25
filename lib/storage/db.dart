import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/models.dart';

/// SQLite database for prompts and answers. The database file lives in the
/// app's private documents directory, which iOS and Android both preserve
/// across app updates. Schema changes go in [_onUpgrade] so an update never
/// requires deleting the app.
class PromptDb {
  static const _version = 1;
  Database? _db;

  Future<Database> get db async => _db ??= await _open();

  Future<Database> _open() async {
    final path = p.join(await getDatabasesPath(), 'ema.db');
    return openDatabase(path, version: _version, onCreate: _onCreate, onUpgrade: _onUpgrade);
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE prompts (
        id INTEGER PRIMARY KEY,
        uid TEXT NOT NULL UNIQUE,
        scheduled_at INTEGER NOT NULL,
        status TEXT NOT NULL,
        opened_at INTEGER,
        submitted_at INTEGER,
        answers TEXT NOT NULL DEFAULT '{}',
        uploaded INTEGER NOT NULL DEFAULT 0,
        upload_attempts INTEGER NOT NULL DEFAULT 0,
        last_upload_error TEXT
      )
    ''');
    await db.execute('CREATE INDEX idx_prompts_status ON prompts(status)');
    await db.execute('CREATE INDEX idx_prompts_scheduled ON prompts(scheduled_at)');
  }

  Future<void> _onUpgrade(Database db, int oldV, int newV) async {
    // Add incremental migrations here, e.g.
    // if (oldV < 2) await db.execute('ALTER TABLE prompts ADD COLUMN foo TEXT');
  }

  Future<void> insert(PromptRecord r) async =>
      (await db).insert('prompts', r.toRow(), conflictAlgorithm: ConflictAlgorithm.replace);

  Future<void> update(PromptRecord r) async =>
      (await db).update('prompts', r.toRow(), where: 'id = ?', whereArgs: [r.id]);

  Future<PromptRecord?> byId(int id) async {
    final rows = await (await db).query('prompts', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : PromptRecord.fromRow(rows.first);
  }

  Future<List<PromptRecord>> byStatus(PromptStatus s) async {
    final rows = await (await db)
        .query('prompts', where: 'status = ?', whereArgs: [s.name], orderBy: 'scheduled_at');
    return rows.map(PromptRecord.fromRow).toList();
  }

  Future<List<PromptRecord>> pendingAfter(DateTime t) async {
    final rows = await (await db).query('prompts',
        where: 'status = ? AND scheduled_at > ?',
        whereArgs: [PromptStatus.pending.name, t.millisecondsSinceEpoch],
        orderBy: 'scheduled_at');
    return rows.map(PromptRecord.fromRow).toList();
  }

  Future<void> deleteIds(List<int> ids) async {
    if (ids.isEmpty) return;
    await (await db).delete('prompts',
        where: 'id IN (${List.filled(ids.length, '?').join(',')})', whereArgs: ids);
  }

  Future<List<PromptRecord>> needingUpload() async {
    final rows = await (await db).query('prompts',
        where: 'uploaded = 0 AND status IN (?, ?)',
        whereArgs: [PromptStatus.answered.name, PromptStatus.expired.name],
        orderBy: 'scheduled_at');
    return rows.map(PromptRecord.fromRow).toList();
  }

  Future<List<PromptRecord>> history({int limit = 200}) async {
    final rows = await (await db).query('prompts',
        where: 'status != ?',
        whereArgs: [PromptStatus.pending.name],
        orderBy: 'scheduled_at DESC',
        limit: limit);
    return rows.map(PromptRecord.fromRow).toList();
  }

  Future<int> nextId() async {
    final r = await (await db).rawQuery('SELECT COALESCE(MAX(id), 0) + 1 AS n FROM prompts');
    return r.first['n'] as int;
  }
}
