// Kelmo Scan - document scanner
// Copyright (C) 2026 Kelmo
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, version 3 of the License.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import '../models/scan_document.dart';

/// SQLite + file storage. Images live in  <appDocs>/scans/<docId>/ ; DB stores paths.
class DocumentRepository {
  DocumentRepository._();
  static final instance = DocumentRepository._();

  late Database _db;
  late Directory _root;

  static String autoTitle() {
    final n = DateTime.now();
    String t(int v) => v.toString().padLeft(2, '0');
    return 'Scan ${n.year}-${t(n.month)}-${t(n.day)} ${t(n.hour)}:${t(n.minute)}';
  }

  static Future<void> _tagTables(Database db) async {
    await db.execute('CREATE TABLE tags(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL COLLATE NOCASE UNIQUE)');
    await db.execute('CREATE TABLE doc_tags(doc_id INTEGER NOT NULL REFERENCES documents(id) ON DELETE CASCADE, '
        'tag_id INTEGER NOT NULL REFERENCES tags(id) ON DELETE CASCADE, PRIMARY KEY(doc_id, tag_id))');
  }

  static String dateStamp() {
    final n = DateTime.now();
    String t(int v) => v.toString().padLeft(2, '0');
    return '${n.year}-${t(n.month)}-${t(n.day)}';
  }

  Future<void> init() async {
    _root = Directory(p.join((await getApplicationDocumentsDirectory()).path, 'scans'))..createSync(recursive: true);
    _db = await openDatabase(
      p.join(await getDatabasesPath(), 'kelmo_scan.db'),
      version: 6,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onUpgrade: (db, old, _) async {
        if (old < 2) await db.execute('ALTER TABLE pages ADD COLUMN ocr_text TEXT');
        if (old < 3) {
          await db.execute('ALTER TABLE documents ADD COLUMN fav INTEGER NOT NULL DEFAULT 0');
          await db.execute("ALTER TABLE documents ADD COLUMN kind TEXT NOT NULL DEFAULT 'document'");
          await _tagTables(db);
        }
        if (old < 4) await db.execute('ALTER TABLE documents ADD COLUMN trashed INTEGER');
        if (old < 5) await db.execute('ALTER TABLE pages ADD COLUMN note TEXT');
        if (old < 6) {
          await db.execute('ALTER TABLE pages ADD COLUMN title TEXT');
          await db.execute('ALTER TABLE documents ADD COLUMN pdf_settings TEXT');
        }
      },
      onCreate: (db, _) async {
        await db.execute('CREATE TABLE folders(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, created INTEGER NOT NULL)');
        await db.execute('CREATE TABLE documents(id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT NOT NULL, '
            'folder_id INTEGER REFERENCES folders(id) ON DELETE SET NULL, created INTEGER NOT NULL, updated INTEGER NOT NULL, '
            "fav INTEGER NOT NULL DEFAULT 0, kind TEXT NOT NULL DEFAULT 'document', trashed INTEGER, pdf_settings TEXT)");
        await db.execute('CREATE TABLE pages(id INTEGER PRIMARY KEY AUTOINCREMENT, '
            'doc_id INTEGER NOT NULL REFERENCES documents(id) ON DELETE CASCADE, position INTEGER NOT NULL, '
            'image_path TEXT NOT NULL, thumb_path TEXT NOT NULL, orig_path TEXT NOT NULL, '
            'corners TEXT NOT NULL, filter TEXT NOT NULL, bytes INTEGER NOT NULL, ocr_text TEXT, note TEXT, title TEXT)');
        await db.execute('CREATE INDEX idx_pages_doc ON pages(doc_id, position)');
        await _tagTables(db);
        final now = DateTime.now().millisecondsSinceEpoch;
        for (final n in ['Personal', 'Work', 'Receipts']) {
          await db.insert('folders', {'name': n, 'created': now});
        }
      },
    );
  }

  // ───────── folders
  Future<List<Folder>> folders() async {
    final rows = await _db.rawQuery('SELECT f.id, f.name, COUNT(d.id) AS c FROM folders f '
        'LEFT JOIN documents d ON d.folder_id = f.id AND d.trashed IS NULL GROUP BY f.id ORDER BY f.id');
    return [for (final r in rows) Folder(r['id'] as int, r['name'] as String, (r['c'] as num).toInt())];
  }

