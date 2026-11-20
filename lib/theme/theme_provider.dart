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
import 'package:shared_preferences/shared_preferences.dart';
import 'app_themes.dart';

/// Holds the active theme and persists the choice.
class ThemeProvider extends ChangeNotifier {
  AppThemeId _id = AppThemeId.royalNavy;
  AppThemeId get id => _id;
  AppPalette get palette => AppThemes.all[_id]!;
  ThemeData get theme => AppThemes.build(palette);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('theme');
    _id = AppThemeId.values.firstWhere((e) => e.name == saved, orElse: () => AppThemeId.royalNavy);
  }

  Future<void> setTheme(AppThemeId id) async {
    _id = id;
    notifyListeners();
    (await SharedPreferences.getInstance()).setString('theme', id.name);
  }
}
