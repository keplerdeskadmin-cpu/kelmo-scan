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
import 'package:share_plus/share_plus.dart';
import '../models/scan_document.dart';
import '../services/document_repository.dart';
import '../services/image_processing_service.dart';
import '../services/ocr_indexer.dart';
import '../services/pdf_exporter.dart';
import '../theme/app_themes.dart';
import '../widgets/cta_button.dart';
import '../widgets/dialogs.dart';
import '../widgets/ocr_sheet.dart';
import '../widgets/share_sheet.dart';
import 'camera_screen.dart';
import 'edit_scan_screen.dart';
import 'redact_screen.dart';

/// One document: drag-to-reorder pages, edit/delete page, add pages, OCR, PDF export.
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

  Future<void> _rename() async {
    final n = await promptText(context, 'Rename', initial: _doc!.title);
    if (n != null) { await _repo.renameDocument(_doc!.id, n); _load(); }
  }

  Future<void> _move() async {
    final id = await pickFolder(context, await _repo.folders(), _doc!.folderId);
    if (id != null) { await _repo.moveDocument(_doc!.id, id == -1 ? null : id); _load(); }
  }

  Future<void> _deleteDoc() async {
    if (await confirm(context, 'Move to Trash?', 'You can restore it from Trash in the menu.')) {
      await _repo.trashDocument(_doc!.id);
      if (mounted) Navigator.pop(context);
    }
  }

  /// Opens the redaction editor; the result REPLACES the page (original photo is discarded -> permanent).
  Future<void> _redactPage(ScanPage pg) async {
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
    unawaited(OcrIndexer.run()); // re-index so redacted text disappears from search
    await _load();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _addTag() async {
    final n = await promptText(context, 'Add tag', hint: 'e.g. client name, Umrah, Visa');
    if (n != null) { await _repo.setTags(_doc!.id, [..._doc!.tags, n]); _load(); }
  }

  Future<void> _removeTag(String t) async {
    await _repo.setTags(_doc!.id, _doc!.tags.where((x) => x != t).toList());
    _load();
  }

  Future<void> _shareImages() =>
      Share.shareXFiles([for (final pg in _pages) XFile(pg.imagePath)]);

  Future<void> _addPages() async {
    final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => CameraScreen(addToDocId: _doc!.id)));
    if (ok == true) _load();
  }

  Future<void> _editPage(ScanPage pg) async {
    final sp = await Navigator.push<ScannedPage>(
      context,
      MaterialPageRoute(
        builder: (_) => EditScanScreen(
          imagePath: pg.origPath, initialCorners: pg.corners,
          initialMode: FilterMode.fromNative(pg.filter), ctaLabel: 'Save'),
      ),
    );
    if (sp != null) { await _repo.replacePage(pg.id, sp); unawaited(OcrIndexer.run()); _load(); }
  }

  Future<void> _deletePage(ScanPage pg) async {
    if (!await confirm(context, 'Delete page?', 'This page will be removed.')) return;
    final left = await _repo.deletePage(pg);
    if (left == 0 && mounted) { Navigator.pop(context); return; }
    _load();
  }

  Future<void> _export() => ShareSheet.show(context, _doc!.title, _pages);

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final d = _doc;
    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: d == null ? null : _rename,
          child: Text(d?.title ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 20)),
        ),
        actions: [
          IconButton(
            icon: Icon(d?.fav == true ? Icons.star_rounded : Icons.star_outline_rounded, color: d?.fav == true ? Colors.amber : null),
            tooltip: 'Favorite',
            onPressed: d == null ? null : () async { await _repo.setFavorite(d.id, !d.fav); _load(); },
          ),
          IconButton(icon: const Icon(Icons.add_a_photo_outlined), tooltip: 'Add pages', onPressed: d == null ? null : _addPages),
          IconButton(
              icon: const Icon(Icons.text_fields_rounded), tooltip: 'OCR all pages',
              onPressed: _pages.isEmpty ? null : () => OcrSheet.show(context, [for (final x in _pages) x.imagePath])),
          PopupMenuButton<String>(
            onSelected: (v) => {'rename': _rename, 'move': _move, 'images': _shareImages, 'delete': _deleteDoc}[v]!(),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'rename', child: Text('Rename')),
              PopupMenuItem(value: 'move', child: Text('Move to folder')),
              PopupMenuItem(value: 'images', child: Text('Share as images (JPG)')),
              PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Row(children: [
            Icon(Icons.drag_indicator, size: 18, color: p.textMuted),
            const SizedBox(width: 6),
            Text(d == null ? '' : '${d.meta}  •  hold & drag to reorder', style: TextStyle(color: p.textMuted)),
          ]),
        ),
        if (d != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
            child: SizedBox(
              width: double.infinity,
              child: Wrap(spacing: 8, children: [
                for (final t in d.tags)
                  InputChip(label: Text(t), onDeleted: () => _removeTag(t), visualDensity: VisualDensity.compact),
                ActionChip(avatar: const Icon(Icons.add, size: 16), label: const Text('Tag'), onPressed: _addTag, visualDensity: VisualDensity.compact),
              ]),
            ),
          ),
        Expanded(
          child: ReorderableListView.builder(
            padding: const EdgeInsets.all(16),
            buildDefaultDragHandles: false,
            itemCount: _pages.length,
            onReorder: (o, n) async {
              if (n > o) n--;
              final it = _pages.removeAt(o);
              _pages.insert(n, it);
              setState(() {});
              await _repo.reorder(widget.docId, [for (final x in _pages) x.id]);
            },
            itemBuilder: (_, i) {
              final pg = _pages[i];
              return Container(
                key: ValueKey(pg.id),
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(p.radius), border: Border.all(color: p.outline)),
                child: Row(children: [
                  GestureDetector(
                    onTap: () => _editPage(pg),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(File(pg.thumbPath), width: 70, height: 92, fit: BoxFit.cover),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(child: Text('Page ${i + 1}', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: p.text))),
                  IconButton(icon: Icon(Icons.edit_outlined, color: p.accent), onPressed: () => _editPage(pg)),
                  PopupMenuButton<String>(
                    icon: Icon(Icons.more_vert, color: p.textMuted),
                    onSelected: (v) => v == 'redact' ? _redactPage(pg) : _deletePage(pg),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'redact', child: Text('Redact / blur / highlight')),
                      PopupMenuItem(value: 'delete', child: Text('Delete page')),
                    ],
                  ),
                  ReorderableDragStartListener(index: i, child: Padding(padding: const EdgeInsets.all(8), child: Icon(Icons.drag_handle, color: p.textMuted))),
                ]),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: SafeArea(
            top: false,
            child: _busy
                ? SizedBox(height: 56, child: Center(child: CircularProgressIndicator(color: p.accent)))
                : CtaButton(label: 'Export PDF', icon: Icons.description_rounded, onTap: _pages.isEmpty ? null : _export),
          ),
        ),
      ]),
    );
  }
}
