import 'package:flutter/material.dart';
import '../app_theme.dart';
import 'auth_screen.dart';

class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Scaffold(
      backgroundColor: colors.voidBg,
      body: SafeArea(
        child: ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
          children: [
            // Кнопка «Назад»
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
                  child: Icon(Icons.arrow_back_rounded, color: colors.ink, size: 18),
                ),
              ),
            ),
            const SizedBox(height: 22),

            // Заголовок
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

            // Секция «ВХОД»
            _buildSectionHeader("ВХОД", colors),
            _buildGroupCard(
              colors: colors,
              children: [
                _buildRowItem(
                  colors: colors,
                  icon: Icons.phone_android_rounded,
                  title: "+7 999 123-45-67",
                  subtitle: "Номер подтверждён",
                  trailing: Icon(Icons.chevron_right_rounded, color: colors.ink3, size: 20),
                ),
                _buildRowItem(
                  colors: colors,
                  icon: Icons.person_outline_rounded,
                  title: "Алексей Козлов",
                  subtitle: "Имя, город, машина",
                  trailing: Icon(Icons.chevron_right_rounded, color: colors.ink3, size: 20),
                ),
              ],
            ),

            // Секция «ЗАПИСЬ»
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
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
                  trailing: Icon(Icons.chevron_right_rounded, color: colors.ink3, size: 20),
                ),
              ],
            ),

            // Секция «ОПАСНАЯ ЗОНА»
            _buildSectionHeader("ОПАСНАЯ ЗОНА", colors),
            _buildGroupCard(
              colors: colors,
              children: [
                _buildRowItem(
                  colors: colors,
                  icon: Icons.logout_rounded,
                  title: "Выйти",
                  subtitle: "Найденные дефекты останутся на карте",
                  onTap: () {
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(builder: (_) => const AuthScreen()),
                      (route) => false,
                    );
                  },
                ),
                _buildRowItem(
                  colors: colors,
                  icon: Icons.delete_outline_rounded,
                  iconColor: colors.s3,
                  iconBg: colors.s3Soft,
                  title: "Удалить аккаунт",
                  titleColor: colors.s3,
                  subtitle: "Номер и профиль стираются, дефекты станут анонимными",
                  onTap: () {
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(builder: (_) => const AuthScreen()),
                      (route) => false,
                    );
                  },
                ),
              ],
            ),

            const SizedBox(height: 28),
            Center(
              child: Text(
                "EasyRide 2.0 · сборка 204",
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