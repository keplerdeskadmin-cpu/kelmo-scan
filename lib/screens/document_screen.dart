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

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../models/scan_document.dart';
import '../services/document_repository.dart';
import '../services/doc_export.dart';
import '../services/image_processing_service.dart';
import '../services/ocr_indexer.dart';
import '../theme/app_themes.dart';
import '../widgets/cs_bars.dart';
import '../widgets/dialogs.dart';
import '../widgets/ocr_sheet.dart';
import 'camera_screen.dart';
import 'edit_scan_screen.dart';
import 'markup_screen.dart';
import 'page_view_screen.dart';
import 'pdf_view_screen.dart';
import 'redact_screen.dart';
import 'share_screen.dart';

/// One document (Clear Scanner style): page grid, PDF preview, add pages, share, more.
class DocumentScreen extends StatefulWidget {
  const DocumentScreen({super.key, required this.docId});
  final int docId;
  @override
  State<DocumentScreen> createState() => _DocumentScreenState();
}

class _DocumentScreenState extends State<DocumentScreen> {
  final _repo = DocumentRepository.instance;
  ScanDocument? _doc;
  List<ScanPage> _pages = [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final d = await _repo.document(widget.docId);
    if (d == null) { if (mounted) Navigator.pop(context); return; }
    final pg = await _repo.pages(widget.docId);
    if (mounted) setState(() { _doc = d; _pages = pg; });
  }

  String get _title => _doc?.title ?? '';

  Future<void> _rename() async {
    final n = await promptText(context, 'Rename', initial: _title);
    if (n != null) { await _repo.renameDocument(widget.docId, n); _load(); }
  }

  Future<void> _move() async {
    final id = await pickFolder(context, await _repo.folders(), _doc!.folderId);
    if (id != null) { await _repo.moveDocument(widget.docId, id == -1 ? null : id); _load(); }
  }

  Future<void> _trash() async {
    if (await confirm(context, 'Move to Trash?', 'You can restore it from Trash in the menu.', yes: 'Move')) {
      await _repo.trashDocument(widget.docId);
      if (mounted) Navigator.pop(context);
    }
  }

  Future<void> _addTag() async {
    final n = await promptText(context, 'Add tag', hint: 'e.g. client name, Umrah, Visa');
    if (n != null) { await _repo.setTags(widget.docId, [..._doc!.tags, n]); _load(); }
  }

  Future<void> _addPages({bool gallery = false}) async {
    final ok = await Navigator.push<bool>(
        context, MaterialPageRoute(builder: (_) => CameraScreen(addToDocId: widget.docId, startWithGallery: gallery)));
    if (ok == true) _load();
  }

