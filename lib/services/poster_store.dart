import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Локальные пользовательские постеры: пользователь может заменить постер фильма
/// или сериала своим изображением. Файлы лежат в `<docs>/posters`, а в модели
/// хранится только ИМЯ файла — полный путь резолвится к текущей папке приложения
/// (устойчиво к обновлению/переустановке). Постер локальный: на сервер/друзьям он
/// не уходит (там остаётся сетевой `posterUrl`).
///
/// Здесь же лежат фото дневника просмотра. В резервную копию картинки едут
/// отдельными файлами, см. `BackupService`.
class PosterStore {
  PosterStore._();
  static final PosterStore instance = PosterStore._();

  String? _dir;

  /// Имена файлов, которые есть в папке. Библиотека из копии или с другого
  /// устройства называет файлы, которых здесь нет: по этому списку [pathOf]
  /// отвечает «нет», и карточка показывает сетевой постер, а не пустоту.
  final Set<String> _files = {};

  /// Вызвать один раз до runApp (кэширует папку постеров для синхронного резолва).
  Future<void> init() async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final d = Directory('${docs.path}/posters');
      if (!await d.exists()) await d.create(recursive: true);
      await _scan(d);
    } catch (_) {/* нет доступа — локальные постеры просто не работают */}
  }

  /// Подменяет папку картинок: тестам нужна своя.
  @visibleForTesting
  Future<void> useDir(Directory d) => _scan(d);

  Future<void> _scan(Directory d) async {
    _dir = d.path;
    _files
      ..clear()
      ..addAll([
        await for (final f in d.list())
          if (f is File) f.uri.pathSegments.last,
      ]);
  }

  /// Папка картинок; null, пока [init] не отработал.
  Directory? get directory => _dir == null ? null : Directory(_dir!);

  /// Абсолютный путь к локальной картинке по имени файла. null, если имени
  /// нет или такого файла на устройстве нет.
  String? pathOf(String? file) =>
      (file == null || _dir == null || !_files.contains(file))
          ? null
          : '$_dir/$file';

  /// Файл картинки, если он есть на устройстве.
  File? fileOf(String? file) {
    final p = pathOf(file);
    return p == null ? null : File(p);
  }

  /// Есть ли картинка с таким именем на устройстве.
  bool has(String file) => _files.contains(file);

  /// Картинка [file] появилась в папке мимо [save]: её положило
  /// восстановление из копии.
  void adopt(String file) => _files.add(file);

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
      _files.add(name);
      return name;
    } catch (_) {
      return null;
    }
  }

  /// Удаляет файл локального постера по имени (если задан).
  Future<void> delete(String? file) async {
    final p = pathOf(file);
    if (p == null) return;
    _files.remove(file);
    try {
      final f = File(p);
      if (await f.exists()) await f.delete();
    } catch (_) {/* не критично */}
  }
}
