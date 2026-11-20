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
import '../theme/app_themes.dart';

/// Number pad with PIN dots. Calls [onComplete] as soon as [length] digits are entered.
class PinPad extends StatefulWidget {
  const PinPad({
    super.key,
    required this.length,
    required this.title,
    required this.onComplete,
    this.error = '',
    this.onBiometric,
    this.disabled = false,
  });
  final int length;
  final String title, error;
  final void Function(String pin) onComplete;
  final VoidCallback? onBiometric;
  final bool disabled;

  @override
  State<PinPad> createState() => _PinPadState();
}

class _PinPadState extends State<PinPad> {
  String _pin = '';

  void _tap(String d) {
    if (widget.disabled || _pin.length >= widget.length) return;
    HapticFeedback.selectionClick();
    setState(() => _pin += d);
    if (_pin.length == widget.length) {
      final v = _pin;
      Future.microtask(() {
        widget.onComplete(v);
        if (mounted) setState(() => _pin = '');
      });
    }
  }

  void _back() {
    if (_pin.isNotEmpty) setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  Widget _key(AppPalette p, {String? label, IconData? icon, VoidCallback? onTap}) => SizedBox(
        width: 84, height: 72,
        child: onTap == null
            ? const SizedBox()
            : InkResponse(
                onTap: onTap,
                radius: 40,
                child: Center(
                  child: label != null
                      ? Text(label, style: TextStyle(fontSize: 30, fontWeight: FontWeight.w500, color: p.text))
                      : Icon(icon, size: 28, color: p.accent),
                ),
              ),
      );

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text(widget.title, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: p.text)),
      const SizedBox(height: 18),
      Row(mainAxisSize: MainAxisSize.min, children: [
        for (int i = 0; i < widget.length; i++)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 9),
            width: 16, height: 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i < _pin.length ? p.accent : Colors.transparent,
              border: Border.all(color: p.accent, width: 2),
            ),
          ),
      ]),
      SizedBox(
        height: 36,
        child: Center(child: Text(widget.error, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFD64545), fontWeight: FontWeight.w600))),
      ),
      for (final row in const [['1', '2', '3'], ['4', '5', '6'], ['7', '8', '9']])
        Row(mainAxisSize: MainAxisSize.min, children: [for (final d in row) _key(p, label: d, onTap: () => _tap(d))]),
      Row(mainAxisSize: MainAxisSize.min, children: [
        _key(p, icon: Icons.fingerprint, onTap: widget.onBiometric),
        _key(p, label: '0', onTap: () => _tap('0')),
        _key(p, icon: Icons.backspace_outlined, onTap: _back),
      ]),
    ]);
  }
}
