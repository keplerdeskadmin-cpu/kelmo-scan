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

import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// PIN lock (salted + iterated SHA-256, stored locally), optional biometrics via native BiometricPrompt,
/// and FLAG_SECURE (hides the app in recents, blocks screenshots).
class AppLock {
  AppLock._();
  static final instance = AppLock._();
  static const _ch = MethodChannel('doc_scanner/cv');
  late SharedPreferences _p;

  Future<void> load() async => _p = await SharedPreferences.getInstance();

  bool get enabled => _p.getString('pinHash') != null;
  int get pinLength => _p.getInt('pinLen') ?? 4;

  bool get biometric => _p.getBool('lockBio') ?? false;
  set biometric(bool v) { _p.setBool('lockBio', v); }

  int get timeoutSec => _p.getInt('lockTimeout') ?? 60;
  set timeoutSec(int v) { _p.setInt('lockTimeout', v); }

  bool get secureScreen => _p.getBool('secureScreen') ?? false;
  set secureScreen(bool v) { _p.setBool('secureScreen', v); }

  String _hash(String salt, String pin) {
    var h = sha256.convert(utf8.encode('$salt:$pin')).bytes;
    for (var i = 0; i < 5000; i++) {
      h = sha256.convert([...h, ...utf8.encode(salt)]).bytes;
    }
    return base64.encode(h);
  }

  Future<void> setPin(String pin) async {
    final r = Random.secure();
    final salt = base64.encode(List<int>.generate(16, (_) => r.nextInt(256)));
    await _p.setString('pinSalt', salt);
    await _p.setString('pinHash', _hash(salt, pin));
    await _p.setInt('pinLen', pin.length);
  }

  bool verify(String pin) {
    final salt = _p.getString('pinSalt');
    final stored = _p.getString('pinHash');
    if (salt == null || stored == null) return false;
    return _hash(salt, pin) == stored;
  }

  Future<void> clearPin() async {
    await _p.remove('pinHash');
    await _p.remove('pinSalt');
    await _p.remove('lockBio');
  }

  Future<bool> biometricAvailable() async {
    try { return (await _ch.invokeMethod<bool>('biometricAvailable')) ?? false; } catch (_) { return false; }
  }

  Future<bool> authenticateBiometric() async {
    try { return (await _ch.invokeMethod<bool>('biometricAuth', {'title': 'Unlock Kelmo Scan'})) ?? false; } catch (_) { return false; }
  }

  Future<void> applySecure() async {
    try { await _ch.invokeMethod('secureScreen', {'on': secureScreen}); } catch (_) {}
  }
}
