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
import '../services/app_lock.dart';
import '../theme/app_themes.dart';
import '../widgets/pin_pad.dart';

/// Wraps the whole app: shows the lock screen on start and after the app was in the
/// background longer than the chosen timeout.
class LockGate extends StatefulWidget {
  const LockGate({super.key, required this.child});
  final Widget child;
  @override
  State<LockGate> createState() => _LockGateState();
}

class _LockGateState extends State<LockGate> with WidgetsBindingObserver {
  bool _locked = AppLock.instance.enabled;
  DateTime? _pausedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.paused) {
      _pausedAt = DateTime.now();
    } else if (s == AppLifecycleState.resumed && AppLock.instance.enabled && !_locked) {
      final t = _pausedAt;
      if (t != null && DateTime.now().difference(t).inSeconds >= AppLock.instance.timeoutSec) {
        setState(() => _locked = true);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Stack(children: [
        widget.child,
        if (_locked) Positioned.fill(child: LockScreen(onUnlocked: () => setState(() => _locked = false))),
      ]);
}

class LockScreen extends StatefulWidget {
  const LockScreen({super.key, required this.onUnlocked});
  final VoidCallback onUnlocked;
  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  String _error = '';
  int _fails = 0;
  DateTime? _until;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (AppLock.instance.biometric) WidgetsBinding.instance.addPostFrameCallback((_) => _bio());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _bio() async {
    if (await AppLock.instance.authenticateBiometric()) widget.onUnlocked();
  }

  void _check(String pin) {
    if (AppLock.instance.verify(pin)) {
      widget.onUnlocked();
      return;
    }
    _fails++;
    setState(() => _error = 'Wrong PIN');
    if (_fails % 5 == 0) {
      _until = DateTime.now().add(const Duration(seconds: 30));
      _timer?.cancel();
      _timer = Timer(const Duration(seconds: 30), () { if (mounted) setState(() { _until = null; _error = ''; }); });
      setState(() => _error = 'Too many attempts. Try again in 30 seconds');
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final disabled = _until != null && DateTime.now().isBefore(_until!);
    return Scaffold(
      backgroundColor: p.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.lock_rounded, size: 56, color: p.accent),
              const SizedBox(height: 10),
              Text('Kelmo Scan is locked', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: p.text, fontFamily: p.headingFont)),
              const SizedBox(height: 26),
              PinPad(
                length: AppLock.instance.pinLength,
                title: 'Enter PIN',
                error: _error,
                disabled: disabled,
                onComplete: _check,
                onBiometric: AppLock.instance.biometric ? _bio : null,
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Choose a new PIN (4 or 6 digits) and confirm it. Pops `true` when saved.
class SetPinScreen extends StatefulWidget {
  const SetPinScreen({super.key});
  @override
  State<SetPinScreen> createState() => _SetPinScreenState();
}

class _SetPinScreenState extends State<SetPinScreen> {
  int _len = 4;
  String? _first;
  String _error = '';
  int _round = 0;

  Future<void> _done(String pin) async {
    if (_first == null) {
      setState(() { _first = pin; _error = ''; });
    } else if (pin == _first) {
      await AppLock.instance.setPin(pin);
      if (mounted) Navigator.pop(context, true);
    } else {
      setState(() { _first = null; _error = 'PINs did not match. Start again.'; _round++; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Scaffold(
      appBar: AppBar(title: const Text('Set PIN')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (_first == null)
                Wrap(spacing: 10, children: [
                  for (final n in [4, 6])
                    ChoiceChip(
                      label: Text('$n digits'),
                      selected: _len == n,
                      showCheckmark: false,
                      selectedColor: p.accent.withAlpha(45),
                      labelStyle: TextStyle(color: _len == n ? p.accent : p.text, fontWeight: FontWeight.w600),
                      onSelected: (_) => setState(() { _len = n; _round++; }),
                    ),
                ]),
              const SizedBox(height: 20),
              PinPad(
                key: ValueKey('$_len-${_first != null}-$_round'),
                length: _len,
                title: _first == null ? 'Choose a PIN' : 'Confirm your PIN',
                error: _error,
                onComplete: _done,
              ),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text('There is no PIN recovery. If you forget it the app data has to be cleared - keep a backup.',
                    textAlign: TextAlign.center, style: TextStyle(color: p.textMuted, fontSize: 12)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Asks for the current PIN. Pops `true` when correct.
class VerifyPinScreen extends StatefulWidget {
  const VerifyPinScreen({super.key});
  @override
  State<VerifyPinScreen> createState() => _VerifyPinScreenState();
}

class _VerifyPinScreenState extends State<VerifyPinScreen> {
  String _error = '';

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Confirm PIN')),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              child: PinPad(
                length: AppLock.instance.pinLength,
                title: 'Enter current PIN',
                error: _error,
                onComplete: (pin) {
                  if (AppLock.instance.verify(pin)) {
                    Navigator.pop(context, true);
                  } else {
                    setState(() => _error = 'Wrong PIN');
                  }
                },
              ),
            ),
          ),
        ),
      );
}
