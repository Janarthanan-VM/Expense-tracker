import 'package:flutter_test/flutter_test.dart';

import 'package:expense_tracker/core/utils/formatters.dart';
import 'package:expense_tracker/features/categories/category.dart';
import 'package:expense_tracker/features/categories/default_categories.dart';
import 'package:expense_tracker/features/transactions/transaction_repository.dart';
import 'package:expense_tracker/features/transactions/txn.dart';

void main() {
  group('money', () {
    test('parses rupees into paise', () {
      expect(parseRupeesToPaise('250'), 25000);
      expect(parseRupeesToPaise('250.5'), 25050);
      expect(parseRupeesToPaise('1,200.75'), 120075);
      expect(parseRupeesToPaise('₹ 99'), 9900);
    });

    test('rejects empty, zero and invalid amounts', () {
      expect(parseRupeesToPaise(''), isNull);
      expect(parseRupeesToPaise('0'), isNull);
      expect(parseRupeesToPaise('-10'), isNull);
      expect(parseRupeesToPaise('abc'), isNull);
    });

    test('formats paise in Indian style', () {
      expect(formatPaise(25000), '₹250');
      expect(formatPaise(25050), '₹250.50');
      expect(formatPaise(10000000), '₹1,00,000');
    });
  });

  group('payee matching', () {
    test('prefers UPI ID over name and ignores case', () {
      expect(
        TransactionRepository.payeeMatchKey(vpa: ' SriStores@OKAXIS ', name: 'Sri Stores'),
        'vpa:sristores@okaxis',
      );
      expect(TransactionRepository.payeeMatchKey(name: 'Ravi Kumar'), 'name:ravi kumar');
      expect(TransactionRepository.payeeMatchKey(), isNull);
    });
  });

  group('payee rules', () {
    test('are kept separately for paid and received money', () {
      const payee = 'vpa:swiggy@icici';
      expect(TransactionRepository.ruleKey(TxnType.debit, payee), 'debit|vpa:swiggy@icici');
      expect(TransactionRepository.ruleKey(TxnType.credit, payee), 'credit|vpa:swiggy@icici');
      expect(
        TransactionRepository.ruleKey(TxnType.debit, payee),
        isNot(TransactionRepository.ruleKey(TxnType.credit, payee)),
      );
    });
  });

  group('payment method', () {
    test('is saved and read back for every method', () {
      for (final mode in PaymentMode.values) {
        final now = DateTime(2026, 10, 13, 9, 30);
        final txn = Txn(
          id: 'id-${mode.name}',
          amountPaise: 5000,
          type: TxnType.debit,
          status: TxnStatus.success,
          source: TxnSource.manual,
          paymentMode: mode,
          txnTime: now,
          createdAt: now,
          updatedAt: now,
        );
        expect(Txn.fromMap(txn.toMap()).paymentMode, mode);
      }
    });

    test('unknown or missing value falls back to other', () {
      final now = DateTime(2026, 10, 13).millisecondsSinceEpoch;
      final row = {
        'id': 'x',
        'amount_paise': 100,
        'type': 'debit',
        'status': 'success',
        'source': 'manual',
        'payment_mode': null,
        'is_reviewed': 0,
        'txn_time': now,
        'created_at': now,
        'updated_at': now,
      };
      expect(Txn.fromMap(row).paymentMode, PaymentMode.other);
    });
  });

  group('default categories', () {
    test('have unique ids', () {
      final ids = defaultCategories.map((c) => c.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('round-trip through the database map', () {
      for (final c in defaultCategories) {
        final back = TxnCategory.fromMap(c.toMap());
        expect(back.id, c.id);
        expect(back.kind, c.kind);
        expect(back.iconKey, c.iconKey);
      }
    });
  });
}
