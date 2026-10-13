import 'package:flutter/material.dart';

import 'category_icons.dart';

enum CategoryKind { expense, income, transfer }

extension CategoryKindLabel on CategoryKind {
  String get label => switch (this) {
        CategoryKind.expense => 'Expense',
        CategoryKind.income => 'Income',
        CategoryKind.transfer => 'Transfer',
      };
}

class TxnCategory {
  const TxnCategory({
    required this.id,
    required this.name,
    required this.iconKey,
    required this.colorValue,
    required this.kind,
    this.parentId,
    this.isDefault = false,
    this.isHidden = false,
    this.sortOrder = 0,
  });

  final String id;
  final String name;
  final String iconKey;
  final int colorValue;
  final CategoryKind kind;
  final String? parentId;
  final bool isDefault;
  final bool isHidden;
  final int sortOrder;

  Color get color => Color(colorValue);
  IconData get icon => categoryIcon(iconKey);

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'icon_key': iconKey,
        'color': colorValue,
        'kind': kind.name,
        'parent_id': parentId,
        'is_default': isDefault ? 1 : 0,
        'is_hidden': isHidden ? 1 : 0,
        'sort_order': sortOrder,
      };

  factory TxnCategory.fromMap(Map<String, Object?> m) => TxnCategory(
        id: m['id']! as String,
        name: m['name']! as String,
        iconKey: m['icon_key']! as String,
        colorValue: m['color']! as int,
        kind: CategoryKind.values.byName(m['kind']! as String),
        parentId: m['parent_id'] as String?,
        isDefault: m['is_default'] == 1,
        isHidden: m['is_hidden'] == 1,
        sortOrder: (m['sort_order'] as int?) ?? 0,
      );
}
