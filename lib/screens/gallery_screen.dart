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
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import '../models/scan_document.dart';
import '../models/scan_recipe.dart';
import '../services/app_settings.dart';
import '../services/backup_service.dart';
import '../services/import_service.dart';
import '../services/update_service.dart';
import '../services/document_repository.dart';
import '../services/image_processing_service.dart';
import '../services/pdf_exporter.dart';
import '../theme/app_themes.dart';
import '../widgets/cs_bars.dart';
import '../widgets/dialogs.dart';
import '../widgets/ocr_sheet.dart';
import '../widgets/theme_picker_sheet.dart';
import 'camera_screen.dart';
import 'document_screen.dart';
import 'markup_screen.dart';
import 'pdf_view_screen.dart';
import 'settings_screen.dart';
import 'share_screen.dart';
import 'trash_screen.dart';

const _appVersion = '1.6.1';
const _apkLink = 'https://github.com/keplerdeskadmin-cpu/kelmo-scan/releases/latest/download/KelmoScan-arm64.apk';

/// "Oct-21, 15:47" — the date style used in the document list.
String listDate(DateTime d) {
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  String t(int v) => v.toString().padLeft(2, '0');
  final y = d.year == DateTime.now().year ? '' : ' ${d.year}';
  return '${m[d.month - 1]}-${t(d.day)}$y, ${t(d.hour)}:${t(d.minute)}';
}

String sizeLabel(int bytes) {
  if (bytes >= 1 << 20) return '${(bytes / (1 << 20)).toStringAsFixed(1)} MB';
  if (bytes >= 1024) return '${(bytes / 1024).round()} KB';
  return '$bytes Byte';
}

