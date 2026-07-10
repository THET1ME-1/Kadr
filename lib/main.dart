import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'l10n/locale_controller.dart';
import 'services/api_keys.dart';
import 'services/app_prefs.dart';
import 'services/auto_backup_service.dart';
import 'services/movie_repository.dart';
import 'services/movie_source.dart';
import 'services/poster_store.dart';
import 'services/social/social_controller.dart';
import 'services/sync/webdav_service.dart';
import 'services/store.dart';
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';
import 'screens/home_shell.dart';
import 'screens/onboarding_screen.dart';
import 'screens/tmdb_key_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ThemeController.instance.load();
  await LocaleController.instance.load();
  await SourceController.instance.load();
  await ApiKeys.load(); // персональные API-ключи (TMDB/kinopoisk)
  await AppPrefs.instance.load();
  await PosterStore.instance.init(); // папка локальных постеров (для displayPoster)
  await MovieRepository.instance.load();
  await AutoBackupService.instance.load();
  // Соц-слой: восстановить сессию и синхронизировать профиль/друзей в фоне
  // (не блокируем старт — экраны слушают контроллер и обновятся сами).
  SocialController.instance.load();
  // Автобекап по расписанию — при запуске (и при возврате в приложение ниже).
  AutoBackupService.instance.maybePeriodic();
  // Сбрасываем отложенную запись библиотеки на диск при уходе в фон, чтобы не
  // потерять последние изменения, если систему решит выгрузить процесс.
  WidgetsBinding.instance.addObserver(_LifecycleFlusher());
  final onboarded = await Store.instance.getBool('onboardingDone');
  runApp(KadrApp(onboarded: onboarded));
}

/// Наблюдатель жизненного цикла: при сворачивании приложения принудительно
/// сохраняет библиотеку (см. [MovieRepository.flush]).
class _LifecycleFlusher extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      MovieRepository.instance.flush();
      // При сворачивании — заливаем изменения сессии на WebDAV (если настроен)
      // и публикуем публичную проекцию для друзей (если вошёл).
      WebdavService.instance.syncSilently();
      SocialController.instance.publishSilently();
    } else if (state == AppLifecycleState.resumed) {
      AutoBackupService.instance.maybePeriodic();
      // При возврате — подтягиваем изменения с других устройств и друзей.
      WebdavService.instance.syncSilently();
      SocialController.instance.refreshFriends();
    }
  }
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
      listenable: Listenable.merge([theme, locale, AppPrefs.instance]),
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
              // Без TMDB-токена приложение почти не работает → сначала экран
              // ввода своего ключа (после онбординга).
              home: !onboarded
                  ? const OnboardingScreen()
                  : (ApiKeys.hasTmdb
                      ? const HomeShell()
                      : const TmdbKeyScreen(gate: true)),
            );
          },
        );
      },
    );
  }
}
