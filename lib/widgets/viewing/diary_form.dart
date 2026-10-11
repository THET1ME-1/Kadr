import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/strings.dart';
import '../../models/library_entry.dart';
import '../../services/poster_store.dart';
import '../../services/social/social_controller.dart';
import '../../theme/app_theme.dart';
import '../review/review_parts.dart';

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

/// Подпись места по коду из дневника; пусто для незнакомого кода.
String diaryPlaceLabel(String? code) {
  for (final p in kDiaryPlaces) {
    if (p.$1 == code) return tr(p.$3);
  }
  return '';
}

/// Дневник одной строкой: настроения, место, с кем. Пусто, если записи нет.
String diarySummary(DiaryEntry? d) {
  if (d == null || d.isEmpty) return '';
  final friends = SocialController.instance.friends.friends;
  final names = [
    for (final f in friends)
      if (d.friendIds.contains(f.user.id)) f.user.displayName,
    if (d.withWhom != null && d.withWhom!.trim().isNotEmpty) d.withWhom!.trim(),
  ];
  final place = diaryPlaceLabel(d.place);
  return [
    if (d.moods.isNotEmpty) d.moods.join(' '),
    if (place.isNotEmpty) place.toLowerCase(),
    if (names.isNotEmpty) names.join(', '),
    if (d.moods.isEmpty && place.isEmpty && names.isEmpty) tr('diary_has_note'),
  ].join(' · ');
}

/// Поля дневника просмотра: настроение, где, с кем, фото и заметка.
///
/// Правит свою копию [initial] и отдаёт её целиком через [onChanged] после
/// каждого изменения. Фото лежит локально, под именем `diary-<photoKey>`.
class DiaryForm extends StatefulWidget {
  final DiaryEntry? initial;
  final String photoKey;
  final ValueChanged<DiaryEntry> onChanged;

  const DiaryForm({
    super.key,
    required this.initial,
    required this.photoKey,
    required this.onChanged,
  });

  @override
  State<DiaryForm> createState() => _DiaryFormState();
}

class _DiaryFormState extends State<DiaryForm> {
  late final List<String> _moods = [...?widget.initial?.moods];
  late final Set<String> _friendIds = {...?widget.initial?.friendIds};
  late String? _place = widget.initial?.place;
  late String? _photoFile = widget.initial?.photoFile;
  late final TextEditingController _with =
      TextEditingController(text: widget.initial?.withWhom ?? '');
  late final TextEditingController _note =
      TextEditingController(text: widget.initial?.note ?? '');
  bool _busyPhoto = false;

  @override
  void dispose() {
    _with.dispose();
    _note.dispose();
    super.dispose();
  }

  void _emit() {
    final withWhom = _with.text.trim(), note = _note.text.trim();
    widget.onChanged(DiaryEntry(
      moods: [..._moods],
      withWhom: withWhom.isEmpty ? null : withWhom,
      friendIds: _friendIds.toList(),
      place: _place,
      photoFile: _photoFile,
      note: note.isEmpty ? null : note,
    ));
  }

