import 'package:flutter/services.dart';

/// Текст, которым поделились с Kadr из другого приложения: ссылка на ролик
/// YouTube из «Поделиться». Android присылает его при запуске и потом, пока
/// приложение открыто (MainActivity.kt, канал `kadr/share`).
class ShareIntent {
  ShareIntent._();

  static const _channel = MethodChannel('kadr/share');

  /// Ловит текст: сразу тот, с которым приложение запустили, и новые.
  static Future<void> listen(void Function(String text) onText) async {
    _channel.setMethodCallHandler((call) async {
      final text = call.arguments;
      if (call.method == 'shared' && text is String && text.isNotEmpty) {
        onText(text);
      }
    });
    try {
      final first = await _channel.invokeMethod<String>('initialText');
      if (first != null && first.isNotEmpty) onText(first);
    } on MissingPluginException {
      // Не Android: делиться некуда.
    } on PlatformException {
      // Канал не ответил: запуск без «Поделиться».
    }
  }
}
