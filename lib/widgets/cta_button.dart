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
import '../theme/app_themes.dart';

/// Big pill button ("Export PDF" / "Save PDF" / "Create PDF"); gradient on gold/copper themes.
class CtaButton extends StatelessWidget {
  const CtaButton({super.key, required this.label, required this.icon, required this.onTap, this.trailing = false});
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool trailing;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Material(
      color: Colors.transparent,
      child: Ink(
        height: 56,
        decoration: BoxDecoration(
          color: p.ctaGradient == null ? p.accent : null,
          gradient: p.ctaGradient,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [BoxShadow(color: p.accent.withAlpha(60), blurRadius: 14, offset: const Offset(0, 6))],
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(28),
          onTap: onTap,
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, color: p.onAccent),
            const SizedBox(width: 10),
            Text(label, style: TextStyle(color: p.onAccent, fontSize: 18, fontWeight: FontWeight.w600, fontFamily: p.headingFont)),
            if (trailing) ...[const SizedBox(width: 10), Icon(Icons.arrow_forward, color: p.onAccent)],
          ]),
        ),
      ),
    );
  }
}
