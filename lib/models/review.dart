// Рецензия критика: всё, кроме самого текста. Текст (Markdown) живёт в старом
// поле `review` у фильма и сериала, чтобы старые версии приложения, бэкапы и
// синхронизация с ними продолжали его видеть. Новое лежит отдельным объектом
// `reviewMeta`, который старые версии просто пропускают.

/// Итог рецензии одной фразой. Порядок — от лучшего к худшему.
enum Verdict { masterpiece, must, worth, niche, miss }

Verdict? verdictFromId(String? id) {
  for (final v in Verdict.values) {
    if (v.name == id) return v;
  }
  return null;
}

/// Вердикт, который подходит к общей оценке (подсказка в редакторе).
Verdict suggestVerdict(double score) {
  if (score >= 9.0) return Verdict.masterpiece;
  if (score >= 8.0) return Verdict.must;
  if (score >= 6.5) return Verdict.worth;
  if (score >= 5.0) return Verdict.niche;
  return Verdict.miss;
}

/// Все пункты разбора в каноническом порядке. Подпись — ключ `crit_<id>`.
const List<String> kCriteria = [
  'story',
  'direction',
  'acting',
  'visuals',
  'sound',
  'pace',
  'script',
  'characters',
  'atmosphere',
  'music',
  'effects',
  'editing',
  'ending',
  'humor',
  'originality',
];

/// Пункты, которые редактор показывает, пока человек не выбрал свои.
const List<String> kDefaultCriteria = [
  'story',
  'direction',
  'acting',
  'visuals',
  'sound',
  'pace',
];

/// Среднее по оценённым пунктам, округлённое до 0.1. Пусто — null.
double? criteriaAverage(Map<String, double> criteria) {
  if (criteria.isEmpty) return null;
  final sum = criteria.values.fold<double>(0, (a, b) => a + b);
  return (sum / criteria.length * 10).round() / 10;
}

/// Оценка пункта в допустимых пределах: 1.0–10.0, шаг 0.1.
double clampScore(double v) => (v.clamp(1.0, 10.0) * 10).round() / 10;

class ReviewMeta {
  /// Заголовок рецензии («Маяк, который светит внутрь»).
  String? title;

  /// Оценки по пунктам: id из [kCriteria] → 1.0–10.0.
  Map<String, double> criteria;
  Verdict? verdict;

  /// Сильное и слабое — короткие фразы-чипы.
  List<String> pros;
  List<String> cons;

  /// В тексте есть спойлеры: друзья увидят текст только после нажатия.
  bool spoilers;

  /// Рецензию видят друзья (при условии, что она опубликована).
  bool shared;

  /// Черновик: владелец ещё не нажал «Опубликовать». Друзьям не уходит.
  bool draft;

  DateTime? createdAt;
  DateTime? updatedAt;

  /// Первая публикация — дата под заголовком и в ленте друзей.
  DateTime? publishedAt;

  ReviewMeta({
    this.title,
    Map<String, double>? criteria,
    this.verdict,
    List<String>? pros,
    List<String>? cons,
    this.spoilers = false,
    this.shared = true,
    this.draft = false,
    this.createdAt,
    this.updatedAt,
    this.publishedAt,
  })  : criteria = criteria ?? {},
        pros = pros ?? [],
        cons = cons ?? [];

  /// Нет ничего, кроме служебных полей.
  bool get isEmptyContent =>
      (title == null || title!.trim().isEmpty) &&
      criteria.isEmpty &&
      verdict == null &&
      pros.isEmpty &&
      cons.isEmpty;

  double? get average => criteriaAverage(criteria);

  /// Дата, которую показываем читателю.
  DateTime? get shownDate => publishedAt ?? updatedAt ?? createdAt;

  ReviewMeta copy() => ReviewMeta.fromJson(toJson());

  static DateTime? _date(dynamic v) =>
      v == null ? null : DateTime.tryParse('$v');

  static List<String> _strings(dynamic v) => [
        for (final e in (v as List? ?? const []))
          if ('$e'.trim().isNotEmpty) '$e'.trim(),
      ];

  factory ReviewMeta.fromJson(Map<String, dynamic> j) {
    final crit = <String, double>{};
    final raw = j['criteria'];
    if (raw is Map) {
      raw.forEach((k, v) {
        if (v is num) crit['$k'] = clampScore(v.toDouble());
      });
    }
    return ReviewMeta(
      title: j['title'] as String?,
      criteria: crit,
      verdict: verdictFromId(j['verdict'] as String?),
      pros: _strings(j['pros']),
      cons: _strings(j['cons']),
      spoilers: j['spoilers'] == true,
      shared: j['shared'] != false,
      draft: j['draft'] == true,
      createdAt: _date(j['createdAt']),
      updatedAt: _date(j['updatedAt']),
      publishedAt: _date(j['publishedAt']),
    );
  }

  Map<String, dynamic> toJson() => {
        if (title != null && title!.trim().isNotEmpty) 'title': title!.trim(),
        if (criteria.isNotEmpty) 'criteria': criteria,
        if (verdict != null) 'verdict': verdict!.name,
        if (pros.isNotEmpty) 'pros': pros,
        if (cons.isNotEmpty) 'cons': cons,
        if (spoilers) 'spoilers': true,
        'shared': shared,
        if (draft) 'draft': true,
        if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
        if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
        if (publishedAt != null) 'publishedAt': publishedAt!.toIso8601String(),
      };
}

/// Общие вопросы о рецензии для фильма и сериала.
mixin HasReview {
  String? get review;
  ReviewMeta? get reviewMeta;

  bool get hasReviewText => review != null && review!.trim().isNotEmpty;

  /// Есть что показать: текст или хоть что-то из разбора.
  bool get hasReview =>
      hasReviewText || !(reviewMeta?.isEmptyContent ?? true);

  /// Уезжает друзьям: опубликована и открыта. Старые рецензии без меты
  /// писались как приватные и остаются приватными.
  bool get reviewIsPublic {
    final meta = reviewMeta;
    return hasReview && meta != null && meta.shared && !meta.draft;
  }
}
