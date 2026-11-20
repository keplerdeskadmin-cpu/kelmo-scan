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

class SaveResult {
  SaveResult(this.title, this.folderId, this.tags);
  final String title;
  final int? folderId;
  final List<String> tags;
}

/// "Name your scan": file name, folder and tags right after scanning.
class SaveSheet extends StatefulWidget {
  const SaveSheet({super.key, required this.suggestedName, required this.pageCount, this.folderId, this.thumbPath});
  final String suggestedName;
  final int pageCount;
  final int? folderId;
  final String? thumbPath;

  static Future<SaveResult?> show(BuildContext c,
          {required String suggestedName, required int pageCount, int? folderId, String? thumbPath}) =>
      showModalBottomSheet<SaveResult>(
        context: c,
        isScrollControlled: true,
        backgroundColor: c.pal.surface,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (ctx) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: SaveSheet(suggestedName: suggestedName, pageCount: pageCount, folderId: folderId, thumbPath: thumbPath),
        ),
      );

  @override
  State<SaveSheet> createState() => _SaveSheetState();
}

class _SaveSheetState extends State<SaveSheet> {
  late final TextEditingController _name = TextEditingController(text: widget.suggestedName);
  final _tagCtl = TextEditingController();
  late int _folder = widget.folderId ?? -1;
  List<Folder> _folders = [];
  List<String> _suggest = [];
  final List<String> _tags = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = DocumentRepository.instance;
    final f = await repo.folders();
    final t = await repo.allTags(limit: 8);
    if (mounted) setState(() { _folders = f; _suggest = t; });
  }

  void _addTag(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return;
    if (!_tags.any((x) => x.toLowerCase() == t.toLowerCase())) setState(() => _tags.add(t));
    _tagCtl.clear();
  }

  void _save() {
    if (_tagCtl.text.trim().isNotEmpty) _addTag(_tagCtl.text);
    final n = _name.text.trim();
    Navigator.pop(context, SaveResult(n.isEmpty ? widget.suggestedName : n, _folder == -1 ? null : _folder, List.of(_tags)));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final folderValue = (_folder == -1 || _folders.any((f) => f.id == _folder)) ? _folder : -1;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: p.outline, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 14),
          Row(children: [
            if (widget.thumbPath != null)
              Padding(
                padding: const EdgeInsets.only(right: 14),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(File(widget.thumbPath!), width: 52, height: 68, fit: BoxFit.cover),
                ),
              ),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Name your scan', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: p.text, fontFamily: p.headingFont)),
                Text('${widget.pageCount} ${widget.pageCount == 1 ? 'page' : 'pages'}', style: TextStyle(color: p.textMuted)),
              ]),
            ),
          ]),
          const SizedBox(height: 14),
          TextField(
            controller: _name,
            decoration: InputDecoration(
              labelText: 'File name',
              suffixIcon: IconButton(icon: const Icon(Icons.close), onPressed: () => _name.clear()),
            ),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Icon(Icons.folder_outlined, color: p.accent),
            const SizedBox(width: 10),
            Expanded(
              child: DropdownButton<int>(
                isExpanded: true, value: folderValue, underline: const SizedBox(), dropdownColor: p.surface,
                items: [
                  const DropdownMenuItem(value: -1, child: Text('No folder')),
                  for (final f in _folders) DropdownMenuItem(value: f.id, child: Text(f.name)),
                ],
                onChanged: (v) => setState(() => _folder = v ?? -1),
              ),
            ),
          ]),
          const SizedBox(height: 6),
          Text('Tags', style: TextStyle(fontWeight: FontWeight.w600, color: p.text)),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 0, children: [
            for (final t in _tags)
              InputChip(label: Text(t), onDeleted: () => setState(() => _tags.remove(t)), visualDensity: VisualDensity.compact),
            for (final t in _suggest.where((x) => !_tags.any((y) => y.toLowerCase() == x.toLowerCase())))
              ActionChip(label: Text('+ $t'), onPressed: () => _addTag(t), visualDensity: VisualDensity.compact),
          ]),
          TextField(
            controller: _tagCtl,
            textInputAction: TextInputAction.done,
            onSubmitted: _addTag,
            decoration: InputDecoration(
              hintText: 'Add tag (client name, trip, visa…)',
              suffixIcon: IconButton(icon: const Icon(Icons.add), onPressed: () => _addTag(_tagCtl.text)),
            ),
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(foregroundColor: p.accent, side: BorderSide(color: p.accent), minimumSize: const Size.fromHeight(50)),
                onPressed: () => Navigator.pop(context),
                child: const Text('Keep scanning'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: p.accent, foregroundColor: p.onAccent, minimumSize: const Size.fromHeight(50)),
                onPressed: _save,
                icon: const Icon(Icons.check_rounded),
                label: const Text('Save'),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}
