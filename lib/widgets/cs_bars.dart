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
import '../services/doc_export.dart';
import '../theme/app_themes.dart';

/// Teal bottom bar used on the document, page and PDF screens.
class CsBottomBar extends StatelessWidget {
  const CsBottomBar({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Container(
        color: context.pal.appBar,
        child: SafeArea(top: false, child: SizedBox(height: 64, child: Row(children: children))),
      );
}

/// Icon with a small label underneath (Share, More, Note, OCR …).
class CsBarButton extends StatelessWidget {
  const CsBarButton({super.key, required this.icon, required this.label, this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, color: onTap == null ? Colors.white38 : Colors.white, size: 26),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(color: onTap == null ? Colors.white38 : Colors.white, fontSize: 13)),
          ]),
        ),
      );
}

/// Big plain icon (gallery / camera) for the bottom bar.
class CsBarIcon extends StatelessWidget {
  const CsBarIcon({super.key, required this.icon, required this.tooltip, this.onTap});
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) =>
      IconButton(iconSize: 34, color: Colors.white, tooltip: tooltip, icon: Icon(icon), onPressed: onTap);
}

/// "More" menu: Send Email, Print, Save to Gallery, Save to storage.
class CsMoreButton extends StatelessWidget {
  const CsMoreButton(
      {super.key, required this.pages, required this.name, this.watermark, this.extra = const [], this.onExtra});
  final List<ScanPage> Function() pages;
  final String Function() name;
  final String Function()? watermark;
  final List<PopupMenuEntry<String>> extra;
  final void Function(String)? onExtra;
  static const _shared = {'email', 'print', 'gallery', 'storage'};

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
        color: Colors.white,
        tooltip: 'More',
        onSelected: (v) => _shared.contains(v)
            ? runMoreAction(context, v, pages(), name(), watermark: watermark?.call() ?? '')
            : onExtra?.call(v),
        itemBuilder: (_) => [
          ...extra,
          _item('email', Icons.email, 'Send Email'),
          _item('print', Icons.print, 'Print'),
          const PopupMenuDivider(),
          _item('gallery', Icons.photo_library, 'Save to Gallery'),
          _item('storage', Icons.save, 'Save to storage'),
        ],
        child: const IgnorePointer(child: CsBarButton(icon: Icons.more_vert, label: 'More', onTap: _noop)),
      );

  static void _noop() {}

  static PopupMenuItem<String> _item(String v, IconData i, String t) => PopupMenuItem(
        value: v,
        child: Row(children: [Icon(i, color: const Color(0xFF202124)), const SizedBox(width: 16), Text(t)]),
      );
}

PopupMenuItem<String> csMenuItem(String v, IconData i, String t) => CsMoreButton._item(v, i, t);

/// Runs one of the shared "More" actions and reports the result with a snack bar.
Future<void> runMoreAction(BuildContext context, String v, List<ScanPage> pages, String name, {String watermark = ''}) async {
  if (pages.isEmpty) return;
  final m = ScaffoldMessenger.of(context);
  void say(String t) => m..hideCurrentSnackBar()..showSnackBar(SnackBar(content: Text(t)));
  try {
    switch (v) {
      case 'email':
        await DocExport.email(pages, name, watermark: watermark);
      case 'print':
        say('Preparing to print…');
        await DocExport.printPdf(pages, name, watermark: watermark);
      case 'gallery':
        final where = await DocExport.toGallery(pages, name);
        say('${pages.length} image(s) saved to $where');
      case 'storage':
        final where = await DocExport.toStorage(pages, name, watermark: watermark);
        say('Saved: $where');
    }
  } catch (e) {
    say('Failed: ${e is Exception ? e.toString().replaceFirst('Exception: ', '') : e}');
  }
}
