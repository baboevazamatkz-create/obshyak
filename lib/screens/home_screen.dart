import 'dart:async';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../data/expense_repository.dart';
import '../data/scan_service.dart';
import '../models/away.dart';
import '../models/currency.dart';
import '../models/expense.dart';
import '../models/fines.dart';
import '../models/shared_budget.dart';
import '../models/shared_split.dart';
import '../models/transaction_type.dart';
import '../theme.dart';
import '../widgets/add_expense_sheet.dart';
import '../widgets/ai_scan_icon.dart';
import '../widgets/app_background_pattern.dart';
import '../widgets/avatar.dart';
import '../widgets/away_banner.dart';
import '../widgets/expense_tile.dart';
import '../widgets/fine_banner.dart';
import '../widgets/fine_sheet.dart';
import '../widgets/glass.dart';
import '../widgets/readable_width.dart';
import '../widgets/receipt_dialog.dart';
import '../widgets/split_card.dart';
import '../widgets/tour.dart';
import 'history_screen.dart';
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

  /// Only one flatmate may delete records or clear the budget.
  bool get _isAdmin => widget.myName == kAdminName;

  // Held in fields rather than created inside build(): a stream built during
  // build is a brand-new Firestore listener on every rebuild, which drops the
  // loaded data back to a spinner and re-reads the collection each time.
  late Stream<List<Expense>> _expensesStream;
  late Stream<AwayBook> _awayStream;

  /// The latest word on who is away. New purchases and fines are stamped
  /// with who is home at the moment they are entered.
  AwayBook _away = AwayBook();

  /// Fines whose judges are being narrowed right now, so one snapshot does
  /// not send the same write twice.
  final Set<String> _narrowing = {};

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

  bool _archiving = false;

  @override
  void initState() {
    super.initState();
    _expensesStream = _repository.watchExpenses(kSharedBudgetCode);
    _awayStream = _repository.watchAway(kSharedBudgetCode);
    _startFirstLoadTimer();
    // After the first frame, so the tour has the real screen to sit over.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) OnboardingTour.showIfNew(context);
    });
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
        _awayStream = _repository.watchAway(kSharedBudgetCode);
        _startFirstLoadTimer();
      });

  /// Stamps whoever is using this phone as the author, unless the record
  /// already names one: a transfer is written for whoever paid, and an
  /// restored record keeps its original author. A new purchase or fine is
  /// also stamped with who is home, the people it is split between.
  Future<void> _addExpense(Expense expense) {
    if (expense.author.isNotEmpty) {
      return _repository.addExpense(kSharedBudgetCode, expense);
    }
    final splits = expense.isFine || expense.type == TransactionType.expense;
    return _repository.addExpense(
      kSharedBudgetCode,
      expense.copyWith(
        author: widget.myName,
        members: splits ? expense.members ?? _away.present : null,
      ),
    );
  }

  /// The «Отпуск» button: ask to go away, withdraw the request, or come
  /// back. Only going away needs the others to agree.
  Future<void> _toggleAway() async {
    final me = widget.myName;
    switch (_away.statusOf(me)) {
      case AwayStatus.away:
        final sure = await _ask(
          'Вернулись?',
          'Новые покупки и штрафы снова будут делиться и на вас.',
          'Да, вернулся',
        );
        if (sure) await _repository.clearAway(kSharedBudgetCode, me);
      case AwayStatus.pending:
        final sure = await _ask(
          'Отменить запрос?',
          'Запрос на отпуск ещё не согласован. Отменить его?',
          'Отменить запрос',
        );
        if (sure) await _repository.clearAway(kSharedBudgetCode, me);
      case AwayStatus.home:
      case AwayStatus.rejected:
        final approvers = [
          for (final name in _away.present)
            if (name != me) name,
        ];
        final sure = await _ask(
          'Уезжаете?',
          'Остальные получат запрос и должны согласовать. Пока вы в '
              'отпуске, новые покупки и штрафы на вас не делятся. Текущие '
              'долги остаются, их нужно закрыть как обычно.',
          'Попросить отпуск',
        );
        if (!sure) return;
        await _repository.requestAway(
          kSharedBudgetCode,
          AwayRequest(name: me, since: DateTime.now(), approvers: approvers),
        );
    }
  }

  Future<void> _voteAway(AwayRequest request, String vote) async {
    final yes = vote == kAwayYes;
    final sure = await _ask(
      yes ? 'Согласовать отпуск?' : 'Отклонить отпуск?',
      yes
          ? 'Когда согласуют все, новые покупки и штрафы перестанут '
              'делиться на ${request.name}.'
          : 'Одного «нет» достаточно, чтобы запрос не прошёл.',
      yes ? 'Согласовать' : 'Отклонить',
    );
    if (!sure) return;
    await _repository.voteAway(
      kSharedBudgetCode,
      request.name,
      widget.myName,
      vote,
    );
  }

  Future<bool> _ask(String title, String body, String yes) async {
    final answer = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(yes),
          ),
        ],
      ),
    );
    return answer == true;
  }

  /// The payer says they sent [settlement]. It is written as a pending
  /// transfer that moves no balance until the recipient confirms it.
  Future<void> _markPaid(Settlement settlement) async {
    final amount = kBudgetCurrency.format.format(settlement.amount);
    final sure = await _ask(
      'Перевод отправлен?',
      'Вы перевели ${settlement.to} $amount. '
          'Долг закроется, когда ${settlement.to} подтвердит.',
      'Да, отправил',
    );
    if (!sure) return;
    await _addExpense(Expense(
      id: const Uuid().v4(),
      amount: settlement.amount,
      date: DateTime.now(),
      currency: kBudgetCurrency,
      type: TransactionType.transfer,
      author: settlement.from,
      recipient: settlement.to,
      confirmed: false,
    ));
  }

  void _openFineSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => GlassSheet(
        child: FineSheet(
          myName: widget.myName,
          onSubmit: _addExpense,
          members: _away.present,
        ),
      ),
    );
  }

  Future<void> _voteOnFine(Expense fine, String vote) async {
    final cancel = vote == kVoteNo;
    final sure = await _ask(
      cancel ? 'Отменить штраф?' : 'Назначить штраф?',
      cancel
          ? 'Один голос против отменяет штраф для всех.'
          : '${fine.offender} будет должен '
              '${kBudgetCurrency.format.format(fine.amount)} остальным.',
      cancel ? 'Да, отменить' : 'Да, назначить',
    );
    if (!sure) return;
    await _repository.voteOnFine(
      kSharedBudgetCode,
      fine.id,
      widget.myName,
      vote,
    );
  }

  Future<void> _answerFine(Expense fine, String answer) async {
    final dispute = answer == kOffenderDispute;
    final sure = await _ask(
      dispute ? 'Оспорить штраф?' : 'Принять штраф?',
      dispute
          ? 'Остальные проголосуют заново: штраф останется, только если '
              'все снова будут за.'
          : 'Вы будете должны '
              '${kBudgetCurrency.format.format(fine.amount)} остальным.',
      dispute ? 'Оспорить' : 'Принять',
    );
    if (!sure) return;
    await _repository.answerFine(kSharedBudgetCode, fine.id, answer);
  }

  /// Cancels two flatmates' debts to each other against one another. No
  /// money moves, so it takes effect at once; whatever is left of the
  /// larger debt stays to be paid.
  Future<void> _offsetDebts(Offset offset) async {
    final amount = kBudgetCurrency.format.format(offset.amount);
    final sure = await _ask(
      'Зачесть встречные долги?',
      '${offset.a} и ${offset.b} должны друг другу. По $amount с каждой '
          'стороны спишется, разница останется долгом.',
      'Зачесть',
    );
    if (!sure) return;
    final other = offset.a == widget.myName ? offset.b : offset.a;
    await _addExpense(Expense(
      id: const Uuid().v4(),
      amount: offset.amount,
      date: DateTime.now(),
      currency: kBudgetCurrency,
      type: TransactionType.offset,
      author: widget.myName,
      recipient: other,
    ));
  }

  /// The recipient confirms that a pending transfer arrived.
  Future<void> _confirmReceived(Expense transfer) async {
    final amount = kBudgetCurrency.format.format(transfer.amount);
    final sure = await _ask(
      'Деньги пришли?',
      '${transfer.author} перевёл вам $amount.',
      'Да, получил',
    );
    if (!sure) return;
    await _repository.confirmTransfer(kSharedBudgetCode, transfer.id);
  }

  /// The only way to add a purchase: a photo or screenshot of its receipt.
  /// With the scanner set up it reads the receipt; without it, or when it
  /// cannot, the purchase is typed in by hand -- with the photo attached
  /// either way, so every purchase has its receipt behind it.
  Future<void> _openScanner(List<Expense> expenses) async {
    await _scanFlow.run(
      context,
      currency: kBudgetCurrency,
      existing: expenses,
      recognize: _scanEnabled,
      onManual: _addByHand,
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
        final receiptId = await _saveReceipt(photo);
        await _repository.addExpenses(
          kSharedBudgetCode,
          [
            for (final expense in added)
              expense.copyWith(
                author: widget.myName,
                receiptId: receiptId,
                members: _away.present,
              ),
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

  Future<String> _saveReceipt(Uint8List photo) async {
    final receiptId = const Uuid().v4();
    await _repository.addReceipt(kSharedBudgetCode, receiptId, photo);
    return receiptId;
  }

  /// The purchase form, for a receipt the scanner did not read, with that
  /// receipt's photo kept on the record.
  Future<void> _addByHand(Uint8List photo) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => GlassSheet(
        child: AddExpenseSheet(
          type: TransactionType.expense,
          currency: kBudgetCurrency,
          onSubmit: (expense) async {
            final receiptId = await _saveReceipt(photo);
            await _addExpense(expense.copyWith(receiptId: receiptId));
          },
        ),
      ),
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
          'Все записи, включая историю, будут удалены у всех участников '
          'безвозвратно. Это действие нельзя отменить.',
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

  void _showReceipt(String receiptId) =>
      showReceiptDialog(context, _repository, receiptId);

  /// Someone who went away while a fine was still being voted on drops out
  /// of it: they no longer judge it, and its money is shared without them.
  /// The offender stays, so a fine already put to them can still stand.
  ///
  /// Driven by the snapshot like [_archiveIfSettled], so any phone that
  /// sees it does it, and doing it twice writes the same thing.
  void _dropAwayJudges(List<Expense> open) {
    for (final fine in open) {
      if (!fine.isFine || fineStatus(fine) != FineStatus.voting) continue;
      final keep = [
        for (final name in fine.sharers)
          if (!_away.isAway(name) || name == fine.offender) name,
      ];
      if (keep.length == fine.sharers.length) continue;
      if (!_narrowing.add(fine.id)) continue;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        try {
          await _repository.setFineMembers(kSharedBudgetCode, fine.id, keep);
        } finally {
          _narrowing.remove(fine.id);
        }
      });
    }
  }

  /// Moves the open period to history once everyone is square.
  ///
  /// Driven by the snapshot rather than by the button that settled the last
  /// debt, so it also fires when purchases happen to even out by themselves
  /// or a deletion squares the flat. The guard keeps one snapshot from
  /// starting the same archive twice while the first is still being
  /// written.
  void _archiveIfSettled(List<Expense> open) {
    if (_archiving || !periodIsClosed(open)) return;
    _archiving = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await _repository.archive(
          kSharedBudgetCode,
          [for (final expense in open) expense.id],
          DateTime.now(),
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Все в расчёте — период перенесён в историю'),
          ),
        );
      } finally {
        _archiving = false;
      }
    });
  }

  void _openHistory() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => const HistoryScreen()),
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

  /// The tap-for-receipt row, which only the admin can swipe away.
  Widget _buildExpenseRow(Expense expense) {
    final tile = ExpenseTile(
      expense: expense,
      currency: kBudgetCurrency,
      onTap: expense.receiptId == null
          ? null
          : () => _showReceipt(expense.receiptId!),
      // Saved records are not edited: a mistake is deleted and entered
      // again, so nobody's figures change under them unnoticed.
    );
    if (!_isAdmin) return tile;
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
      child: tile,
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

  /// Proposing a fine sits right above the add button, in the same column.
  Widget _fineButton() {
    return FloatingActionButton.small(
      heroTag: 'propose_fine',
      backgroundColor: expenseColor(context).withValues(alpha: kFabFillOpacity),
      foregroundColor: const Color(0xFFF6F2EA),
      onPressed: _openFineSheet,
      tooltip: 'Предложить штраф',
      child: const Icon(Icons.gavel_rounded, size: 20),
    );
  }

  /// The one add button: a purchase always comes in through its receipt.
  Widget _scanButton(List<Expense> expenses) {
    return FloatingActionButton(
      heroTag: 'scan_receipt',
      backgroundColor: kChampagne.withValues(alpha: kFabFillOpacity),
      onPressed: () => _openScanner(expenses),
      tooltip: _scanEnabled
          ? 'Добавить покупку по чеку — ИИ прочитает'
          : 'Добавить покупку по фото чека',
      child: _scanEnabled
          ? const AiScanIcon(size: 26)
          : const Icon(Icons.receipt_long_rounded),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AwayBook>(
      stream: _awayStream,
      builder: (context, awaySnapshot) {
        _away = awaySnapshot.data ?? _away;
        return _buildWithExpenses(context);
      },
    );
  }

  Widget _buildWithExpenses(BuildContext context) {
    return StreamBuilder<List<Expense>>(
      stream: _expensesStream,
      builder: (context, snapshot) {
        // Only the open period is on this screen; settled ones live in
        // history.
        final expenses = [
          for (final expense in snapshot.data ?? const <Expense>[])
            if (expense.archivedAt == null) expense,
        ];
        if (snapshot.hasData) {
          _dropAwayJudges(expenses);
          _archiveIfSettled(expenses);
        }
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
            // Whose phone this is, where the app's name used to be.
            title: HomeTitle(
              name: widget.myName,
              away: _away.statusOf(widget.myName),
              onAway: _toggleAway,
            ),
            titleSpacing: 24,
            actions: [
              IconButton(
                onPressed: _openHistory,
                icon: const Icon(Icons.history_rounded),
                tooltip: 'История',
              ),
              const SizedBox(width: 8),
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
                  snapshot.hasData && _isAdmin
                      ? _clearButton()
                      : const SizedBox.shrink(),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Away, you neither fine anyone nor get fined.
                      if (!_away.isAway(widget.myName)) ...[
                        _fineButton(),
                        const SizedBox(height: 14),
                      ],
                      _scanButton(expenses),
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
                          // Capped and scrollable: a few fines under
                          // vote must not push the list off the screen.
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxHeight:
                                  MediaQuery.of(context).size.height * 0.55,
                            ),
                            child: SingleChildScrollView(
                              child: Column(
                                children: [
                                  SplitCard(
                                    pool: pool,
                                    currency: kBudgetCurrency,
                                    myName: widget.myName,
                                    pending: [
                                      for (final expense in expenses)
                                        if (expense.isPendingTransfer) expense,
                                    ],
                                    onPaid: _markPaid,
                                    onConfirm: _confirmReceived,
                                    onOffset: _offsetDebts,
                                    away: {
                                      for (final name in kRoommates)
                                        if (_away.isAway(name)) name,
                                    },
                                  ),
                                  for (final request in _away.requests.values)
                                    if (_away.statusOf(request.name) ==
                                            AwayStatus.pending ||
                                        (_away.statusOf(request.name) ==
                                                AwayStatus.rejected &&
                                            request.name == widget.myName))
                                      AwayBanner(
                                        request: request,
                                        myName: widget.myName,
                                        book: _away,
                                        onVote: (vote) =>
                                            _voteAway(request, vote),
                                        onDismiss: () => _repository.clearAway(
                                          kSharedBudgetCode,
                                          widget.myName,
                                        ),
                                      ),
                                  for (final fine in expenses)
                                    if (fine.isFine &&
                                        fineStatus(fine) == FineStatus.voting)
                                      FineBanner(
                                        fine: fine,
                                        myName: widget.myName,
                                        onVote: (vote) =>
                                            _voteOnFine(fine, vote),
                                        onAnswer: (answer) =>
                                            _answerFine(fine, answer),
                                      ),
                                ],
                              ),
                            ),
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

/// The app bar's title: whose phone this is, and their «Отпуск» switch
/// right beside the name.
class HomeTitle extends StatelessWidget {
  final String name;
  final AwayStatus away;
  final VoidCallback onAway;

  const HomeTitle({
    super.key,
    required this.name,
    required this.away,
    required this.onAway,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Avatar(name, size: 30),
        const SizedBox(width: 10),
        Flexible(child: Text(name, overflow: TextOverflow.ellipsis)),
        const SizedBox(width: 10),
        AwayButton(status: away, onPressed: onAway),
      ],
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
