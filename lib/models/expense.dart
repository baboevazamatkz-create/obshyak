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

  /// Income only: true when it is pooled for everyone (split four ways),
  /// false when it is the author's own money.
  final bool shared;

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
    this.shared = false,
  });

  bool get isIncome => type == TransactionType.income;

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
        shared: shared,
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
        'shared': shared,
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
        shared: json['shared'] as bool? ?? false,
      );
}
