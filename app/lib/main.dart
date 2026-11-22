import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'api_service.dart';
import 'app_theme.dart';
import 'main_scaffold.dart';
import 'screens/auth_screen.dart';
import 'theme_store.dart';


final ValueNotifier<ThemeMode> themeModeNotifier = ValueNotifier(
  ThemeMode.system,
);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterForegroundTask.initCommunicationPort();

  themeModeNotifier.value = await ThemeStore.load();
  themeModeNotifier.addListener(() => ThemeStore.save(themeModeNotifier.value));

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeModeNotifier,
      builder: (context, themeMode, _) {
        return MaterialApp(
          title: 'Дорожный пульс',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: themeMode,
          home: const AuthGate(),
        );
      },
    );
  }
}


class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> with WidgetsBindingObserver {


  bool? _authenticated;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkSession();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _checkSession() async {
    final ok = await ApiService.isAuthenticated();
    if (mounted && ok != _authenticated) setState(() => _authenticated = ok);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;

    _checkSession();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return switch (_authenticated) {
      null => Scaffold(
        backgroundColor: colors.voidBg,
        body: Center(
          child: CircularProgressIndicator(strokeWidth: 2.5, color: colors.mark),
        ),
      ),
      true => const MainScaffold(),
      false => const AuthScreen(),
    };
  }
}