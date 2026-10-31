import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../achievement_service.dart';
import '../api_service.dart';
import '../app_theme.dart';
import '../widgets/theme_mode_selector.dart';
import 'auth_screen.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  Map<String, dynamic> _profile = {
    'phone': '+7 999 123-45-67',
    'name': 'Водитель',
    'city': 'Москва',
    'car_clearance': 0,
    'car_model': '',
    'car_tires': '',
  };

  String _appVersionString = 'Дорожный пульс';

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _loadAppVersion();
  }

  Future<void> _loadAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() {
          _appVersionString =
              'Дорожный пульс ${info.version} · сборка ${info.buildNumber}';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _appVersionString = 'Дорожный пульс 2.0.0 · сборка 19';
        });
      }
    }
  }

  Future<void> _loadProfile() async {
    final p = await ApiService.getUserProfile();
    final prefs = await SharedPreferences.getInstance();
    p['car_model'] = prefs.getString('auth_car_model') ?? '';
    p['car_tires'] = prefs.getString('auth_car_tires') ?? '';
    if (mounted) {
      setState(() => _profile = p);
    }
  }

  Future<void> _showEditProfileDialog(PolotnoColors colors) async {
    final nameCtrl = TextEditingController(text: _profile['name']);
    final cityCtrl = TextEditingController(text: _profile['city']);
    final currentClearance = _profile['car_clearance'];
    final clearanceCtrl = TextEditingController(
      text: (currentClearance is int && currentClearance > 0)
          ? currentClearance.toString()
          : '',
    );
    final modelCtrl = TextEditingController(text: _profile['car_model'] ?? '');
    final tiresCtrl = TextEditingController(text: _profile['car_tires'] ?? '');

    await showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: colors.surf,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            "Редактировать данные",
            style: TextStyle(
              fontFamily: AppTheme.fontDisplay,
              fontSize: 18,
              color: colors.ink,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  style: TextStyle(
                    fontFamily: AppTheme.fontUi,
                    color: colors.ink,
                  ),
                  decoration: InputDecoration(
                    labelText: "Имя (ФИО)*",
                    labelStyle: TextStyle(color: colors.ink3),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: cityCtrl,
                  style: TextStyle(
                    fontFamily: AppTheme.fontUi,
                    color: colors.ink,
                  ),
                  decoration: InputDecoration(
                    labelText: "Город*",
                    labelStyle: TextStyle(color: colors.ink3),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: modelCtrl,
                  style: TextStyle(
                    fontFamily: AppTheme.fontUi,
                    color: colors.ink,
                  ),
                  decoration: InputDecoration(
                    labelText: "Марка и модель авто",
                    labelStyle: TextStyle(color: colors.ink3),
                    hintText: "Например, Skoda Octavia",
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: tiresCtrl,
                  style: TextStyle(
                    fontFamily: AppTheme.fontUi,
                    color: colors.ink,
                  ),
                  decoration: InputDecoration(
                    labelText: "Параметры шин",
                    labelStyle: TextStyle(color: colors.ink3),
                    hintText: "Например, 205/55 R16",
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: clearanceCtrl,
                  keyboardType: TextInputType.number,
                  style: TextStyle(
                    fontFamily: AppTheme.fontUi,
                    color: colors.ink,
                  ),
                  decoration: InputDecoration(
                    labelText: "Клиренс (мм), не обязательно",
                    labelStyle: TextStyle(color: colors.ink3),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text("Отмена", style: TextStyle(color: colors.ink3)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.mark,
                foregroundColor: colors.onMark,
                elevation: 0,
              ),
              onPressed: () async {
                final name = nameCtrl.text.trim();
                final city = cityCtrl.text.trim();
                if (name.isEmpty || city.isEmpty) {
                  return;
                }
                final clearance = int.tryParse(clearanceCtrl.text.trim()) ?? 0;
                final model = modelCtrl.text.trim();
                final tires = tiresCtrl.text.trim();

                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('auth_car_model', model);
                await prefs.setString('auth_car_tires', tires);

                await AchievementService.checkCarProfile(
                  model: model,
                  tires: tires,
                  clearance: clearance,
                );

                await ApiService.updateProfile(
                  name: name,
                  city: city,
                  clearance: clearance,
                );
                if (mounted) {
                  _loadProfile();
                }
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                }
              },
              child: const Text("Сохранить"),
            ),
          ],
        );
      },
    );
  }

  Future<void> _handleLogout() async {
    await ApiService.logout();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const AuthScreen()),
      (route) => false,
    );
  }

  Future<void> _handleDeleteAccount(PolotnoColors colors) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: colors.surf,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            "Удалить аккаунт?",
            style: TextStyle(
              fontFamily: AppTheme.fontDisplay,
              fontSize: 18,
              color: colors.ink,
            ),
          ),
          content: Text(
            "Ваш профиль и номер телефона будут безвозвратно удалены. Записанные дефекты полотна останутся на карте анонимно.",
            style: TextStyle(
              fontFamily: AppTheme.fontUi,
              fontSize: 13.5,
              color: colors.ink2,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text("Отмена", style: TextStyle(color: colors.ink3)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.s3,
                foregroundColor: Colors.white,
                elevation: 0,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text("Удалить"),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      final success = await ApiService.deleteAccount();
      if (!mounted) return;
      if (success) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const AuthScreen()),
          (route) => false,
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Не удалось удалить аккаунт на сервере")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    final clearanceVal = _profile['car_clearance'];
    final clearanceStr = (clearanceVal is int && clearanceVal > 0)
        ? "клиренс $clearanceVal мм"
        : "клиренс не указан";
    final carModel = _profile['car_model'] as String? ?? '';
    final carSubtitle = carModel.isNotEmpty
        ? "${_profile['city']} · $carModel · $clearanceStr"
        : "${_profile['city']} · $clearanceStr";

    return Scaffold(
      backgroundColor: colors.voidBg,
      body: SafeArea(
        child: ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: InkWell(
                onTap: () => Navigator.pop(context),
                borderRadius: BorderRadius.circular(13),
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: colors.surf,
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(color: colors.edge2),
                  ),
                  child: Icon(
                    Icons.arrow_back_rounded,
                    color: colors.ink,
                    size: 18,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 22),
            Text(
              "Аккаунт",
              style: TextStyle(
                fontFamily: AppTheme.fontDisplay,
                fontSize: 30,
                fontWeight: FontWeight.w700,
                color: colors.ink,
                letterSpacing: -0.8,
              ),
            ),
            _buildSectionHeader("ВХОД", colors),
            _buildGroupCard(
              colors: colors,
              children: [
                _buildRowItem(
                  colors: colors,
                  icon: Icons.phone_android_rounded,
                  title: _profile['phone'] ?? 'Номер не указан',
                  subtitle: "Номер подтверждён",
                  trailing: Icon(
                    Icons.chevron_right_rounded,
                    color: colors.ink3,
                    size: 20,
                  ),
                ),
                _buildRowItem(
                  colors: colors,
                  icon: Icons.person_outline_rounded,
                  title: _profile['name'] ?? 'Водитель',
                  subtitle: carSubtitle,
                  trailing: Icon(
                    Icons.edit_outlined,
                    color: colors.markInk,
                    size: 18,
                  ),
                  onTap: () => _showEditProfileDialog(colors),
                ),
              ],
            ),
            _buildSectionHeader("ВНЕШНИЙ ВИД", colors),
            const ThemeModeSelector(),
            _buildSectionHeader("ЗАПИСЬ", colors),
            _buildGroupCard(
              colors: colors,
              children: [
                _buildRowItem(
                  colors: colors,
                  icon: Icons.location_on_outlined,
                  title: "Геопозиция в фоне",
                  subtitle: "Разрешена",
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: colors.s1Soft,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      "ВКЛ",
                      style: TextStyle(
                        fontFamily: AppTheme.fontUi,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: colors.s1,
                      ),
                    ),
                  ),
                ),
                _buildRowItem(
                  colors: colors,
                  icon: Icons.speed_rounded,
                  title: "Порог записи",
                  subtitle: "20 км/ч · рекомендованный",
                  trailing: Icon(
                    Icons.chevron_right_rounded,
                    color: colors.ink3,
                    size: 20,
                  ),
                ),
              ],
            ),
            _buildSectionHeader("ОПАСНАЯ ЗОНА", colors),
            _buildGroupCard(
              colors: colors,
              children: [
                _buildRowItem(
                  colors: colors,
                  icon: Icons.logout_rounded,
                  title: "Выйти",
                  subtitle: "Найденные дефекты останутся на карте",
                  onTap: _handleLogout,
                ),
                _buildRowItem(
                  colors: colors,
                  icon: Icons.delete_outline_rounded,
                  iconColor: colors.s3,
                  iconBg: colors.s3Soft,
                  title: "Удалить аккаунт",
                  titleColor: colors.s3,
                  subtitle:
                      "Номер и профиль стираются, дефекты станут анонимными",
                  onTap: () => _handleDeleteAccount(colors),
                ),
              ],
            ),
            const SizedBox(height: 28),
            Center(
              child: Text(
                _appVersionString,
                style: TextStyle(
                  fontFamily: AppTheme.fontMono,
                  fontSize: 11.5,
                  color: colors.ink3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, PolotnoColors colors) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 26, 0, 10),
      child: Text(
        title,
        style: TextStyle(
          fontFamily: AppTheme.fontMono,
          fontSize: 10,
          fontWeight: FontWeight.w500,
          letterSpacing: 1.5,
          color: colors.ink3,
        ),
      ),
    );
  }

  Widget _buildGroupCard({
    required PolotnoColors colors,
    required List<Widget> children,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: colors.surf,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.edge2),
      ),
      child: Column(
        children: List.generate(children.length, (index) {
          final isLast = index == children.length - 1;
          return Column(
            children: [
              children[index],
              if (!isLast) Divider(color: colors.edge2, height: 1),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildRowItem({
    required PolotnoColors colors,
    required IconData icon,
    Color? iconColor,
    Color? iconBg,
    required String title,
    Color? titleColor,
    required String subtitle,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: iconBg ?? colors.surf2,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, color: iconColor ?? colors.ink2, size: 18),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontFamily: AppTheme.fontUi,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: titleColor ?? colors.ink,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontFamily: AppTheme.fontUi,
                      fontSize: 12.5,
                      color: colors.ink2,
                    ),
                  ),
                ],
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}