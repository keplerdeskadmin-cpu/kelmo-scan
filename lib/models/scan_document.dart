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
import 'dart:ui' show Offset;

String _dateLabel(DateTime d) {
  final n = DateTime.now();
  String hm(DateTime x) => '${x.hour.toString().padLeft(2, '0')}:${x.minute.toString().padLeft(2, '0')}';
  bool same(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
  if (same(d, n)) return 'Today, ${hm(d)}';
  if (same(d, n.subtract(const Duration(days: 1)))) return 'Yesterday, ${hm(d)}';
  const m = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
  return '${m[d.month - 1]} ${d.day}, ${d.year}';
}

class Folder {
  const Folder(this.id, this.name, this.count);
  final int id;
  final String name;
  final int count;
}

class ScanDocument {
  ScanDocument({
    required this.id, required this.title, required this.folderId, required this.updated,
    required this.pageCount, required this.bytes, this.thumbPath,
    this.fav = false, this.kind = 'document', this.tags = const [],
  });

  factory ScanDocument.fromRow(Map<String, Object?> r) {
    final tl = r['tag_list'] as String?;
    return ScanDocument(
      id: r['id'] as int,
      title: r['title'] as String,
      folderId: r['folder_id'] as int?,
      updated: DateTime.fromMillisecondsSinceEpoch(r['updated'] as int),
      pageCount: (r['pc'] as num).toInt(),
      bytes: (r['bytes'] as num).toInt(),
      thumbPath: r['thumb'] as String?,
      fav: ((r['fav'] as num?) ?? 0) == 1,
      kind: (r['kind'] as String?) ?? 'document',
      tags: (tl == null || tl.isEmpty) ? const [] : tl.split('\u001f'),
    );
  }

  final int id, pageCount, bytes;
  final String title;
  final int? folderId;
  final DateTime updated;
  final String? thumbPath;
  final bool fav;
  final String kind;
  final List<String> tags;

  String get dateLabel => _dateLabel(updated);
  String get meta {
    final size = bytes >= 1 << 20 ? '${(bytes / (1 << 20)).toStringAsFixed(1)} MB' : '${(bytes / 1024).round()} KB';
    return '$pageCount ${pageCount == 1 ? 'page' : 'pages'} • $size';
  }
}

/// A page stored in the database.
class ScanPage {
  ScanPage({required this.id, required this.docId, required this.position, required this.imagePath,
      required this.thumbPath, required this.origPath, required this.corners, required this.filter, this.note});

  factory ScanPage.fromRow(Map<String, Object?> r) => ScanPage(
        id: r['id'] as int,
        docId: r['doc_id'] as int,
        position: r['position'] as int,
        imagePath: r['image_path'] as String,
        thumbPath: r['thumb_path'] as String,
        origPath: r['orig_path'] as String,
        corners: [
          for (final e in jsonDecode(r['corners'] as String) as List)
            Offset((e[0] as num).toDouble(), (e[1] as num).toDouble())
        ],
        filter: r['filter'] as String,
        note: r['note'] as String?,
      );

  final int id, docId, position;
  final String imagePath, thumbPath, origPath, filter;
  final List<Offset> corners;
  final String? note;
}

/// Result returned by the edit screen (files are still in temp; repository copies them).
class ScannedPage {
  ScannedPage({required this.origPath, required this.finalPath, required this.thumbPath,
      required this.corners, required this.filter});
  final String origPath, finalPath, thumbPath, filter;
  final List<Offset> corners;
  String get cornersJson => jsonEncode([for (final c in corners) [c.dx, c.dy]]);
}
