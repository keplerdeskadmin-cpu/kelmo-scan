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
import '../models/scan_document.dart';
import '../services/document_repository.dart';
import '../theme/app_themes.dart';
import '../widgets/dialogs.dart';

/// Deleted documents: restore them or delete them for good.
class TrashScreen extends StatefulWidget {
  const TrashScreen({super.key});
  @override
  State<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends State<TrashScreen> {
  final _repo = DocumentRepository.instance;
  List<ScanDocument> _docs = [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final d = await _repo.trashedDocuments();
    if (mounted) setState(() { _docs = d; _loaded = true; });
  }

  Future<void> _empty() async {
    if (_docs.isEmpty) return;
    if (await confirm(context, 'Empty Trash?', '${_docs.length} document(s) will be deleted forever.', yes: 'Delete')) {
      await _repo.emptyTrash();
      _load();
    }
  }

  Future<void> _act(String v, ScanDocument d) async {
    if (v == 'restore') {
      await _repo.restoreDocument(d.id);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('"${d.title}" restored')));
    } else if (v == 'delete') {
      if (!await confirm(context, 'Delete forever?', '"${d.title}" cannot be recovered.', yes: 'Delete')) return;
      await _repo.deleteDocument(d.id);
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: p.appBar,
        title: Text('Trash (${_docs.length})'),
        actions: [
          if (_docs.isNotEmpty)
            TextButton(onPressed: _empty, child: Text('EMPTY', style: TextStyle(color: p.onAppBar, fontWeight: FontWeight.w600))),
        ],
      ),
      body: !_loaded
          ? const SizedBox()
          : _docs.isEmpty
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.delete_outline, size: 72, color: p.textMuted.withAlpha(120)),
                    const SizedBox(height: 12),
                    Text('Trash is empty', style: TextStyle(color: p.textMuted, fontSize: 16)),
                  ]),
                )
              : ListView.separated(
                  itemCount: _docs.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFE6E9E9)),
                  itemBuilder: (_, i) {
                    final d = _docs[i];
                    return ListTile(
                      contentPadding: const EdgeInsets.fromLTRB(8, 6, 0, 6),
                      leading: Container(
                        width: 80, height: 56,
                        decoration: BoxDecoration(border: Border.all(color: const Color(0xFFA1AAA5))),
                        child: d.thumbPath != null
                            ? Image.file(File(d.thumbPath!), fit: BoxFit.contain, cacheWidth: 240)
                            : const Icon(Icons.description_outlined),
                      ),
                      title: Text(d.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                      subtitle: Text(d.meta),
                      trailing: PopupMenuButton<String>(
                        color: Colors.white,
                        onSelected: (v) => _act(v, d),
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'restore', child: Text('Restore')),
                          PopupMenuItem(value: 'delete', child: Text('Delete forever')),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
