/// One entry in the shared `resource_catalog` — something a user might already
/// own. Read-only to the app; the catalogue is curated, not user-editable.
class Resource {
  const Resource({
    required this.id,
    required this.slug,
    required this.name,
    this.category,
    this.icon,
  });

  factory Resource.fromMap(Map<String, dynamic> map) {
    return Resource(
      id: map['id'] as String,
      slug: map['slug'] as String,
      name: map['name'] as String,
      category: map['category'] as String?,
      icon: map['icon'] as String?,
    );
  }

  final String id;

  /// Stable natural key, referenced by `activities.required_resource_ids`
  /// through the seed importer.
  final String slug;
  final String name;

  /// Groups the picker: outdoor, kitchen, craft, sports, games, tech, transport.
  final String? category;

  /// A Material Symbols name such as `deck`. Resolved to an `IconData` by a
  /// const lookup in the UI layer — Flutter cannot build one from a string at
  /// runtime without disabling icon tree-shaking.
  final String? icon;
}
