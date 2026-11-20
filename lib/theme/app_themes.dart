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
import 'package:flutter/services.dart';

/// The six themes reverse-engineered from the mock-up screenshots.
/// Hex values were estimated visually from the images (see README).
enum AppThemeId { royalNavy, ivoryGold, forestCopper, midnightGold, blackGold, charcoalSand }

/// Every colour / shape token the UI needs. Widgets read it via `context.pal`.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.id,
    required this.name,
    required this.brightness,
    required this.background,
    required this.surface,
    required this.surfaceAlt,
    required this.appBar,
    required this.onAppBar,
    required this.text,
    required this.textMuted,
    required this.accent,
    required this.onAccent,
    required this.outline,
    required this.folderCard,
    required this.onFolderCard,
    required this.folderIcon,
    required this.cropLine,
    required this.cropHandle,
    this.ctaGradient,
    this.headingFont,
    this.radius = 16,
    this.centerTitle = false,
    this.hasMenuIcon = true,
  });

  final AppThemeId id;
  final String name;
  final Brightness brightness;
  final Color background, surface, surfaceAlt, appBar, onAppBar;
  final Color text, textMuted, accent, onAccent, outline;
  final Color folderCard, onFolderCard, folderIcon; // folder tiles
  final Color cropLine, cropHandle; // crop frame + pins
  final Gradient? ctaGradient; // "Save PDF / Export PDF" button
  final String? headingFont; // serif for the gold/ivory themes
  final double radius; // card corner radius
  final bool centerTitle, hasMenuIcon;

  @override
  AppPalette copyWith() => this;
  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) =>
      t < .5 ? this : (other as AppPalette? ?? this);
}

extension PaletteX on BuildContext {
  AppPalette get pal => Theme.of(this).extension<AppPalette>()!;
}

