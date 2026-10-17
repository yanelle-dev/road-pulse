import 'dart:async';

import 'package:flutter/material.dart';

import '../api_service.dart';
import '../app_theme.dart';
import '../main_scaffold.dart';

enum AuthStep { start, phone, code, codeError, name, access }

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  AuthStep _step = AuthStep.start;

  String _phoneDigits = "";
  String _codeDigits = "";
  String? _devCode;
  int _resendTimerSeconds = 60;
  Timer? _resendTimer;
  bool _isLoading = false;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _cityController = TextEditingController();
  final TextEditingController _clearanceController = TextEditingController();

  @override
  void dispose() {
    _resendTimer?.cancel();
    _nameController.dispose();
    _cityController.dispose();
    _clearanceController.dispose();
    super.dispose();
  }

  void _startTimer() {
    _resendTimer?.cancel();
    setState(() => _resendTimerSeconds = 60);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_resendTimerSeconds <= 1) {
        timer.cancel();
        setState(() => _resendTimerSeconds = 0);
      } else {
        setState(() => _resendTimerSeconds--);
      }
    });
  }

  Future<void> _handleRequestCode() async {
    setState(() => _isLoading = true);
    final phone = "+7$_phoneDigits";
    final code = await ApiService.requestCode(phone);
    setState(() => _isLoading = false);

    if (code != null) {
      _startTimer();
      setState(() {
        _devCode = code.isNotEmpty ? code : null;
        _codeDigits = "";
        _step = AuthStep.code;
      });
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Ошибка отправки запроса. Проверьте сеть."),
        ),
      );
    }
  }

  Future<void> _handleVerifyCode(String code) async {
    setState(() => _isLoading = true);
    final phone = "+7$_phoneDigits";
    final result = await ApiService.verifyCode(phone, code);
    setState(() => _isLoading = false);

    if (!mounted) return;

    if (result.success) {
      if (result.isNewUser) {
        setState(() => _step = AuthStep.name);
      } else {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const MainScaffold()),
          (route) => false,
        );
      }
    } else {
      setState(() => _step = AuthStep.codeError);
    }
  }

  Future<void> _handleSaveProfileAndContinue() async {
    final name = _nameController.text.trim();
    final city = _cityController.text.trim();
    final clearanceText = _clearanceController.text.trim();

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Пожалуйста, укажите ваше имя")),
      );
      return;
    }

    if (city.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Пожалуйста, укажите ваш город")),
      );
      return;
    }

    final clearance = int.tryParse(clearanceText) ?? 0;

    await ApiService.updateProfile(
      name: name,
      city: city,
      clearance: clearance,
    );
    if (!mounted) return;
    setState(() => _step = AuthStep.access);
  }

  void _onKeyPress(String key) {
    if (_isLoading) return;

    if (_step == AuthStep.phone) {
      if (key == 'del') {
        if (_phoneDigits.isNotEmpty) {
          setState(
            () => _phoneDigits = _phoneDigits.substring(
              0,
              _phoneDigits.length - 1,
            ),
          );
        }
      } else if (_phoneDigits.length < 10) {
        setState(() => _phoneDigits += key);
      }
    } else if (_step == AuthStep.code || _step == AuthStep.codeError) {
      if (key == 'del') {
        if (_codeDigits.isNotEmpty) {
          setState(() {
            _codeDigits = _codeDigits.substring(0, _codeDigits.length - 1);
            if (_step == AuthStep.codeError) _step = AuthStep.code;
          });
        }
      } else if (_codeDigits.length < 4) {
        setState(() => _codeDigits += key);
        if (_codeDigits.length == 4) {
          _handleVerifyCode(_codeDigits);
        }
      }
    }
  }

  String _formatPhone(String raw) {
    String res = "";
    const mask = "(###) ###-##-##";
    int di = 0;
    for (int i = 0; i < mask.length; i++) {
      if (mask[i] == '#') {
        if (di < raw.length) {
          res += raw[di++];
        } else {
          break;
        }
      } else {
        if (di >= raw.length && di > 0) break;
        res += mask[i];
      }
    }
    return res;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Scaffold(
      backgroundColor: colors.voidBg,
      body: SafeArea(
        child: switch (_step) {
          AuthStep.start => _buildStartStep(colors),
          AuthStep.phone => _buildPhoneStep(colors),
          AuthStep.code || AuthStep.codeError => _buildCodeStep(colors),
          AuthStep.name => _buildNameStep(colors),
          AuthStep.access => _buildAccessStep(colors),
        },
      ),
    );
  }

  Widget _buildStartStep(PolotnoColors colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Spacer(),
          Container(
            width: 74,
            height: 6,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              gradient: const LinearGradient(
                colors: [Color(0xFFFFD21E), Color(0xFF101113)],
                stops: [0.5, 0.5],
                tileMode: TileMode.repeated,
              ),
            ),
          ),
          const SizedBox(height: 28),
          Text(
            "Дорога\nпишется\nсама",
            style: TextStyle(
              fontFamily: AppTheme.fontDisplay,
              fontSize: 40,
              fontWeight: FontWeight.w800,
              color: colors.ink,
              height: 0.98,
              letterSpacing: -1.5,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            "Общая карта ям, которую строят водители. Чтобы ваш вклад засчитывался, нужен номер телефона — больше ничего.",
            style: TextStyle(
              fontFamily: AppTheme.fontUi,
              fontSize: 15.5,
              color: colors.ink2,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 36),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
              backgroundColor: colors.mark,
              foregroundColor: colors.onMark,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
            onPressed: () => setState(() => _step = AuthStep.phone),
            child: Text(
              "Войти по номеру",
              style: TextStyle(
                fontFamily: AppTheme.fontUi,
                fontSize: 16.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Center(
            child: Text(
              "Продолжая, вы принимаете условия и политику",
              style: TextStyle(
                fontFamily: AppTheme.fontUi,
                fontSize: 11.5,
                color: colors.ink3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhoneStep(PolotnoColors colors) {
    final formatted = _formatPhone(_phoneDigits);
    final bool canProceed = _phoneDigits.length == 10 && !_isLoading;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildBackButton(
                colors,
                () => setState(() => _step = AuthStep.start),
              ),
              const SizedBox(height: 20),
              Text(
                "Ваш номер\nтелефона",
                style: TextStyle(
                  fontFamily: AppTheme.fontDisplay,
                  fontSize: 31,
                  fontWeight: FontWeight.w800,
                  color: colors.ink,
                  height: 1.05,
                  letterSpacing: -1.0,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                "Отправим короткий код в SMS. Номер виден только вам — в приложении отображается только имя.",
                style: TextStyle(
                  fontFamily: AppTheme.fontUi,
                  fontSize: 14,
                  color: colors.ink2,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 24),
              Container(
                height: 62,
                decoration: BoxDecoration(
                  color: colors.surf,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: canProceed ? colors.mark : colors.edge,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        border: Border(right: BorderSide(color: colors.edge2)),
                      ),
                      child: Row(
                        children: [
                          const Text("🇷🇺 ", style: TextStyle(fontSize: 16)),
                          Text(
                            "+7",
                            style: TextStyle(
                              fontFamily: AppTheme.fontUi,
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              color: colors.ink,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          formatted.isEmpty ? "(999) 000-00-00" : formatted,
                          style: TextStyle(
                            fontFamily: AppTheme.fontMono,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: formatted.isEmpty ? colors.ink3 : colors.ink,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                  backgroundColor: canProceed ? colors.mark : colors.surf2,
                  foregroundColor: canProceed ? colors.onMark : colors.ink3,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                onPressed: canProceed ? _handleRequestCode : null,
                child: _isLoading
                    ? SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: colors.onMark,
                        ),
                      )
                    : Text(
                        "Получить код",
                        style: TextStyle(
                          fontFamily: AppTheme.fontUi,
                          fontSize: 16.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ],
          ),
        ),
        const Spacer(),
        _buildKeypad(colors),
      ],
    );
  }

  Widget _buildCodeStep(PolotnoColors colors) {
    final bool isError = _step == AuthStep.codeError;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildBackButton(
                colors,
                () => setState(() => _step = AuthStep.phone),
              ),
              const SizedBox(height: 20),
              Text(
                "Код из SMS",
                style: TextStyle(
                  fontFamily: AppTheme.fontDisplay,
                  fontSize: 31,
                  fontWeight: FontWeight.w800,
                  color: colors.ink,
                  letterSpacing: -1.0,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "Отправили на +7 ${_formatPhone(_phoneDigits)}",
                style: TextStyle(
                  fontFamily: AppTheme.fontUi,
                  fontSize: 14.5,
                  color: colors.ink2,
                ),
              ),
              if (_devCode != null) ...[
                const SizedBox(height: 14),
                InkWell(
                  onTap: () {
                    setState(() => _codeDigits = _devCode!);
                    _handleVerifyCode(_devCode!);
                  },
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: colors.surf,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: colors.mark, width: 1.5),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.vpn_key_rounded,
                          size: 16,
                          color: colors.markInk,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          "Тестовый код: $_devCode (нажмите)",
                          style: TextStyle(
                            fontFamily: AppTheme.fontMono,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: colors.ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 22),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(4, (index) {
                  final String char = index < _codeDigits.length
                      ? _codeDigits[index]
                      : "";
                  final bool isFilled = index < _codeDigits.length;

                  return Container(
                    width: 68,
                    height: 68,
                    decoration: BoxDecoration(
                      color: colors.surf,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: isError
                            ? colors.s3
                            : (isFilled ? colors.mark : colors.edge),
                        width: 1.5,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: _isLoading && isFilled && index == 3
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: colors.mark,
                            ),
                          )
                        : Text(
                            char,
                            style: TextStyle(
                              fontFamily: AppTheme.fontDisplay,
                              fontSize: 28,
                              fontWeight: FontWeight.w700,
                              color: isError ? colors.s3 : colors.ink,
                            ),
                          ),
                  );
                }),
              ),
              if (isError) ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    Icon(
                      Icons.error_outline_rounded,
                      color: colors.s3,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        "Неверный код. Введите актуальный код подтверждения",
                        style: TextStyle(
                          fontFamily: AppTheme.fontUi,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: colors.s3,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: () => setState(() => _step = AuthStep.phone),
                    child: Text(
                      "Изменить номер",
                      style: TextStyle(
                        fontFamily: AppTheme.fontUi,
                        fontWeight: FontWeight.w600,
                        color: colors.markInk,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _resendTimerSeconds == 0 && !_isLoading
                        ? _handleRequestCode
                        : null,
                    child: Text(
                      _resendTimerSeconds == 0
                          ? "Отправить снова"
                          : "Отправить снова · 0:${_resendTimerSeconds.toString().padLeft(2, '0')}",
                      style: TextStyle(
                        fontFamily: AppTheme.fontUi,
                        fontWeight: FontWeight.w600,
                        color: _resendTimerSeconds == 0
                            ? colors.markInk
                            : colors.ink3,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const Spacer(),
        _buildKeypad(colors),
      ],
    );
  }

  Widget _buildNameStep(PolotnoColors colors) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          Text(
            "Как к вам\nобращаться?",
            style: TextStyle(
              fontFamily: AppTheme.fontDisplay,
              fontSize: 31,
              fontWeight: FontWeight.w800,
              color: colors.ink,
              height: 1.05,
              letterSpacing: -1.0,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            "Имя и город обязательны. Клиренс машины можно указать позже.",
            style: TextStyle(
              fontFamily: AppTheme.fontUi,
              fontSize: 14.5,
              color: colors.ink2,
            ),
          ),
          const SizedBox(height: 24),
          _buildEditableInputTile(
            colors: colors,
            icon: Icons.person_outline_rounded,
            controller: _nameController,
            hint: "Ваше имя (обязательно)",
          ),
          const SizedBox(height: 12),
          _buildEditableInputTile(
            colors: colors,
            icon: Icons.location_on_outlined,
            controller: _cityController,
            hint: "Город (обязательно, например, Москва)",
          ),
          const SizedBox(height: 12),
          _buildEditableInputTile(
            colors: colors,
            icon: Icons.directions_car_outlined,
            controller: _clearanceController,
            hint: "Клиренс машины в мм (не обязательно)",
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 14),
          Text(
            "Если клиренс не указан, приложение использует стандартную оценку качества покрытия.",
            style: TextStyle(
              fontFamily: AppTheme.fontUi,
              fontSize: 12.5,
              color: colors.ink3,
            ),
          ),
          const SizedBox(height: 36),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
              backgroundColor: colors.mark,
              foregroundColor: colors.onMark,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
            onPressed: _handleSaveProfileAndContinue,
            child: Text(
              "Продолжить",
              style: TextStyle(
                fontFamily: AppTheme.fontUi,
                fontSize: 16.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildAccessStep(PolotnoColors colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Spacer(),
          Container(
            width: 74,
            height: 6,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              gradient: const LinearGradient(
                colors: [Color(0xFFFFD21E), Color(0xFF101113)],
                stops: [0.5, 0.5],
                tileMode: TileMode.repeated,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            "Последний\nшаг",
            style: TextStyle(
              fontFamily: AppTheme.fontDisplay,
              fontSize: 36,
              fontWeight: FontWeight.w800,
              color: colors.ink,
              height: 1.0,
              letterSpacing: -1.0,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            "Чтобы записывать дорогу, приложению нужны два доступа. Оба можно отозвать в любой момент.",
            style: TextStyle(
              fontFamily: AppTheme.fontUi,
              fontSize: 15,
              color: colors.ink2,
            ),
          ),
          const SizedBox(height: 26),
          _buildAccessItem(
            colors,
            Icons.location_on_outlined,
            "Геопозиция, в том числе в фоне",
            "Чтобы привязать удар к точке дороги, а не к моменту времени",
          ),
          Divider(color: colors.edge2, height: 26),
          _buildAccessItem(
            colors,
            Icons.show_chart_rounded,
            "Акселерометр",
            "Читаем только вибрацию корпуса. Ни камеры, ни микрофона",
          ),
          Divider(color: colors.edge2, height: 26),
          _buildAccessItem(
            colors,
            Icons.shield_outlined,
            "Только карта дефектов",
            "Маршруты не сохраняются, номер не показывается другим",
          ),
          const Spacer(),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
              backgroundColor: colors.mark,
              foregroundColor: colors.onMark,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
            onPressed: () {
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const MainScaffold()),
                (route) => false,
              );
            },
            child: Text(
              "Разрешить и поехали",
              style: TextStyle(
                fontFamily: AppTheme.fontUi,
                fontSize: 16.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              "Без геопозиции карта работает, но запись — нет",
              style: TextStyle(
                fontFamily: AppTheme.fontUi,
                fontSize: 11.5,
                color: colors.ink3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackButton(PolotnoColors colors, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
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
    );
  }

  Widget _buildEditableInputTile({
    required PolotnoColors colors,
    required IconData icon,
    required TextEditingController controller,
    required String hint,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: colors.surf,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: colors.edge),
      ),
      child: Row(
        children: [
          Icon(icon, color: colors.ink3, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType: keyboardType,
              style: TextStyle(
                fontFamily: AppTheme.fontUi,
                fontSize: 15.5,
                fontWeight: FontWeight.w600,
                color: colors.ink,
              ),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: TextStyle(
                  fontFamily: AppTheme.fontUi,
                  fontSize: 14.5,
                  color: colors.ink3,
                ),
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccessItem(
    PolotnoColors colors,
    IconData icon,
    String title,
    String desc,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: colors.surf2,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(icon, color: colors.markInk, size: 18),
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
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: colors.ink,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                desc,
                style: TextStyle(
                  fontFamily: AppTheme.fontUi,
                  fontSize: 12.5,
                  color: colors.ink2,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildKeypad(PolotnoColors colors) {
    final keys = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['', '0', 'del'],
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 26),
      child: Column(
        children: keys.map((row) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: Row(
              children: row.map((k) {
                if (k.isEmpty) {
                  return const Expanded(child: SizedBox(height: 54));
                }

                return Expanded(
                  child: Container(
                    height: 54,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colors.surf,
                        foregroundColor: colors.ink,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(color: colors.edge2),
                        ),
                      ),
                      onPressed: () => _onKeyPress(k),
                      child: k == 'del'
                          ? Icon(
                              Icons.backspace_outlined,
                              size: 20,
                              color: colors.ink,
                            )
                          : Text(
                              k,
                              style: TextStyle(
                                fontFamily: AppTheme.fontDisplay,
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                    ),
                  ),
                );
              }).toList(),
            ),
          );
        }).toList(),
      ),
    );
  }
}