import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/strings.dart';
import '../services/facts_service.dart';
import '../theme/app_theme.dart';

/// Блок «Знаете ли вы»: интересные факты и киноляпы с ПоискКино.
///
/// Крупная цифра слева, текст справа. Разделителей между фактами нет: ритм
/// держат цифры и воздух. Удержание копирует факт, спойлеры размыты, пока по
/// ним не нажали.
///
/// Ничего не рисует, пока фактов нет: без ключа ПоискКино, при исчерпанном
/// лимите и для фильмов, которых у КП нет, блок просто отсутствует.
class FactsSection extends StatefulWidget {
  /// Откуда брать факты. Вызывается один раз при появлении блока.
  final Future<List<KpFact>> Function() loader;

  /// Сколько фактов показать до нажатия «Ещё N».
  final int previewCount;

  const FactsSection({super.key, required this.loader, this.previewCount = 4});

  @override
  State<FactsSection> createState() => _FactsSectionState();
}

class _FactsSectionState extends State<FactsSection> {
  List<KpFact> _facts = const [];
  bool _expanded = false;
  final Set<int> _revealed = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!FactsService.available) return;
    final facts = await widget.loader();
    if (!mounted || facts.isEmpty) return;
    setState(() => _facts = facts);
  }

  void _copy(String text) {
    HapticFeedback.selectionClick();
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(tr('copied'))));
  }

  @override
  Widget build(BuildContext context) {
    if (_facts.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final facts = _facts.where((f) => !f.blooper).toList();
    final bloopers = _facts.where((f) => f.blooper).toList();
    final shown = _expanded ? facts : facts.take(widget.previewCount).toList();
    final hidden = facts.length - shown.length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 22, 4, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr('facts_title'),
              style: TextStyle(
                  fontFamily: AppTheme.displayFont,
                  fontWeight: FontWeight.w800,
                  fontSize: 22,
                  height: 1.1,
                  color: scheme.onSurface)),
          const SizedBox(height: 14),
          for (var i = 0; i < shown.length; i++)
            _factRow(scheme, shown[i], i + 1, i),
          if (hidden > 0) ...[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => setState(() => _expanded = true),
                child: Text(trf('facts_more_n', {'n': hidden})),
              ),
            ),
          ],
          if (bloopers.isNotEmpty) ...[
            const SizedBox(height: 22),
            Row(
              children: [
                Icon(Icons.auto_fix_high_rounded,
                    size: 18, color: scheme.tertiary),
                const SizedBox(width: 8),
                Text(tr('facts_bloopers'),
                    style: TextStyle(
                        fontFamily: AppTheme.displayFont,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: scheme.tertiary)),
              ],
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < bloopers.length; i++)
              _factRow(scheme, bloopers[i], i + 1, 1000 + i, blooper: true),
          ],
          const SizedBox(height: 12),
          Text(tr('facts_source'),
              style: TextStyle(
                  fontFamily: AppTheme.bodyFont,
                  fontSize: 11.5,
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.7))),
        ],
      ),
    );
  }

  Widget _factRow(ColorScheme scheme, KpFact fact, int number, int key,
      {bool blooper = false}) {
    final hidden = fact.spoiler && !_revealed.contains(key);
    final text = Text(
      fact.text,
      style: TextStyle(
          fontFamily: AppTheme.bodyFont,
          fontSize: 15,
          height: 1.6,
          color: scheme.onSurface),
    );
    return GestureDetector(
      onLongPress: hidden ? null : () => _copy(fact.text),
      onTap: hidden ? () => setState(() => _revealed.add(key)) : null,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        // Воздух вместо линий: строки разделяет отступ, а не разделитель.
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Номер в одну строку: с десятого факта две цифры Unbounded в
            // прежние 46 точек не помещались.
            SizedBox(
              width: 58,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text('$number',
                    maxLines: 1,
                    softWrap: false,
                    style: TextStyle(
                        fontFamily: AppTheme.displayFont,
                        fontWeight: FontWeight.w800,
                        fontSize: 34,
                        height: 1.0,
                        color: (blooper ? scheme.tertiary : scheme.primary)
                            .withValues(alpha: 0.45))),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (hidden)
                    // Текст на месте, но нечитаем: размытие снимается тапом.
                    ImageFiltered(
                      imageFilter: ui.ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                      child: text,
                    )
                  else
                    text,
                  if (hidden) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.lock_outline_rounded,
                            size: 15, color: scheme.onSurfaceVariant),
                        const SizedBox(width: 6),
                        Text(tr('facts_spoiler'),
                            style: TextStyle(
                                fontFamily: AppTheme.bodyFont,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: scheme.onSurfaceVariant)),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