  Future<void> _openPage(int i) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => PageViewScreen(docId: widget.docId, title: _title, initial: i)));
    imageCache.clear();
    _load();
  }

  Future<void> _editPage(ScanPage pg) async {
    final sp = await Navigator.push<ScannedPage>(
      context,
      MaterialPageRoute(
        builder: (_) => EditScanScreen(
            imagePath: pg.origPath, initialCorners: pg.corners, initialMode: FilterMode.fromNative(pg.filter), ctaLabel: 'Save'),
      ),
    );
    if (sp == null) return;
    await _repo.replacePage(pg.id, sp);
    unawaited(OcrIndexer.run());
    imageCache.clear();
    _load();
  }

  Future<void> _markupPage(ScanPage pg, {bool redact = false}) async {
    final out = await Navigator.push<String>(context, MaterialPageRoute(
        builder: (_) => redact ? RedactScreen(imagePath: pg.imagePath) : MarkupScreen(imagePath: pg.imagePath)));
    if (out == null) return;
    setState(() => _busy = true);
    final thumb = await ImageProcessingService.instance.applyFilter(out, FilterMode.original, maxSide: 360);
    await _repo.replacePage(
      pg.id,
      ScannedPage(
        origPath: out, finalPath: out, thumbPath: thumb, filter: 'original',
        corners: const [Offset(0, 0), Offset(1, 0), Offset(1, 1), Offset(0, 1)],
      ),
    );
    unawaited(OcrIndexer.run());
    imageCache.clear();
    await _load();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _movePage(int i, int dir) async {
    final j = i + dir;
    if (j < 0 || j >= _pages.length) return;
    final ids = [for (final x in _pages) x.id];
    final t = ids[i]; ids[i] = ids[j]; ids[j] = t;
    await _repo.reorder(widget.docId, ids);
    _load();
  }

  Future<void> _deletePage(ScanPage pg) async {
    if (!await confirm(context, 'Delete page?', 'This page will be removed.')) return;
    final left = await _repo.deletePage(pg);
    if (left == 0 && mounted) { Navigator.pop(context); return; }
    _load();
  }

  Future<void> _pageMenu(int i) async {
    final pg = _pages[i];
    final v = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(title: Text('Page ${i + 1}', style: const TextStyle(fontWeight: FontWeight.w600))),
          ListTile(leading: const Icon(Icons.crop), title: const Text('Crop & filter'), onTap: () => Navigator.pop(ctx, 'edit')),
          ListTile(leading: const Icon(Icons.edit), title: const Text('Markup & signature'), onTap: () => Navigator.pop(ctx, 'markup')),
          ListTile(leading: const Icon(Icons.format_color_fill), title: const Text('Redact / blur / highlight'), onTap: () => Navigator.pop(ctx, 'redact')),
          ListTile(leading: const Icon(Icons.document_scanner_outlined), title: const Text('OCR (extract text)'), onTap: () => Navigator.pop(ctx, 'ocr')),
          if (i > 0) ListTile(leading: const Icon(Icons.arrow_back), title: const Text('Move earlier'), onTap: () => Navigator.pop(ctx, 'up')),
          if (i < _pages.length - 1)
            ListTile(leading: const Icon(Icons.arrow_forward), title: const Text('Move later'), onTap: () => Navigator.pop(ctx, 'down')),
          ListTile(leading: const Icon(Icons.delete_outline), title: const Text('Delete page'), onTap: () => Navigator.pop(ctx, 'delete')),
        ]),
      ),
    );
    switch (v) {
      case 'edit': await _editPage(pg);
      case 'markup': await _markupPage(pg);
      case 'redact': await _markupPage(pg, redact: true);
      case 'ocr': if (mounted) OcrSheet.show(context, [pg.imagePath]);
      case 'up': await _movePage(i, -1);
      case 'down': await _movePage(i, 1);
      case 'delete': await _deletePage(pg);
    }
  }

  void _docMenu(String v) {
    switch (v) {
      case 'rename': _rename();
      case 'move': _move();
      case 'fav': _repo.setFavorite(widget.docId, !(_doc?.fav ?? false)).then((_) => _load());
      case 'tag': _addTag();
      case 'ocr': if (_pages.isNotEmpty) OcrSheet.show(context, [for (final x in _pages) x.imagePath]);
      case 'delete': _trash();
    }
  }

  String _pageInfo(ScanPage pg) {
    var b = 0;
    try { b = File(pg.imagePath).lengthSync(); } catch (_) {}
    final day = _doc?.dateLabel.split(',').first ?? '';
    return '$day, ${bytesLabel(b)}';
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final d = _doc;
    return Scaffold(
      backgroundColor: const Color(0xFFE4E6E6),
      appBar: AppBar(
        backgroundColor: p.appBar,
        titleSpacing: 0,
        title: GestureDetector(
          onTap: d == null ? null : _rename,
          child: Text(_title, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            tooltip: 'PDF',
            onPressed: _pages.isEmpty
                ? null
                : () => Navigator.push(context, MaterialPageRoute(builder: (_) => PdfViewScreen(title: _title, pages: _pages))),
          ),
          PopupMenuButton<String>(
            color: Colors.white,
            onSelected: _docMenu,
            itemBuilder: (_) => [
              csMenuItem('rename', Icons.edit, 'Rename'),
              csMenuItem('move', Icons.drive_file_move_outline, 'Move to folder'),
              csMenuItem('fav', d?.fav == true ? Icons.star : Icons.star_border, d?.fav == true ? 'Remove favorite' : 'Add to favorites'),
              csMenuItem('tag', Icons.sell_outlined, 'Add tag'),
              csMenuItem('ocr', Icons.document_scanner_outlined, 'OCR all pages'),
              csMenuItem('delete', Icons.delete_outline, 'Delete'),
            ],
          ),
        ],
      ),
      body: Stack(children: [
        GridView.builder(
          padding: const EdgeInsets.all(12),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: .72),
          itemCount: _pages.length,
          itemBuilder: (_, i) {
            final pg = _pages[i];
            return GestureDetector(
              onTap: () => _openPage(i),
              onLongPress: () => _pageMenu(i),
              child: Container(
                decoration: const BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 3)]),
                child: Stack(children: [
                  Positioned.fill(
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Image.file(File(pg.thumbPath), key: ValueKey(pg.thumbPath), fit: BoxFit.contain),
                    ),
                  ),
                  Positioned(
                    left: 0, right: 0, bottom: 0,
                    child: Container(
                      color: const Color(0xE6224646),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      child: Row(children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          decoration: BoxDecoration(border: Border.all(color: Colors.white, width: 1.2)),
                          child: Text((i + 1).toString().padLeft(2, '0'), style: const TextStyle(color: Colors.white, fontSize: 12)),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(_pageInfo(pg), maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white, fontSize: 12)),
                        ),
                        if ((pg.note ?? '').isNotEmpty) const Icon(Icons.sticky_note_2, color: Colors.white, size: 14),
                      ]),
                    ),
                  ),
                ]),
              ),
            );
          },
        ),
        if (_busy) Positioned.fill(child: Container(color: Colors.black26, child: Center(child: CircularProgressIndicator(color: p.accent)))),
      ]),
      bottomNavigationBar: CsBottomBar(children: [
        const Spacer(),
        CsBarIcon(icon: Icons.image, tooltip: 'Add from gallery', onTap: d == null ? null : () => _addPages(gallery: true)),
        const SizedBox(width: 10),
        CsBarIcon(icon: Icons.photo_camera, tooltip: 'Add pages', onTap: d == null ? null : _addPages),
        const Spacer(),
        CsBarButton(icon: Icons.share, label: 'Share', onTap: _pages.isEmpty ? null : () => ShareScreen.open(context, _title, _pages)),
        CsMoreButton(pages: () => _pages, name: () => _title),
      ]),
    );
  }
}
