import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'category.dart';
import 'category_icons.dart';

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

  /// Creates a category and returns its id.
  Future<String> add({
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

    final id = _uuid.v4();
    await _db.insert(
      'categories',
      TxnCategory(
        id: id,
        name: name.trim(),
        iconKey: iconKey,
        colorValue: colorValue,
        kind: kind,
        sortOrder: maxOrder + 1,
      ).toMap(),
    );
    return id;
  }

  /// Quick add from the category picker: just a name. The icon and colour can
  /// be changed later on the Categories page.
  Future<String> addNamed(String name, CategoryKind kind) async {
    final count = Sqflite.firstIntValue(await _db.rawQuery('SELECT COUNT(*) FROM categories')) ?? 0;
    return add(
      name: name,
      kind: kind,
      iconKey: 'label',
      colorValue: kCategoryColors[count % kCategoryColors.length],
    );
  }

  /// Changes name, icon and colour.
  Future<void> update(String id, {required String name, required String iconKey, required int colorValue}) =>
      _db.update(
        'categories',
        {'name': name.trim(), 'icon_key': iconKey, 'color': colorValue},
        where: 'id = ?',
        whereArgs: [id],
      );

  /// True when a category with this name (any case) already exists for [kind].
  Future<String?> idForName(String name, CategoryKind kind) async {
    final rows = await _db.query(
      'categories',
      columns: ['id'],
      where: 'LOWER(TRIM(name)) = ? AND kind = ?',
      whereArgs: [name.trim().toLowerCase(), kind.name],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['id']! as String;
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
