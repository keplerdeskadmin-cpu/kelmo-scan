import 'package:flutter/material.dart';

const navy = Color(0xFF0F1E3D);
const navy2 = Color(0xFF18294F);
const gold = Color(0xFFE9B949);
const waGreen = Color(0xFF1FA855);
const bubbleMine = Color(0xFFDCF3E4);
const chatBg = Color(0xFFEEF1F6);
const muted = Color(0xFF5B6478);

ThemeData fktTheme() {
  final base = ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: navy, primary: navy, secondary: waGreen));
  return base.copyWith(
    scaffoldBackgroundColor: Colors.white,
    appBarTheme: const AppBarTheme(backgroundColor: navy, foregroundColor: Colors.white, elevation: 0, scrolledUnderElevation: 0),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(backgroundColor: waGreen, foregroundColor: Colors.white),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    ),
  );
}

const _palette = [Color(0xFF1565C0), Color(0xFF6A1B9A), Color(0xFF2E7D32), Color(0xFFEF6C00), Color(0xFFAD1457),
  Color(0xFF00838F), Color(0xFF4E342E), Color(0xFF283593)];

class Avatar extends StatelessWidget {
  const Avatar(this.text, {super.key, this.size = 46, this.group = false, this.online = false, this.seed = ''});
  final String text, seed;
  final double size;
  final bool group, online;
  @override
  Widget build(BuildContext context) {
    final c = _palette[(seed.isEmpty ? text : seed).codeUnits.fold<int>(0, (a, b) => a + b) % _palette.length];
    return Stack(clipBehavior: Clip.none, children: [
      CircleAvatar(
        radius: size / 2,
        backgroundColor: c.withAlpha(36),
        child: group
            ? Icon(Icons.groups, color: c, size: size * .55)
            : Text(text, style: TextStyle(color: c, fontWeight: FontWeight.w700, fontSize: size * .36)),
      ),
      if (online)
        Positioned(
          right: 0, bottom: 0,
          child: Container(width: size * .28, height: size * .28,
              decoration: BoxDecoration(color: waGreen, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2))),
        ),
    ]);
  }
}

String two(int v) => v.toString().padLeft(2, '0');

String hhmm(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '$h:${two(d.minute)} ${d.hour < 12 ? 'AM' : 'PM'}';
}

const _mon = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String dayLabel(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  final n = DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  final day = DateTime(d.year, d.month, d.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  return '${d.day} ${_mon[d.month - 1]} ${d.year}';
}

/// Chat list time: 3:05 PM today, "Yesterday", or 12/11/26.
String listTime(int ms) {
  final l = dayLabel(ms);
  if (l == 'Today') return hhmm(ms);
  if (l == 'Yesterday') return l;
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${two(d.day)}/${two(d.month)}/${d.year % 100}';
}

String lastSeenText(int ms) {
  if (ms == 0) return 'offline';
  final l = dayLabel(ms);
  return 'last seen ${l == 'Today' ? 'today' : l == 'Yesterday' ? 'yesterday' : l} at ${hhmm(ms)}';
}

String durLabel(int ms) {
  final s = (ms / 1000).round();
  return '${s ~/ 60}:${two(s % 60)}';
}

Widget tickIcon(int t, {double size = 16}) {
  switch (t) {
    case 0: return Icon(Icons.schedule, size: size - 2, color: muted);
    case 1: return Icon(Icons.done, size: size, color: muted);
    case 2: return Icon(Icons.done_all, size: size, color: muted);
    default: return Icon(Icons.done_all, size: size, color: const Color(0xFF34B7F1));
  }
}

void toast(BuildContext context, String m) =>
    ScaffoldMessenger.of(context)..hideCurrentSnackBar()..showSnackBar(SnackBar(content: Text(m)));
