import 'dart:async';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../data/expense_repository.dart';
import '../data/scan_service.dart';
import '../models/currency.dart';
import '../models/expense.dart';
import '../models/shared_budget.dart';
import '../models/shared_split.dart';
import '../models/transaction_type.dart';
import '../theme.dart';
import '../widgets/add_expense_sheet.dart';
import '../widgets/ai_scan_icon.dart';
import '../widgets/app_background_pattern.dart';
import '../widgets/expense_tile.dart';
import '../widgets/glass.dart';
import '../widgets/readable_width.dart';
import '../widgets/split_card.dart';
import 'scan_flow.dart';

final _monthDividerFormat = DateFormat('LLLL', 'ru');

/// How solid the three bottom-row buttons -- scan, expense, income -- sit
/// over the list behind them. One figure for all three rather than each
/// button choosing its own: they read as a set, so a difference in fill
/// opacity between them shows up as an inconsistency even when no single
/// button looks wrong on its own.
const double kFabFillOpacity = 0.82;

/// "Сентябрь" for the current year, "Сентябрь 2025" once it isn't -- the
/// label on a divider marking where one month's entries end and an older
/// month's begin in the chronological list. Not private, so it can be
/// unit-tested directly rather than only indirectly through a widget.
String monthDividerLabel(DateTime date) {
  final raw = _monthDividerFormat.format(date);
  final month = raw.isEmpty ? raw : raw[0].toUpperCase() + raw.substring(1);
  return date.year == DateTime.now().year ? month : '$month ${date.year}';
}

class HomeScreen extends StatefulWidget {
  /// The flatmate using this phone. Written into every record they add.
  final String myName;

  const HomeScreen({super.key, required this.myName});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _repository = ExpenseRepository();
  final _scanFlow = ScanFlow();

  /// Scanning needs a worker to talk to. With none configured there is
  /// nothing behind the button, so it is not shown at all.
  bool get _scanEnabled => ScanService.isConfigured;

  // Held in fields rather than created inside build(): a stream built during
  // build is a brand-new Firestore listener on every rebuild, which drops the
  // loaded data back to a spinner and re-reads the collection each time.
  late Stream<List<Expense>> _expensesStream;

  // The list's own controller, read by the top-edge fade so the band can
  // follow the scroll offset.
  final ScrollController _listController = ScrollController();

  // A stalled Firestore listener -- the case that matters is a backgrounded
  // mobile browser tab dropping its realtime connection -- would otherwise
  // leave the indeterminate spinner below spinning forever. That is not
  // just a bad look: an indeterminate CircularProgressIndicator keeps its
  // AnimationController ticking, which keeps the web engine requesting a
  // new frame every frame for as long as the tab stays open. This timer
  // gives up on that first wait after a while and offers a retry instead.
  Timer? _firstLoadTimer;
  bool _firstLoadTimedOut = false;

  @override
  void initState() {
    super.initState();
    _expensesStream = _repository.watchExpenses(kSharedBudgetCode);
    _startFirstLoadTimer();
  }

  @override
  void dispose() {
    _listController.dispose();
    _scanFlow.dispose();
    _firstLoadTimer?.cancel();
    super.dispose();
  }

  void _startFirstLoadTimer() {
    _firstLoadTimedOut = false;
    _firstLoadTimer?.cancel();
    _firstLoadTimer = Timer(const Duration(seconds: 20), () {
      if (mounted) setState(() => _firstLoadTimedOut = true);
    });
  }

  /// Drops the stalled listener and opens a fresh one, which is the closest
  /// thing to "reconnect" a Firestore stream offers from here.
  void _retryFirstLoad() => setState(() {
        _expensesStream = _repository.watchExpenses(kSharedBudgetCode);
        _startFirstLoadTimer();
      });

  /// Stamps whoever is using this phone as the author, unless the record
  /// already names one: a transfer is written for whoever paid, and an
  /// edited record keeps its original author.
  Future<void> _addExpense(Expense expense) {
    return _repository.addExpense(
      kSharedBudgetCode,
      expense.author.isEmpty
          ? expense.copyWith(author: widget.myName)
          : expense,
    );
  }

