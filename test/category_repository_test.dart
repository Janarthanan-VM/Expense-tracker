import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:expense_tracker/core/db/app_database.dart';
import 'package:expense_tracker/features/categories/category.dart';
import 'package:expense_tracker/features/categories/category_repository.dart';

void main() {
  sqfliteFfiInit();
  late Database db;
  late CategoryRepository repo;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    await AppDatabase.createSchema(db);
    repo = CategoryRepository(db);
  });

  tearDown(() => db.close());

  test('quick add creates a category with just a name', () async {
    final id = await repo.addNamed('Gym', CategoryKind.expense);
    final c = (await repo.all()).firstWhere((c) => c.id == id);
    expect(c.name, 'Gym');
    expect(c.kind, CategoryKind.expense);
    expect(c.iconKey, 'label');
  });

  test('an existing name is found instead of creating a duplicate', () async {
    expect(await repo.idForName(' groceries ', CategoryKind.expense), 'groceries');
    expect(await repo.idForName('Groceries', CategoryKind.income), isNull);
  });

  test('name, icon and colour can be changed later', () async {
    final id = await repo.addNamed('Gym', CategoryKind.expense);
    await repo.update(id, name: 'Fitness', iconKey: 'fitness', colorValue: 0xFF00796B);
    final c = (await repo.all()).firstWhere((c) => c.id == id);
    expect(c.name, 'Fitness');
    expect(c.iconKey, 'fitness');
    expect(c.colorValue, 0xFF00796B);
  });
}