class AppThemes {
  static final Map<AppThemeId, AppPalette> all = {
    // ── LIGHT 1 — navy header, white cards, blue crop frame (image 1)
    AppThemeId.royalNavy: const AppPalette(
      id: AppThemeId.royalNavy, name: 'Royal Navy', brightness: Brightness.light,
      background: Color(0xFFF4F6FA), surface: Color(0xFFFFFFFF), surfaceAlt: Color(0xFFEDEFF5),
      appBar: Color(0xFF14315F), onAppBar: Colors.white,
      text: Color(0xFF111C33), textMuted: Color(0xFF6A7387),
      accent: Color(0xFF14315F), onAccent: Colors.white, outline: Color(0xFFE4E8F0),
      folderCard: Color(0xFFEFF1F6), onFolderCard: Color(0xFF111C33), folderIcon: Color(0xFF14315F),
      cropLine: Color(0xFF2F6BEA), cropHandle: Color(0xFF2F6BEA),
      radius: 16, hasMenuIcon: false,
    ),
    // ── LIGHT 2 — ivory + metallic gold, serif headings (image 2)
    AppThemeId.ivoryGold: const AppPalette(
      id: AppThemeId.ivoryGold, name: 'Ivory Gold', brightness: Brightness.light,
      background: Color(0xFFFBF6EA), surface: Color(0xFFF7F0E0), surfaceAlt: Color(0xFFF1E7D0),
      appBar: Color(0xFFFBF6EA), onAppBar: Color(0xFF3B2A12),
      text: Color(0xFF3B2A12), textMuted: Color(0xFF8B7A5E),
      accent: Color(0xFFB48C45), onAccent: Colors.white, outline: Color(0xFFEADFC6),
      folderCard: Color(0xFFF7F0E0), onFolderCard: Color(0xFF3B2A12), folderIcon: Color(0xFFC2A15E),
      cropLine: Color(0xFFC9A24D), cropHandle: Color(0xFFE2BD6B),
      ctaGradient: LinearGradient(colors: [Color(0xFFC9A45C), Color(0xFFA77C36)]),
      headingFont: 'serif', radius: 18, centerTitle: true,
    ),
    // ── LIGHT 3 — forest green bar, cream cards, copper accent (image 3)
    AppThemeId.forestCopper: const AppPalette(
      id: AppThemeId.forestCopper, name: 'Forest Copper', brightness: Brightness.light,
      background: Color(0xFFF3F2EA), surface: Color(0xFFFAF9F4), surfaceAlt: Color(0xFFE9E8DC),
      appBar: Color(0xFF3F604C), onAppBar: Colors.white,
      text: Color(0xFF1F3A2A), textMuted: Color(0xFF6C7B70),
      accent: Color(0xFFB8652F), onAccent: Colors.white, outline: Color(0xFFE6E4D8),
      folderCard: Color(0xFFFAF9F4), onFolderCard: Color(0xFF1F3A2A), folderIcon: Color(0xFF4A6B57),
      cropLine: Color(0xFF2ECC71), cropHandle: Color(0xFF8FCB8F),
      ctaGradient: LinearGradient(colors: [Color(0xFFC8773F), Color(0xFFA9582A)]),
      radius: 14, centerTitle: true,
    ),
    // ── DARK 1 — midnight navy + gold (image 4)
    AppThemeId.midnightGold: const AppPalette(
      id: AppThemeId.midnightGold, name: 'Midnight Gold', brightness: Brightness.dark,
      background: Color(0xFF0A1330), surface: Color(0xFF13213F), surfaceAlt: Color(0xFF1A2A4D),
      appBar: Color(0xFF0A1330), onAppBar: Color(0xFFF3F4F8),
      text: Color(0xFFF3F4F8), textMuted: Color(0xFFA1ACC4),
      accent: Color(0xFFE9B949), onAccent: Color(0xFF1A1405), outline: Color(0xFF2A3A60),
      folderCard: Color(0xFF13213F), onFolderCard: Color(0xFFF3F4F8), folderIcon: Color(0xFFE9B949),
      cropLine: Color(0xFFF0C14B), cropHandle: Color(0xFFF0C14B),
      ctaGradient: LinearGradient(colors: [Color(0xFFF3CC6A), Color(0xFFD9A93A)]),
      radius: 16,
    ),
    // ── DARK 2 — pure black with luxe gold borders (images 5 & 6, identical)
    AppThemeId.blackGold: const AppPalette(
      id: AppThemeId.blackGold, name: 'Black Gold', brightness: Brightness.dark,
      background: Color(0xFF050505), surface: Color(0xFF15130F), surfaceAlt: Color(0xFF1E1A12),
      appBar: Color(0xFF050505), onAppBar: Color(0xFFE2C26C),
      text: Color(0xFFF6F1E3), textMuted: Color(0xFFA79C7D),
      accent: Color(0xFFD4AF37), onAccent: Color(0xFF1A1405), outline: Color(0xFF4F3F18),
      folderCard: Color(0xFF15130F), onFolderCard: Color(0xFFF6F1E3), folderIcon: Color(0xFFD9B04A),
      cropLine: Color(0xFFD4AF37), cropHandle: Color(0xFFD4AF37),
      ctaGradient: LinearGradient(colors: [Color(0xFFE7C766), Color(0xFFB8902C)]),
      radius: 18, centerTitle: true,
    ),
    // ── DARK 3 — charcoal with sand/tan folder tiles (image 7)
    AppThemeId.charcoalSand: const AppPalette(
      id: AppThemeId.charcoalSand, name: 'Charcoal Sand', brightness: Brightness.dark,
      background: Color(0xFF161719), surface: Color(0xFF212224), surfaceAlt: Color(0xFF2A2B2E),
      appBar: Color(0xFF161719), onAppBar: Color(0xFFF1ECE3),
      text: Color(0xFFF1ECE3), textMuted: Color(0xFFA9A398),
      accent: Color(0xFFE2BC8B), onAccent: Color(0xFF2A1E0E), outline: Color(0xFF34363A),
      folderCard: Color(0xFFDDBB8A), onFolderCard: Color(0xFF2B2417), folderIcon: Color(0xFF8C7653),
      cropLine: Color(0xFFE9C89A), cropHandle: Colors.white,
      radius: 14,
    ),
  };

  /// Turns a palette into a full Material [ThemeData].
  static ThemeData build(AppPalette p) {
    final base = ThemeData(brightness: p.brightness, useMaterial3: true);
    final scheme = ColorScheme(
      brightness: p.brightness,
      primary: p.accent, onPrimary: p.onAccent,
      secondary: p.accent, onSecondary: p.onAccent,
      error: const Color(0xFFD64545), onError: Colors.white,
      surface: p.surface, onSurface: p.text,
    );
    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: p.background,
      textTheme: base.textTheme.apply(bodyColor: p.text, displayColor: p.text),
      dividerColor: p.outline,
      appBarTheme: AppBarTheme(
        backgroundColor: p.appBar,
        foregroundColor: p.onAppBar,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: p.centerTitle,
        titleTextStyle: TextStyle(
            color: p.onAppBar, fontSize: 24, fontWeight: FontWeight.w600, fontFamily: p.headingFont),
        iconTheme: IconThemeData(color: p.onAppBar),
        actionsIconTheme: IconThemeData(color: p.onAppBar),
        systemOverlayStyle: p.appBar.computeLuminance() < .5
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
      ),
      popupMenuTheme: PopupMenuThemeData(color: p.surface),
      extensions: [p],
    );
  }
}
