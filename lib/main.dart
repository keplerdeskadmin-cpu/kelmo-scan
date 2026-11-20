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

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'screens/gallery_screen.dart';
import 'screens/lock_screen.dart';
import 'services/app_lock.dart';
import 'services/app_settings.dart';
import 'services/document_repository.dart';
import 'services/ocr_indexer.dart';
import 'theme/theme_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Camera overlay maths assume portrait.
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await AppSettings.instance.load();
  await AppLock.instance.load();
  await AppLock.instance.applySecure();
  await DocumentRepository.instance.init();
  final themes = ThemeProvider();
  await themes.load();
  runApp(ChangeNotifierProvider.value(value: themes, child: const ScanApp()));
  unawaited(OcrIndexer.run()); // index any pages not yet searchable
}

class ScanApp extends StatelessWidget {
  const ScanApp({super.key});
  @override
  Widget build(BuildContext context) {
    final t = context.watch<ThemeProvider>();
    return MaterialApp(
      title: 'Kelmo Scan',
      debugShowCheckedModeBanner: false,
      theme: t.theme,
      builder: (context, child) => LockGate(child: child ?? const SizedBox()),
      home: const GalleryScreen(),
    );
  }
}
