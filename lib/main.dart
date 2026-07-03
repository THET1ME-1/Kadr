import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'l10n/locale_controller.dart';
import 'services/movie_repository.dart';
import 'services/movie_source.dart';
import 'services/store.dart';
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';
import 'screens/home_shell.dart';
import 'screens/onboarding_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ThemeController.instance.load();
  await LocaleController.instance.load();
  await SourceController.instance.load();
  await MovieRepository.instance.load();
  final onboarded = await Store.instance.getBool('onboardingDone');
  runApp(KadrApp(onboarded: onboarded));
}

/// Корень приложения. Слушает контроллеры темы и языка — при смене цвета,
/// режима или языка всё дерево перестраивается на лету.
class KadrApp extends StatelessWidget {
  final bool onboarded;
  const KadrApp({super.key, this.onboarded = true});

  @override
  Widget build(BuildContext context) {
    final theme = ThemeController.instance;
    final locale = LocaleController.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([theme, locale]),
      builder: (context, _) {
        return DynamicColorBuilder(
          builder: (lightDynamic, darkDynamic) {
            final ThemeData lightTheme;
            final ThemeData darkTheme;
            if (theme.useDynamicColor &&
                lightDynamic != null &&
                darkDynamic != null) {
              // Схема из плагина dynamic_color приходит без новых M3-тонов
              // surfaceContainer* — карточки сливаются с фоном («пропадают
              // блоки»). Поэтому строим ПОЛНУЮ схему из wallpaper-цвета.
              lightTheme = AppTheme.light(lightDynamic.primary);
              darkTheme =
                  AppTheme.dark(darkDynamic.primary, amoled: theme.amoled);
            } else {
              lightTheme = AppTheme.light(theme.seedColor);
              darkTheme = AppTheme.dark(theme.seedColor, amoled: theme.amoled);
            }
            return MaterialApp(
              title: 'Kadr',
              debugShowCheckedModeBanner: false,
              theme: lightTheme,
              darkTheme: darkTheme,
              themeMode: theme.themeMode,
              locale: locale.locale,
              supportedLocales: LocaleController.supported,
              localizationsDelegates: const [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              navigatorObservers: [appRouteObserver],
              home: onboarded ? const HomeShell() : const OnboardingScreen(),
            );
          },
        );
      },
    );
  }
}
