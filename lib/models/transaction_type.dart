/// [income] is only read back from records made before the flat stopped
/// recording income; nothing creates it any more. [transfer] is one flatmate
/// paying another back.
enum TransactionType { expense, income, transfer }

extension TransactionTypeX on TransactionType {
  String get storageKey => name;

  static TransactionType fromStorageKey(String? key) {
    return TransactionType.values.firstWhere(
      (t) => t.name == key,
      orElse: () => TransactionType.expense,
    );
  }
}
