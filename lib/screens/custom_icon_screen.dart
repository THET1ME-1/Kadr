import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../services/app_icon_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_icon_preview.dart';
import '../widgets/color_picker_sheet.dart';

/// «Своя иконка»: любые цвета фона и знака → ярлык на рабочем столе.
///
/// ВАЖНО (и об этом честно сказано на экране): это НЕ смена иконки приложения.
/// Android разрешает произвольную картинку только ярлыкам — launcher-иконка
/// обязана лежать в APK, поэтому готовые колеровки живут отдельным списком
/// (Настройки → Оформление → Иконка приложения).
class CustomIconScreen extends StatefulWidget {
  const CustomIconScreen({super.key});

  @override
  State<CustomIconScreen> createState() => _CustomIconScreenState();
}

class _CustomIconScreenState extends State<CustomIconScreen> {
  final _service = AppIconService.instance;

  Color _mark = const Color(0xFF00B5C7);
  Color _bg = const Color(0xFF0E1316);
  bool _canPin = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _service.canPinShortcut().then((v) {
      if (mounted) setState(() => _canPin = v);
    });
    _service.loadCustomColors().then((colors) {
      if (colors != null && mounted) {
        setState(() {
          _mark = colors.$1;
          _bg = colors.$2;
        });
      }
    });
  }

  Future<void> _pick({required bool mark}) async {
    final picked = await showColorPickerSheet(
      context,
      initial: mark ? _mark : _bg,
      title: tr(mark ? 'custom_icon_mark' : 'custom_icon_bg'),
    );
    if (picked == null) return;
    setState(() {
      if (mark) {
        _mark = picked;
      } else {
        _bg = picked;
      }
    });
  }

  Future<void> _pin() async {
    setState(() => _busy = true);
    final png = await renderIconPng(mark: _mark, background: _bg);
    var ok = false;
    if (png != null) {
      ok = await _service.pinCustomShortcut(png, tr('app_name'));
      if (ok) await _service.saveCustomColors(_mark, _bg);
    }
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(tr(ok ? 'custom_icon_sent' : 'custom_icon_failed'))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(tr('custom_icon'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          // Превью: то же, что уйдёт в ярлык — маску наложит лаунчер.
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: AppIconPreview.colors(
                mark: _mark,
                background: _bg,
                size: 132,
                radiusFactor: 0.24,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            margin: EdgeInsets.zero,
            color: scheme.tertiaryContainer.withValues(alpha: 0.4),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_rounded, size: 20, color: scheme.tertiary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      tr('custom_icon_warning'),
                      style: TextStyle(
                        fontFamily: AppTheme.bodyFont,
                        fontSize: 13,
                        height: 1.35,
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  leading: _swatch(_bg),
                  title: Text(
                    tr('custom_icon_bg'),
                    style: const TextStyle(
                      fontFamily: AppTheme.bodyFont,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(colorToHex(_bg)),
                  onTap: () => _pick(mark: false),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  leading: _swatch(_mark),
                  title: Text(
                    tr('custom_icon_mark'),
                    style: const TextStyle(
                      fontFamily: AppTheme.bodyFont,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(colorToHex(_mark)),
                  onTap: () => _pick(mark: true),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: (_canPin && !_busy) ? _pin : null,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.add_to_home_screen_rounded),
            label: Text(tr('custom_icon_pin')),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
          if (!_canPin)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                tr('custom_icon_unsupported'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: AppTheme.bodyFont,
                  fontSize: 12.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _swatch(Color c) => Container(
    width: 34,
    height: 34,
    decoration: BoxDecoration(
      color: c,
      borderRadius: BorderRadius.circular(11),
      border: Border.all(
        color: Theme.of(context).colorScheme.outlineVariant,
      ),
    ),
  );
}
