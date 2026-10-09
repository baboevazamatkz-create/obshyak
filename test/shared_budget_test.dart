import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:expense_tracker/data/name_store.dart';
import 'package:expense_tracker/models/currency.dart';
import 'package:expense_tracker/models/expense.dart';
import 'package:expense_tracker/models/fines.dart';
import 'package:expense_tracker/models/history.dart';
import 'package:expense_tracker/models/shared_budget.dart';
import 'package:expense_tracker/models/shared_split.dart';
import 'package:expense_tracker/models/transaction_type.dart';
import 'package:expense_tracker/data/scan_service.dart';
import 'package:expense_tracker/screens/name_picker_screen.dart';
import 'package:expense_tracker/widgets/fine_banner.dart';
import 'package:expense_tracker/widgets/fine_sheet.dart';
import 'package:expense_tracker/widgets/glass.dart';
import 'package:expense_tracker/widgets/split_card.dart';

Expense _spend(String id, double amount, DateTime date) => Expense(
      id: id,
      amount: amount,
      date: date,
      currency: AppCurrency.kzt,
    );

void main() {
  group('sharedPool', () {
    Expense buy(String who, double amount, {double personal = 0}) => Expense(
          id: '$who-$amount-$personal',
          amount: amount,
          date: DateTime(2026, 10, 1),
          author: who,
          personal: personal,
          currency: AppCurrency.kzt,
        );

    Expense paidBack(String from, String to, double amount) => Expense(
          id: '$from-$to-$amount',
          amount: amount,
          date: DateTime(2026, 10, 2),
          author: from,
          recipient: to,
          currency: AppCurrency.kzt,
          type: TransactionType.transfer,
        );

    PoolPerson person(SharedPool pool, String name) =>
        pool.people.singleWhere((p) => p.name == name);

    test('one purchase: the buyer is owed three quarters, the rest owe one',
        () {
      final pool = sharedPool([buy('Азамат', 8000)]);
      expect(pool.sharedTotal, 8000);
      expect(pool.perPerson, 2000);
      expect(person(pool, 'Азамат').paid, 8000);
      expect(person(pool, 'Азамат').balance, 6000);
      expect(person(pool, 'Аслан').balance, -2000);
      expect(pool.settlements.length, 3);
      expect(pool.settlements.every((s) => s.to == 'Азамат'), isTrue);
      expect(pool.settlements.every((s) => s.amount == 2000), isTrue);
    });

    test('two buyers owe each other a quarter, both debts kept', () {
      final pool = sharedPool([buy('Азамат', 4000), buy('Аслан', 2000)]);
      Settlement between(String from, String to) =>
          pool.settlements.singleWhere((s) => s.from == from && s.to == to);
      expect(between('Аслан', 'Азамат').amount, 1000);
      expect(between('Азамат', 'Аслан').amount, 500);
      expect(between('Мухаммад', 'Азамат').amount, 1000);
      expect(between('Мухаммад', 'Аслан').amount, 500);
    });

    test('a debtor buying something big does not wipe their debt', () {
      final pool = sharedPool([buy('Азамат', 8000), buy('Аслан', 8000)]);
      Settlement between(String from, String to) =>
          pool.settlements.singleWhere((s) => s.from == from && s.to == to);
      // Equal purchases: the two still owe each other until both pay.
      expect(between('Аслан', 'Азамат').amount, 2000);
      expect(between('Азамат', 'Аслан').amount, 2000);
    });

    test('an offset cancels the common part and leaves the difference', () {
      final records = [buy('Азамат', 8000), buy('Аслан', 6000)];
      final before = sharedPool(records);
      final offer = before.offsets.single;
      expect(offer.involves('Азамат') && offer.involves('Аслан'), isTrue);
      expect(offer.amount, 1500);

      final after = sharedPool([
        ...records,
        Expense(
          id: 'offset',
          amount: offer.amount,
          date: DateTime(2026, 10, 3),
          author: 'Аслан',
          recipient: 'Азамат',
          currency: AppCurrency.kzt,
          type: TransactionType.offset,
        ),
      ]);
      Settlement? between(String from, String to) => after.settlements
          .where((s) => s.from == from && s.to == to)
          .firstOrNull;
      // Аслан owed 2 000, Азамат 1 500: 500 is left, the other way gone.
      expect(between('Аслан', 'Азамат')!.amount, 500);
      expect(between('Азамат', 'Аслан'), isNull);
      expect(after.offsets, isEmpty);
      // Nobody's balance moves.
      for (var i = 0; i < kRoommates.length; i++) {
        expect(after.people[i].balance, before.people[i].balance);
      }
    });

    test('the personal part of a receipt is not split', () {
      final pool = sharedPool([buy('Имран', 10000, personal: 2000)]);
      expect(pool.sharedTotal, 8000);
      expect(person(pool, 'Имран').paid, 8000);
      expect(person(pool, 'Имран').balance, 6000);
    });

    test('a recorded transfer closes that debt', () {
      final pool = sharedPool([
        buy('Азамат', 8000),
        paidBack('Аслан', 'Азамат', 2000),
      ]);
      expect(person(pool, 'Аслан').balance, 0);
      expect(person(pool, 'Азамат').balance, 4000);
      // The 2 000 paid back is Аслан's spending now, and no longer Азамат's.
      expect(person(pool, 'Аслан').spent, 2000);
      expect(person(pool, 'Азамат').spent, 6000);
      expect(pool.settlements.any((s) => s.from == 'Аслан'), isFalse);
    });

    test('a transfer not yet confirmed moves no balance', () {
      final pool = sharedPool([
        buy('Азамат', 8000),
        Expense(
          id: 'pending',
          amount: 2000,
          date: DateTime(2026, 10, 2),
          author: 'Аслан',
          recipient: 'Азамат',
          currency: AppCurrency.kzt,
          type: TransactionType.transfer,
          confirmed: false,
        ),
      ]);
      expect(person(pool, 'Аслан').balance, -2000);
      expect(pool.settlements.any((s) => s.from == 'Аслан'), isTrue);
    });

    test('equal purchases still leave every debt to be paid back', () {
      final pool = sharedPool([
        for (final name in kRoommates) buy(name, 4000),
      ]);
      // Balances are even, but nobody's debt cancels anybody else's.
      for (final p in pool.people) {
        expect(p.balance, 0);
      }
      expect(pool.settlements.length, 12);
      expect(pool.settlements.every((s) => s.amount == 1000), isTrue);
    });

    test('balances always add up to zero', () {
      final pool = sharedPool([
        buy('Азамат', 4300),
        buy('Аслан', 1250, personal: 250),
        buy('Мухаммад', 999),
        paidBack('Имран', 'Азамат', 700),
      ]);
      final sum = pool.people.fold<double>(0, (s, p) => s + p.balance);
      expect(sum.abs(), lessThan(0.001));
    });

    test('settling the suggested transfers brings everyone to zero', () {
      final records = [
        buy('Азамат', 4300),
        buy('Аслан', 1000),
        buy('Мухаммад', 999),
      ];
      final first = sharedPool(records);
      final settled = sharedPool([
        ...records,
        for (final s in first.settlements) paidBack(s.from, s.to, s.amount),
      ]);
      expect(settled.isSettled, isTrue);
    });

    test('a purchase with no known author is left out of the split', () {
      final pool = sharedPool([
        Expense(
          id: 'old',
          amount: 5000,
          date: DateTime(2026, 1, 1),
          currency: AppCurrency.kzt,
        ),
      ]);
      expect(pool.sharedTotal, 0);
      expect(pool.isSettled, isTrue);
    });

    test('legacy income records change nothing', () {
      final pool = sharedPool([
        Expense(
          id: 'income',
          amount: 60000,
          date: DateTime(2026, 1, 1),
          author: 'Азамат',
          currency: AppCurrency.kzt,
          type: TransactionType.income,
        ),
      ]);
      expect(pool.sharedTotal, 0);
      expect(pool.isSettled, isTrue);
    });

    test('an empty budget is settled and splits to zero', () {
      final pool = sharedPool(const []);
      expect(pool.sharedTotal, 0);
      expect(pool.perPerson, 0);
      expect(pool.isSettled, isTrue);
      expect(pool.people.length, kRoommateCount);
    });
  });

  group('closing a period', () {
    Expense buy(String who, double amount, {DateTime? archivedAt}) => Expense(
          id: '$who-$amount-${archivedAt?.day}',
          amount: amount,
          date: DateTime(2026, 10, 1),
          author: who,
          currency: AppCurrency.kzt,
          archivedAt: archivedAt,
        );

    Expense paidBack(String from, String to, double amount) => Expense(
          id: 'back-$from-$to',
          amount: amount,
          date: DateTime(2026, 10, 2),
          author: from,
          recipient: to,
          currency: AppCurrency.kzt,
          type: TransactionType.transfer,
        );

    test('an empty period is not closed: there is nothing to put away', () {
      expect(periodIsClosed(const []), isFalse);
    });

    test('a period with debts still open stays open', () {
      expect(periodIsClosed([buy('Азамат', 8000)]), isFalse);
    });

    test('once every debt is paid back, the period closes', () {
      expect(
        periodIsClosed([
          buy('Азамат', 8000),
          paidBack('Аслан', 'Азамат', 2000),
          paidBack('Мухаммад', 'Азамат', 2000),
          paidBack('Имран', 'Азамат', 2000),
        ]),
        isTrue,
      );
    });

    test('even purchases close the period only once every debt is paid', () {
      final open = [for (final name in kRoommates) buy(name, 4000)];
      expect(periodIsClosed(open), isFalse);
      final paid = [
        ...open,
        for (final from in kRoommates)
          for (final to in kRoommates)
            if (from != to) paidBack(from, to, 1000),
      ];
      expect(periodIsClosed(paid), isTrue);
    });

    test('history groups records by the moment their period closed', () {
      final first = DateTime(2026, 9, 30);
      final second = DateTime(2026, 10, 7);
      final periods = historyPeriods([
        buy('Азамат', 100, archivedAt: first),
        buy('Аслан', 200, archivedAt: second),
        buy('Имран', 300, archivedAt: second),
        buy('Мухаммад', 999), // still open, not history
      ]);
      expect(periods.length, 2);
      expect(periods.first.closedAt, second, reason: 'latest first');
      expect(periods.first.records.length, 2);
      expect(periods.first.sharedTotal, 500);
      expect(periods.last.records.single.author, 'Азамат');
    });
  });

  group('fines', () {
    Expense fine({
      Map<String, String> votes = const {'Азамат': kVoteYes},
      String? offenderVote,
    }) =>
        Expense(
          id: 'fine',
          amount: 6000,
          date: DateTime(2026, 10, 3),
          note: 'не помыл посуду',
          author: 'Азамат',
          offender: 'Имран',
          votes: votes,
          offenderVote: offenderVote,
          currency: AppCurrency.kzt,
          type: TransactionType.fine,
        );

    const allYes = {
      'Азамат': kVoteYes,
      'Аслан': kVoteYes,
      'Мухаммад': kVoteYes,
    };

    testWidgets('anyone can be fined, yourself included', (tester) async {
      Expense? proposed;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: GlassSheet(
            child: FineSheet(myName: 'Аслан', onSubmit: (e) => proposed = e),
          ),
        ),
      ));
      await tester.tap(find.text('Аслан (я)'));
      await tester.enterText(find.byType(TextField).last, 'опоздал');
      await tester.tap(find.text('Предложить штраф'));
      await tester.pump();

      expect(proposed!.offender, 'Аслан');
      // Owning up: already accepted, and the other three decide.
      expect(proposed!.offenderVote, kOffenderAccept);
      expect(proposed!.votes, isEmpty);
      expect(fineAwaiting(proposed!), ['Азамат', 'Мухаммад', 'Имран']);
    });

    test('the offender is not a judge', () {
      expect(fineJudges(fine()), ['Азамат', 'Аслан', 'Мухаммад']);
    });

    test('a fresh proposal is being voted on and waits on everyone else', () {
      expect(fineStatus(fine()), FineStatus.voting);
      expect(fineAwaiting(fine()), ['Аслан', 'Мухаммад', 'Имран']);
    });

    test('all judges for and the offender accepting puts it in force', () {
      expect(
        fineStatus(fine(votes: allYes, offenderVote: kOffenderAccept)),
        FineStatus.active,
      );
    });

    test('all judges for still waits on the offender to answer', () {
      final f = fine(votes: allYes);
      expect(fineStatus(f), FineStatus.voting);
      expect(fineAwaiting(f), ['Имран']);
    });

    test('a single judge against cancels it', () {
      expect(
        fineStatus(fine(votes: {'Азамат': kVoteYes, 'Аслан': kVoteNo})),
        FineStatus.cancelled,
      );
    });

    test('after a dispute, the judges confirming again overrules it', () {
      // A dispute clears the votes; these are the second round.
      final f = fine(votes: allYes, offenderVote: kOffenderDispute);
      expect(fineIsDisputed(f), isTrue);
      expect(fineStatus(f), FineStatus.active);
    });

    test('a disputed fine with votes cleared waits on all three judges', () {
      final f = fine(votes: const {}, offenderVote: kOffenderDispute);
      expect(fineStatus(f), FineStatus.voting);
      expect(fineAwaiting(f), ['Азамат', 'Аслан', 'Мухаммад']);
    });

    test('a fine in force: the offender owes it, split among the others', () {
      final pool = sharedPool([
        fine(votes: allYes, offenderVote: kOffenderAccept),
      ]);
      PoolPerson p(String n) => pool.people.singleWhere((x) => x.name == n);
      expect(p('Имран').balance, -6000);
      expect(p('Азамат').balance, 2000);
      expect(p('Аслан').balance, 2000);
      expect(pool.sharedTotal, 0, reason: 'a fine is not spending');
      expect(pool.settlements.every((s) => s.from == 'Имран'), isTrue);
      expect(pool.settlements.length, 3);
    });

    test('a fine still being voted on changes no balance', () {
      final pool = sharedPool([fine()]);
      expect(pool.isSettled, isTrue);
    });

    test('a period does not close while a fine is being voted on', () {
      expect(periodIsClosed([fine()]), isFalse);
    });

    test('a paid-off fine closes the period', () {
      final open = [
        fine(votes: allYes, offenderVote: kOffenderAccept),
        for (final to in ['Азамат', 'Аслан', 'Мухаммад'])
          Expense(
            id: 'pay-$to',
            amount: 2000,
            date: DateTime(2026, 10, 4),
            author: 'Имран',
            recipient: to,
            currency: AppCurrency.kzt,
            type: TransactionType.transfer,
          ),
      ];
      expect(periodIsClosed(open), isTrue);
    });

    test('fine fields survive storage', () {
      final restored = Expense.fromJson(
        fine(votes: allYes, offenderVote: kOffenderDispute).toJson(),
      );
      expect(restored.isFine, isTrue);
      expect(restored.offender, 'Имран');
      expect(restored.votes, allYes);
      expect(restored.offenderVote, kOffenderDispute);
    });

    Future<void> pumpBanner(
      WidgetTester tester,
      Expense f,
      String me, {
      ValueChanged<String>? onVote,
      ValueChanged<String>? onAnswer,
    }) {
      return tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: FineBanner(
            fine: f,
            myName: me,
            onVote: onVote ?? (_) {},
            onAnswer: onAnswer ?? (_) {},
          ),
        ),
      ));
    }

    testWidgets('the offender is asked to accept or dispute', (tester) async {
      String? answer;
      await pumpBanner(tester, fine(), 'Имран', onAnswer: (a) => answer = a);
      expect(find.text('Принять'), findsOneWidget);
      await tester.tap(find.text('Оспорить'));
      expect(answer, kOffenderDispute);
    });

    testWidgets('a judge who has not voted is asked to set or cancel',
        (tester) async {
      String? vote;
      await pumpBanner(tester, fine(), 'Аслан', onVote: (v) => vote = v);
      await tester.tap(find.text('Назначить'));
      expect(vote, kVoteYes);
    });

    testWidgets('the proposer, having voted, only sees who it waits on',
        (tester) async {
      await pumpBanner(tester, fine(), 'Азамат');
      expect(find.text('Назначить'), findsNothing);
      expect(find.text('Ждём: Аслан, Мухаммад, Имран'), findsOneWidget);
    });

    testWidgets('after a dispute the judges are told to confirm again',
        (tester) async {
      await pumpBanner(
        tester,
        fine(votes: const {}, offenderVote: kOffenderDispute),
        'Аслан',
      );
      expect(
          find.text('Имран оспорил. Нужно подтвердить заново'), findsOneWidget);
      expect(find.text('Назначить'), findsOneWidget);
    });
  });

  group('Expense storage', () {
    test('round-trips the author and receipt id', () {
      final expense = Expense(
        id: 'e1',
        amount: 1200,
        date: DateTime(2026, 10, 1),
        author: 'Аслан',
        receiptId: 'r1',
        personal: 300,
        recipient: 'Имран',
        archivedAt: DateTime(2026, 10, 8, 12),
        confirmed: false,
        currency: AppCurrency.kzt,
      );
      final restored = Expense.fromJson(expense.toJson());
      expect(restored.confirmed, isFalse);
      expect(restored.archivedAt, DateTime(2026, 10, 8, 12));
      expect(restored.author, 'Аслан');
      expect(restored.receiptId, 'r1');
      expect(restored.personal, 300);
      expect(restored.recipient, 'Имран');
    });

    test('records written before names existed read as anonymous, no receipt',
        () {
      final restored = Expense.fromJson({
        'id': 'old',
        'amount': 500,
        'category': 'food',
        'note': '',
        'date': Timestamp.fromDate(DateTime(2026, 1, 1)),
        'currency': 'kzt',
        'type': 'expense',
      });
      expect(restored.author, '');
      expect(restored.receiptId, isNull);
      expect(restored.personal, 0);
      expect(restored.archivedAt, isNull);
      expect(restored.confirmed, isTrue, reason: 'old transfers count');
    });

    test('copyWith stamps the author without touching the rest', () {
      final stamped = _spend('s', 10, DateTime(2026, 1, 1))
          .copyWith(author: 'Имран', receiptId: 'r9');
      expect(stamped.id, 's');
      expect(stamped.amount, 10);
      expect(stamped.author, 'Имран');
      expect(stamped.receiptId, 'r9');
    });
  });

  group('NameStore', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('nothing is remembered until a name is picked', () async {
      expect(await NameStore.load(), isNull);
    });

    test('the picked name is remembered', () async {
      await NameStore.save('Мухаммад');
      expect(await NameStore.load(), 'Мухаммад');
    });

    test('a stored name that is no longer one of the four is forgotten',
        () async {
      SharedPreferences.setMockInitialValues({'my_name': 'Незнакомец'});
      expect(await NameStore.load(), isNull);
    });
  });

  group('prepareReceiptPhoto', () {
    test('garbage that is not an image produces no photo', () {
      expect(prepareReceiptPhoto(Uint8List.fromList([1, 2, 3, 4])), isNull);
    });

    test('a wide screenshot is shrunk to the receipt width and stays a JPEG',
        () {
      final source = img.Image(width: 2000, height: 1000);
      final bytes = Uint8List.fromList(img.encodePng(source));

      final photo = prepareReceiptPhoto(bytes);

      expect(photo, isNotNull);
      final decoded = img.decodeJpg(photo!);
      expect(decoded, isNotNull);
      expect(decoded!.width, kReceiptWidth);
      expect(photo.length, lessThanOrEqualTo(kReceiptMaxBytes));
    });
  });

  testWidgets('the name picker offers the four flatmates and reports the pick',
      (tester) async {
    String? picked;
    await tester.pumpWidget(MaterialApp(
      home: NamePickerScreen(onPicked: (name) => picked = name),
    ));

    for (final name in kRoommates) {
      expect(find.text(name), findsOneWidget);
    }
    await tester.tap(find.text('Аслан'));
    expect(picked, 'Аслан');
  });

  group('the pool card', () {
    final purchase = Expense(
      id: 'food',
      amount: 8000,
      date: DateTime(2026, 10, 2),
      author: 'Азамат',
      currency: AppCurrency.kzt,
    );
    final sent = Expense(
      id: 'sent',
      amount: 2000,
      date: DateTime(2026, 10, 3),
      author: 'Аслан',
      recipient: 'Азамат',
      currency: AppCurrency.kzt,
      type: TransactionType.transfer,
      confirmed: false,
    );

    Future<void> pump(
      WidgetTester tester, {
      required String me,
      List<Expense> pending = const [],
      ValueChanged<Settlement>? onPaid,
      ValueChanged<Expense>? onConfirm,
      ValueChanged<Offset>? onOffset,
      List<Expense> extra = const [],
    }) {
      return tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SplitCard(
              pool: sharedPool([purchase, ...extra, ...pending]),
              currency: AppCurrency.kzt,
              myName: me,
              pending: pending,
              onPaid: onPaid ?? (_) {},
              onConfirm: onConfirm ?? (_) {},
              onOffset: onOffset ?? (_) {},
            ),
          ),
        ),
      ));
    }

    testWidgets('only the payer can mark their own row as paid',
        (tester) async {
      Settlement? paid;
      await pump(tester, me: 'Аслан', onPaid: (s) => paid = s);

      expect(find.text('Аслан → Азамат'), findsOneWidget);
      expect(find.text('Оплатить'), findsOneWidget);
      expect(find.text('не оплачено'), findsNWidgets(2));
      await tester.tap(find.text('Оплатить'));
      expect(paid!.from, 'Аслан');
      expect(paid!.to, 'Азамат');
    });

    testWidgets('a pending transfer waits, yellow, on the payer\'s phone',
        (tester) async {
      await pump(tester, me: 'Аслан', pending: [sent]);
      expect(find.text('ожидает'), findsOneWidget);
      expect(find.text('Оплатить'), findsNothing);
    });

    testWidgets('the recipient confirms a pending transfer', (tester) async {
      Expense? confirmed;
      await pump(
        tester,
        me: 'Азамат',
        pending: [sent],
        onConfirm: (e) => confirmed = e,
      );
      expect(find.text('Подтвердить'), findsOneWidget);
      await tester.tap(find.text('Подтвердить'));
      expect(confirmed!.id, 'sent');
    });

    testWidgets('only the two who owe each other can offset', (tester) async {
      final theirs = Expense(
        id: 'theirs',
        amount: 4000,
        date: DateTime(2026, 10, 2),
        author: 'Аслан',
        currency: AppCurrency.kzt,
      );
      Offset? offered;
      await pump(
        tester,
        me: 'Азамат',
        extra: [theirs],
        onOffset: (o) => offered = o,
      );
      expect(find.text('Азамат ⇄ Аслан'), findsOneWidget);
      await tester.tap(find.text('Зачесть'));
      expect(offered!.amount, 1000);

      await pump(tester, me: 'Имран', extra: [theirs]);
      expect(find.text('Зачесть'), findsNothing);
      expect(find.text('встречные'), findsOneWidget);
    });

    testWidgets('a settled flat says so instead of listing transfers',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SplitCard(
              pool: sharedPool(const []),
              currency: AppCurrency.kzt,
              myName: 'Аслан',
              pending: const [],
              onPaid: (_) {},
              onConfirm: (_) {},
              onOffset: (_) {},
            ),
          ),
        ),
      ));
      expect(find.text('Все в расчёте'), findsOneWidget);
    });
  });
}
