import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import 'reveal.dart';

/// Каркас экранов настроек, перенесённый из Togetherly.
///
/// Подпись раздела капсом → группа блоков → блок с круглым значком, заголовком
/// и подписью. Каждый пункт лежит своим блоком, между блоками зазор, внешние
/// углы группы скруглены сильнее внутренних. Новый пункт добавляется ещё одним
/// [SettingsRow] в нужную [SettingsGroup], и вид остаётся единым.
///
/// ```dart
/// SettingsPage(
///   title: tr('set_group_tracking'),
///   children: [
///     SettingsGroup([
///       SettingsSwitchRow(
///         icon: Icons.playlist_add_check_rounded,
///         title: tr('seq_mode'),
///         value: seq,
///         onChanged: setSeq,
///       ),
///     ]),
///   ],
/// )
/// ```

/// Экран настроек: заголовок по центру и прокручиваемый список групп.
class SettingsPage extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const SettingsPage({super.key, required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          4,
          16,
          MediaQuery.of(context).padding.bottom + 32,
        ),
        children: children,
      ),
    );
  }
}

/// Подпись раздела: капс, Onest 12/700, разрядка 1,1, акцентный цвет.
///
/// Значок без подложки. Круглая подложка есть только у строк, у подписи её
/// не заводить.
class SettingsSection extends StatelessWidget {
  final String title;
  final IconData? icon;

  /// Цвет подписи; по умолчанию `primary`, для опасных разделов `error`.
  final Color? color;

  const SettingsSection(this.title, {super.key, this.icon, this.color});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tint = color ?? scheme.primary;
    final label = Text(
      title.toUpperCase(),
      style: TextStyle(
        fontFamily: AppTheme.bodyFont,
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.1,
        color: tint,
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 24, 8, 10),
      child: icon == null
          ? label
          : Row(
              children: [
                Icon(icon, size: 18, color: tint),
                const SizedBox(width: 10),
                Expanded(child: label),
              ],
            ),
    );
  }
}

/// Группа настроек: каждый пункт — свой блок, блоки разделены зазором.
///
/// Форму блока задаёт его место: первому большой верх, последнему большой
/// низ, средним малый радиус со всех сторон. Единственный пункт скруглён
/// целиком. Заливка лежит на самом блоке, у группы её нет.
class SettingsGroup extends StatelessWidget {
  final List<Widget> children;

  const SettingsGroup(this.children, {super.key});

  static const double outerRadius = 28;
  static const double innerRadius = 8;
  static const double gap = 4;

  /// Шаг каскада при появлении блоков.
  static const Duration _step = Duration(milliseconds: 35);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const outer = Radius.circular(outerRadius);
    const inner = Radius.circular(innerRadius);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(height: gap),
          Reveal(
            delay: _step * (i < 8 ? i : 8),
            child: Material(
              color: scheme.surfaceContainerHigh,
              clipBehavior: Clip.antiAlias,
              borderRadius: BorderRadius.vertical(
                top: i == 0 ? outer : inner,
                bottom: i == children.length - 1 ? outer : inner,
              ),
              child: children[i],
            ),
          ),
        ],
      ],
    );
  }
}

/// Круглый значок строки: 44, подложка `primaryContainer`.
class SettingsIconChip extends StatelessWidget {
  final IconData icon;
  final Color? bg;
  final Color? fg;

  const SettingsIconChip(this.icon, {super.key, this.bg, this.fg});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg ?? scheme.primaryContainer,
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 22, color: fg ?? scheme.onPrimaryContainer),
    );
  }
}

/// Строка настроек: круглый значок, заголовок с подписью и трейлинг.
///
/// Вместо значка можно передать [leading]: аватар в строке аккаунта, превью
/// иконки приложения.
class SettingsRow extends StatelessWidget {
  final IconData? icon;
  final Widget? leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? iconBg;
  final Color? iconFg;

  /// Цвет заголовка; для опасных строк `error`.
  final Color? titleColor;

  const SettingsRow({
    super.key,
    this.icon,
    this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.iconBg,
    this.iconFg,
    this.titleColor,
  }) : assert(icon != null || leading != null);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            leading ?? SettingsIconChip(icon!, bg: iconBg, fg: iconFg),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontFamily: AppTheme.bodyFont,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      height: 1.25,
                      color: titleColor ?? scheme.onSurface,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: TextStyle(
                        fontFamily: AppTheme.bodyFont,
                        fontSize: 13,
                        height: 1.3,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 12), trailing!],
          ],
        ),
      ),
    );
  }
}

/// Строка с тумблером: тап по всей строке переключает его.
class SettingsSwitchRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  const SettingsSwitchRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final change = onChanged;
    return SettingsRow(
      icon: icon,
      title: title,
      subtitle: subtitle,
      trailing: Switch(value: value, onChanged: change),
      onTap: change == null
          ? null
          : () {
              HapticFeedback.selectionClick();
              change(!value);
            },
    );
  }
}

/// Стрелка перехода, чтобы не повторять её у каждой строки.
class SettingsChevron extends StatelessWidget {
  const SettingsChevron({super.key});

  @override
  Widget build(BuildContext context) => Icon(
    Icons.chevron_right_rounded,
    color: Theme.of(context).colorScheme.outline,
  );
}