  Future<int> totalDocuments() async =>
      Sqflite.firstIntValue(await _db.rawQuery('SELECT COUNT(*) FROM documents WHERE trashed IS NULL')) ?? 0;

  Future<void> addFolder(String name) =>
      _db.insert('folders', {'name': name, 'created': DateTime.now().millisecondsSinceEpoch});
  Future<void> renameFolder(int id, String name) =>
      _db.update('folders', {'name': name}, where: 'id = ?', whereArgs: [id]);
  Future<void> deleteFolder(int id) => _db.delete('folders', where: 'id = ?', whereArgs: [id]); // docs → no folder

  // ───────── documents
  Future<List<ScanDocument>> _docs(String where, List<Object?> args) async {
    final rows = await _db.rawQuery('''
      SELECT d.*,
        (SELECT COUNT(*) FROM pages WHERE doc_id = d.id) AS pc,
        (SELECT COALESCE(SUM(bytes), 0) FROM pages WHERE doc_id = d.id) AS bytes,
        (SELECT thumb_path FROM pages WHERE doc_id = d.id ORDER BY position LIMIT 1) AS thumb,
        (SELECT group_concat(t.name, char(31)) FROM doc_tags dt JOIN tags t ON t.id = dt.tag_id WHERE dt.doc_id = d.id) AS tag_list
      FROM documents d ${where.isEmpty ? '' : 'WHERE $where'} ORDER BY d.updated DESC''', args);
    return [for (final r in rows) ScanDocument.fromRow(r)];
  }

  Future<List<ScanDocument>> documents(
      {int? folderId, String query = '', bool favOnly = false, List<String>? kinds, String? tag}) {
    final w = <String>['d.trashed IS NULL'];
    final a = <Object?>[];
    if (folderId != null) { w.add('d.folder_id = ?'); a.add(folderId); }
    if (favOnly) w.add('d.fav = 1');
    if (kinds != null && kinds.isNotEmpty) {
      w.add('d.kind IN (${List.filled(kinds.length, '?').join(',')})');
      a.addAll(kinds);
    }
    if (tag != null) {
      w.add('EXISTS (SELECT 1 FROM doc_tags dt JOIN tags t ON t.id = dt.tag_id WHERE dt.doc_id = d.id AND t.name = ?)');
      a.add(tag);
    }
    if (query.trim().isNotEmpty) {
      final q = '%${query.trim()}%';
      w.add('(d.title LIKE ? OR EXISTS (SELECT 1 FROM pages WHERE doc_id = d.id AND ocr_text LIKE ?) '
          'OR EXISTS (SELECT 1 FROM doc_tags dt JOIN tags t ON t.id = dt.tag_id WHERE dt.doc_id = d.id AND t.name LIKE ?))');
      a..add(q)..add(q)..add(q);
    }
    return _docs(w.join(' AND '), a);
  }

  Future<ScanDocument?> document(int id) async {
    final l = await _docs('d.id = ?', [id]);
    return l.isEmpty ? null : l.first;
  }

