import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../../utils/season_pass.dart';

/// Полоса пересмотра сезона под кнопками: какой по счёту просмотр идёт и
/// сколько серий в нём уже есть, а у законченного — сколько раз сезон
/// просмотрен и когда в последний раз.
///
/// Показывать её стоит, когда [SeasonPassState.showsStrip]: у первого
/// просмотра ход виден на таблетке сезона.
class PassStrip extends StatelessWidget {
  final SeasonPassState state;
  const PassStrip({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = scheme.onTertiaryContainer;
    final st = state;
    final String title;
    String? sub;
    if (st.inProgress) {
      title = trf('pass_progress', {
        'view': trf('viewing_n', {'n': st.current}),
        'done': st.done,
        'total': st.total,
      });
      if (st.from != null) {
        sub = trf('pass_started', {'date': numericDate(st.from!)});
      }
    } else {
      title = trn('pass_done', st.completed);
      if (st.from != null && st.to != null) {
        sub = trf('pass_last', {'dates': dateRangeNumeric(st.from!, st.to!)});
      }
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          Row(
            spacing: 10,
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: scheme.tertiary,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.repeat_rounded,
                    size: 18, color: scheme.onTertiary),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            fontFamily: AppTheme.displayFont,
                            fontWeight: FontWeight.w700,
                            fontSize: 13.5,
                            color: fg)),
                    if (sub != null)
                      Text(sub,
                          style: TextStyle(
                              fontFamily: AppTheme.bodyFont,
                              fontSize: 12,
                              color: fg.withValues(alpha: 0.85))),
                  ],
                ),
              ),
            ],
          ),
          // Своя полоса, а не LinearProgressIndicator: у того в M3 разрыв
          // дорожки и точка на конце, а здесь нужна сплошная линейка.
          if (st.inProgress)
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                height: 8,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ColoredBox(color: scheme.surface),
                    FractionallySizedBox(
                      alignment: AlignmentDirectional.centerStart,
                      widthFactor: (st.done / st.total).clamp(0.0, 1.0),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: scheme.tertiary,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
