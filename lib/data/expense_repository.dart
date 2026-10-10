import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/away.dart';
import '../models/expense.dart';
import '../models/fines.dart';

class ExpenseRepository {
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _budgetRef(String householdCode) =>
      _firestore.collection('households').doc(householdCode);

  CollectionReference<Map<String, dynamic>> _expensesRef(
          String householdCode) =>
      _budgetRef(householdCode).collection('expenses');

  CollectionReference<Map<String, dynamic>> _receiptsRef(
          String householdCode) =>
      _budgetRef(householdCode).collection('receipts');

  /// Who is away lives in one settings document, apart from the records:
  /// it is state rather than history, and closing a period must not
  /// archive it.
  DocumentReference<Map<String, dynamic>> _awayRef(String householdCode) =>
      _budgetRef(householdCode).collection('settings').doc('away');

  Stream<AwayBook> watchAway(String householdCode) => _awayRef(householdCode)
      .snapshots()
      .map((snapshot) => AwayBook.fromJson(snapshot.data()));

  /// Asks to be counted out. Replaces any earlier request of [name]'s
  /// whole, so the votes on a turned-down one do not carry over.
  Future<void> requestAway(String householdCode, AwayRequest request) {
    return _awayRef(householdCode).set(
      {request.name: request.toJson()},
      SetOptions(mergeFields: [
        FieldPath([request.name])
      ]),
    );
  }

  /// An approver's answer, written to the one field so two answering at
  /// once never overwrite each other.
  Future<void> voteAway(
    String householdCode,
    String name,
    String judge,
    String vote,
  ) {
    return _awayRef(householdCode).update({
      FieldPath([name, 'votes', judge]): vote
    });
  }

  /// Back home, a request withdrawn, or a refusal seen: [name] is simply
  /// home again.
  Future<void> clearAway(String householdCode, String name) {
    return _awayRef(householdCode).set(
      {name: FieldValue.delete()},
      SetOptions(merge: true),
    );
  }

  Stream<List<Expense>> watchExpenses(String householdCode) {
    return _expensesRef(householdCode)
        .orderBy('date', descending: true)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => Expense.fromJson(doc.data())).toList());
  }

  Future<void> addExpense(String householdCode, Expense expense) {
    return _expensesRef(householdCode).doc(expense.id).set(expense.toJson());
  }

  /// Writes several records at once.
  ///
  /// One batch rather than a loop of writes: the scanner can hand over a
  /// dozen rows off a single screenshot, and a batch is both one round
  /// trip and all-or-nothing -- a half-entered statement would be worse
  /// than none of it.
  Future<void> addExpenses(String householdCode, List<Expense> expenses) {
    if (expenses.isEmpty) return Future.value();
    final batch = _firestore.batch();
    final ref = _expensesRef(householdCode);
    for (final expense in expenses) {
      batch.set(ref.doc(expense.id), expense.toJson());
    }
    return batch.commit();
  }

  Future<void> deleteExpense(String householdCode, String expenseId) {
    return _expensesRef(householdCode).doc(expenseId).delete();
  }

  /// Stores a receipt photo under [receiptId]. Kept apart from the records
  /// so the list never has to download a picture to show a row.
  Future<void> addReceipt(
    String householdCode,
    String receiptId,
    Uint8List jpeg,
  ) {
    return _receiptsRef(householdCode).doc(receiptId).set({
      'data': base64Encode(jpeg),
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Null when the photo is gone, which is the case for a receipt whose
  /// budget was cleared.
  Future<Uint8List?> fetchReceipt(
      String householdCode, String receiptId) async {
    final snapshot = await _receiptsRef(householdCode).doc(receiptId).get();
    final data = snapshot.data()?['data'] as String?;
    return data == null ? null : base64Decode(data);
  }

  /// The recipient's word that a transfer arrived; from here on it moves
  /// balances.
  Future<void> confirmTransfer(String householdCode, String expenseId) {
    return _expensesRef(householdCode)
        .doc(expenseId)
        .update({'confirmed': true});
  }

  /// A judge's vote on a fine. Written to the one field, so two judges
  /// voting at once never overwrite each other.
  Future<void> voteOnFine(
    String householdCode,
    String fineId,
    String judge,
    String vote,
  ) {
    return _expensesRef(householdCode).doc(fineId).update({
      FieldPath(['votes', judge]): vote
    });
  }

  /// The offender's answer. A dispute also clears the judges' votes, so
  /// the fine only stands if they all confirm it again.
  Future<void> answerFine(String householdCode, String fineId, String answer) {
    return _expensesRef(householdCode).doc(fineId).update({
      'offenderVote': answer,
      if (answer == kOffenderDispute) 'votes': <String, String>{},
    });
  }

  /// Moves a settled period to history by stamping every one of its
  /// records with the same [at]. Chunked like [clearAll]: Firestore refuses
  /// a batch of more than 500 writes.
  Future<void> archive(
    String householdCode,
    List<String> expenseIds,
    DateTime at,
  ) async {
    const chunkSize = 500;
    final ref = _expensesRef(householdCode);
    for (var i = 0; i < expenseIds.length; i += chunkSize) {
      final batch = _firestore.batch();
      for (final id in expenseIds.skip(i).take(chunkSize)) {
        batch.update(ref.doc(id), {'archivedAt': Timestamp.fromDate(at)});
      }
      await batch.commit();
    }
  }

  /// Deletes every record in the budget. Firestore refuses a batch of more
  /// than 500 writes, so a budget that has been running for a while is
  /// cleared in chunks.
  Future<void> clearAll(String householdCode) async {
    final snapshot = await _expensesRef(householdCode).get();
    const chunkSize = 500;
    for (var i = 0; i < snapshot.docs.length; i += chunkSize) {
      final batch = _firestore.batch();
      for (final doc in snapshot.docs.skip(i).take(chunkSize)) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    }
  }
}