  Future<int> createDocument({
    required String title,
    int? folderId,
    required List<ScannedPage> pages,
    String kind = 'document',
    List<String> tags = const [],
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    return _db.transaction((txn) async {
      final id = await txn.insert('documents',
          {'title': title, 'folder_id': folderId, 'created': now, 'updated': now, 'kind': kind});
      for (var i = 0; i < pages.length; i++) { await _insertPage(txn, id, i, pages[i]); }
      if (tags.isNotEmpty) await _setTagsOn(txn, id, tags);
      return id;
    });
  }

  // ───────── tags / favourites / collections
  Future<void> _setTagsOn(DatabaseExecutor ex, int docId, List<String> names) async {
    await ex.delete('doc_tags', where: 'doc_id = ?', whereArgs: [docId]);
    for (final raw in names) {
      final n = raw.trim().replaceAll(',', ' ').trim();
      if (n.isEmpty) continue;
      await ex.rawInsert('INSERT OR IGNORE INTO tags(name) VALUES(?)', [n]);
      final id = Sqflite.firstIntValue(await ex.rawQuery('SELECT id FROM tags WHERE name = ?', [n]));
      if (id != null) await ex.rawInsert('INSERT OR IGNORE INTO doc_tags(doc_id, tag_id) VALUES(?, ?)', [docId, id]);
    }
  }

  Future<void> setTags(int docId, List<String> names) async {
    await _db.transaction((txn) => _setTagsOn(txn, docId, names));
    await _touch(docId, {});
  }

  /// Most used tags first (used for gallery chips and suggestions).
  Future<List<String>> allTags({int limit = 12}) async {
    final rows = await _db.rawQuery(
        'SELECT t.name, COUNT(dt.doc_id) AS c FROM tags t LEFT JOIN doc_tags dt ON dt.tag_id = t.id '
        'GROUP BY t.id ORDER BY c DESC, t.name LIMIT ?', [limit]);
    return [for (final r in rows) r['name'] as String];
  }

  Future<void> setFavorite(int id, bool v) =>
      _db.update('documents', {'fav': v ? 1 : 0}, where: 'id = ?', whereArgs: [id]);

  /// Dashboard numbers: pages, bytes, documents created this month.
  Future<({int pages, int bytes, int month})> stats() async {
    final r = (await _db.rawQuery('SELECT COUNT(*) AS n, COALESCE(SUM(p.bytes), 0) AS b FROM pages p '
        'JOIN documents d ON d.id = p.doc_id WHERE d.trashed IS NULL')).first;
    final n = DateTime.now();
    final from = DateTime(n.year, n.month).millisecondsSinceEpoch;
    final m = Sqflite.firstIntValue(
            await _db.rawQuery('SELECT COUNT(*) FROM documents WHERE trashed IS NULL AND created >= ?', [from])) ??
        0;
    return (pages: (r['n'] as num).toInt(), bytes: (r['b'] as num).toInt(), month: m);
  }

  Future<Map<String, int>> kindCounts() async {
    final rows = await _db.rawQuery('SELECT kind, COUNT(*) AS c FROM documents WHERE trashed IS NULL GROUP BY kind');
    return {for (final r in rows) r['kind'] as String: (r['c'] as num).toInt()};
  }

  Future<void> renameDocument(int id, String title) => _touch(id, {'title': title});
  Future<void> moveDocument(int id, int? folderId) => _touch(id, {'folder_id': folderId});

  Future<void> _touch(int id, Map<String, Object?> v) =>
      _db.update('documents', {...v, 'updated': DateTime.now().millisecondsSinceEpoch}, where: 'id = ?', whereArgs: [id]);

  // ───────── trash (documents stay on disk until emptied)
  Future<void> trashDocument(int id) =>
      _db.update('documents', {'trashed': DateTime.now().millisecondsSinceEpoch}, where: 'id = ?', whereArgs: [id]);
  Future<void> restoreDocument(int id) => _db.update('documents', {'trashed': null}, where: 'id = ?', whereArgs: [id]);
  Future<List<ScanDocument>> trashedDocuments() => _docs('d.trashed IS NOT NULL', []);
  Future<int> trashCount() async =>
      Sqflite.firstIntValue(await _db.rawQuery('SELECT COUNT(*) FROM documents WHERE trashed IS NOT NULL')) ?? 0;
  Future<void> emptyTrash() async {
    for (final d in await trashedDocuments()) { await deleteDocument(d.id); }
  }

  /// Permanently deletes a document and its files.
  Future<void> deleteDocument(int id) async {
    final dir = Directory(p.join(_root.path, '$id'));
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    await _db.delete('documents', where: 'id = ?', whereArgs: [id]); // pages cascade
  }

  // ───────── pages
  Future<List<ScanPage>> pages(int docId) async => [
        for (final r in await _db.query('pages', where: 'doc_id = ?', whereArgs: [docId], orderBy: 'position'))
          ScanPage.fromRow(r)
      ];

  Future<void> addPages(int docId, List<ScannedPage> pages) async {
    final start = (Sqflite.firstIntValue(
                await _db.rawQuery('SELECT COALESCE(MAX(position), -1) FROM pages WHERE doc_id = ?', [docId])) ?? -1) + 1;
    await _db.transaction((txn) async {
      for (var i = 0; i < pages.length; i++) { await _insertPage(txn, docId, start + i, pages[i]); }
    });
    await _touch(docId, {});
  }

  Future<void> replacePage(int pageId, ScannedPage sp) async {
    final row = (await _db.query('pages', where: 'id = ?', whereArgs: [pageId])).first;
    final old = ScanPage.fromRow(row);
    final f = await _copyIn(old.docId, sp);
    await _db.update('pages', {
      'image_path': f.$1, 'thumb_path': f.$2, 'orig_path': f.$3,
      'corners': sp.cornersJson, 'filter': sp.filter, 'bytes': File(f.$1).lengthSync(), 'ocr_text': null,
    }, where: 'id = ?', whereArgs: [pageId]);
    for (final x in [old.imagePath, old.thumbPath, old.origPath]) { _rm(x); }
    await _touch(old.docId, {});
  }

  Future<void> setPageTitle(int pageId, String? title) =>
      _db.update('pages', {'title': (title == null || title.trim().isEmpty) ? null : title.trim()}, where: 'id = ?', whereArgs: [pageId]);

  /// Per-document PDF settings (JSON) or null = use the defaults from Settings.
  Future<Map<String, dynamic>?> pdfSettings(int docId) async {
    final r = await _db.query('documents', columns: ['pdf_settings'], where: 'id = ?', whereArgs: [docId]);
    final v = r.isEmpty ? null : r.first['pdf_settings'] as String?;
    return v == null ? null : Map<String, dynamic>.from(jsonDecode(v) as Map);
  }

  Future<void> setPdfSettings(int docId, Map<String, dynamic> v) =>
      _db.update('documents', {'pdf_settings': jsonEncode(v)}, where: 'id = ?', whereArgs: [docId]);

  ScannedPage _asScanned(ScanPage pg) => ScannedPage(
      origPath: pg.origPath, finalPath: pg.imagePath, thumbPath: pg.thumbPath, corners: pg.corners, filter: pg.filter);

  /// Copies pages (files too) to the end of [docId].
  Future<void> copyPagesTo(List<ScanPage> pages, int docId) => addPages(docId, [for (final pg in pages) _asScanned(pg)]);

  /// Moves pages to the end of [docId]; the source document is deleted if it becomes empty.
  Future<void> movePagesTo(List<ScanPage> pages, int docId) async {
    await copyPagesTo(pages, docId);
    for (final pg in pages) { await deletePage(pg); }
  }

  /// New document with copies of [pages].
  Future<int> newDocumentFromPages(String title, int? folderId, List<ScanPage> pages) =>
      createDocument(title: title, folderId: folderId, pages: [for (final pg in pages) _asScanned(pg)]);

  Future<int> copyDocument(int id) async {
    final d = (await document(id))!;
    return newDocumentFromPages('${d.title} (copy)', d.folderId, await pages(id));
  }

  /// Merges documents (in the given order) into a new one and removes the originals.
  Future<int> mergeDocuments(List<int> ids, String title) async {
    final all = <ScanPage>[];
    int? folder;
    for (final id in ids) {
      folder ??= (await document(id))?.folderId;
      all.addAll(await pages(id));
    }
    final nid = await newDocumentFromPages(title, folder, all);
    for (final id in ids) { await deleteDocument(id); }
    return nid;
  }

  Future<void> setPageNote(int pageId, String? note) =>
      _db.update('pages', {'note': (note == null || note.trim().isEmpty) ? null : note.trim()}, where: 'id = ?', whereArgs: [pageId]);

  /// Returns pages left; deletes the whole document when none remain.
  Future<int> deletePage(ScanPage pg) async {
    for (final x in [pg.imagePath, pg.thumbPath, pg.origPath]) { _rm(x); }
    await _db.delete('pages', where: 'id = ?', whereArgs: [pg.id]);
    final left = Sqflite.firstIntValue(await _db.rawQuery('SELECT COUNT(*) FROM pages WHERE doc_id = ?', [pg.docId])) ?? 0;
    if (left == 0) { await deleteDocument(pg.docId); } else { await _touch(pg.docId, {}); }
    return left;
  }

  Future<void> reorder(int docId, List<int> orderedPageIds) async {
    final b = _db.batch();
    for (var i = 0; i < orderedPageIds.length; i++) {
      b.update('pages', {'position': i}, where: 'id = ?', whereArgs: [orderedPageIds[i]]);
    }
    await b.commit(noResult: true);
    await _touch(docId, {});
  }

  // ───────── file helpers
  Future<(String, String, String)> _copyIn(int docId, ScannedPage sp) async {
    final dir = Directory(p.join(_root.path, '$docId'))..createSync(recursive: true);
    final stamp = DateTime.now().microsecondsSinceEpoch;
    Future<String> put(String src, String tag) async {
      final dst = p.join(dir.path, '${tag}_$stamp.jpg');
      await File(src).copy(dst);
      return dst;
    }
    return (await put(sp.finalPath, 'page'), await put(sp.thumbPath, 'thumb'), await put(sp.origPath, 'orig'));
  }

  Future<void> _insertPage(DatabaseExecutor ex, int docId, int pos, ScannedPage sp) async {
    final f = await _copyIn(docId, sp);
    await ex.insert('pages', {
      'doc_id': docId, 'position': pos, 'image_path': f.$1, 'thumb_path': f.$2, 'orig_path': f.$3,
      'corners': sp.cornersJson, 'filter': sp.filter, 'bytes': File(f.$1).lengthSync(),
    });
  }

  void _rm(String path) {
    try { File(path).deleteSync(); } catch (_) {}
  }

  // ───────── OCR search index
  Future<List<ScanPage>> pagesNeedingOcr({int limit = 4}) async => [
        for (final r in await _db.query('pages', where: 'ocr_text IS NULL', orderBy: 'id', limit: limit))
          ScanPage.fromRow(r)
      ];

  Future<int> pendingOcrCount() async =>
      Sqflite.firstIntValue(await _db.rawQuery('SELECT COUNT(*) FROM pages WHERE ocr_text IS NULL')) ?? 0;

  Future<void> setOcrText(int pageId, String text) =>
      _db.update('pages', {'ocr_text': text}, where: 'id = ?', whereArgs: [pageId]);

  Future<void> resetOcrIndex() => _db.update('pages', {'ocr_text': null});

  // ───────── backup / restore
  Future<({Map<String, Object?> manifest, Map<String, String> files})> buildBackupData() async {
    final files = <String, String>{};
    final pages = <Map<String, Object?>>[];
    for (final r in await _db.query('pages')) {
      final m = Map<String, Object?>.from(r);
      for (final k in ['image_path', 'thumb_path', 'orig_path']) {
        final abs = m[k] as String;
        final rel = p.relative(abs, from: _root.path).replaceAll('\\', '/');
        m[k] = rel;
        files['files/$rel'] = abs;
      }
      pages.add(m);
    }
    return (
      manifest: <String, Object?>{
        'app': 'kelmo_scan',
        'version': 1,
        'created': DateTime.now().toIso8601String(),
        'folders': await _db.query('folders'),
        'documents': await _db.query('documents'),
        'pages': pages,
        'tags': await _db.query('tags'),
        'doc_tags': await _db.query('doc_tags'),
      },
      files: files,
    );
  }

  /// [dir] = extracted backup (manifest.json + files/<docId>/...). Replaces everything.
  Future<void> restoreFromDir(Directory dir) async {
    final mf = File(p.join(dir.path, 'manifest.json'));
    if (!mf.existsSync()) throw const FormatException('Not a Kelmo Scan backup (manifest missing)');
    final m = jsonDecode(mf.readAsStringSync()) as Map<String, dynamic>;
    if (m['app'] != 'kelmo_scan' && m['app'] != 'rugal_scan') throw const FormatException('Not a Kelmo Scan backup');

    // 1) files
    if (_root.existsSync()) _root.deleteSync(recursive: true);
    _root.createSync(recursive: true);
    final src = Directory(p.join(dir.path, 'files'));
    if (src.existsSync()) {
      for (final e in src.listSync()) {
        e.renameSync(p.join(_root.path, p.basename(e.path)));
      }
    }
    // 2) database rows (ids preserved so relative paths stay valid)
    await _db.transaction((txn) async {
      await txn.delete('pages');
      await txn.delete('doc_tags');
      await txn.delete('tags');
      await txn.delete('documents');
      await txn.delete('folders');
      for (final f in m['folders'] as List) { await txn.insert('folders', Map<String, Object?>.from(f as Map)); }
      for (final d in m['documents'] as List) { await txn.insert('documents', Map<String, Object?>.from(d as Map)); }
      for (final t in (m['tags'] as List?) ?? const []) { await txn.insert('tags', Map<String, Object?>.from(t as Map)); }
      for (final t in (m['doc_tags'] as List?) ?? const []) { await txn.insert('doc_tags', Map<String, Object?>.from(t as Map)); }
      for (final pg in m['pages'] as List) {
        final row = Map<String, Object?>.from(pg as Map);
        for (final k in ['image_path', 'thumb_path', 'orig_path']) {
          row[k] = p.join(_root.path, row[k] as String);
        }
        await txn.insert('pages', row);
      }
    });
  }
}
