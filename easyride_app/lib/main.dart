import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'api_service.dart';
import 'app_theme.dart';
import 'main_scaffold.dart';
import 'screens/auth_screen.dart'; // Если файл лежит в папке screens, укажите: 'screens/auth_screen.dart'

/// Глобальный нотификатор для мгновенного переключения темы (Light/Dark/System)
final ValueNotifier<ThemeMode> themeModeNotifier = ValueNotifier(
  ThemeMode.system,
);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterForegroundTask.initCommunicationPort();
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

/// Виджет-шлюз: проверяет наличие токена сессии перед показом интерфейса
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late Future<bool> _authFuture;

  @override
  void initState() {
    super.initState();
    _authFuture = ApiService.isAuthenticated();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return FutureBuilder<bool>(
      future: _authFuture,
      builder: (context, snapshot) {
        // Пока читаются SharedPreferences — лаконичный фон без мерцания
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

        // Если токен валиден — сразу главный экран
        if (snapshot.data == true) {
          return const MainScaffold();
        }

        // Если не авторизован — экран входа по SMS
        return const AuthScreen();
      },
    );
  }
}