/// Home screen: "My Docs" list in the Clear Scanner style.
class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});
  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  final _repo = DocumentRepository.instance;
  final _settings = AppSettings.instance;
  final _key = GlobalKey<ScaffoldState>();
  List<Folder> _folders = [];
  List<ScanDocument> _docs = [];
  int _total = 0, _trash = 0;
  Folder? _folder; // null = root
  bool _searching = false, _busy = false, _selectMode = false;
  String _q = '';
  final Set<int> _sel = {};
  int _tab = 0; // dashboard style: 0 = Home, 1 = Docs
  ({int pages, int bytes, int month}) _st = (pages: 0, bytes: 0, month: 0);
  List<ScanDocument> _recent = [];

  bool get _dash => _settings.homeStyle == 'dashboard';

  @override
  void initState() {
    super.initState();
    _reload();
    WidgetsBinding.instance.addPostFrameCallback((_) => Future.delayed(const Duration(seconds: 3), () {
          if (mounted) UpdateService.autoCheck(context);
        }));
  }

  Future<void> _reload() async {
    final f = await _repo.folders();
    final d = await _repo.documents(folderId: _folder?.id, query: _q);
    final t = await _repo.totalDocuments();
    final tr = await _repo.trashCount();
    final st = await _repo.stats();
    final rec = (_folder == null && _q.isEmpty) ? d.toList() : await _repo.documents();
    rec.sort((a, b) => b.updated.compareTo(a.updated));
    _sort(d);
    if (mounted) setState(() { _folders = f; _docs = d; _total = t; _trash = tr; _st = st; _recent = rec.take(5).toList(); });
  }

  void _sort(List<ScanDocument> d) => sortDocs(d, _settings.homeSort, _settings.homeSortAsc);

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  // ───────── navigation
  Future<void> _camera({bool gallery = false}) async {
    final ok = await Navigator.push<bool>(context,
        MaterialPageRoute(builder: (_) => CameraScreen(folderId: _folder?.id, startWithGallery: gallery)));
    if (ok == true) _reload();
  }

  Future<void> _openDoc(ScanDocument d) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => DocumentScreen(docId: d.id)));
    _reload();
  }

  Future<void> _push(Widget w) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => w));
    _reload();
  }

  // ───────── overflow menu
  Future<void> _menu(String v) async {
    switch (v) {
      case 'select': setState(() { _selectMode = true; _sel.clear(); });
      case 'grid': _settings.homeGrid = !_settings.homeGrid; setState(() {});
      case 'sort': await _pickSort();
      case 'pdf': await _importPdf();
      case 'images': await _camera(gallery: true);
      case 'folder':
        final n = await promptText(context, 'New Folder', hint: 'Folder name');
        if (n != null) { await _repo.addFolder(n); _reload(); }
      case 'blank': await _newBlank();
    }
  }

  Future<void> _work(Future<void> Function() job) async {
    setState(() => _busy = true);
    try {
      await job();
    } catch (e) {
      if (mounted) _snack('Failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
      _reload();
    }
  }

  Future<void> _importPdf() async {
    final imgs = await ImportService.pickPdfPages();
    if (imgs == null) return;
    await _work(() async {
      if (imgs.isEmpty) throw Exception('This PDF has no pages (or it is password protected)');
      final pages = await ImportService.pagesFromImages(imgs);
      await _repo.createDocument(title: _settings.newDocumentName(), folderId: _folder?.id, pages: pages);
      _snack('${pages.length} page(s) imported');
    });
  }

  Future<void> _newBlank() => _work(() async {
        final pg = await ImportService.pageFromImage(await ImportService.blankPage());
        final id = await _repo.createDocument(title: _settings.newDocumentName(), folderId: _folder?.id, pages: [pg]);
        if (mounted) await Navigator.push(context, MaterialPageRoute(builder: (_) => DocumentScreen(docId: id)));
      });

  Future<void> _pickSort() async {
    final r = await pickSort(context, _settings.homeSort, _settings.homeSortAsc);
    if (r != null) { _settings.homeSort = r.$1; _settings.homeSortAsc = r.$2; _reload(); }
  }

  // ───────── per-item actions
  Future<void> _docMenu(String v, ScanDocument d) async {
    switch (v) {
      case 'preview':
        final pages = await _repo.pages(d.id);
        if (mounted) await Navigator.push(context, MaterialPageRoute(builder: (_) => PdfViewScreen(title: d.title, pages: pages)));
      case 'email' || 'print' || 'gallery' || 'storage':
        final pages = await _repo.pages(d.id);
        if (mounted) await runMoreAction(context, v, pages, d.title);
      case 'share':
        final pages = await _repo.pages(d.id);
        if (mounted) await ShareScreen.open(context, d.title, pages);
      case 'ocr':
        final pages = await _repo.pages(d.id);
        if (mounted) OcrSheet.show(context, [for (final p in pages) p.imagePath]);
      case 'rename':
        final n = await promptText(context, 'Rename', initial: d.title);
        if (n != null) await _repo.renameDocument(d.id, n);
      case 'move':
        final id = await pickFolder(context, _folders, d.folderId);
        if (id != null) await _repo.moveDocument(d.id, id == -1 ? null : id);
      case 'fav':
        await _repo.setFavorite(d.id, !d.fav);
      case 'delete':
        await _repo.trashDocument(d.id);
        if (mounted) _snack('"${d.title}" moved to Trash');
    }
    _reload();
  }

  Future<void> _folderMenu(String v, Folder f) async {
    if (v == 'rename') {
      final n = await promptText(context, 'Rename folder', initial: f.name);
      if (n != null) await _repo.renameFolder(f.id, n);
    } else if (v == 'delete') {
      if (await confirm(context, 'Delete "${f.name}"?', 'Documents inside are kept (moved out of the folder).')) {
        await _repo.deleteFolder(f.id);
      }
    }
    _reload();
  }

  // ───────── selection
  void _toggle(int id) => setState(() {
        if (!_sel.remove(id)) _sel.add(id);
        if (_sel.isEmpty) _selectMode = false;
      });

  void _endSelect() => setState(() { _sel.clear(); _selectMode = false; });

  Future<void> _shareSelected() async {
    if (_sel.isEmpty) return;
    final mode = await showModalBottomSheet<String>(
      context: context,
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
      final size = _settings.pdfSize;
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
      _endSelect();
    } catch (e) {
      if (mounted) _snack('Share failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _trashSelected() async {
    if (_sel.isEmpty) return;
    final n = _sel.length;
    for (final id in _sel) { await _repo.trashDocument(id); }
    _endSelect();
    _reload();
    if (mounted) _snack('$n document(s) moved to Trash');
  }

  List<int> get _selInOrder => [for (final d in _docs) if (_sel.contains(d.id)) d.id];

  Future<void> _mergeSelected() async {
    if (_sel.length < 2) { _snack('Select 2 or more documents to merge'); return; }
    final first = _docs.firstWhere((d) => d.id == _selInOrder.first);
    final n = await promptText(context, 'Merge ${_sel.length} documents', initial: first.title, hint: 'New document name');
    if (n == null) return;
    final ids = _selInOrder;
    _endSelect();
    await _work(() async { await _repo.mergeDocuments(ids, n); _snack('Documents merged'); });
  }

  Future<void> _copySelected() async {
    final ids = _selInOrder;
    _endSelect();
    await _work(() async {
      for (final id in ids) { await _repo.copyDocument(id); }
      _snack('${ids.length} document(s) copied');
    });
  }

  Future<void> _moveSelected() async {
    if (_sel.isEmpty) return;
    final id = await pickFolder(context, _folders, null);
    if (id == null) return;
    for (final d in _sel) { await _repo.moveDocument(d, id == -1 ? null : id); }
    _endSelect();
    _reload();
  }

  // ───────── cloud / backup
  Future<void> _syncToCloud() async {
    setState(() => _busy = true);
    try {
      final path = await BackupService.create();
      await Share.shareXFiles([XFile(path)],
          text: 'Kelmo Scan backup — save it to Google Drive or Dropbox. Restore it from Backup file / Restore.');
    } catch (e) {
      if (mounted) _snack('Backup failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _tutorial() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('How to use Kelmo Scan'),
        content: const SingleChildScrollView(
          child: Text(
            '1. Tap the camera button to scan. Hold the phone steady — the edges are found automatically.\n\n'
            '2. Drag the corners to adjust the border, then pick a filter.\n\n'
            '3. Tap the gallery button to import photos you already have.\n\n'
            '4. Open a document to add pages, run OCR (English / Urdu) or share it as PDF.\n\n'
            '5. Long-press a document to select several and share or delete them together.\n\n'
            '6. Deleted documents go to Trash — restore them from the menu.',
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
      ),
    );
  }

  void _about() => showAboutDialog(
        context: context,
        applicationName: 'Kelmo Scan',
        applicationVersion: 'Version $_appVersion (build ${UpdateService.build})',
        applicationLegalese: 'Free & open-source (GPLv3)\nNo ads • No tracking • 100% offline',
      );

  // ───────── dashboard quick actions
  Future<void> _quickStamp() async {
    final docs = await _repo.documents();
    if (!mounted) return;
    if (docs.isEmpty) { _snack('Scan a document first'); return; }
    final id = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Stamp which document?'),
        children: [
          for (final d in docs.take(30))
            SimpleDialogOption(onPressed: () => Navigator.pop(ctx, d.id), child: Text(d.title, style: const TextStyle(fontSize: 16))),
        ],
      ),
    );
    if (id == null || !mounted) return;
    final pg = (await _repo.pages(id)).first;
    if (!mounted) return;
    final out = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => MarkupScreen(imagePath: pg.imagePath, openStamp: true)));
    if (out == null) return;
    await _work(() async {
      final thumb = await ImageProcessingService.instance.applyFilter(out, FilterMode.original, maxSide: 360);
      await _repo.replacePage(pg.id, ScannedPage(origPath: out, finalPath: out, thumbPath: thumb, filter: 'original',
          corners: const [Offset(0, 0), Offset(1, 0), Offset(1, 1), Offset(0, 1)]));
      imageCache.clear();
      _snack('Stamp added');
    });
  }

  Future<void> _quickOcr() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (x != null && mounted) OcrSheet.show(context, [x.path]);
  }

  Future<void> _scanAs(ScanKind k) async {
    final ok = await Navigator.push<bool>(context,
        MaterialPageRoute(builder: (_) => CameraScreen(folderId: _folder?.id, recipe: ScanRecipe.byName(k.name))));
    if (ok == true) _reload();
  }

  // ───────── UI
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final selecting = _selectMode || _sel.isNotEmpty;
    final inFolder = _folder != null;
    final onHome = _dash && _tab == 0 && !_searching && !inFolder && !selecting;
    return PopScope(
      canPop: !selecting && !_searching && !inFolder && !(_dash && _tab == 1),
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (selecting) { _endSelect(); return; }
        if (_searching) { setState(() { _searching = false; _q = ''; }); _reload(); return; }
        if (inFolder) { setState(() => _folder = null); _reload(); return; }
        if (_dash && _tab == 1) setState(() => _tab = 0);
      },
      child: Scaffold(
        key: _key,
        drawer: _drawer(p),
        backgroundColor: onHome ? const Color(0xFFF2F5F5) : p.background,
        appBar: selecting ? _selectBar(p) : _mainBar(p),
        body: Stack(children: [
          RefreshIndicator(
              onRefresh: _reload, color: p.accent,
              child: onHome ? _dashboard(p) : _settings.homeGrid ? _grid(p) : _list(p)),
          if (_busy) Container(color: Colors.black38, child: Center(child: CircularProgressIndicator(color: p.accent))),
        ]),
        bottomNavigationBar: selecting ? null : _dash ? _navBar(p) : _bottomBar(p),
      ),
    );
  }

  PreferredSizeWidget _mainBar(AppPalette p) => AppBar(
        backgroundColor: p.appBar,
        leading: _searching
            ? IconButton(icon: const Icon(Icons.arrow_back), onPressed: () { setState(() { _searching = false; _q = ''; }); _reload(); })
            : _folder != null
                ? IconButton(icon: const Icon(Icons.arrow_back), onPressed: () { setState(() => _folder = null); _reload(); })
                : IconButton(icon: const Icon(Icons.menu), onPressed: () => _key.currentState?.openDrawer()),
        titleSpacing: 4,
        title: _searching
            ? TextField(
                autofocus: true,
                style: TextStyle(color: p.onAppBar, fontSize: 18),
                cursorColor: p.onAppBar,
                decoration: InputDecoration(
                    border: InputBorder.none, hintText: 'Search name or text…', hintStyle: TextStyle(color: p.onAppBar.withAlpha(150))),
                onChanged: (v) { _q = v; _reload(); },
              )
            : Text(_folder != null
                ? '${_folder!.name} (${_docs.length})'
                : (_dash && _tab == 0) ? 'Kelmo Scan' : 'My Docs ($_total)'),
        actions: [
          if (!_searching)
            IconButton(icon: const Icon(Icons.search), tooltip: 'Search', onPressed: () => setState(() { _searching = true; _tab = 1; })),
          if (!_searching) IconButton(icon: const Icon(Icons.cloud_outlined), tooltip: 'Sync to Cloud', onPressed: _syncToCloud),
          if (!_searching)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              color: Colors.white,
              onSelected: _menu,
              itemBuilder: (_) => [
                _mi('select', Icons.check_box, 'Select'),
                _mi('grid', _settings.homeGrid ? Icons.view_list : Icons.grid_view_rounded, _settings.homeGrid ? 'View as list' : 'View as grid'),
                _mi('sort', Icons.sort, 'Sort'),
                const PopupMenuDivider(),
                _mi('pdf', Icons.picture_as_pdf, 'Import PDF'),
                _mi('images', Icons.add_photo_alternate, 'Import images'),
                const PopupMenuDivider(),
                _mi('folder', Icons.create_new_folder, 'New Folder'),
                _mi('blank', Icons.note_add, 'New Blank page'),
              ],
            ),
        ],
      );

  PopupMenuItem<String> _mi(String v, IconData i, String t) => PopupMenuItem(
        value: v,
        child: Row(children: [Icon(i, color: const Color(0xFF202124), size: 22), const SizedBox(width: 16), Text(t)]),
      );

  PreferredSizeWidget _selectBar(AppPalette p) => AppBar(
        backgroundColor: p.appBar,
        leading: IconButton(icon: const Icon(Icons.close), onPressed: _endSelect),
        title: Text('${_sel.length} selected'),
        actions: [
          IconButton(
            icon: const Icon(Icons.select_all),
            tooltip: 'Select all',
            onPressed: () => setState(() {
              if (_sel.length == _docs.length) { _sel.clear(); } else { _sel.addAll(_docs.map((d) => d.id)); }
            }),
          ),
          IconButton(icon: const Icon(Icons.drive_file_move_outline), tooltip: 'Move', onPressed: _moveSelected),
          IconButton(icon: const Icon(Icons.share), tooltip: 'Share', onPressed: _shareSelected),
          IconButton(icon: const Icon(Icons.delete_outline), tooltip: 'Delete', onPressed: _trashSelected),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            color: Colors.white,
            onSelected: (v) => v == 'merge' ? _mergeSelected() : _copySelected(),
            itemBuilder: (_) => [
              _mi('merge', Icons.merge_type, 'Merge'),
              _mi('copy', Icons.file_copy, 'Copy'),
            ],
          ),
        ],
      );

  Widget _bottomBar(AppPalette p) => Container(
        color: p.appBar,
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 60,
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              IconButton(
                iconSize: 36, color: Colors.white, tooltip: 'Import images',
                icon: const Icon(Icons.image), onPressed: () => _camera(gallery: true),
              ),
              const SizedBox(width: 18),
              IconButton(
                iconSize: 36, color: Colors.white, tooltip: 'Scan',
                icon: const Icon(Icons.photo_camera), onPressed: _camera,
              ),
            ]),
          ),
        ),
      );

  Widget _drawer(AppPalette p) {
    Widget item(IconData i, String t, VoidCallback onTap) => ListTile(
          leading: Icon(i, color: const Color(0xFF202124)),
          title: Text(t, style: const TextStyle(fontSize: 16)),
          onTap: () { Navigator.pop(context); onTap(); },
        );
    return Drawer(
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(),
      child: Column(children: [
        Container(
          width: double.infinity,
          color: p.appBar,
          padding: EdgeInsets.fromLTRB(16, MediaQuery.of(context).padding.top + 18, 16, 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Kelmo Scan',
                style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w700, fontStyle: FontStyle.italic, letterSpacing: .5)),
            const SizedBox(height: 4),
            Row(children: [
              const Text('Version $_appVersion', style: TextStyle(color: Colors.white, fontSize: 14)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(border: Border.all(color: Colors.white), borderRadius: BorderRadius.circular(3)),
                child: const Text('FREE', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
              ),
            ]),
          ]),
        ),
        Expanded(
          child: ListView(padding: EdgeInsets.zero, children: [
            item(Icons.settings, 'Settings', () => _push(const SettingsScreen())),
            const Divider(height: 1),
            item(Icons.cloud_outlined, 'Sync to Cloud', _syncToCloud),
            item(Icons.restore, 'Backup file / Restore', () => _push(const SettingsScreen())),
            item(Icons.delete, 'Trash ($_trash)', () => _push(const TrashScreen())),
            const Divider(height: 1),
            item(Icons.palette_outlined, 'Themes', () => ThemePickerSheet.show(context)),
            item(Icons.help_outline, 'Tutorial', _tutorial),
            item(Icons.thumb_up_outlined, 'I love this app!',
                () => Share.share('I use Kelmo Scan — a free document scanner with Urdu OCR. Download: $_apkLink')),
            item(Icons.feedback_outlined, 'Feature Request / Bug ...',
                () => Share.share('Kelmo Scan $_appVersion — feature request / bug:\n\n')),
            item(Icons.system_update, 'Check for updates', () => UpdateService.manualCheck(context)),
            item(Icons.info_outline, 'About Kelmo Scan', _about),
          ]),
        ),
      ]),
    );
  }

  // ───────── dashboard (accounts-app style)
  Widget _card({required Widget child, EdgeInsets pad = const EdgeInsets.all(14), VoidCallback? onTap}) => Material(
        color: Colors.white,
        elevation: 0,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: pad,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE3E9E9)),
              boxShadow: const [BoxShadow(color: Color(0x0F000000), blurRadius: 10, offset: Offset(0, 3))],
            ),
            child: child,
          ),
        ),
      );

  Widget _stat(AppPalette p, IconData i, String value, String label, Color c, VoidCallback? onTap) => _card(
        onTap: onTap,
        child: Row(children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(color: c.withAlpha(30), borderRadius: BorderRadius.circular(12)),
            child: Icon(i, color: c),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
              FittedBox(
                fit: BoxFit.scaleDown, alignment: Alignment.centerLeft,
                child: Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xFF17262A))),
              ),
              Text(label, style: const TextStyle(fontSize: 13, color: Color(0xFF6F7777))),
            ]),
          ),
        ]),
      );

  Widget _action(AppPalette p, IconData i, String label, VoidCallback onTap) => InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 54, height: 54,
              decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE3E9E9)),
                boxShadow: const [BoxShadow(color: Color(0x0D000000), blurRadius: 6, offset: Offset(0, 2))],
              ),
              child: Icon(i, color: p.accent, size: 26),
            ),
            const SizedBox(height: 6),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: Color(0xFF2B3A3D), fontWeight: FontWeight.w500)),
          ]),
        ),
      );

  Widget _title(String t, {String? link, VoidCallback? onLink}) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 8, 8),
        child: Row(children: [
          Text(t, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Color(0xFF17262A))),
          const Spacer(),
          if (link != null) TextButton(onPressed: onLink, child: Text(link)),
        ]),
      );

  String _greeting() {
    final h = DateTime.now().hour;
    return h < 12 ? 'Good morning' : h < 17 ? 'Good afternoon' : 'Good evening';
  }

  Widget _dashboard(AppPalette p) {
    const m = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    const wd = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    final now = DateTime.now();
    final light = Color.lerp(p.appBar, Colors.white, .18)!;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 22),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [p.appBar, light], begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(26)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Assalam o Alaikum 👋', style: TextStyle(color: Colors.white.withAlpha(230), fontSize: 15)),
            const SizedBox(height: 2),
            Text(_greeting(), style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('${wd[now.weekday - 1]}, ${now.day} ${m[now.month - 1]} ${now.year}',
                style: TextStyle(color: Colors.white.withAlpha(200), fontSize: 13)),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Total documents', style: TextStyle(color: Colors.white.withAlpha(200), fontSize: 13)),
                  Text('$_total', style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w900, height: 1.1)),
                ]),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: p.appBar,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                onPressed: _camera,
                icon: const Icon(Icons.photo_camera),
                label: const Text('Scan', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ]),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 0),
          child: GridView.count(
            crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 2.15,
            children: [
              _stat(p, Icons.description, '$_total', 'Documents', const Color(0xFF1565C0), () => setState(() => _tab = 1)),
              _stat(p, Icons.layers, '${_st.pages}', 'Pages', const Color(0xFF6A1B9A), null),
              _stat(p, Icons.calendar_month, '${_st.month}', 'This month', const Color(0xFF2E7D32), null),
              _stat(p, Icons.sd_storage, sizeLabel(_st.bytes), 'Storage', const Color(0xFFEF6C00), null),
            ],
          ),
        ),
        _title('Quick actions'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: GridView.count(
            crossAxisCount: 4, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), childAspectRatio: .9,
            children: [
              _action(p, Icons.document_scanner, 'Scan', _camera),
              _action(p, Icons.picture_as_pdf, 'Import PDF', _importPdf),
              _action(p, Icons.badge, 'ID Card', () => _scanAs(ScanKind.idCard)),
              _action(p, Icons.menu_book, 'Passport', () => _scanAs(ScanKind.passport)),
              _action(p, Icons.approval, 'Stamp', _quickStamp),
              _action(p, Icons.text_fields, 'OCR', _quickOcr),
              _action(p, Icons.add_photo_alternate, 'Images', () => _camera(gallery: true)),
              _action(p, Icons.create_new_folder, 'New Folder', () => _menu('folder')),
            ],
          ),
        ),
        _title('Recent documents', link: _recent.isEmpty ? null : 'See all', onLink: () => setState(() => _tab = 1)),
        if (_recent.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: _card(
              onTap: _camera,
              child: Row(children: [
                Icon(Icons.info_outline, color: p.accent),
                const SizedBox(width: 12),
                const Expanded(child: Text('No documents yet. Tap Scan to start.', style: TextStyle(color: Color(0xFF6F7777)))),
              ]),
            ),
          ),
        for (final d in _recent)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: _card(
              pad: const EdgeInsets.all(10),
              onTap: () => _openDoc(d),
              child: Row(children: [
                ClipRRect(borderRadius: BorderRadius.circular(8), child: _thumb(d.thumbPath, w: 48, h: 60)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(d.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF17262A))),
                    const SizedBox(height: 3),
                    Text('${d.pageCount} ${d.pageCount == 1 ? 'page' : 'pages'} • ${sizeLabel(d.bytes)}',
                        style: const TextStyle(fontSize: 13, color: Color(0xFF6F7777))),
                  ]),
                ),
                Text(listDate(d.updated).split(', ').last, style: const TextStyle(fontSize: 12, color: Color(0xFF6F7777))),
                const Icon(Icons.chevron_right, color: Color(0xFFA1AAA5)),
              ]),
            ),
          ),
      ],
    );
  }

  Widget _navBar(AppPalette p) {
    Widget item(IconData i, String t, bool sel, VoidCallback onTap) => Expanded(
          child: InkWell(
            onTap: onTap,
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(i, color: sel ? p.accent : const Color(0xFF8A9494)),
              const SizedBox(height: 2),
              Text(t, style: TextStyle(fontSize: 11, color: sel ? p.accent : const Color(0xFF8A9494),
                  fontWeight: sel ? FontWeight.w700 : FontWeight.w500)),
            ]),
          ),
        );
    return Container(
      decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Color(0xFFE3E9E9)))),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(children: [
            item(Icons.dashboard, 'Home', _tab == 0, () {
              setState(() { _tab = 0; _searching = false; _q = ''; _folder = null; });
              _reload();
            }),
            item(Icons.folder_copy, 'Docs', _tab == 1, () => setState(() => _tab = 1)),
            Expanded(
              child: Center(
                child: GestureDetector(
                  onTap: _camera,
                  child: Container(
                    width: 56, height: 56,
                    decoration: BoxDecoration(
                      color: p.accent, shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: p.accent.withAlpha(90), blurRadius: 10, offset: const Offset(0, 4))],
                    ),
                    child: const Icon(Icons.photo_camera, color: Colors.white, size: 28),
                  ),
                ),
              ),
            ),
            item(Icons.delete_outline, 'Trash', false, () => _push(const TrashScreen())),
            item(Icons.settings_outlined, 'Settings', false, () => _push(const SettingsScreen())),
          ]),
        ),
      ),
    );
  }

  // ───────── list view
  Widget _list(AppPalette p) {
    final showFolders = _folder == null && !_searching && _q.isEmpty;
    final items = <Widget>[
      if (showFolders) for (final f in _folders) _folderRow(p, f),
      for (final d in _docs) _docRow(p, d),
    ];
    if (items.isEmpty) return _empty(p);
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 12),
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(height: 1, thickness: 1, color: Color(0xFFE6E9E9)),
      itemBuilder: (_, i) => items[i],
    );
  }

  Widget _empty(AppPalette p) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 120),
          Icon(Icons.description_outlined, size: 72, color: p.textMuted.withAlpha(120)),
          const SizedBox(height: 14),
          Text(_q.isNotEmpty ? 'No results found' : 'No documents yet.\nTap the camera to scan.',
              textAlign: TextAlign.center, style: TextStyle(color: p.textMuted, fontSize: 16)),
        ],
      );

  Widget _thumb(String? path, {double w = 92, double h = 62}) => Container(
        width: w,
        height: h,
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: const Color(0xFFA1AAA5), width: 1)),
        child: path != null
            ? Image.file(File(path), fit: BoxFit.contain, cacheWidth: 300,
                errorBuilder: (_, __, ___) => const Icon(Icons.warning_amber_rounded, size: 32))
            : const Icon(Icons.warning_amber_rounded, size: 32),
      );

  Widget _pageBadge(int n) => Container(
        margin: const EdgeInsets.only(left: 6),
        padding: const EdgeInsets.symmetric(horizontal: 3),
        constraints: const BoxConstraints(minWidth: 14),
        decoration: BoxDecoration(border: Border.all(color: const Color(0xFF5F6666), width: 1.2), borderRadius: BorderRadius.circular(2)),
        child: Text('$n', textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, height: 1.25, color: Color(0xFF5F6666))),
      );

  Widget _docRow(AppPalette p, ScanDocument d) {
    final sel = _sel.contains(d.id);
    final selecting = _selectMode || _sel.isNotEmpty;
    return Material(
      color: sel ? const Color(0xFFE4EFEE) : Colors.white,
      child: InkWell(
        onTap: () => selecting ? _toggle(d.id) : _openDoc(d),
        onLongPress: () => _toggle(d.id),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 10, 0, 10),
          child: Row(children: [
            Stack(children: [
              _thumb(d.thumbPath),
              if (selecting)
                Positioned(
                  left: 2, top: 2,
                  child: Icon(sel ? Icons.check_box : Icons.check_box_outline_blank, color: p.accent, size: 22),
                ),
            ]),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(
                    child: Text(d.title,
                        maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 17, color: Color(0xFF202124), height: 1.2)),
                  ),
                  if (d.fav) const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.star_rounded, color: Colors.amber, size: 18)),
                ]),
                const SizedBox(height: 3),
                Row(children: [
                  Text(sizeLabel(d.bytes), style: const TextStyle(fontSize: 14, color: Color(0xFF6F7777))),
                  _pageBadge(d.pageCount),
                ]),
                const SizedBox(height: 1),
                Text(listDate(d.updated), style: const TextStyle(fontSize: 14, color: Color(0xFF6F7777))),
              ]),
            ),
            if (!selecting)
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: Color(0xFF5F6666)),
                color: Colors.white,
                onSelected: (v) => _docMenu(v, d),
                itemBuilder: (_) => [
                  _mi('preview', Icons.picture_as_pdf, 'PDF Preview'),
                  _mi('share', Icons.share, 'Share'),
                  _mi('email', Icons.email, 'Send Email'),
                  _mi('print', Icons.print, 'Print'),
                  const PopupMenuDivider(),
                  _mi('gallery', Icons.photo_library, 'Save to Gallery'),
                  _mi('storage', Icons.save, 'Save to storage'),
                  const PopupMenuDivider(),
                  _mi('rename', Icons.edit, 'Rename'),
                  _mi('move', Icons.drive_file_move, 'Move'),
                  _mi('ocr', Icons.text_fields, 'Extract text (OCR)'),
                  _mi('delete', Icons.delete, 'Delete'),
                ],
              )
            else
              const SizedBox(width: 12),
          ]),
        ),
      ),
    );
  }

  Widget _folderRow(AppPalette p, Folder f) => Material(
        color: Colors.white,
        child: InkWell(
          onTap: () { setState(() => _folder = f); _reload(); },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 0, 8),
            child: Row(children: [
              SizedBox(width: 92, height: 62, child: Icon(Icons.folder, size: 60, color: p.folderIcon)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 17, color: Color(0xFF202124))),
                  const SizedBox(height: 3),
                  Text('${f.count} ${f.count == 1 ? 'doc' : 'docs'}', style: const TextStyle(fontSize: 14, color: Color(0xFF6F7777))),
                ]),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: Color(0xFF5F6666)),
                color: Colors.white,
                onSelected: (v) => _folderMenu(v, f),
                itemBuilder: (_) => [
                  _mi('rename', Icons.edit, 'Rename'),
                  _mi('delete', Icons.delete_outline, 'Delete folder'),
                ],
              ),
            ]),
          ),
        ),
      );

  // ───────── grid view
  Widget _grid(AppPalette p) {
    final showFolders = _folder == null && !_searching && _q.isEmpty;
    final folders = showFolders ? _folders : <Folder>[];
    if (folders.isEmpty && _docs.isEmpty) return _empty(p);
    return GridView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(10),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: .78),
      itemCount: folders.length + _docs.length,
      itemBuilder: (_, i) {
        if (i < folders.length) {
          final f = folders[i];
          return InkWell(
            onTap: () { setState(() => _folder = f); _reload(); },
            onLongPress: () => _folderMenu('rename', f),
            child: Column(children: [
              Expanded(child: Container(color: const Color(0xFFF1F4F4), child: Center(child: Icon(Icons.folder, size: 90, color: p.folderIcon)))),
              const SizedBox(height: 6),
              Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15)),
              Text('${f.count} docs', style: const TextStyle(fontSize: 12, color: Color(0xFF6F7777))),
            ]),
          );
        }
        final d = _docs[i - folders.length];
        final sel = _sel.contains(d.id);
        final selecting = _selectMode || _sel.isNotEmpty;
        return InkWell(
          onTap: () => selecting ? _toggle(d.id) : _openDoc(d),
          onLongPress: () => _toggle(d.id),
          child: Column(children: [
            Expanded(
              child: Stack(children: [
                Positioned.fill(child: _thumb(d.thumbPath, w: double.infinity, h: double.infinity)),
                Positioned(
                  left: 0, right: 0, bottom: 0,
                  child: Container(
                    color: const Color(0xCC224646),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    child: Text('${d.pageCount.toString().padLeft(2, '0')}   ${sizeLabel(d.bytes)}',
                        style: const TextStyle(color: Colors.white, fontSize: 12)),
                  ),
                ),
                if (selecting)
                  Positioned(left: 4, top: 4, child: Icon(sel ? Icons.check_box : Icons.check_box_outline_blank, color: p.accent)),
              ]),
            ),
            const SizedBox(height: 6),
            Text(d.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15)),
            Text(listDate(d.updated), style: const TextStyle(fontSize: 12, color: Color(0xFF6F7777))),
          ]),
        );
      },
    );
  }
}

