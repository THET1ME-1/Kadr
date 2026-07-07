import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/strings.dart';
import '../../services/social/social_api.dart';
import '../../services/social/social_controller.dart';
import '../../theme/app_theme.dart';
import 'auth_screen.dart';

/// Показывает код восстановления (после регистрации/сброса/перегенерации).
/// Требует явного «Я сохранил», чтобы пользователь не проскочил.
Future<void> showRecoveryCodeSheet(BuildContext context, String code,
    {bool isNew = false}) {
  final scheme = Theme.of(context).colorScheme;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    backgroundColor: scheme.surfaceContainer,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(Icons.vpn_key_rounded, size: 40, color: scheme.primary),
            const SizedBox(height: 14),
            Text(tr('recovery_title'),
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontFamily: AppTheme.displayFont,
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                    color: scheme.onSurface)),
            const SizedBox(height: 8),
            Text(tr('recovery_save_hint'),
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    fontSize: 13.5,
                    height: 1.35,
                    color: scheme.onSurfaceVariant)),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: () {
                Clipboard.setData(ClipboardData(text: code));
                ScaffoldMessenger.of(ctx)
                  ..clearSnackBars()
                  ..showSnackBar(SnackBar(
                      content: Text(tr('recovery_copied')),
                      behavior: SnackBarBehavior.floating));
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
                decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(18)),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(code,
                        style: TextStyle(
                            fontFamily: AppTheme.displayFont,
                            fontWeight: FontWeight.w800,
                            fontSize: 24,
                            letterSpacing: 2,
                            color: scheme.onPrimaryContainer)),
                    const SizedBox(width: 10),
                    Icon(Icons.copy_rounded,
                        size: 20, color: scheme.onPrimaryContainer),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14)),
              child: Text(tr('recovery_saved'),
                  style: const TextStyle(
                      fontFamily: AppTheme.displayFont,
                      fontWeight: FontWeight.w700,
                      fontSize: 15)),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Экран сброса пароля по коду восстановления: email + код + новый пароль.
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _email = TextEditingController();
  final _code = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    final email = _email.text.trim();
    final code = _code.text.trim();
    final pass = _password.text;
    if (!email.contains('@')) {
      setState(() => _error = tr('social_err_email'));
      return;
    }
    if (code.isEmpty) {
      setState(() => _error = tr('reset_err_code'));
      return;
    }
    if (pass.length < 8) {
      setState(() => _error = tr('social_err_weak'));
      return;
    }
    setState(() => _busy = true);
    try {
      final newCode = await SocialController.instance
          .resetPassword(email: email, recoveryCode: code, newPassword: pass);
      if (!mounted) return;
      // Показать НОВЫЙ код восстановления, затем закрыть экран (уже вошли).
      if (newCode != null && newCode.isNotEmpty) {
        await showRecoveryCodeSheet(context, newCode, isNew: true);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        _error = e is SocialException && e.code == 'invalid_recovery'
            ? tr('reset_err_invalid')
            : socialErrorText(e);
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(tr('reset_title'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          Text(tr('reset_hint'),
              style: TextStyle(
                  fontFamily: AppTheme.bodyFont,
                  fontSize: 13.5,
                  height: 1.35,
                  color: scheme.onSurfaceVariant)),
          const SizedBox(height: 20),
          _field(_email, 'Email', Icons.alternate_email_rounded,
              keyboardType: TextInputType.emailAddress),
          const SizedBox(height: 14),
          _field(_code, tr('reset_code'), Icons.vpn_key_rounded,
              caps: true),
          const SizedBox(height: 14),
          _field(_password, tr('reset_new_password'), Icons.lock_rounded,
              obscure: _obscure,
              suffix: IconButton(
                icon: Icon(_obscure
                    ? Icons.visibility_rounded
                    : Icons.visibility_off_rounded),
                onPressed: () => setState(() => _obscure = !_obscure),
              )),
          if (_error != null) ...[
            const SizedBox(height: 14),
            Text(_error!,
                style: TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    fontSize: 13,
                    color: scheme.error)),
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
                : Text(tr('reset_submit'),
                    style: const TextStyle(
                        fontFamily: AppTheme.displayFont,
                        fontWeight: FontWeight.w700,
                        fontSize: 15)),
          ),
        ],
      ),
    );
  }

  Widget _field(TextEditingController c, String label, IconData icon,
      {bool obscure = false,
      bool caps = false,
      TextInputType? keyboardType,
      Widget? suffix}) {
    return TextField(
      controller: c,
      obscureText: obscure,
      keyboardType: keyboardType,
      textCapitalization:
          caps ? TextCapitalization.characters : TextCapitalization.none,
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
