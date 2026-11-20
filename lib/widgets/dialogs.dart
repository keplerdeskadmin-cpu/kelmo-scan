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

import 'package:flutter/material.dart';
import '../models/scan_document.dart';
import '../theme/app_themes.dart';

Future<String?> promptText(BuildContext c, String title, {String initial = '', String hint = ''}) {
  final ctl = TextEditingController(text: initial);
  return showDialog<String>(
    context: c,
    builder: (ctx) => AlertDialog(
      backgroundColor: ctx.pal.surface,
      title: Text(title),
      content: TextField(controller: ctl, autofocus: true, decoration: InputDecoration(hintText: hint)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, ctl.text.trim().isEmpty ? null : ctl.text.trim()),
            child: const Text('OK')),
      ],
    ),
  );
}

Future<bool> confirm(BuildContext c, String title, String msg, {String yes = 'Delete'}) async =>
    (await showDialog<bool>(
      context: c,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.pal.surface,
        title: Text(title),
        content: Text(msg),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(yes)),
        ],
      ),
    )) ??
    false;

/// Returns folder id, -1 for "No folder", or null if cancelled.
Future<int?> pickFolder(BuildContext c, List<Folder> folders, int? current) => showModalBottomSheet<int>(
      context: c,
      backgroundColor: c.pal.surface,
      builder: (ctx) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          ListTile(
              leading: const Icon(Icons.folder_off_outlined),
              title: const Text('No folder'),
              onTap: () => Navigator.pop(ctx, -1)),
          for (final f in folders)
            ListTile(
              leading: Icon(Icons.folder_rounded, color: ctx.pal.accent),
              title: Text(f.name),
              trailing: f.id == current ? Icon(Icons.check, color: ctx.pal.accent) : null,
              onTap: () => Navigator.pop(ctx, f.id),
            ),
        ]),
      ),
    );