/// Sort used by Clear Scanner: Date created / Date modified / Name, ascending or descending.
void sortDocs(List<ScanDocument> d, String field, bool asc) {
  int c(ScanDocument a, ScanDocument b) => switch (field) {
        'created' => a.created.compareTo(b.created),
        'name' => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        _ => a.updated.compareTo(b.updated),
      };
  d.sort((a, b) => asc ? c(a, b) : c(b, a));
}

/// The "Sort" dialog: field radio list + Ascending / Descending.
Future<(String, bool)?> pickSort(BuildContext context, String field, bool asc,
    {Map<String, String> fields = const {'created': 'Date created', 'modified': 'Date modified', 'name': 'Name'}}) {
  var f = field, a = asc;
  final accent = context.pal.accent;
  return showDialog<(String, bool)>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: const Text('Sort'),
        contentPadding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final e in fields.entries)
            RadioListTile<String>(
              dense: true, activeColor: accent, value: e.key, groupValue: f,
              title: Text(e.value, style: const TextStyle(fontSize: 16)),
              onChanged: (v) => set(() => f = v!),
            ),
          const Divider(),
          RadioListTile<bool>(
            dense: true, activeColor: accent, value: true, groupValue: a,
            title: const Text('Ascending', style: TextStyle(fontSize: 16)), onChanged: (v) => set(() => a = v!),
          ),
          RadioListTile<bool>(
            dense: true, activeColor: accent, value: false, groupValue: a,
            title: const Text('Descending', style: TextStyle(fontSize: 16)), onChanged: (v) => set(() => a = v!),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL')),
          TextButton(onPressed: () => Navigator.pop(ctx, (f, a)), child: const Text('OK')),
        ],
      ),
    ),
  );
}
