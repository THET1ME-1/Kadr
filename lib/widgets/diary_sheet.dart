import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../models/library_entry.dart';
import '../services/poster_store.dart';
import '../services/social/social_controller.dart';
import '../theme/app_theme.dart';

/// Набор эмодзи-настроений для дневника (мультивыбор).
const List<String> kDiaryMoods = [
  '😍', '😂', '🥹', '🤯', '😱', '😎', '🤔', '😴', '😐', '😢', '🔥', '💔'
];

/// Места просмотра: код → (иконка, ключ подписи).
const List<(String, IconData, String)> kDiaryPlaces = [
  ('home', Icons.home_rounded, 'diary_place_home'),
  ('cinema', Icons.theaters_rounded, 'diary_place_cinema'),
  ('guest', Icons.weekend_rounded, 'diary_place_guest'),
  ('trip', Icons.luggage_rounded, 'diary_place_trip'),
];

/// Панель дневника просмотра. Редактирует копию [initial]; на «Сохранить»
/// возвращает изменённую [DiaryEntry], иначе null. [photoKey] — уникальное имя
/// для файла фото (локально, приватно).
Future<DiaryEntry?> showDiarySheet(
  BuildContext context, {
  required DiaryEntry initial,
  required String photoKey,
}) {
  return showModalBottomSheet<DiaryEntry>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _DiarySheet(initial: initial, photoKey: photoKey),
  );
}

class _DiarySheet extends StatefulWidget {
  final DiaryEntry initial;
  final String photoKey;
  const _DiarySheet({required this.initial, required this.photoKey});

  @override
  State<_DiarySheet> createState() => _DiarySheetState();
}

class _DiarySheetState extends State<_DiarySheet> {
  late final List<String> _moods = [...widget.initial.moods];
  late final Set<String> _friendIds = {...widget.initial.friendIds};
  late String? _place = widget.initial.place;
  late String? _photoFile = widget.initial.photoFile;
  late final TextEditingController _with =
      TextEditingController(text: widget.initial.withWhom ?? '');
  late final TextEditingController _note =
      TextEditingController(text: widget.initial.note ?? '');
  bool _busyPhoto = false;

  @override
  void dispose() {
    _with.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    setState(() => _busyPhoto = true);
    try {
      final res = await FilePicker.platform
          .pickFiles(type: FileType.image, withData: true);
      if (res == null || res.files.isEmpty) return;
      final f = res.files.single;
      final bytes =
          f.bytes ?? (f.path != null ? await File(f.path!).readAsBytes() : null);
      if (bytes == null) return;
      final saved = await PosterStore.instance
          .save('diary-${widget.photoKey}', bytes, old: _photoFile);
      if (mounted) setState(() => _photoFile = saved);
    } finally {
      if (mounted) setState(() => _busyPhoto = false);
    }
  }

  Future<void> _removePhoto() async {
    await PosterStore.instance.delete(_photoFile);
    if (mounted) setState(() => _photoFile = null);
  }

