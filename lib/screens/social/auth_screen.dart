import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../services/social/social_api.dart';
import '../../services/social/social_controller.dart';
import '../../theme/app_theme.dart';

/// Понятный текст ошибки соц-слоя по её коду.
String socialErrorText(Object e) {
  if (e is SocialException) {
    return tr(switch (e.code) {
      'email_taken' => 'social_err_email_taken',
      'invalid_credentials' => 'social_err_credentials',
      'weak_password' => 'social_err_weak',
      'invalid_email' => 'social_err_email',
      'invalid_name' => 'social_err_name',
      'rate_limited' => 'social_err_rate',
      'user_not_found' => 'social_err_user_not_found',
      'network' => 'social_err_network',
      _ => 'social_err_generic',
    });
  }
  return tr('social_err_generic');
}

/// Вход и регистрация профиля Kadr (email + пароль). Аватар и ник настраиваются
/// на экране профиля после входа. При успехе — pop.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool _register = true;
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    final pass = _password.text;
    final name = _name.text.trim();
    setState(() => _error = null);
    if (!email.contains('@') || !email.contains('.')) {
      setState(() => _error = tr('social_err_email'));
      return;
    }
    if (pass.length < 8) {
      setState(() => _error = tr('social_err_weak'));
      return;
    }
    if (_register && name.isEmpty) {
      setState(() => _error = tr('social_err_name'));
      return;
    }
    setState(() => _busy = true);
    try {
      final ctl = SocialController.instance;
      if (_register) {
        await ctl.register(email: email, password: pass, displayName: name);
      } else {
        await ctl.login(email: email, password: pass);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _error = socialErrorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(_register ? tr('social_register') : tr('social_login')),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          // Заголовок-герой.
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [scheme.primary, scheme.tertiary],
              ),
              borderRadius: BorderRadius.circular(26),
            ),
            child: Row(
              children: [
                Icon(Icons.group_rounded,
                    color: Colors.white.withValues(alpha: 0.95), size: 34),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(tr('social_intro'),
                      style: const TextStyle(
                          fontFamily: AppTheme.bodyFont,
                          fontWeight: FontWeight.w600,
                          fontSize: 13.5,
                          height: 1.3,
                          color: Colors.white)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          // Переключатель Вход / Регистрация.
          _toggle(scheme),
          const SizedBox(height: 20),
          if (_register) ...[
            _field(_name, tr('social_name'), Icons.badge_rounded,
                textInputAction: TextInputAction.next),
            const SizedBox(height: 14),
          ],
          _field(_email, 'Email', Icons.alternate_email_rounded,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next),
          const SizedBox(height: 14),
          _field(_password, tr('social_password'), Icons.lock_rounded,
              obscure: _obscure,
              textInputAction: TextInputAction.done,
              onSubmit: (_) => _submit(),
              suffix: IconButton(
                icon: Icon(_obscure
                    ? Icons.visibility_rounded
                    : Icons.visibility_off_rounded),
                onPressed: () => setState(() => _obscure = !_obscure),
              )),
          if (_error != null) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Icon(Icons.error_outline_rounded,
                    size: 18, color: scheme.error),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(_error!,
                      style: TextStyle(
                          fontFamily: AppTheme.bodyFont,
                          fontSize: 13,
                          color: scheme.error)),
                ),
              ],
            ),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy ? null : _submit,
            style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 15)),
            child: _busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.4))
                : Text(_register ? tr('social_register') : tr('social_login'),
                    style: const TextStyle(
                        fontFamily: AppTheme.displayFont,
                        fontWeight: FontWeight.w700,
                        fontSize: 15)),
          ),
        ],
      ),
    );
  }

  Widget _toggle(ColorScheme scheme) {
    Widget seg(bool reg, String label) {
      final selected = _register == reg;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() {
            _register = reg;
            _error = null;
          }),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(vertical: 11),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? scheme.primaryContainer : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(label,
                style: TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: selected
                        ? scheme.onPrimaryContainer
                        : scheme.onSurfaceVariant)),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(20)),
      child: Row(
        children: [
          seg(true, tr('social_register')),
          seg(false, tr('social_login')),
        ],
      ),
    );
  }

  Widget _field(TextEditingController c, String label, IconData icon,
      {bool obscure = false,
      TextInputType? keyboardType,
      TextInputAction? textInputAction,
      Widget? suffix,
      ValueChanged<String>? onSubmit}) {
    return TextField(
      controller: c,
      obscureText: obscure,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      onSubmitted: onSubmit,
      style: const TextStyle(fontFamily: AppTheme.bodyFont),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        suffixIcon: suffix,
        filled: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