  /// Records that [settlement] has been paid, after asking: anyone can mark
  /// it, so the dialog spells out who paid whom.
  Future<void> _confirmSettlement(Settlement settlement) async {
    final amount = kBudgetCurrency.format.format(settlement.amount);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Перевод сделан?'),
        content: Text(
          '${settlement.from} перевёл ${settlement.to} $amount.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Да, оплачено'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _addExpense(Expense(
      id: const Uuid().v4(),
      amount: settlement.amount,
      date: DateTime.now(),
      currency: kBudgetCurrency,
      type: TransactionType.transfer,
      author: settlement.from,
      recipient: settlement.to,
    ));
  }

  Future<void> _openScanner(List<Expense> expenses) async {
    await _scanFlow.run(
      context,
      currency: kBudgetCurrency,
      existing: expenses,
      onAdd: (scanned, photo) async {
        // The flat records purchases only; an incoming payment read off a
        // bank screenshot has nowhere to go.
        final added = scanned.where((e) => !e.isIncome).toList();
        if (added.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('На снимке нет покупок')),
            );
          }
          return;
        }
        // The photo is written first so that no record ever points at a
        // receipt that is not there.
        String? receiptId;
        if (photo != null) {
          receiptId = const Uuid().v4();
          await _repository.addReceipt(kSharedBudgetCode, receiptId, photo);
        }
        await _repository.addExpenses(
          kSharedBudgetCode,
          [
            for (final expense in added)
              expense.copyWith(author: widget.myName, receiptId: receiptId),
          ],
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context)
          ..removeCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(added.length == 1
                  ? 'Запись добавлена'
                  : 'Добавлено записей: ${added.length}'),
            ),
          );
      },
    );
  }

  Future<void> _deleteExpense(Expense expense) async {
    await _repository.deleteExpense(kSharedBudgetCode, expense.id);

    if (!mounted) return;
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(expense.isTransfer ? 'Перевод удалён' : 'Запись удалена'),
        duration: const Duration(seconds: 2),
        persist: false,
        action: SnackBarAction(
          label: 'Отменить',
          onPressed: () => _addExpense(expense),
        ),
      ),
    );
  }

  Future<void> _confirmClearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Очистить бюджет?'),
        content: const Text(
          'Все расходы и доходы у всех участников будут удалены безвозвратно. '
          'Это действие нельзя отменить.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: expenseColor(context),
              foregroundColor: const Color(0xFFF6F2EA),
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Очистить'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _repository.clearAll(kSharedBudgetCode);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Бюджет очищен')),
    );
  }

  void _openAddSheet(TransactionType type, {Expense? existing}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => GlassSheet(
        child: AddExpenseSheet(
          type: type,
          currency: kBudgetCurrency,
          existing: existing,
          onSubmit: _addExpense,
        ),
      ),
    );
  }

  /// Opens the receipt photo kept for a scanned record. The fetch starts
  /// before the dialog so that rebuilding the dialog does not fetch again.
  void _showReceipt(String receiptId) {
    final photo = _repository.fetchReceipt(kSharedBudgetCode, receiptId);
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

  /// A thin rule with the month's name, shown only where the month changes
  /// between two rows of the list.
  Widget _monthDivider(DateTime month) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 14, 0, 10),
      child: Row(
        children: [
          Text(
            monthDividerLabel(month).toUpperCase(),
            style: microLabel(
              context,
              color: goldFor(context).withValues(alpha: 0.85),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Divider(color: hairlineColor(context))),
        ],
      ),
    );
  }

  Widget _buildSeparator(List<Expense> expenses, int index) {
    final current = expenses[index].date;
    final next = expenses[index + 1].date;
    final monthChanged =
        current.year != next.year || current.month != next.month;
    return monthChanged ? _monthDivider(next) : const SizedBox(height: 7);
  }

  /// The swipe-to-delete / long-press-to-edit / tap-for-receipt row.
  Widget _buildExpenseRow(Expense expense) {
    return Dismissible(
      key: ValueKey(expense.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: expenseColor(context),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Icon(
          Icons.delete_outline_rounded,
          color: Color(0xFFF6F2EA),
        ),
      ),
      onDismissed: (_) => _deleteExpense(expense),
      child: ExpenseTile(
        expense: expense,
        currency: kBudgetCurrency,
        onTap: expense.receiptId == null
            ? null
            : () => _showReceipt(expense.receiptId!),
        // A transfer has no form of its own: delete it and mark it again.
        onLongPress: expense.isTransfer
            ? null
            : () => _openAddSheet(expense.type, existing: expense),
      ),
    );
  }

  /// Wiping the budget lives in the bottom-left corner: it is the only
  /// destructive action on this screen, and it has no business sitting a
  /// few millimetres from the buttons people press several times a day.
  Widget _clearButton() {
    return FloatingActionButton.small(
      heroTag: 'clear_budget',
      backgroundColor: expenseColor(context).withValues(alpha: kFabFillOpacity),
      foregroundColor: const Color(0xFFF6F2EA),
      onPressed: _confirmClearAll,
      tooltip: 'Очистить бюджет',
      child: const Icon(Icons.delete_sweep_outlined, size: 20),
    );
  }

  Widget _scanButton(List<Expense> expenses) {
    return FloatingActionButton.small(
      heroTag: 'scan_receipt',
      // A champagne wash blended into the sheet's own surface first, then
      // the same fixed translucency as its neighbours, so all three buttons
      // fade into the list behind them by the same amount.
      backgroundColor: Color.alphaBlend(
        goldFor(context).withValues(alpha: 0.14),
        sheetSurface(context),
      ).withValues(alpha: kFabFillOpacity),
      foregroundColor: goldFor(context),
      elevation: 3,
      shape: CircleBorder(
        side: BorderSide(color: goldFor(context).withValues(alpha: 0.55)),
      ),
      onPressed: () => _openScanner(expenses),
      tooltip: 'Распознать чек или скриншот — ИИ',
      child: const AiScanIcon(size: 20),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Expense>>(
      stream: _expensesStream,
      builder: (context, snapshot) {
        final expenses = snapshot.data ?? const <Expense>[];
        // Real data arrived -- the wait that timer was guarding against is
        // over, so it should not fire a stale "no connection" state later.
        if (snapshot.hasData) _firstLoadTimer?.cancel();
        final pool = sharedPool(expenses);

        return Scaffold(
          // The list runs under the app bar so there is something for the
          // bar's frosting to actually blur.
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            flexibleSpace: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: appBarGlassTint(context),
                    border: Border(
                      bottom: BorderSide(color: hairlineColor(context)),
                    ),
                  ),
                ),
              ),
            ),
            title: const Text('Общак'),
            titleSpacing: 24,
            actions: [
              Center(
                child: Padding(
                  padding: const EdgeInsets.only(right: 20),
                  child: Text(
                    widget.myName,
                    style: TextStyle(
                      fontSize: 14,
                      color: accentForeground(context).withValues(alpha: 0.7),
                    ),
                  ),
                ),
              ),
            ],
          ),
          // All the buttons share the one FAB slot, laid out across the full
          // width, so the whole group lifts together when a snackbar shows.
          floatingActionButtonLocation:
              FloatingActionButtonLocation.centerFloat,
          floatingActionButton: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: ReadableWidth.maxWidth),
            child: Padding(
              padding: const EdgeInsets.only(left: 22, right: 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  snapshot.hasData ? _clearButton() : const SizedBox.shrink(),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_scanEnabled) ...[
                        _scanButton(expenses),
                        const SizedBox(height: 14),
                      ],
                      FloatingActionButton(
                        heroTag: 'add_expense',
                        backgroundColor:
                            (Theme.of(context).brightness == Brightness.dark
                                    ? kChampagne
                                    : kAccentColor)
                                .withValues(alpha: kFabFillOpacity),
                        onPressed: () => _openAddSheet(TransactionType.expense),
                        tooltip: 'Добавить покупку',
                        child: const Icon(Icons.add_rounded),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          body: AppBackgroundPattern(
            child: ReadableWidth(
              child: !snapshot.hasData
                  ? (_firstLoadTimedOut
                      ? _ConnectionTimedOut(onRetry: _retryFirstLoad)
                      : Center(
                          child: CircularProgressIndicator(
                            backgroundColor:
                                goldFor(context).withValues(alpha: 0.16),
                            color: goldFor(context),
                          ),
                        ))
                  : Column(
                      children: [
                        Padding(
                          padding: EdgeInsets.fromLTRB(
                            20,
                            MediaQuery.of(context).padding.top +
                                kToolbarHeight +
                                10,
                            20,
                            8,
                          ),
                          child: SplitCard(
                            pool: pool,
                            currency: kBudgetCurrency,
                            onSettle: _confirmSettlement,
                          ),
                        ),
                        Expanded(
                          // Rows slide up under the card and dissolve there,
                          // rather than being clipped at its edge.
                          child: TopFadeMask(
                            controller: _listController,
                            child: CustomScrollView(
                              controller: _listController,
                              slivers: [
                                if (expenses.isEmpty)
                                  const SliverFillRemaining(
                                    hasScrollBody: false,
                                    child: _EmptyState(),
                                  )
                                else
                                  SliverPadding(
                                    padding: const EdgeInsets.fromLTRB(
                                        24, 22, 24, 100),
                                    sliver: SliverList.separated(
                                      itemCount: expenses.length,
                                      separatorBuilder: (context, index) =>
                                          _buildSeparator(expenses, index),
                                      itemBuilder: (context, index) =>
                                          _buildExpenseRow(expenses[index]),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.receipt_long_outlined,
              size: 56,
              color: accentForeground(context).withValues(alpha: 0.55),
            ),
            const SizedBox(height: 16),
            Text(
              'Пока нет расходов',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.normal,
                color: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.color
                    ?.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown in place of the initial spinner once the first Firestore snapshot
/// has taken too long to arrive, with a way to try again.
class _ConnectionTimedOut extends StatelessWidget {
  final VoidCallback onRetry;

  const _ConnectionTimedOut({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_rounded,
              size: 48,
              color: goldFor(context).withValues(alpha: 0.6),
            ),
            const SizedBox(height: 16),
            Text(
              'Не удаётся загрузить данные.\nПроверьте соединение',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: accentForeground(context).withValues(alpha: 0.75),
              ),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: onRetry,
              child: const Text('Повторить'),
            ),
          ],
        ),
      ),
    );
  }
}
