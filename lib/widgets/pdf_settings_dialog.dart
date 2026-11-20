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
import '../services/doc_export.dart';
import '../services/document_repository.dart';
import '../services/pdf_exporter.dart';
import '../theme/app_themes.dart';

const pdfResolutionLabels = {'low': 'Low', 'medium': 'Medium', 'high': 'High', 'original': 'Original'};
const pdfOrientationLabels = {'auto': 'Auto', 'portrait': 'Portrait', 'landscape': 'Landscape'};
const pdfScaleLabels = {'fit': 'Fit width or height', 'fill': 'Fill the entire page'};

/// "PDF Settings" for one document (Page Size, Resolution, Page Orientation, Image Scale).
/// Returns true when saved.
Future<bool> showPdfSettings(BuildContext context, int docId) async {
  final o = await PdfOpts.forDoc(docId);
  if (!context.mounted) return false;
  var m = o.toMap();
  final accent = context.pal.accent;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
      Widget row(String title, String key, Map<String, String> opts) => ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(title),
            subtitle: Text(opts[m[key]] ?? '', style: TextStyle(color: accent)),
            onTap: () async {
              final v = await pickOption(ctx, title, opts, m[key] as String);
              if (v != null) set(() => m = {...m, key: v});
            },
          );
      return AlertDialog(
        title: const Text('PDF Settings'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          row('Page Size', 'page', {for (final p in PdfSize.values) p.name: p.label}),
          row('Resolution', 'resolution', pdfResolutionLabels),
          row('Page Orientation', 'orientation', pdfOrientationLabels),
          row('Image Scale', 'scale', pdfScaleLabels),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('OK')),
        ],
      );
    }),
  );
  if (ok != true) return false;
  await DocumentRepository.instance.setPdfSettings(docId, m);
  return true;
}

/// Single-choice list dialog (the Clear Scanner ListPreference look).
Future<String?> pickOption(BuildContext context, String title, Map<String, String> opts, String current) {
  final accent = context.pal.accent;
  return showDialog<String>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: Text(title),
      children: [
        for (final e in opts.entries)
          RadioListTile<String>(
            activeColor: accent, value: e.key, groupValue: current,
            title: Text(e.value), onChanged: (v) => Navigator.pop(ctx, v),
          ),
      ],
    ),
  );
}
