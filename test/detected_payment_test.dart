import 'package:flutter_test/flutter_test.dart';

import 'package:expense_tracker/features/detection/detected_payment.dart';

void main() {
  test('reads a full payment from the Android queue', () {
    final p = DetectedPayment.fromJson({
      'id': 'abc',
      'amountPaise': 25000,
      'isDebit': true,
      'mode': 'upi',
      'source': 'sms',
      'app': 'HDFCBK',
      'time': 1760300000000,
      'payeeName': 'Sri Krishna Stores',
      'payeeVpa': 'shop@okaxis',
      'upiRef': '428612345678',
    });
    expect(p.hasPayment, isTrue);
    expect(p.amountPaise, 25000);
    expect(p.isDebit, isTrue);
    expect(p.time, DateTime.fromMillisecondsSinceEpoch(1760300000000));
    expect(p.upiRef, '428612345678');
    expect(p.categoryId, isNull);
  });

  test('a category-only item is not a new payment', () {
    final p = DetectedPayment.fromJson({'id': 'abc', 'categoryId': 'food'});
    expect(p.hasPayment, isFalse);
    expect(p.categoryId, 'food');
  });

  test('blank strings are treated as missing', () {
    final p = DetectedPayment.fromJson({
      'id': 'x',
      'amountPaise': 100,
      'isDebit': false,
      'payeeName': '  ',
    });
    expect(p.payeeName, isNull);
    expect(p.hasPayment, isTrue);
  });
}
