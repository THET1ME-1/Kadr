import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../l10n/strings.dart';
import '../theme/app_theme.dart';
import '../widgets/reveal.dart';

/// Экран «О приложении»: иконка, название, версия, атрибуция источников.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(tr('drawer_about'))),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Reveal(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(36),
                  child: Image.asset('assets/icon/app_icon.png',
                      width: 128, height: 128),
                ),
              ),
              const SizedBox(height: 20),
              Text('Kadr',
                  style: TextStyle(
                      fontFamily: AppTheme.displayFont,
                      fontWeight: FontWeight.w800,
                      fontSize: 32,
                      color: scheme.onSurface)),
              const SizedBox(height: 4),
              Text(tr('about_sub'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontFamily: AppTheme.bodyFont,
                      fontSize: 14,
                      color: scheme.onSurfaceVariant)),
              const SizedBox(height: 12),
              FutureBuilder<PackageInfo>(
                future: PackageInfo.fromPlatform(),
                builder: (context, snap) {
                  final v = snap.hasData
                      ? '${snap.data!.version} (${snap.data!.buildNumber})'
                      : '';
                  return Text('${tr('version')} $v',
                      style: TextStyle(
                          fontFamily: AppTheme.bodyFont,
                          fontSize: 13,
                          color: scheme.onSurfaceVariant));
                },
              ),
              const SizedBox(height: 32),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(18)),
                child: Text(tr('about_attribution'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontFamily: AppTheme.bodyFont,
                        fontSize: 12.5,
                        height: 1.4,
                        color: scheme.onSurfaceVariant)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
