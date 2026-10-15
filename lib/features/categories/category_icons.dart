import 'package:flutter/material.dart';

/// Icons are stored in the database by key (not code point) so Flutter's
/// icon tree-shaking keeps working in release builds.
const Map<String, IconData> kCategoryIcons = {
  'restaurant': Icons.restaurant,
  'coffee': Icons.local_cafe,
  'groceries': Icons.shopping_cart,
  'transport': Icons.directions_bus,
  'fuel': Icons.local_gas_station,
  'bills': Icons.receipt_long,
  'phone': Icons.phone_android,
  'home': Icons.home,
  'shopping': Icons.shopping_bag,
  'health': Icons.local_hospital,
  'entertainment': Icons.movie,
  'education': Icons.school,
  'travel': Icons.flight,
  'personal': Icons.face,
  'gift': Icons.card_giftcard,
  'family': Icons.people,
  'pets': Icons.pets,
  'fitness': Icons.fitness_center,
  'salary': Icons.work,
  'refund': Icons.undo,
  'received': Icons.call_received,
  'cashback': Icons.savings,
  'transfer': Icons.swap_horiz,
  'split': Icons.call_split,
  'other': Icons.more_horiz,
  'label': Icons.sell_outlined,
};

IconData categoryIcon(String key) => kCategoryIcons[key] ?? Icons.category;

/// Colour choices offered when the user creates a category.
const List<int> kCategoryColors = [
  0xFFE65100, 0xFF2E7D32, 0xFF1565C0, 0xFF6D4C41, 0xFF6A1B9A,
  0xFF283593, 0xFFAD1457, 0xFFC62828, 0xFFF9A825, 0xFF00796B,
  0xFF0277BD, 0xFF558B2F, 0xFF4E342E, 0xFF546E7A,
];