  void _save() {
    final entry = DiaryEntry(
      moods: _moods,
      withWhom: _with.text.trim().isEmpty ? null : _with.text.trim(),
      friendIds: _friendIds.toList(),
      place: _place,
      photoFile: _photoFile,
      note: _note.text.trim().isEmpty ? null : _note.text.trim(),
    );
    Navigator.pop(context, entry);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final friends = SocialController.instance.friends.friends;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          children: [
            Text(tr('diary_title'),
                style: TextStyle(
                    fontFamily: AppTheme.displayFont,
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                    color: scheme.onSurface)),
            const SizedBox(height: 18),

            // Настроение.
            _label(scheme, tr('diary_mood')),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final e in kDiaryMoods)
                  _MoodChip(
                    emoji: e,
                    selected: _moods.contains(e),
                    onTap: () => setState(() =>
                        _moods.contains(e) ? _moods.remove(e) : _moods.add(e)),
                  ),
              ],
            ),
            const SizedBox(height: 18),

            // Где.
            _label(scheme, tr('diary_where')),
            const SizedBox(height: 8),
            Row(
              children: [
                for (final p in kDiaryPlaces) ...[
                  Expanded(
                    child: _PlaceButton(
                      icon: p.$2,
                      label: tr(p.$3),
                      selected: _place == p.$1,
                      onTap: () => setState(
                          () => _place = _place == p.$1 ? null : p.$1),
                    ),
                  ),
                  if (p != kDiaryPlaces.last) const SizedBox(width: 10),
                ],
              ],
            ),
            const SizedBox(height: 18),

            // С кем.
            _label(scheme, tr('diary_with')),
            const SizedBox(height: 8),
            if (friends.isNotEmpty) ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final f in friends)
                    FilterChip(
                      label: Text(f.user.displayName),
                      selected: _friendIds.contains(f.user.id),
                      onSelected: (v) => setState(() => v
                          ? _friendIds.add(f.user.id)
                          : _friendIds.remove(f.user.id)),
                    ),
                ],
              ),
              const SizedBox(height: 10),
            ],
            TextField(
              controller: _with,
              style: const TextStyle(fontFamily: AppTheme.bodyFont),
              decoration: InputDecoration(
                hintText: tr('diary_with_hint'),
                prefixIcon: const Icon(Icons.people_alt_rounded),
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 18),

            // Фото.
            _label(scheme, tr('diary_photo')),
            const SizedBox(height: 8),
            if (_photoFile != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Stack(
                  children: [
                    Image.file(
                      File(PosterStore.instance.pathOf(_photoFile)!),
                      width: double.infinity,
                      height: 180,
                      fit: BoxFit.cover,
                    ),
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Material(
                        color: Colors.black.withValues(alpha: 0.5),
                        shape: const CircleBorder(),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: _removePhoto,
                          child: const Padding(
                            padding: EdgeInsets.all(6),
                            child: Icon(Icons.close_rounded,
                                size: 18, color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              OutlinedButton.icon(
                onPressed: _busyPhoto ? null : _pickPhoto,
                style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    minimumSize: const Size(double.infinity, 0)),
                icon: _busyPhoto
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.add_photo_alternate_rounded),
                label: Text(tr('diary_photo_add')),
              ),
            const SizedBox(height: 18),

            // Заметка.
            _label(scheme, tr('diary_note')),
            const SizedBox(height: 8),
            TextField(
              controller: _note,
              minLines: 2,
              maxLines: 5,
              style: const TextStyle(fontFamily: AppTheme.bodyFont),
              decoration: InputDecoration(
                hintText: tr('diary_note_hint'),
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _save,
                style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 15)),
                child: Text(tr('save'),
                    style: const TextStyle(
                        fontFamily: AppTheme.displayFont,
                        fontWeight: FontWeight.w700,
                        fontSize: 15)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(ColorScheme scheme, String text) => Text(text,
      style: TextStyle(
          fontFamily: AppTheme.displayFont,
          fontWeight: FontWeight.w700,
          fontSize: 14,
          color: scheme.onSurfaceVariant));
}

class _MoodChip extends StatelessWidget {
  final String emoji;
  final bool selected;
  final VoidCallback onTap;
  const _MoodChip(
      {required this.emoji, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 46,
        height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? scheme.primaryContainer : scheme.surfaceContainerHigh,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? scheme.primary : Colors.transparent,
            width: 2,
          ),
        ),
        child: Text(emoji, style: const TextStyle(fontSize: 22)),
      ),
    );
  }
}

class _PlaceButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _PlaceButton(
      {required this.icon,
      required this.label,
      required this.selected,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? scheme.primaryContainer : scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            children: [
              Icon(icon,
                  size: 22,
                  color: selected
                      ? scheme.onPrimaryContainer
                      : scheme.onSurfaceVariant),
              const SizedBox(height: 4),
              Text(label,
                  style: TextStyle(
                      fontFamily: AppTheme.bodyFont,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: selected
                          ? scheme.onPrimaryContainer
                          : scheme.onSurface)),
            ],
          ),
        ),
      ),
    );
  }
}
