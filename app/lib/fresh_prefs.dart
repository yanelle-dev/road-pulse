import 'package:shared_preferences/shared_preferences.dart';



Future<SharedPreferences> freshPrefs() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  return prefs;
}