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

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../models/scan_document.dart';
import '../models/scan_recipe.dart';
import '../services/app_settings.dart';
import '../services/document_repository.dart';
import '../services/pdf_exporter.dart';
import '../theme/app_themes.dart';
import '../widgets/dialogs.dart';
import '../widgets/ocr_sheet.dart';
import '../widgets/theme_picker_sheet.dart';
import 'camera_screen.dart';
import 'document_screen.dart';
import 'settings_screen.dart';

/// A filter chip above the document list (favourites, smart collection or tag).
class _Filter {
  const _Filter(this.label, {this.fav = false, this.kinds, this.tag});
  final String label;
  final bool fav;
  final List<String>? kinds;
  final String? tag;
  @override
  bool operator ==(Object o) => o is _Filter && o.label == label;
  @override
  int get hashCode => label.hashCode;
}

/// Gallery: quick-scan recipes, folders, smart filters, search, multi-select sharing.
class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});
  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  final _repo = DocumentRepository.instance;
  final _key = GlobalKey<ScaffoldState>();
  List<Folder> _folders = [];
  List<ScanDocument> _docs = [];
  List<String> _tags = [];
  Map<String, int> _kindCounts = {};
  int _total = 0;
  int? _folder; // null = all folders
  _Filter? _filter; // null = no filter
  bool _searching = false, _busy = false;
  String _q = '';
  final Set<int> _sel = {};

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final f = await _repo.folders();
    final d = await _repo.documents(
        folderId: _folder, query: _q, favOnly: _filter?.fav ?? false, kinds: _filter?.kinds, tag: _filter?.tag);
    final t = await _repo.totalDocuments();
    final tags = await _repo.allTags(limit: 8);
    final kc = await _repo.kindCounts();
    if (mounted) setState(() { _folders = f; _docs = d; _total = t; _tags = tags; _kindCounts = kc; });
  }

  Future<void> _scan([ScanRecipe? recipe]) async {
    final ok = await Navigator.push<bool>(
        context, MaterialPageRoute(builder: (_) => CameraScreen(folderId: _folder, recipe: recipe)));
    if (ok == true) _reload();
  }

  Future<void> _openDoc(ScanDocument d) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => DocumentScreen(docId: d.id)));
    _reload();
  }

  Future<void> _openSettings() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
    _reload();
  }

  Future<void> _newFolder() async {
    final n = await promptText(context, 'New folder', hint: 'Folder name');
    if (n != null) { await _repo.addFolder(n); _reload(); }
  }

  Future<void> _folderMenu(Folder f) async {
    final act = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: context.pal.surface,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.edit_outlined), title: const Text('Rename'), onTap: () => Navigator.pop(ctx, 'rename')),
          ListTile(leading: const Icon(Icons.delete_outline), title: const Text('Delete folder'), onTap: () => Navigator.pop(ctx, 'delete')),
        ]),
      ),
    );
    if (act == 'rename') {
      final n = await promptText(context, 'Rename folder', initial: f.name);
      if (n != null) await _repo.renameFolder(f.id, n);
    } else if (act == 'delete') {
      if (await confirm(context, 'Delete "${f.name}"?', 'Documents inside are kept (moved out of the folder).')) {
        await _repo.deleteFolder(f.id);
        if (_folder == f.id) _folder = null;
      }
    }
    _reload();
  }

  Future<void> _docMenu(String v, ScanDocument d) async {
    if (v == 'fav') {
      await _repo.setFavorite(d.id, !d.fav);
    } else if (v == 'rename') {
      final n = await promptText(context, 'Rename', initial: d.title);
      if (n != null) await _repo.renameDocument(d.id, n);
    } else if (v == 'move') {
      final id = await pickFolder(context, _folders, d.folderId);
      if (id != null) await _repo.moveDocument(d.id, id == -1 ? null : id);
    } else if (v == 'delete') {
      if (await confirm(context, 'Delete "${d.title}"?', 'This cannot be undone.')) await _repo.deleteDocument(d.id);
    }
    _reload();
  }

  Future<void> _quickPdf(ScanDocument d) async {
    final pages = await _repo.pages(d.id);
    await PdfExporter.exportAndShare(d.title, [for (final p in pages) p.imagePath], AppSettings.instance.pdfSize);
  }

  Future<void> _quickOcr(ScanDocument d) async {
    final pages = await _repo.pages(d.id);
    if (mounted) OcrSheet.show(context, [for (final p in pages) p.imagePath]);
  }

  // ───────── multi-select
  void _toggle(int id) => setState(() { if (!_sel.remove(id)) _sel.add(id); });

  Future<void> _shareSelected() async {
    final mode = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: context.pal.surface,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.picture_as_pdf_outlined), title: const Text('One merged PDF'), onTap: () => Navigator.pop(ctx, 'merged')),
          ListTile(leading: const Icon(Icons.file_copy_outlined), title: Text('Separate PDFs (${_sel.length} files)'), onTap: () => Navigator.pop(ctx, 'separate')),
          ListTile(leading: const Icon(Icons.image_outlined), title: const Text('All pages as images (JPG)'), onTap: () => Navigator.pop(ctx, 'images')),
        ]),
      ),
    );
    if (mode == null) return;
    setState(() => _busy = true);
    try {
      final docs = _docs.where((d) => _sel.contains(d.id)).toList();
      final size = AppSettings.instance.pdfSize;
      if (mode == 'merged') {
        final images = <String>[];
        for (final d in docs) { images.addAll((await _repo.pages(d.id)).map((p) => p.imagePath)); }
        await PdfExporter.exportAndShare('Kelmo_Scan_${docs.length}_documents', images, size);
      } else if (mode == 'separate') {
        final files = <XFile>[];
        for (final d in docs) {
          final pages = await _repo.pages(d.id);
          files.add(XFile(await PdfExporter.save([for (final p in pages) p.imagePath], d.title, size: size)));
        }
        await Share.shareXFiles(files);
      } else {
        final files = <XFile>[];
        for (final d in docs) { files.addAll((await _repo.pages(d.id)).map((p) => XFile(p.imagePath))); }
        await Share.shareXFiles(files);
      }
      if (mounted) setState(() => _sel.clear());
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Share failed: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteSelected() async {
    if (!await confirm(context, 'Delete ${_sel.length} documents?', 'This cannot be undone.')) return;
    for (final id in _sel) { await _repo.deleteDocument(id); }
    setState(() => _sel.clear());
    _reload();
  }

  IconData _iconFor(String n) {
    final s = n.toLowerCase();
    if (s.contains('personal')) return Icons.folder_shared_rounded;
    if (s.contains('work')) return Icons.work_rounded;
    if (s.contains('receipt')) return Icons.receipt_long_rounded;
    return Icons.folder_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final selecting = _sel.isNotEmpty;
    return PopScope(
      canPop: !selecting,
      onPopInvokedWithResult: (didPop, _) { if (!didPop) setState(() => _sel.clear()); },
      child: Scaffold(
        key: _key,
        drawer: Drawer(
          backgroundColor: p.surface,
          child: SafeArea(
            child: ListView(children: [
              ListTile(
                leading: Icon(Icons.palette_outlined, color: p.accent),
                title: const Text('Themes'),
                onTap: () { Navigator.pop(context); ThemePickerSheet.show(context); },
              ),
            ]),
          ),
        ),
        appBar: selecting
            ? AppBar(
                leading: IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _sel.clear())),
                title: Text('${_sel.length} selected'),
                actions: [
                  IconButton(icon: const Icon(Icons.share_outlined), onPressed: _shareSelected),
                  IconButton(icon: const Icon(Icons.delete_outline), onPressed: _deleteSelected),
                ],
              )
            : AppBar(
                leading: _searching
                    ? IconButton(icon: const Icon(Icons.arrow_back), onPressed: () { setState(() { _searching = false; _q = ''; }); _reload(); })
                    : (p.hasMenuIcon ? IconButton(icon: const Icon(Icons.menu), onPressed: () => _key.currentState?.openDrawer()) : null),
                title: _searching
                    ? TextField(
                        autofocus: true,
                        style: TextStyle(color: p.onAppBar, fontSize: 18),
                        cursorColor: p.onAppBar,
                        decoration: InputDecoration(border: InputBorder.none, hintText: 'Search name, tag or text…', hintStyle: TextStyle(color: p.onAppBar.withAlpha(150))),
                        onChanged: (v) { _q = v; _reload(); },
                      )
                    : const Text('My Documents'),
                actions: [
                  if (!_searching) IconButton(icon: const Icon(Icons.search), onPressed: () => setState(() => _searching = true)),
                  if (!_searching) IconButton(icon: const Icon(Icons.settings_outlined), onPressed: _openSettings),
                ],
              ),
        body: Stack(children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 110),
            children: [
              _sectionTitle(p, 'Quick scan'),
              SizedBox(
                height: 44,
                child: ListView(scrollDirection: Axis.horizontal, children: [
                  for (final k in ['passport', 'idCard', 'receipt', 'document'])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ActionChip(
                        avatar: Icon(ScanRecipe.byName(k).icon, size: 18, color: p.accent),
                        label: Text(ScanRecipe.byName(k).label),
                        backgroundColor: p.surface,
                        side: BorderSide(color: p.outline),
                        onPressed: () => _scan(ScanRecipe.byName(k)),
                      ),
                    ),
                ]),
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 112,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _folders.length + 2,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (_, i) {
                    if (i == 0) {
                      return _folderTile(p, 'All Documents', '$_total items', Icons.folder_rounded, _folder == null,
                          () { setState(() => _folder = null); _reload(); }, null);
                    }
                    if (i == _folders.length + 1) {
                      return _folderTile(p, 'New', 'Add folder', Icons.create_new_folder_rounded, false, _newFolder, null);
                    }
                    final f = _folders[i - 1];
                    return _folderTile(p, f.name, '${f.count} items', _iconFor(f.name), _folder == f.id,
                        () { setState(() => _folder = f.id); _reload(); }, () => _folderMenu(f));
                  },
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(height: 40, child: _filterChips(p)),
              const SizedBox(height: 12),
              Text(_q.isNotEmpty ? 'Results' : 'Recent Scans',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: p.text, fontFamily: p.headingFont)),
              const SizedBox(height: 10),
              if (_docs.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 50),
                  child: Column(children: [
                    Icon(Icons.document_scanner_outlined, size: 64, color: p.textMuted),
                    const SizedBox(height: 12),
                    Text(_q.isNotEmpty || _filter != null ? 'No matches' : 'No documents yet.\nTap the camera to scan.',
                        textAlign: TextAlign.center, style: TextStyle(color: p.textMuted, fontSize: 16)),
                  ]),
                ),
              for (final d in _docs) _docTile(p, d),
            ],
          ),
          if (_busy) Container(color: Colors.black38, child: Center(child: CircularProgressIndicator(color: p.accent))),
        ]),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
        floatingActionButton: SizedBox(
          width: 70, height: 70,
          child: FloatingActionButton(
            heroTag: 'scan', elevation: 6, shape: const CircleBorder(),
            backgroundColor: p.accent, foregroundColor: p.onAccent, onPressed: () => _scan(),
            child: const Icon(Icons.photo_camera_rounded, size: 32),
          ),
        ),
        bottomNavigationBar: BottomAppBar(
          color: p.surface, surfaceTintColor: Colors.transparent,
          shape: const CircularNotchedRectangle(), notchMargin: 8, height: 70,
          child: Row(children: [
            Expanded(child: _nav(p, Icons.home_rounded, 'Documents', true, () {})),
            const SizedBox(width: 76),
            Expanded(child: _nav(p, Icons.settings_rounded, 'Settings', false, _openSettings)),
          ]),
        ),
      ),
    );
  }

  Widget _sectionTitle(AppPalette p, String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.textMuted)),
      );

  Widget _filterChips(AppPalette p) {
    final chips = <_Filter?>[null, const _Filter('★ Favorites', fav: true)];
    for (final c in ScanCollection.all) {
      final n = c.kinds.fold<int>(0, (s, k) => s + (_kindCounts[k] ?? 0));
      if (n > 0) chips.add(_Filter(c.label, kinds: c.kinds));
    }
    for (final t in _tags) { chips.add(_Filter('#$t', tag: t)); }
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: chips.length,
      separatorBuilder: (_, __) => const SizedBox(width: 8),
      itemBuilder: (_, i) {
        final f = chips[i];
        final on = _filter == f;
        return ChoiceChip(
          label: Text(f?.label ?? 'All'),
          selected: on,
          showCheckmark: false,
          selectedColor: p.accent.withAlpha(45),
          backgroundColor: p.surface,
          side: BorderSide(color: on ? p.accent : p.outline),
          labelStyle: TextStyle(color: on ? p.accent : p.text, fontWeight: FontWeight.w600),
          onSelected: (_) { setState(() => _filter = f); _reload(); },
        );
      },
    );
  }

  Widget _nav(AppPalette p, IconData i, String l, bool sel, VoidCallback t) => InkWell(
        onTap: t,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(i, color: sel ? p.accent : p.textMuted),
          Text(l, style: TextStyle(fontSize: 12, color: sel ? p.accent : p.textMuted, fontWeight: sel ? FontWeight.w600 : FontWeight.w400)),
          const SizedBox(height: 2),
          Container(height: 3, width: 36, decoration: BoxDecoration(color: sel ? p.accent : Colors.transparent, borderRadius: BorderRadius.circular(2))),
        ]),
      );

  Widget _folderTile(AppPalette p, String name, String sub, IconData icon, bool sel, VoidCallback tap, VoidCallback? longPress) =>
      GestureDetector(
        onTap: tap,
        onLongPress: longPress,
        child: Container(
          width: 128,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: sel ? p.accent.withAlpha(30) : p.folderCard,
            borderRadius: BorderRadius.circular(p.radius),
            border: Border.all(color: sel ? p.accent.withAlpha(110) : p.outline),
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 38, color: p.folderIcon),
            const SizedBox(height: 6),
            Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w600, color: p.onFolderCard)),
            Text(sub, style: TextStyle(fontSize: 12, color: p.onFolderCard.withAlpha(170))),
          ]),
        ),
      );

  Widget _docTile(AppPalette p, ScanDocument d) {
    final sel = _sel.contains(d.id);
    return GestureDetector(
      onTap: () => _sel.isNotEmpty ? _toggle(d.id) : _openDoc(d),
      onLongPress: () => _toggle(d.id),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: sel ? p.accent.withAlpha(25) : p.surface,
          borderRadius: BorderRadius.circular(p.radius),
          border: Border.all(color: sel ? p.accent : p.outline, width: sel ? 2 : 1),
        ),
        child: Row(children: [
          Stack(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 64, height: 76,
                child: d.thumbPath != null
                    ? Image.file(File(d.thumbPath!), fit: BoxFit.cover, cacheWidth: 200)
                    : Container(color: p.surfaceAlt, child: Icon(Icons.description_outlined, color: p.textMuted, size: 30)),
              ),
            ),
            if (sel) Positioned(right: 2, top: 2, child: Icon(Icons.check_circle, color: p.accent, size: 22)),
          ]),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(
                  child: Text(d.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: p.text, fontFamily: p.headingFont)),
                ),
                if (d.fav) const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.star_rounded, color: Colors.amber, size: 18)),
              ]),
              const SizedBox(height: 2),
              Text('${d.dateLabel} • ${d.meta}', style: TextStyle(color: p.textMuted, fontSize: 13)),
              if (d.tags.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(d.tags.map((t) => '#$t').join('  '), maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: p.accent, fontSize: 12, fontWeight: FontWeight.w600)),
                ),
              const SizedBox(height: 6),
              Row(children: [
                _chip(p, Icons.picture_as_pdf_outlined, 'PDF', () => _quickPdf(d)),
                const SizedBox(width: 8),
                _chip(p, Icons.text_fields_rounded, 'OCR', () => _quickOcr(d)),
              ]),
            ]),
          ),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, color: p.textMuted),
            onSelected: (v) => _docMenu(v, d),
            itemBuilder: (_) => [
              PopupMenuItem(value: 'fav', child: Text(d.fav ? 'Remove from favorites' : 'Add to favorites')),
              const PopupMenuItem(value: 'rename', child: Text('Rename')),
              const PopupMenuItem(value: 'move', child: Text('Move to folder')),
              const PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ]),
      ),
    );
  }

  Widget _chip(AppPalette p, IconData i, String l, VoidCallback t) => InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: t,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: p.accent.withAlpha(30), borderRadius: BorderRadius.circular(16)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(i, size: 16, color: p.accent),
            const SizedBox(width: 4),
            Text(l, style: TextStyle(color: p.accent, fontSize: 13, fontWeight: FontWeight.w600)),
          ]),
        ),
      );
}
