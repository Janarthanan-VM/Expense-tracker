import 'category.dart';

/// Seeded on first launch. IDs are fixed so rules and future
/// auto-categorisation can refer to them.
const List<TxnCategory> defaultCategories = [
  // Expense
  TxnCategory(id: 'food', name: 'Food & dining', iconKey: 'restaurant', colorValue: 0xFFE65100, kind: CategoryKind.expense, isDefault: true, sortOrder: 1),
  TxnCategory(id: 'groceries', name: 'Groceries', iconKey: 'groceries', colorValue: 0xFF2E7D32, kind: CategoryKind.expense, isDefault: true, sortOrder: 2),
  TxnCategory(id: 'transport', name: 'Transport', iconKey: 'transport', colorValue: 0xFF1565C0, kind: CategoryKind.expense, isDefault: true, sortOrder: 3),
  TxnCategory(id: 'fuel', name: 'Fuel', iconKey: 'fuel', colorValue: 0xFF6D4C41, kind: CategoryKind.expense, isDefault: true, sortOrder: 4),
  TxnCategory(id: 'bills', name: 'Bills & recharge', iconKey: 'bills', colorValue: 0xFF6A1B9A, kind: CategoryKind.expense, isDefault: true, sortOrder: 5),
  TxnCategory(id: 'rent', name: 'Rent', iconKey: 'home', colorValue: 0xFF283593, kind: CategoryKind.expense, isDefault: true, sortOrder: 6),
  TxnCategory(id: 'shopping', name: 'Shopping', iconKey: 'shopping', colorValue: 0xFFAD1457, kind: CategoryKind.expense, isDefault: true, sortOrder: 7),
  TxnCategory(id: 'health', name: 'Health', iconKey: 'health', colorValue: 0xFFC62828, kind: CategoryKind.expense, isDefault: true, sortOrder: 8),
  TxnCategory(id: 'entertainment', name: 'Entertainment', iconKey: 'entertainment', colorValue: 0xFFF9A825, kind: CategoryKind.expense, isDefault: true, sortOrder: 9),
  TxnCategory(id: 'education', name: 'Education', iconKey: 'education', colorValue: 0xFF00796B, kind: CategoryKind.expense, isDefault: true, sortOrder: 10),
  TxnCategory(id: 'travel', name: 'Travel', iconKey: 'travel', colorValue: 0xFF0277BD, kind: CategoryKind.expense, isDefault: true, sortOrder: 11),
  TxnCategory(id: 'family', name: 'Family & friends', iconKey: 'family', colorValue: 0xFF558B2F, kind: CategoryKind.expense, isDefault: true, sortOrder: 12),
  TxnCategory(id: 'other_expense', name: 'Other', iconKey: 'other', colorValue: 0xFF546E7A, kind: CategoryKind.expense, isDefault: true, sortOrder: 99),

  // Income
  TxnCategory(id: 'salary', name: 'Salary', iconKey: 'salary', colorValue: 0xFF2E7D32, kind: CategoryKind.income, isDefault: true, sortOrder: 1),
  TxnCategory(id: 'received', name: 'Received from people', iconKey: 'received', colorValue: 0xFF1565C0, kind: CategoryKind.income, isDefault: true, sortOrder: 2),
  TxnCategory(id: 'refund', name: 'Refund', iconKey: 'refund', colorValue: 0xFF00796B, kind: CategoryKind.income, isDefault: true, sortOrder: 3),
  TxnCategory(id: 'cashback', name: 'Cashback & rewards', iconKey: 'cashback', colorValue: 0xFFF9A825, kind: CategoryKind.income, isDefault: true, sortOrder: 4),
  TxnCategory(id: 'other_income', name: 'Other income', iconKey: 'other', colorValue: 0xFF546E7A, kind: CategoryKind.income, isDefault: true, sortOrder: 99),

  // Transfer (not counted as spending or income)
  TxnCategory(id: 'self_transfer', name: 'Own account transfer', iconKey: 'transfer', colorValue: 0xFF546E7A, kind: CategoryKind.transfer, isDefault: true, sortOrder: 1),
];
