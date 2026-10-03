import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'api_service.dart';
import 'app_theme.dart';
import 'main_scaffold.dart';
import 'screens/auth_screen.dart';

/// Глобальный нотификатор для мгновенного переключения темы (Light/Dark/System)
final ValueNotifier<ThemeMode> themeModeNotifier = ValueNotifier(
  ThemeMode.system,
);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterForegroundTask.initCommunicationPort();

  // Логирование холодного старта приложения
  await ApiService.recordAppOpen();

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

/// Виджет-шлюз: проверяет наличие токена сессии и отслеживает активность
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> with WidgetsBindingObserver {
  late Future<bool> _authFuture;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _authFuture = ApiService.isAuthenticated();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Фиксация возврата в приложение из фонового режима
    if (state == AppLifecycleState.resumed) {
      ApiService.recordAppOpen();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return FutureBuilder<bool>(
      future: _authFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            backgroundColor: colors.voidBg,
            body: Center(
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: colors.mark,
              ),
            ),
          );
        }

        if (snapshot.data == true) {
          return const MainScaffold();
        }

        return const AuthScreen();
      },
    );
  }
}