  void _change(VoidCallback fn) {
    HapticFeedback.selectionClick();
    setState(fn);
    _emit();
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
      if (!mounted) return;
      setState(() => _photoFile = saved);
      _emit();
    } catch (_) {
      // Отмена выбора или сбой чтения файла: дневник остаётся как был.
    } finally {
      if (mounted) setState(() => _busyPhoto = false);
    }
  }

  Future<void> _removePhoto() async {
    await PosterStore.instance.delete(_photoFile);
    if (!mounted) return;
    setState(() => _photoFile = null);
    _emit();
  }

  InputDecoration _field(ColorScheme scheme, String hint, {IconData? icon}) =>
      InputDecoration(
        hintText: hint,
        isDense: true,
        prefixIcon: icon == null ? null : Icon(icon, size: 20),
        filled: true,
        fillColor: scheme.surfaceContainer,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final friends = SocialController.instance.friends.friends;
    final photo = PosterStore.instance.pathOf(_photoFile);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        ReviewCaps(tr('diary_mood')),
        LayoutBuilder(builder: (context, box) {
          const gap = 6.0;
          final side = (box.maxWidth - gap * 5) / 6;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final e in kDiaryMoods)
                _MoodChip(
                  emoji: e,
                  side: side,
                  selected: _moods.contains(e),
                  onTap: () => _change(() =>
                      _moods.contains(e) ? _moods.remove(e) : _moods.add(e)),
                ),
            ],
          );
        }),
        ReviewCaps(tr('diary_where')),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final p in kDiaryPlaces)
              _PlaceChip(
                icon: p.$2,
                label: tr(p.$3),
                selected: _place == p.$1,
                onTap: () =>
                    _change(() => _place = _place == p.$1 ? null : p.$1),
              ),
          ],
        ),
        ReviewCaps(tr('diary_with')),
        if (friends.isNotEmpty)
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final f in friends)
                _PlaceChip(
                  icon: Icons.person_rounded,
                  label: f.user.displayName,
                  selected: _friendIds.contains(f.user.id),
                  onTap: () => _change(() => _friendIds.contains(f.user.id)
                      ? _friendIds.remove(f.user.id)
                      : _friendIds.add(f.user.id)),
                ),
            ],
          ),
        TextField(
          controller: _with,
          onChanged: (_) => _emit(),
          style: const TextStyle(fontFamily: AppTheme.bodyFont, fontSize: 14),
          decoration: _field(scheme, tr('diary_with_hint'),
              icon: Icons.group_rounded),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 10,
          children: [
            Semantics(
              button: true,
              label: tr(photo == null ? 'diary_photo_add' : 'diary_photo'),
              child: Material(
                color: scheme.surfaceContainer,
                borderRadius: BorderRadius.circular(18),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: _busyPhoto
                      ? null
                      : (photo == null ? _pickPhoto : _removePhoto),
                  child: SizedBox(
                    width: 72,
                    height: 72,
                    child: photo != null
                        ? Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.file(File(photo), fit: BoxFit.cover),
                              Align(
                                alignment: Alignment.topRight,
                                child: Container(
                                  margin: const EdgeInsets.all(4),
                                  padding: const EdgeInsets.all(2),
                                  decoration: BoxDecoration(
                                    color: scheme.secondaryContainer,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(Icons.close_rounded,
                                      size: 14,
                                      color: scheme.onSecondaryContainer),
                                ),
                              ),
                            ],
                          )
                        : _busyPhoto
                            ? const Center(
                                child: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2)))
                            : Icon(Icons.add_a_photo_rounded,
                                color: scheme.onSurfaceVariant),
                  ),
                ),
              ),
            ),
            Expanded(
              child: TextField(
                controller: _note,
                onChanged: (_) => _emit(),
                minLines: 2,
                maxLines: 5,
                style:
                    const TextStyle(fontFamily: AppTheme.bodyFont, fontSize: 14),
                decoration: _field(scheme, tr('diary_note_hint')),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _MoodChip extends StatelessWidget {
  final String emoji;
  final double side;
  final bool selected;
  final VoidCallback onTap;
  const _MoodChip({
    required this.emoji,
    required this.side,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: emoji,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: side,
          height: side,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color:
                selected ? scheme.primaryContainer : scheme.surfaceContainer,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? scheme.primary : Colors.transparent,
              width: 2,
            ),
          ),
          child: Text(emoji, style: TextStyle(fontSize: side * 0.46)),
        ),
      ),
    );
  }
}

class _PlaceChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _PlaceChip({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = selected ? scheme.onSecondaryContainer : scheme.onSurface;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? scheme.secondaryContainer : scheme.surfaceContainer,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 6,
              children: [
                Icon(icon, size: 17, color: fg),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: AppTheme.bodyFont,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: fg,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
