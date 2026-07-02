import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'l10n/locale_controller.dart';
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';
import 'screens/home_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ThemeController.instance.load();
  await LocaleController.instance.load();
  runApp(const KadrApp());
}

/// Корень приложения. Слушает контроллеры темы и языка — при смене цвета,
/// режима или языка всё дерево перестраивается на лету.
class KadrApp extends StatelessWidget {
  const KadrApp({super.key});

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
              lightTheme = AppTheme.fromScheme(lightDynamic.harmonized());
              darkTheme = AppTheme.fromScheme(darkDynamic.harmonized());
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
              home: const HomeShell(),
            );
          },
        );
      },
    );
  }
}
