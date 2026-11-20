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
import 'package:provider/provider.dart';
import '../theme/app_themes.dart';
import '../theme/theme_provider.dart';

/// Lets the user switch between the six themes.
class ThemePickerSheet extends StatelessWidget {
  const ThemePickerSheet({super.key});
  static Future<void> show(BuildContext c) => showModalBottomSheet(
      context: c, backgroundColor: c.pal.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => const ThemePickerSheet());

  @override
  Widget build(BuildContext context) {
    final tp = context.watch<ThemeProvider>();
    final p = context.pal;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Theme', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: p.text, fontFamily: p.headingFont)),
          const SizedBox(height: 16),
          Wrap(spacing: 12, runSpacing: 12, children: [
            for (final t in AppThemes.all.values)
              GestureDetector(
                onTap: () => tp.setTheme(t.id),
                child: Container(
                  width: 100, padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: tp.id == t.id ? p.accent : p.outline, width: tp.id == t.id ? 2.5 : 1),
                  ),
                  child: Column(children: [
                    Container(
                      height: 54,
                      decoration: BoxDecoration(color: t.background, borderRadius: BorderRadius.circular(10)),
                      child: Column(children: [
                        Container(height: 16, decoration: BoxDecoration(color: t.appBar, borderRadius: const BorderRadius.vertical(top: Radius.circular(10)))),
                        const Spacer(),
                        Container(height: 10, width: 44, margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(color: t.accent, borderRadius: BorderRadius.circular(5))),
                      ]),
                    ),
                    const SizedBox(height: 6),
                    Text(t.name, textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: p.text)),
                  ]),
                ),
              ),
          ]),
        ]),
      ),
    );
  }
}
