import 'package:shared_preferences/shared_preferences.dart';

/// Возвращает экземпляр SharedPreferences с принудительной синхронизацией с диском.
/// Исключает рассинхронизацию данных между фоновым изолятом датчиков и UI.
Future<SharedPreferences> freshPrefs() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  return prefs;
}