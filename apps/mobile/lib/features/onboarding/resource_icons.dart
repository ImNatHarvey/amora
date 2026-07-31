import 'package:flutter/material.dart';

/// Maps `resource_catalog.icon` values to real icons.
///
/// The database stores Material Symbols *names* as text. Flutter cannot build
/// an `IconData` from a string at runtime unless icon tree-shaking is disabled,
/// which inflates the bundle for every icon in the font — so the mapping is an
/// explicit const table instead.
///
/// Anything unmapped falls back to [_fallback] rather than breaking the grid,
/// which means a new seed row renders sensibly before this table catches up.
const _icons = <String, IconData>{
  // outdoor
  'deck': Icons.deck,
  'cabin': Icons.cabin,
  'camping': Icons.holiday_village,
  'chair': Icons.chair,
  'kitchen': Icons.kitchen,
  'flashlight_on': Icons.flashlight_on,
  // kitchen
  'egg': Icons.egg,
  'blender': Icons.blender,
  'outdoor_grill': Icons.outdoor_grill,
  'cake': Icons.cake,
  // craft
  'palette': Icons.palette,
  'description': Icons.description,
  'content_cut': Icons.content_cut,
  'edit': Icons.edit,
  'redeem': Icons.redeem,
  'print': Icons.print,
  'photo_camera': Icons.photo_camera,
  // sports
  'sports_basketball': Icons.sports_basketball,
  'sports_tennis': Icons.sports_tennis,
  'sports_volleyball': Icons.sports_volleyball,
  'self_improvement': Icons.self_improvement,
  // games
  'casino': Icons.casino,
  'style': Icons.style,
  'menu_book': Icons.menu_book,
  'sports_esports': Icons.sports_esports,
  // tech
  'speaker': Icons.speaker,
  'cast': Icons.cast,
  // transport
  'pedal_bike': Icons.pedal_bike,
  'two_wheeler': Icons.two_wheeler,
  'directions_car': Icons.directions_car,
};

const _fallback = Icons.inventory_2_outlined;

IconData resourceIcon(String? name) => _icons[name] ?? _fallback;

/// Turns a catalogue category slug into a section heading.
String resourceCategoryLabel(String? category) => switch (category) {
      'outdoor' => 'Outdoor',
      'kitchen' => 'Kitchen',
      'craft' => 'Craft and paper',
      'sports' => 'Sports',
      'games' => 'Games and books',
      'tech' => 'Tech',
      'transport' => 'Getting around',
      _ => 'Other',
    };
