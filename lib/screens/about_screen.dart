import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/strings.dart';
import '../theme/app_theme.dart';
import '../widgets/reveal.dart';

/// Ссылка «Поддержать авторов» (Boosty).
final Uri kBoostyUrl = Uri.parse('https://boosty.to/sntcompany');

/// Ссылка DonationAlerts (разовый донат — картой/СБП).
final Uri kDonationAlertsUrl =
    Uri.parse('https://www.donationalerts.com/r/thet1me');

/// Почта поддержки — куда писать пользователям.
const String kSupportEmail = 'stgroup.dev@gmail.com';

/// Публичный репозиторий приложения.
final Uri kRepoUrl = Uri.parse('https://github.com/THET1ME-1/Kadr');

Future<void> openRepo() async {
  await launchUrl(kRepoUrl, mode: LaunchMode.externalApplication);
}

Future<void> openSupportAuthors() async {
  await launchUrl(kBoostyUrl, mode: LaunchMode.externalApplication);
}

Future<void> openDonationAlerts() async {
  await launchUrl(kDonationAlertsUrl, mode: LaunchMode.externalApplication);
}

Future<void> openSupportEmail() async {
  await launchUrl(Uri.parse('mailto:$kSupportEmail?subject=Kadr'));
}

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
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: openSupportAuthors,
                  style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14)),
                  icon: const Icon(Icons.favorite_rounded),
                  label: Text(tr('support_authors'),
                      style: const TextStyle(
                          fontFamily: AppTheme.displayFont,
                          fontWeight: FontWeight.w700,
                          fontSize: 15)),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  onPressed: openDonationAlerts,
                  style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 13)),
                  icon: const Icon(Icons.card_giftcard_rounded, size: 18),
                  label: const Text('DonationAlerts',
                      style: TextStyle(
                          fontFamily: AppTheme.displayFont,
                          fontWeight: FontWeight.w700,
                          fontSize: 15)),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: openSupportEmail,
                  style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 13)),
                  icon: const Icon(Icons.mail_outline_rounded, size: 18),
                  label: Text(tr('contact_support')),
                ),
              ),
              const SizedBox(height: 24),
              GestureDetector(
                onTap: () => launchUrl(Uri.parse('https://www.themoviedb.org'),
                    mode: LaunchMode.externalApplication),
                child: Image.asset('assets/tmdb_logo.png', height: 18),
              ),
              const SizedBox(height: 12),
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
