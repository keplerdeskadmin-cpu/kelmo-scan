import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'models.dart';
import 'screens/chat_screen.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/onboarding_screens.dart';
import 'session.dart';
import 'store.dart';
import 'ui.dart';

final navKey = GlobalKey<NavigatorState>();
final messengerKey = GlobalKey<ScaffoldMessengerState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Session.load();
  runApp(ChangeNotifierProvider(create: (_) => ChatStore(), child: const FktApp()));
}

class FktApp extends StatefulWidget {
  const FktApp({super.key});
  @override
  State<FktApp> createState() => _FktAppState();
}

class _FktAppState extends State<FktApp> with WidgetsBindingObserver {
  StreamSubscription<Msg>? _sub;
  StreamSubscription<String>? _sub2;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final store = context.read<ChatStore>();
    _sub2 = store.notices.listen((t) => messengerKey.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(behavior: SnackBarBehavior.floating, backgroundColor: navy, content: Text(t))));
    _sub = store.incoming.listen((m) {
      final c = store.chat(m.chatId);
      if (c == null) return;
      HapticFeedback.mediumImpact();
      final who = store.user(m.from)?.name ?? '';
      final title = c.isGroup ? '${c.name} · $who' : who;
      messengerKey.currentState
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: navy,
          content: Text('$title: ${m.preview}', maxLines: 2, overflow: TextOverflow.ellipsis),
          action: SnackBarAction(
            label: 'OPEN', textColor: gold,
            onPressed: () => navKey.currentState?.push(MaterialPageRoute(builder: (_) => ChatScreen(chatId: c.id))),
          ),
        ));
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) context.read<ChatStore>().resume();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _sub2?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Widget home = Session.token == null
        ? const LoginScreen()
        : !Session.hasName
            ? const NameScreen()
            : !Session.approved
                ? const PendingScreen()
                : const HomeScreen();
    return MaterialApp(
      title: 'Kepler Messenger',
      debugShowCheckedModeBanner: false,
      navigatorKey: navKey,
      scaffoldMessengerKey: messengerKey,
      theme: fktTheme(),
      home: home,
    );
  }
}
