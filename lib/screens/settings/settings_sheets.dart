import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../l10n/locale_controller.dart';
import '../../l10n/strings.dart';
import '../../services/movie_repository.dart';
import '../../services/update_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/update_sheet.dart';

/// Вариант в листе выбора: значок или свой [leading], подпись и пояснение.
class ChoiceOption<T> {
  final T value;
  final String label;
  final String? subtitle;
  final IconData? icon;
  final Widget? leading;

  const ChoiceOption({
    required this.value,
    required this.label,
    this.subtitle,
    this.icon,
    this.leading,
  });
}

/// Нижняя панель выбора одного варианта: ручка, заголовок, пояснение и список
/// с галочкой у текущего. Панель закрывается до [onPick], поэтому обработчик
/// может показывать снекбар или ждать сеть.
Future<void> showChoiceSheet<T>(
  BuildContext context, {
  required String title,
  String? hint,
  required List<ChoiceOption<T>> options,
  required T selected,
  required void Function(T value) onPick,
}) {
  final scheme = Theme.of(context).colorScheme;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: scheme.surfaceContainer,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(ctx).size.height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 12),
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
              child: Text(
                title,
                style: TextStyle(
                  fontFamily: AppTheme.displayFont,
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                  color: scheme.onSurface,
                ),
              ),
            ),
            if (hint != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 10),
                child: Text(
                  hint,
                  style: TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    fontSize: 13,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final o in options)
                    ListTile(
                      leading:
                          o.leading ?? (o.icon == null ? null : Icon(o.icon)),
                      title: Text(
                        o.label,
                        style: const TextStyle(
                          fontFamily: AppTheme.bodyFont,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: o.subtitle == null ? null : Text(o.subtitle!),
                      trailing: o.value == selected
                          ? Icon(
                              Icons.check_circle_rounded,
                              color: scheme.primary,
                            )
                          : null,
                      onTap: () {
                        Navigator.pop(ctx);
                        onPick(o.value);
                      },
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    ),
  );
}

/// Название текущего языка на нём самом.
String currentLanguageName() {
  final code = LocaleController.instance.code;
  for (final l in LocaleController.languages) {
    if (l.code == code) return l.nativeName;
  }
  return code;
}

/// Лист выбора языка. После смены названия в библиотеке переводятся заново.
Future<void> pickLanguage(BuildContext context) {
  final locale = LocaleController.instance;
  return showChoiceSheet<String>(
    context,
    title: tr('language'),
    selected: locale.code,
    options: [
      for (final l in LocaleController.languages)
        ChoiceOption(value: l.code, label: l.nativeName),
    ],
    onPick: (code) {
      // setCode меняет код синхронно (сохранение идёт в фоне), поэтому
      // пере-локализация ниже уже видит новый язык.
      locale.setCode(code);
      MovieRepository.instance.relocalizeTitlesSweep();
    },
  );
}

/// Ручная проверка обновления: меню обновления или «последняя версия».
Future<void> checkForUpdates(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  void say(String key) => messenger
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(content: Text(tr(key)), behavior: SnackBarBehavior.floating),
    );

  say('checking_updates');
  final current = (await PackageInfo.fromPlatform()).version;
  try {
    final info = await UpdateService.checkForUpdate(current);
    if (!context.mounted) return;
    if (info == null) {
      say('up_to_date');
    } else {
      messenger.clearSnackBars();
      await UpdateSheet.show(context, info, current);
    }
  } catch (_) {
    if (context.mounted) say('update_check_failed');
  }
}

/// Короткое сообщение внизу экрана.
void showSettingsSnack(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
    );
}
