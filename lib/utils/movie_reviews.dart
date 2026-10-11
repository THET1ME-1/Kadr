import '../models/library_entry.dart';
import '../models/review.dart';

/// Рецензия фильма вместе с просмотром, о котором она написана.
class MovieReviewRef {
  /// Сам фильм (первая написанная рецензия) или [ExtraReview].
  final HasReview item;

  /// Просмотр рецензии; null, если у фильма нет просмотров.
  final Viewing? viewing;

  /// Номер просмотра по порядку, 0 без просмотра.
  final int ordinal;
  const MovieReviewRef(this.item, this.viewing, this.ordinal);

  /// Id дополнительной рецензии; null у первой.
  String? get extraId {
    final it = item;
    return it is ExtraReview ? it.id : null;
  }

  ReviewMeta? get meta => item.reviewMeta;
}

/// Просмотр, о котором рецензия [item] фильма [m].
///
/// У привязанной рецензии это просмотр из [ReviewMeta.viewId]. Рецензии,
/// написанные до привязки, встают к последнему просмотру, который был раньше
/// неё; рецензия без дат — к последнему просмотру фильма.
Viewing? reviewViewing(LibraryMovie m, HasReview item) {
  final linked = m.viewingById(item.reviewMeta?.viewId);
  if (linked != null) return linked;
  final ordered = m.orderedViewings;
  if (ordered.isEmpty) return null;
  final meta = item.reviewMeta;
  final at = meta?.createdAt ?? meta?.publishedAt ?? meta?.updatedAt;
  if (at == null) return ordered.last;
  Viewing? best;
  for (final v in ordered) {
    final d = v.date;
    if (d == null || !d.isAfter(at)) best = v;
  }
  return best ?? ordered.first;
}

/// Рецензии фильма по порядку просмотров; рецензии без просмотра в конце.
/// Если две рецензии выводятся к одному просмотру, вторая остаётся без него.
List<MovieReviewRef> movieReviews(LibraryMovie m) {
  final ordered = m.orderedViewings;
  final taken = <String>{};
  final refs = <MovieReviewRef>[];
  // Сначала привязанные по id: старая рецензия без привязки не должна занять
  // просмотр, на который уже написана другая.
  final items = m.allReviews
    ..sort((a, b) {
      final al = m.viewingById(a.reviewMeta?.viewId) != null ? 0 : 1;
      final bl = m.viewingById(b.reviewMeta?.viewId) != null ? 0 : 1;
      return al.compareTo(bl);
    });
  for (final item in items) {
    var v = reviewViewing(m, item);
    if (v != null && !taken.add(v.id)) v = null;
    refs.add(MovieReviewRef(item, v, v == null ? 0 : ordered.indexOf(v) + 1));
  }
  refs.sort((a, b) {
    if (a.ordinal == 0 || b.ordinal == 0) {
      return a.ordinal == b.ordinal ? 0 : (a.ordinal == 0 ? 1 : -1);
    }
    return a.ordinal.compareTo(b.ordinal);
  });
  return refs;
}

/// Записывает рецензиям фильма просмотр, который им достался по дате.
///
/// Делается один раз при загрузке библиотеки. Пока привязка считалась при
/// каждом чтении, рецензия без дат уходила к новому пересмотру и пропадала,
/// когда его удаляли. Рецензия старой версии получает разбор закрытым от
/// друзей, как и была; дата правки не появляется.
void bindLooseReviews(LibraryMovie m) {
  if (m.viewings.isEmpty || (!m.hasReview && m.moreReviews.isEmpty)) return;
  for (final r in movieReviews(m)) {
    final v = r.viewing;
    if (v == null || r.meta?.viewId == v.id) continue;
    final item = r.item;
    if (item is LibraryMovie) {
      (item.reviewMeta ??= ReviewMeta(shared: false)).viewId = v.id;
    } else if (item is ExtraReview) {
      (item.reviewMeta ??= ReviewMeta(shared: false)).viewId = v.id;
    }
  }
}

/// Рецензия на просмотр [viewId]; с null — рецензия без просмотра.
HasReview? reviewOfViewing(LibraryMovie m, String? viewId) {
  for (final r in movieReviews(m)) {
    if (r.viewing?.id == viewId) return r.item;
  }
  return null;
}

/// Просмотры, на которые рецензии ещё нет, по порядку.
List<Viewing> unreviewedViewings(LibraryMovie m) {
  final taken = {
    for (final r in movieReviews(m))
      if (r.viewing != null) r.viewing!.id,
  };
  return [
    for (final v in m.orderedViewings)
      if (!taken.contains(v.id)) v,
  ];
}

/// Столбец свода: одна рецензия.
class ReviewColumn {
  /// Номер просмотра (у сериала — номер просмотра сезона).
  final int ordinal;

  /// Общая оценка: у фильма оценка просмотра, иначе средняя по пунктам.
  final double? score;
  final DateTime? date;
  final Map<String, double> criteria;
  const ReviewColumn({
    required this.ordinal,
    this.score,
    this.date,
    this.criteria = const {},
  });
}

/// Свод по пересмотрам: столбец на рецензию, строка на пункт разбора.
class ReviewsTableData {
  final List<ReviewColumn> columns;

  /// Пункты, оценённые хотя бы в одной рецензии, в каноническом порядке.
  final List<String> criteria;

  /// Разница по пункту между последней и первой рецензией, где он оценён.
  /// Пункта нет в карте, если он оценён меньше чем в двух рецензиях.
  final Map<String, double> deltas;

  /// Пункт с наибольшей разницей; null, если все разницы меньше 0.05.
  final String? strongest;

  /// Разница общей оценки между последней и первой рецензией.
  final double? scoreDelta;
  const ReviewsTableData({
    required this.columns,
    required this.criteria,
    required this.deltas,
    this.strongest,
    this.scoreDelta,
  });
}

/// Собирает свод из готовых столбцов; null, если их меньше двух.
ReviewsTableData? buildReviewsTable(List<ReviewColumn> columns) {
  if (columns.length < 2) return null;
  final criteria =
      sortCriteria([for (final c in columns) ...c.criteria.keys]);
  final deltas = <String, double>{};
  String? strongest;
  var gap = 0.05;
  for (final id in criteria) {
    final values = [
      for (final c in columns)
        if (c.criteria[id] != null) c.criteria[id]!,
    ];
    if (values.length < 2) continue;
    final d = ((values.last - values.first) * 10).round() / 10;
    deltas[id] = d;
    if (d.abs() > gap) {
      gap = d.abs();
      strongest = id;
    }
  }
  final scores = [
    for (final c in columns)
      if (c.score != null) c.score!,
  ];
  return ReviewsTableData(
    columns: columns,
    criteria: criteria,
    deltas: deltas,
    strongest: strongest,
    scoreDelta: scores.length < 2
        ? null
        : ((scores.last - scores.first) * 10).round() / 10,
  );
}

/// Свод по пересмотрам фильма: опубликованные рецензии с просмотром, по
/// порядку. null, если таких меньше двух.
ReviewsTableData? movieReviewsTable(LibraryMovie m) => buildReviewsTable([
      for (final r in movieReviews(m))
        if (r.viewing != null && !(r.meta?.draft ?? false))
          ReviewColumn(
            ordinal: r.ordinal,
            score: r.viewing!.score ?? r.meta?.average,
            date: r.viewing!.date ?? r.meta?.shownDate,
            criteria: r.meta?.criteria ?? const {},
          ),
    ]);
