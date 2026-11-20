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
  // Release builds show a blank grey box for build errors; show the message instead.
  ErrorWidget.builder = (details) => Material(
        color: const Color(0xFFFFF3F3),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Text('Error: ${details.exceptionAsString()}',
              style: const TextStyle(color: Color(0xFFB00020), fontSize: 13)),
        ),
      );
  runApp(const BootApp());
}

/// Runs the start-up steps while showing progress, so a failing or stuck
/// step is visible on screen instead of the app hanging on the splash logo.
class BootApp extends StatefulWidget {
  const BootApp({super.key});
  @override
  State<BootApp> createState() => _BootAppState();
}

class _BootAppState extends State<BootApp> {
  String _step = 'Starting';
  Object? _error;
  StackTrace? _stack;
  ThemeProvider? _themes;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _run(String name, Future<void> Function() task) async {
    if (mounted) setState(() => _step = name);
    await task().timeout(const Duration(seconds: 20),
        onTimeout: () => throw TimeoutException('"$name" did not finish in 20 seconds'));
  }

  Future<void> _boot() async {
    setState(() { _error = null; _stack = null; });
    try {
      // Camera overlay maths assume portrait.
      await _run('Screen orientation',
          () => SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]));
      await _run('Settings', AppSettings.instance.load);
      await _run('App lock', AppLock.instance.load);
      await _run('Secure screen', AppLock.instance.applySecure);
      await _run('Documents database', DocumentRepository.instance.init);
      final themes = ThemeProvider();
      await _run('Theme', themes.load);
      if (!mounted) return;
      setState(() => _themes = themes);
      unawaited(OcrIndexer.run()); // index any pages not yet searchable
    } catch (e, st) {
      if (mounted) setState(() { _error = e; _stack = st; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final themes = _themes;
    if (themes != null) {
      return ChangeNotifierProvider.value(value: themes, child: const ScanApp());
    }
    const navy = Color(0xFF0F1B3D);
    final err = _error;
    final details = err == null ? '' : 'Step: $_step\n\n$err\n\n${_stack.toString().split('\n').take(12).join('\n')}';
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: navy,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: err == null
                ? Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Text('Kelmo Scan',
                          style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 24),
                      const CircularProgressIndicator(color: Colors.white),
                      const SizedBox(height: 16),
                      Text('Loading: $_step', style: const TextStyle(color: Colors.white70)),
                    ]),
                  )
                : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    const SizedBox(height: 12),
                    const Text('Kelmo Scan could not start',
                        style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    const Text('Please take a screenshot of this screen.',
                        style: TextStyle(color: Colors.white70)),
                    const SizedBox(height: 16),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(10)),
                        child: SingleChildScrollView(
                          child: SelectableText(details,
                              style: const TextStyle(color: Color(0xFFFFB4B4), fontSize: 12, fontFamily: 'monospace')),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Clipboard.setData(ClipboardData(text: details)),
                          style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
                          child: const Text('Copy error'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(onPressed: _boot, child: const Text('Try again')),
                      ),
                    ]),
                  ]),
          ),
        ),
      ),
    );
  }
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
