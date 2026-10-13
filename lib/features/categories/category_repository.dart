import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'category.dart';

class CategoryRepository {
  CategoryRepository(this._db);

  final Database _db;
  static const _uuid = Uuid();

  Future<List<TxnCategory>> all({bool includeHidden = true}) async {
    final rows = await _db.query(
      'categories',
      where: includeHidden ? null : 'is_hidden = 0',
      orderBy: 'sort_order, name',
    );
    return rows.map(TxnCategory.fromMap).toList();
  }

  Future<void> add({
    required String name,
    required CategoryKind kind,
    required String iconKey,
    required int colorValue,
  }) async {
    // Custom categories go just before "Other" (sort_order 99).
    final result = await _db.rawQuery(
      'SELECT COALESCE(MAX(sort_order), 0) AS max_order FROM categories '
      'WHERE kind = ? AND sort_order < 99',
      [kind.name],
    );
    final maxOrder = (result.first['max_order'] as int?) ?? 0;

    await _db.insert(
      'categories',
      TxnCategory(
        id: _uuid.v4(),
        name: name.trim(),
        iconKey: iconKey,
        colorValue: colorValue,
        kind: kind,
        sortOrder: maxOrder + 1,
      ).toMap(),
    );
  }

  Future<void> rename(String id, String name) => _db.update(
        'categories',
        {'name': name.trim()},
        where: 'id = ?',
        whereArgs: [id],
      );

  /// Hidden categories stay on old payments but are not offered in the picker.
  Future<void> setHidden(String id, bool hidden) => _db.update(
        'categories',
        {'is_hidden': hidden ? 1 : 0},
        where: 'id = ?',
        whereArgs: [id],
      );
}
