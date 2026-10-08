import 'package:cloud_firestore/cloud_firestore.dart';

import 'currency.dart';
import 'expense_category.dart';
import 'transaction_type.dart';

class Expense {
  final String id;
  final double amount;
  final ExpenseCategory? category;
  final String note;
  final DateTime date;
  final AppCurrency currency;
  final TransactionType type;

  /// Which of the flatmates entered the record. Empty for records written
  /// before names existed.
  final String author;

  /// Id of the receipt photo in the budget's `receipts` collection, when
  /// the record came from a scan.
  final String? receiptId;

  /// Expense only: the part of the receipt that was for the author alone.
  /// It is kept out of what the flat splits.
  final double personal;

  /// Transfer only: the flatmate who was paid back. The author is the one
  /// who paid.
  final String? recipient;

  /// When the period this record belonged to was settled and moved to
  /// history. Null while the record is part of the open period.
  final DateTime? archivedAt;

  /// Transfer only: false from the moment the payer says they paid until
  /// the recipient confirms the money arrived. An unconfirmed transfer
  /// moves no balance. Older transfers, made before confirmation existed,
  /// read as confirmed.
  final bool confirmed;

  const Expense({
    required this.id,
    required this.amount,
    required this.date,
    this.category,
    this.note = '',
    this.currency = AppCurrency.rub,
    this.type = TransactionType.expense,
    this.author = '',
    this.receiptId,
    this.personal = 0,
    this.recipient,
    this.archivedAt,
    this.confirmed = true,
  });

  bool get isIncome => type == TransactionType.income;
  bool get isTransfer => type == TransactionType.transfer;
  bool get isPendingTransfer => isTransfer && !confirmed;

  /// What goes into the flat's split: the receipt minus the personal part.
  double get sharedAmount {
    final shared = amount - personal;
    return shared < 0 ? 0 : shared;
  }

  Expense copyWith({String? author, String? receiptId}) => Expense(
        id: id,
        amount: amount,
        date: date,
        category: category,
        note: note,
        currency: currency,
        type: type,
        author: author ?? this.author,
        receiptId: receiptId ?? this.receiptId,
        personal: personal,
        recipient: recipient,
        archivedAt: archivedAt,
        confirmed: confirmed,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'amount': amount,
        'category': category?.storageKey,
        'note': note,
        'date': Timestamp.fromDate(date),
        'currency': currency.storageKey,
        'type': type.storageKey,
        'author': author,
        'receiptId': receiptId,
        'personal': personal,
        'recipient': recipient,
        'archivedAt':
            archivedAt == null ? null : Timestamp.fromDate(archivedAt!),
        'confirmed': confirmed,
      };

  factory Expense.fromJson(Map<String, dynamic> json) => Expense(
        id: json['id'] as String,
        amount: (json['amount'] as num).toDouble(),
        category: json['category'] != null
            ? ExpenseCategoryX.fromStorageKey(json['category'] as String)
            : null,
        note: json['note'] as String? ?? '',
        date: (json['date'] as Timestamp).toDate(),
        currency: AppCurrencyX.fromStorageKey(json['currency'] as String?),
        type: TransactionTypeX.fromStorageKey(json['type'] as String?),
        author: json['author'] as String? ?? '',
        receiptId: json['receiptId'] as String?,
        personal: (json['personal'] as num?)?.toDouble() ?? 0,
        recipient: json['recipient'] as String?,
        archivedAt: (json['archivedAt'] as Timestamp?)?.toDate(),
        confirmed: json['confirmed'] as bool? ?? true,
      );
}
