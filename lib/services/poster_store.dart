import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// Локальные пользовательские постеры: пользователь может заменить постер фильма
/// или сериала своим изображением. Файлы лежат в `<docs>/posters`, а в модели
/// хранится только ИМЯ файла — полный путь резолвится к текущей папке приложения
/// (устойчиво к обновлению/переустановке). Постер локальный: на сервер/друзьям он
/// не уходит (там остаётся сетевой `posterUrl`).
class PosterStore {
  PosterStore._();
  static final PosterStore instance = PosterStore._();

  String? _dir;

  /// Вызвать один раз до runApp (кэширует папку постеров для синхронного резолва).
  Future<void> init() async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final d = Directory('${docs.path}/posters');
      if (!await d.exists()) await d.create(recursive: true);
      _dir = d.path;
    } catch (_) {/* нет доступа — локальные постеры просто не работают */}
  }

  /// Абсолютный путь к локальному постеру по имени файла (или null).
  String? pathOf(String? file) =>
      (file == null || file.isEmpty || _dir == null) ? null : '$_dir/$file';

  /// Сохраняет изображение постера для [key] (uuid фильма / tvShowId сериала),
  /// удаляет прежний файл [old]. Возвращает имя нового файла или null при ошибке.
  Future<String?> save(String key, Uint8List bytes, {String? old}) async {
    if (_dir == null) await init();
    if (_dir == null) return null;
    await delete(old);
    final safe = key.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final name = 'p_${safe}_${DateTime.now().millisecondsSinceEpoch}.jpg';
    try {
      await File('$_dir/$name').writeAsBytes(bytes, flush: true);
      return name;
    } catch (_) {
      return null;
    }
  }

  /// Удаляет файл локального постера по имени (если задан).
  Future<void> delete(String? file) async {
    final p = pathOf(file);
    if (p == null) return;
    try {
      final f = File(p);
      if (await f.exists()) await f.delete();
    } catch (_) {/* не критично */}
  }
}
