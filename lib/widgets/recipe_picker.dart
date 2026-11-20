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
import '../models/scan_recipe.dart';
import '../theme/app_themes.dart';

/// "Smart Scan Recipes" bottom sheet – one tap picks capture mode + default filter.
Future<ScanRecipe?> pickRecipe(BuildContext c, ScanRecipe current) => showModalBottomSheet<ScanRecipe>(
      context: c,
      isScrollControlled: true,
      backgroundColor: c.pal.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        final p = ctx.pal;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Smart Scan Recipes', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: p.text, fontFamily: p.headingFont)),
              Text('One tap. Better results. For every document.', style: TextStyle(color: p.textMuted)),
              const SizedBox(height: 12),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 2.2,
                children: [
                  for (final r in ScanRecipe.all)
                    InkWell(
                      borderRadius: BorderRadius.circular(p.radius),
                      onTap: () => Navigator.pop(ctx, r),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: r.kind == current.kind ? p.accent.withAlpha(30) : p.background,
                          borderRadius: BorderRadius.circular(p.radius),
                          border: Border.all(color: r.kind == current.kind ? p.accent : p.outline, width: r.kind == current.kind ? 2 : 1),
                        ),
                        child: Row(children: [
                          Icon(r.icon, color: p.accent, size: 28),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(r.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, color: p.text)),
                              Text(r.hint, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: p.textMuted)),
                            ]),
                          ),
                        ]),
                      ),
                    ),
                ],
              ),
            ]),
          ),
        );
      },
    );
