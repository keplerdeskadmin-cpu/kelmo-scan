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
import '../services/image_processing_service.dart';
import '../services/ocr_indexer.dart';
import '../theme/app_themes.dart';
import '../widgets/cs_bars.dart';
import '../widgets/dialogs.dart';
import '../widgets/ocr_sheet.dart';
import 'edit_scan_screen.dart';
import 'markup_screen.dart';
import 'redact_screen.dart';
import 'share_screen.dart';

/// One page full screen (swipe for the others): crop, markup, note, OCR, share.
class PageViewScreen extends StatefulWidget {
  const PageViewScreen({super.key, required this.docId, required this.title, this.initial = 0});
  final int docId;
  final String title;
  final int initial;
  @override
  State<PageViewScreen> createState() => _PageViewScreenState();
}

class _PageViewScreenState extends State<PageViewScreen> {
  final _repo = DocumentRepository.instance;
  late final PageController _pc = PageController(initialPage: widget.initial);
  late int _i = widget.initial;
  List<ScanPage> _pages = [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final pg = await _repo.pages(widget.docId);
    if (!mounted) return;
    if (pg.isEmpty) { Navigator.pop(context); return; }
    setState(() { _pages = pg; if (_i >= pg.length) _i = pg.length - 1; });
  }

  ScanPage get _pg => _pages[_i];

  Future<void> _edit() async {
    final pg = _pg;
    final sp = await Navigator.push<ScannedPage>(
      context,
      MaterialPageRoute(
        builder: (_) => EditScanScreen(
            imagePath: pg.origPath, initialCorners: pg.corners, initialMode: FilterMode.fromNative(pg.filter), ctaLabel: 'Save'),
      ),
    );
    if (sp == null) return;
    setState(() => _busy = true);
    await _repo.replacePage(pg.id, sp);
    unawaited(OcrIndexer.run());
    imageCache.clear();
    await _load();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _markup({bool redact = false, bool stamp = false}) async {
    final pg = _pg;
    final out = await Navigator.push<String>(context, MaterialPageRoute(
        builder: (_) => redact ? RedactScreen(imagePath: pg.imagePath) : MarkupScreen(imagePath: pg.imagePath, openStamp: stamp)));
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

  Future<void> _note() async {
    final pg = _pg;
    final v = await promptText(context, 'Note', initial: pg.note ?? '', hint: 'Write a note for this page');
    if (v == null) return;
    await _repo.setPageNote(pg.id, v);
    _load();
  }

  /// Rotates the page 90° clockwise (the original too, so a later crop stays correct).
  Future<void> _rotate() async {
    final pg = _pg;
    setState(() => _busy = true);
    try {
      final svc = ImageProcessingService.instance;
      final img = await svc.rotate90(pg.imagePath);
      final thumb = await svc.applyFilter(img, FilterMode.original, maxSide: 360);
      await _repo.replacePage(pg.id, ScannedPage(origPath: img, finalPath: img, thumbPath: thumb, filter: pg.filter,
          corners: const [Offset(0, 0), Offset(1, 0), Offset(1, 1), Offset(0, 1)]));
      imageCache.clear();
      await _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pageTitle() async {
    final v = await promptText(context, 'Page Title', initial: _pg.title ?? '', hint: 'Title of this page');
    if (v == null) return;
    await _repo.setPageTitle(_pg.id, v);
    _load();
  }

  Future<void> _delete() async {
    if (!await confirm(context, 'Delete page?', 'This page will be removed.')) return;
    final left = await _repo.deletePage(_pg);
    if (left == 0) { if (mounted) Navigator.pop(context); return; }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final ready = _pages.isNotEmpty;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: p.appBar,
        titleSpacing: 0,
        title: Text(ready ? '${(_pg.title ?? '').isNotEmpty ? _pg.title : widget.title}  ${_i + 1}/${_pages.length}' : widget.title,
            maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(icon: const Icon(Icons.crop), tooltip: 'Crop image', onPressed: ready ? _edit : null),
          IconButton(icon: const Icon(Icons.edit), tooltip: 'Markup', onPressed: ready ? () => _markup() : null),
          PopupMenuButton<String>(
            color: Colors.white,
            enabled: ready,
            onSelected: (v) => switch (v) {
              'rotate' => _rotate(),
              'title' => _pageTitle(),
              'delete' => _delete(),
              'redact' => _markup(redact: true),
              'stamp' => _markup(stamp: true),
              _ => runMoreAction(context, v, [_pg], widget.title),
            },
            itemBuilder: (_) => [
              csMenuItem('stamp', Icons.approval, 'Add Stamp'),
              csMenuItem('rotate', Icons.rotate_right, 'Rotate page'),
              csMenuItem('title', Icons.title, 'Page Title'),
              csMenuItem('delete', Icons.delete, 'Delete page'),
              const PopupMenuDivider(),
              csMenuItem('redact', Icons.format_color_fill, 'Redact / blur / highlight'),
            ],
          ),
        ],
      ),
      body: Stack(children: [
        if (ready)
          PageView.builder(
            controller: _pc,
            itemCount: _pages.length,
            onPageChanged: (i) => setState(() => _i = i),
            itemBuilder: (_, i) => InteractiveViewer(
              maxScale: 5,
              child: Center(child: Image.file(File(_pages[i].imagePath), key: ValueKey(_pages[i].imagePath))),
            ),
          ),
        if (ready && (_pg.note ?? '').isNotEmpty)
          Positioned(
            left: 12, right: 12, bottom: 12,
            child: GestureDetector(
              onTap: _note,
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: const Color(0xFFFFF59D), borderRadius: BorderRadius.circular(6)),
                child: Text(_pg.note!, style: const TextStyle(fontSize: 15, color: Color(0xFF202124))),
              ),
            ),
          ),
        if (_busy) Positioned.fill(child: Container(color: Colors.black38, child: const Center(child: CircularProgressIndicator(color: Colors.white)))),
      ]),
      bottomNavigationBar: CsBottomBar(children: [
        CsBarButton(icon: Icons.sticky_note_2_outlined, label: 'Note', onTap: ready ? _note : null),
        CsBarButton(icon: Icons.document_scanner_outlined, label: 'OCR', onTap: ready ? () => OcrSheet.show(context, [_pg.imagePath]) : null),
        const Spacer(),
        CsBarButton(
          icon: Icons.share, label: 'Share',
          onTap: ready ? () => ShareScreen.open(context, '${widget.title} ${_i + 1}', [_pg]) : null,
        ),
        CsMoreButton(pages: () => ready ? [_pg] : [], name: () => '${widget.title} ${_i + 1}'),
      ]),
    );
  }
}
