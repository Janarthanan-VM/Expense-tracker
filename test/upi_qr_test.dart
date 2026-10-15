import 'package:flutter_test/flutter_test.dart';

import 'package:expense_tracker/features/scanpay/upi_qr.dart';

void main() {
  group('UPI QR', () {
    test('reads a merchant QR with amount and category code', () {
      final qr = UpiQr.parse(
        'upi://pay?pa=SriStores@okaxis&pn=Sri%20Krishna%20Stores&am=250.00&cu=INR&mc=5411&tn=Order%2012',
      )!;
      expect(qr.vpa, 'sristores@okaxis');
      expect(qr.name, 'Sri Krishna Stores');
      expect(qr.amountPaise, 25000);
      expect(qr.note, 'Order 12');
      expect(qr.suggestedCategoryId, 'groceries');
    });

    test('reads a personal QR without amount', () {
      final qr = UpiQr.parse('upi://pay?pa=ravi@ybl&pn=Ravi+Kumar')!;
      expect(qr.name, 'Ravi Kumar');
      expect(qr.amountPaise, isNull);
      expect(qr.suggestedCategoryId, isNull);
    });

    test('keys are read in any case', () {
      expect(UpiQr.parse('UPI://PAY?PA=shop@paytm&PN=Shop')?.vpa, 'shop@paytm');
    });

    test('rejects things that are not UPI payment QRs', () {
      expect(UpiQr.parse('https://example.com'), isNull);
      expect(UpiQr.parse('upi://pay?pn=NoId'), isNull);
      expect(UpiQr.parse('upi://pay?pa=not-a-upi-id'), isNull);
      expect(UpiQr.parse(null), isNull);
      expect(UpiQr.parse('upi://pay?pa=a@b&am=%ZZ'), isNull);
    });

    test('the pay link keeps the QR and adds a missing amount', () {
      final qr = UpiQr.parse('upi://pay?pa=ravi@ybl&pn=Ravi%20Kumar')!;
      expect(qr.payLink(amountPaise: 15050), 'upi://pay?pa=ravi@ybl&pn=Ravi%20Kumar&am=150.50&cu=INR');
    });

    test('the pay link never changes a fixed amount', () {
      const raw = 'upi://pay?pa=shop@okaxis&am=99.00&cu=INR&sign=abc';
      expect(UpiQr.parse(raw)!.payLink(amountPaise: 1), raw);
    });

    test('an empty amount field is filled in', () {
      final qr = UpiQr.parse('upi://pay?pa=shop@okaxis&am=&cu=INR')!;
      expect(qr.payLink(amountPaise: 2000), 'upi://pay?pa=shop@okaxis&am=20.00&cu=INR');
    });

    test('category codes map to categories', () {
      expect(UpiQr.mccCategory('5812'), 'food');
      expect(UpiQr.mccCategory('5541'), 'fuel');
      expect(UpiQr.mccCategory('4121'), 'transport');
      expect(UpiQr.mccCategory('0000'), isNull);
      expect(UpiQr.mccCategory(null), isNull);
    });
  });

  group('UPI app reply', () {
    test('success with a bank reference', () {
      final r = UpiResponse.parse('txnId=AXI123&responseCode=00&Status=SUCCESS&txnRef=x1&ApprovalRefNo=428612345678');
      expect(r.result, UpiResult.success);
      expect(r.reference, '428612345678');
    });

    test('failure', () {
      expect(UpiResponse.parse('Status=FAILURE&responseCode=ZD').result, UpiResult.failure);
    });

    test('submitted is still waiting', () {
      expect(UpiResponse.parse('status=submitted').result, UpiResult.submitted);
    });

    test('no reply is unknown', () {
      expect(UpiResponse.parse(null).result, UpiResult.unknown);
      expect(UpiResponse.parse('').result, UpiResult.unknown);
    });
  });
}
