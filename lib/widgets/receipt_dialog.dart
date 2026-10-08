import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../data/expense_repository.dart';
import '../models/shared_budget.dart';

/// Opens the receipt photo kept for a scanned record. The fetch starts
/// before the dialog so that rebuilding the dialog does not fetch again.
void showReceiptDialog(
  BuildContext context,
  ExpenseRepository repository,
  String receiptId,
) {
  final photo = repository.fetchReceipt(kSharedBudgetCode, receiptId);
  showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      insetPadding: const EdgeInsets.all(12),
      clipBehavior: Clip.antiAlias,
      child: FutureBuilder<Uint8List?>(
        future: photo,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const SizedBox(
              height: 240,
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final bytes = snapshot.data;
          if (bytes == null) {
            return const SizedBox(
              height: 160,
              child: Center(child: Text('Фото не найдено')),
            );
          }
          return InteractiveViewer(child: Image.memory(bytes));
        },
      ),
    ),
  );
}
