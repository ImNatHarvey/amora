/// Something a couple can do, independent of where they do it.
///
/// Activities are generic and reusable — "picnic in the park", "street food
/// crawl" — which is why they carry a budget range and a resource requirement
/// but no location. The place supplies the where.
class Activity {
  const Activity({
    required this.id,
    required this.slug,
    required this.title,
    required this.minBudgetPhpCents,
    this.category,
    this.maxBudgetPhpCents,
    this.durationMinutes,
    this.weatherDependent = false,
    this.isDiy = false,
  });

  factory Activity.fromMap(Map<String, dynamic> map) {
    return Activity(
      id: map['activity_id'] as String,
      slug: map['slug'] as String,
      title: map['title'] as String,
      category: map['category'] as String?,
      minBudgetPhpCents: map['min_budget_php_cents'] as int,
      maxBudgetPhpCents: map['max_budget_php_cents'] as int?,
      durationMinutes: map['duration_minutes'] as int?,
      weatherDependent: map['weather_dependent'] as bool? ?? false,
      isDiy: map['is_diy'] as bool? ?? false,
    );
  }

  final String id;
  final String slug;
  final String title;

  /// `outdoor`, `fitness`, `diy`, `cooking`, `food`, `indoor`.
  final String? category;
  final int minBudgetPhpCents;
  final int? maxBudgetPhpCents;
  final int? durationMinutes;

  /// Matters from Phase 8 (weather-aware replanning). Carried now because the
  /// column already exists and dropping it on the floor would be a lie about
  /// what retrieval returned.
  final bool weatherDependent;
  final bool isDiy;
}
