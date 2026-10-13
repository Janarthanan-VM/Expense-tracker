import 'dart:convert';

import '../categories/category.dart';
import '../categories/category_repository.dart';
import '../transactions/transaction_repository.dart';
import '../transactions/txn.dart';
import 'detection_service.dart';

/// Moves payments queued by the Android listener into the encrypted database
/// and keeps the notification's category buttons up to date.
class DetectionSync {
  DetectionSync(this._service, this._txns, this._categories);

  final DetectionService _service;
  final TransactionRepository _txns;
  final CategoryRepository _categories;

  bool _running = false;
  bool _again = false;

  /// Returns true if any transaction was added or changed.
  /// Calls made while a sync is running are folded into it.
  Future<bool> run() async {
    if (_running) {
      _again = true;
      return false;
    }
    _running = true;
    var changed = false;
    try {
      do {
        _again = false;
        changed = await _runOnce() || changed;
      } while (_again);
    } finally {
      _running = false;
    }
    return changed;
  }

  Future<bool> _runOnce() async {
    final events = await _service.takeEvents();
    final categories = await _categories.all();
    var changed = false;

    if (events.isNotEmpty) {
      final validIds = {for (final c in categories) c.id};
      final ordered = [...events]
        ..sort((a, b) => (a.time ?? DateTime(0)).compareTo(b.time ?? DateTime(0)));
      for (final e in ordered) {
        if (await _txns.upsertDetected(e, validIds)) changed = true;
      }
    }

    await _pushHints(categories);
    return changed;
  }

  Future<void> _pushHints(List<TxnCategory> categories) async {
    final byId = {for (final c in categories) c.id: c};
    Future<List<Map<String, String>>> top(TxnType type) async {
      final ids = await _txns.topCategoryIds(type);
      return [
        for (final id in ids)
          if (byId[id] != null) {'id': id, 'name': byId[id]!.name},
      ];
    }

    final hints = {
      'debit': await top(TxnType.debit),
      'credit': await top(TxnType.credit),
    };
    await _service.setCategoryHints(jsonEncode(hints));
  }
}
