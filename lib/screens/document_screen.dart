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
import '../services/app_settings.dart';
import '../services/document_repository.dart';
import '../services/import_service.dart';
import '../services/doc_export.dart';
import '../services/image_processing_service.dart';
import '../services/ocr_indexer.dart';
import '../theme/app_themes.dart';
import '../widgets/cs_bars.dart';
import '../widgets/dialogs.dart';
import '../widgets/ocr_sheet.dart';
import '../widgets/pdf_settings_dialog.dart';
import 'camera_screen.dart';
import 'edit_scan_screen.dart';
import 'gallery_screen.dart' show pickSort;
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
  bool _busy = false, _selecting = false;
  final Set<int> _sel = {};

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

  Future<void> _markupPage(ScanPage pg, {bool redact = false, bool stamp = false}) async {
    if (!redact) {
      if (await editPageMarkup(context, pg, stamp: stamp)) {
        unawaited(OcrIndexer.run());
        await _load();
      }
      return;
    }
    final out = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => RedactScreen(imagePath: pg.imagePath)));
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
          ListTile(leading: const Icon(Icons.approval), title: const Text('Add Stamp'), onTap: () => Navigator.pop(ctx, 'stamp')),
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
      case 'stamp': await _markupPage(pg, stamp: true);
      case 'redact': await _markupPage(pg, redact: true);
      case 'ocr': if (mounted) OcrSheet.show(context, [pg.imagePath]);
      case 'up': await _movePage(i, -1);
      case 'down': await _movePage(i, 1);
      case 'delete': await _deletePage(pg);
    }
  }

  void _snack(String m) => ScaffoldMessenger.of(context)..hideCurrentSnackBar()..showSnackBar(SnackBar(content: Text(m)));

  Future<void> _work(Future<void> Function() job) async {
    setState(() => _busy = true);
    try {
      await job();
    } catch (e) {
      if (mounted) _snack('Failed: $e');
    } finally {
      imageCache.clear();
      await _load();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importPdf() async {
    final imgs = await ImportService.pickPdfPages();
    if (imgs == null) return;
    await _work(() async {
      if (imgs.isEmpty) throw Exception('This PDF has no pages (or it is password protected)');
      await _repo.addPages(widget.docId, await ImportService.pagesFromImages(imgs));
      _snack('${imgs.length} page(s) imported');
    });
  }

  Future<void> _importImages() async {
    final imgs = await ImportService.pickImages();
    if (imgs.isEmpty) return;
    await _work(() async => _repo.addPages(widget.docId, await ImportService.pagesFromImages(imgs)));
  }

  Future<void> _blank() => _work(() async =>
      _repo.addPages(widget.docId, [await ImportService.pageFromImage(await ImportService.blankPage())]));

  Future<void> _sortPages() async {
    final r = await pickSort(context, 'created', true, fields: const {'created': 'Date created', 'name': 'Page title'});
    if (r == null) return;
    final l = [..._pages];
    int c(ScanPage a, ScanPage b) =>
        r.$1 == 'name' ? (a.title ?? '').toLowerCase().compareTo((b.title ?? '').toLowerCase()) : a.id.compareTo(b.id);
    l.sort((a, b) => r.$2 ? c(a, b) : c(b, a));
    await _repo.reorder(widget.docId, [for (final x in l) x.id]);
    _load();
  }

  // ───────── page selection (Move / Copy to Current / Existing / New Document)
  List<ScanPage> get _selPages => [for (final x in _pages) if (_sel.contains(x.id)) x];
  void _endSelect() => setState(() { _selecting = false; _sel.clear(); });
  void _toggle(int id) => setState(() { if (!_sel.remove(id)) _sel.add(id); });

  Future<void> _transfer(bool move) async {
    final pages = _selPages;
    if (pages.isEmpty) return;
    final where = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(move ? 'Move to' : 'Copy to'),
        children: [
          if (!move) SimpleDialogOption(onPressed: () => Navigator.pop(ctx, 'current'), child: const Text('Current Document', style: TextStyle(fontSize: 16))),
          SimpleDialogOption(onPressed: () => Navigator.pop(ctx, 'existing'), child: const Text('Existing Document', style: TextStyle(fontSize: 16))),
          SimpleDialogOption(onPressed: () => Navigator.pop(ctx, 'new'), child: const Text('New Document', style: TextStyle(fontSize: 16))),
        ],
      ),
    );
    if (where == null || !mounted) return;
    int? target;
    if (where == 'current') {
      target = widget.docId;
    } else if (where == 'existing') {
      final docs = (await _repo.documents()).where((x) => x.id != widget.docId).toList();
      if (!mounted) return;
      if (docs.isEmpty) { _snack('No other documents'); return; }
      target = await showDialog<int>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('Select Document'),
          children: [
            for (final x in docs)
              SimpleDialogOption(onPressed: () => Navigator.pop(ctx, x.id), child: Text(x.title, style: const TextStyle(fontSize: 16))),
          ],
        ),
      );
      if (target == null) return;
    }
    final allMoved = move && pages.length == _pages.length;
    _endSelect();
    await _work(() async {
      if (where == 'new') {
        await _repo.newDocumentFromPages(AppSettings.instance.newDocumentName(), _doc?.folderId, pages);
        if (move) { for (final pg in pages) { await _repo.deletePage(pg); } }
      } else if (move) {
        await _repo.movePagesTo(pages, target!);
      } else {
        await _repo.copyPagesTo(pages, target!);
      }
      _snack('${pages.length} page(s) ${move ? 'moved' : 'copied'}');
    });
    if (allMoved && mounted) Navigator.pop(context);
  }

  Future<void> _deleteSelected() async {
    final pages = _selPages;
    if (pages.isEmpty) return;
    if (!await confirm(context, 'Delete ${pages.length} page(s)?', 'The selected pages will be removed.')) return;
    _endSelect();
    var left = 1;
    for (final pg in pages) { left = await _repo.deletePage(pg); }
    if (left == 0 && mounted) { Navigator.pop(context); return; }
    _load();
  }

  /// Process All: the same filter on every page (re-made from the original photo + border).
  Future<void> _processAll() async {
    if (_pages.isEmpty) return;
    const opts = [
      (FilterMode.original, 'Original'),
      (FilterMode.photo, 'Photo'),
      (FilterMode.auto, 'Docs (color)'),
      (FilterMode.bw, 'Docs (B&W)'),
      (FilterMode.magicColor, 'Clear (color)'),
      (FilterMode.grayscale, 'Clear (gray)'),
    ];
    final mode = await showDialog<FilterMode>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('Process All (${_pages.length} pages)'),
        children: [
          for (final o in opts)
            SimpleDialogOption(onPressed: () => Navigator.pop(ctx, o.$1), child: Text(o.$2, style: const TextStyle(fontSize: 16))),
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 8, 24, 0),
            child: Text('Markup on these pages will be removed.', style: TextStyle(fontSize: 12, color: Color(0xFF6F7777))),
          ),
        ],
      ),
    );
    if (mode == null) return;
    final svc = ImageProcessingService.instance;
    var done = 0;
    await _work(() async {
      for (final pg in List.of(_pages)) {
        final flat = await svc.warp(pg.origPath, pg.corners);
        final full = await svc.applyFilter(flat, mode);
        final thumb = await svc.applyFilter(flat, mode, maxSide: 360);
        await _repo.replacePage(pg.id, ScannedPage(origPath: pg.origPath, finalPath: full, thumbPath: thumb, corners: pg.corners, filter: mode.native));
        done++;
      }
      unawaited(OcrIndexer.run());
    });
    if (mounted) _snack('$done page(s) processed');
  }

  Future<void> _docMenu(String v) async {
    switch (v) {
      case 'process': await _processAll();
      case 'select': setState(() { _selecting = true; _sel.clear(); });
      case 'sort': await _sortPages();
      case 'pdf': await _importPdf();
      case 'images': await _importImages();
      case 'blank': await _blank();
      case 'pdfset': await showPdfSettings(context, widget.docId);
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
    return PopScope(
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, _) { if (!didPop) _endSelect(); },
      child: Scaffold(
      backgroundColor: const Color(0xFFE4E6E6),
      appBar: _selecting ? _selectBar(p) : AppBar(
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
              csMenuItem('select', Icons.check_box, 'Select'),
              csMenuItem('sort', Icons.sort, 'Sort'),
              csMenuItem('process', Icons.auto_fix_high, 'Process All'),
              const PopupMenuDivider(),
              csMenuItem('pdf', Icons.picture_as_pdf, 'Import PDF'),
              csMenuItem('images', Icons.add_photo_alternate, 'Import images'),
              csMenuItem('blank', Icons.note_add, 'New Blank page'),
              const PopupMenuDivider(),
              csMenuItem('rename', Icons.edit, 'Rename'),
              csMenuItem('pdfset', Icons.settings, 'PDF Settings'),
              const PopupMenuDivider(),
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
            final sel = _sel.contains(pg.id);
            return GestureDetector(
              onTap: () => _selecting ? _toggle(pg.id) : _openPage(i),
              onLongPress: () => _selecting ? _toggle(pg.id) : _pageMenu(i),
              child: Container(
                decoration: const BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 3)]),
                child: Stack(children: [
                  Positioned.fill(
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Image.file(File(pg.thumbPath), key: ValueKey(pg.thumbPath), fit: BoxFit.contain, cacheWidth: 400),
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
                          child: Text((pg.title ?? '').isNotEmpty ? pg.title! : _pageInfo(pg), maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white, fontSize: 12)),
                        ),
                        if ((pg.note ?? '').isNotEmpty) const Icon(Icons.sticky_note_2, color: Colors.white, size: 14),
                      ]),
                    ),
                  ),
                  if (_selecting)
                    Positioned(left: 4, top: 4, child: Icon(sel ? Icons.check_box : Icons.check_box_outline_blank, color: p.accent, size: 26)),
                ]),
              ),
            );
          },
        ),
        if (_busy) Positioned.fill(child: Container(color: Colors.black26, child: Center(child: CircularProgressIndicator(color: p.accent)))),
      ]),
      bottomNavigationBar: _selecting ? null : CsBottomBar(children: [
        const Spacer(),
        CsBarIcon(icon: Icons.image, tooltip: 'Add from gallery', onTap: d == null ? null : () => _addPages(gallery: true)),
        const SizedBox(width: 10),
        CsBarIcon(icon: Icons.photo_camera, tooltip: 'Add pages', onTap: d == null ? null : _addPages),
        const Spacer(),
        CsBarButton(icon: Icons.share, label: 'Share', onTap: _pages.isEmpty ? null : () => ShareScreen.open(context, _title, _pages)),
        CsMoreButton(pages: () => _pages, name: () => _title),
      ]),
    ),
    );
  }

  PreferredSizeWidget _selectBar(AppPalette p) => AppBar(
        backgroundColor: p.appBar,
        leading: IconButton(icon: const Icon(Icons.close), onPressed: _endSelect),
        title: Text('${_sel.length} selected'),
        actions: [
          IconButton(
            icon: const Icon(Icons.select_all), tooltip: 'Select all',
            onPressed: () => setState(() {
              if (_sel.length == _pages.length) { _sel.clear(); } else { _sel.addAll(_pages.map((x) => x.id)); }
            }),
          ),
          IconButton(
            icon: const Icon(Icons.share), tooltip: 'Share',
            onPressed: _sel.isEmpty ? null : () => ShareScreen.open(context, _title, _selPages),
          ),
          IconButton(icon: const Icon(Icons.delete), tooltip: 'Delete', onPressed: _sel.isEmpty ? null : _deleteSelected),
          PopupMenuButton<String>(
            color: Colors.white,
            enabled: _sel.isNotEmpty,
            onSelected: (v) => _transfer(v == 'move'),
            itemBuilder: (_) => [
              csMenuItem('move', Icons.drive_file_move, 'Move to…'),
              csMenuItem('copy', Icons.file_copy, 'Copy to…'),
            ],
          ),
        ],
      );
}
