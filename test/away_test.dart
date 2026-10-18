import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:expense_tracker/models/away.dart';
import 'package:expense_tracker/models/currency.dart';
import 'package:expense_tracker/models/expense.dart';
import 'package:expense_tracker/models/fines.dart';
import 'package:expense_tracker/models/shared_budget.dart';
import 'package:expense_tracker/models/shared_split.dart';
import 'package:expense_tracker/models/transaction_type.dart';
import 'package:expense_tracker/widgets/add_expense_sheet.dart';
import 'package:expense_tracker/widgets/fine_banner.dart';
import 'package:expense_tracker/widgets/split_card.dart';

final _day = DateTime(2026, 10, 1);
var _id = 0;

Expense buy(String who, double amount, {List<String>? members}) => Expense(
      id: 'b${_id++}',
      amount: amount,
      date: _day,
      author: who,
      currency: AppCurrency.kzt,
      members: members,
    );

Expense pay(String from, String to, double amount) => Expense(
      id: 't${_id++}',
      amount: amount,
      date: _day,
      author: from,
      recipient: to,
      currency: AppCurrency.kzt,
      type: TransactionType.transfer,
    );

double owed(SharedPool pool, String from, String to) => pool.settlements
    .where((s) => s.from == from && s.to == to)
    .fold(0.0, (sum, s) => sum + s.amount);

const home = ['Азамат', 'Аслан', 'Мухаммад'];

AwayRequest request({Map<String, String> votes = const {}}) => AwayRequest(
      name: 'Имран',
      since: _day,
      approvers: home,
      votes: votes,
    );

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  group('who shares a purchase', () {
    test('a purchase made while Имран is away is split between the three', () {
      final pool = sharedPool([buy('Азамат', 3000, members: home)]);
      expect(owed(pool, 'Аслан', 'Азамат'), 1000);
      expect(owed(pool, 'Мухаммад', 'Азамат'), 1000);
      expect(owed(pool, 'Имран', 'Азамат'), 0);
    });

    test('a debt from before he left stays; new purchases do not add to it',
        () {
      final pool = sharedPool([
        buy('Азамат', 4000),
        buy('Азамат', 3000, members: home),
      ]);
      expect(owed(pool, 'Имран', 'Азамат'), 1000);
      expect(owed(pool, 'Аслан', 'Азамат'), 2000);
    });

    test('records from before away existed are split four ways', () {
      expect(buy('Азамат', 1).sharers, hasLength(4));
    });

    test('paying off the old debt while away still settles it', () {
      final pool = sharedPool([
        buy('Азамат', 4000),
        buy('Азамат', 3000, members: home),
        pay('Имран', 'Азамат', 1000),
        pay('Аслан', 'Азамат', 2000),
        pay('Мухаммад', 'Азамат', 2000),
      ]);
      expect(pool.isSettled, isTrue);
      final imran = pool.people.firstWhere((p) => p.name == 'Имран');
      expect(imran.spent, 1000);
    });

    test('some purchases skip the one away, some are put on him too', () {
      final pool = sharedPool([
        buy('Азамат', 3000, members: home),
        buy('Азамат', 4000), // the admin put this one on all four
        buy('Аслан', 2000, members: const ['Аслан', 'Имран']),
      ]);
      expect(owed(pool, 'Имран', 'Азамат'), 1000);
      expect(owed(pool, 'Имран', 'Аслан'), 1000);
      expect(owed(pool, 'Аслан', 'Азамат'), 2000);
      expect(owed(pool, 'Мухаммад', 'Азамат'), 2000);
      expect(owed(pool, 'Мухаммад', 'Аслан'), 0);
      expect(pool.sharedTotal, 9000);
      final total = pool.people.fold(0.0, (sum, p) => sum + p.balance);
      expect(total, closeTo(0, 0.001));
    });

    test('a purchase the admin books to someone away is owed to him', () {
      final pool = sharedPool([buy('Имран', 3000, members: home)]);
      for (final n in home) {
        expect(owed(pool, n, 'Имран'), 1000, reason: n);
      }
    });

    test('random mixed splits always balance and settle to each share', () {
      final random = Random(7);
      for (var round = 0; round < 200; round++) {
        final records = <Expense>[];
        final share = {for (final n in kRoommates) n: 0.0};
        for (var i = 0; i < 1 + random.nextInt(8); i++) {
          final among = [
            for (final n in kRoommates)
              if (random.nextBool()) n,
          ];
          if (among.isEmpty) among.add(kRoommates[random.nextInt(4)]);
          final payer = kRoommates[random.nextInt(4)];
          final amount = (1 + random.nextInt(20000)).toDouble();
          records.add(buy(payer, amount, members: among));
          final parts = splitEvenly(amount, among.length);
          for (var k = 0; k < among.length; k++) {
            share[among[k]] = share[among[k]]! + parts[k];
          }
        }
        final pool = sharedPool(records);
        final total = pool.people.fold(0.0, (sum, p) => sum + p.balance);
        expect(total, closeTo(0, 0.001), reason: 'round $round');

        final settled = sharedPool([
          ...records,
          for (final s in pool.settlements) pay(s.from, s.to, s.amount),
        ]);
        expect(settled.isSettled, isTrue, reason: 'round $round');
        for (final p in settled.people) {
          expect(p.spent, closeTo(share[p.name]!, 1),
              reason: 'round $round, ${p.name}');
        }
      }
    });

    test('members survive a round trip through Firestore', () {
      final json = buy('Азамат', 1, members: home).toJson();
      json['date'] = buy('x', 1).toJson()['date'];
      expect(Expense.fromJson(json).members, home);
    });
  });

  group('fines while someone is away', () {
    final f = Expense(
      id: 'f',
      amount: 3000,
      date: _day,
      author: 'Азамат',
      offender: 'Аслан',
      votes: const {'Азамат': kVoteYes},
      currency: AppCurrency.kzt,
      type: TransactionType.fine,
      members: home,
    );

    test('only those home judge it, and wait only on them', () {
      expect(fineJudges(f), ['Азамат', 'Мухаммад']);
      expect(fineAwaiting(f), ['Аслан', 'Мухаммад']);
    });

    test('nothing of it goes to the one away', () {
      final active = Expense.fromJson({
        ...f.toJson(),
        'votes': {'Азамат': kVoteYes, 'Мухаммад': kVoteYes},
        'offenderVote': kOffenderAccept,
      });
      final pool = sharedPool([active]);
      expect(owed(pool, 'Аслан', 'Азамат'), 1500);
      expect(owed(pool, 'Аслан', 'Мухаммад'), 1500);
      expect(owed(pool, 'Аслан', 'Имран'), 0);
    });

    testWidgets('someone who is not a judge gets no vote buttons',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: FineBanner(
            fine: f,
            myName: 'Имран',
            onVote: (_) {},
            onAnswer: (_) {},
          ),
        ),
      ));
      expect(find.text('Назначить'), findsNothing);
      expect(find.textContaining('Ждём'), findsOneWidget);
    });
  });

  group('the away request', () {
    test('waits until everyone home agrees', () {
      expect(request().status(), AwayStatus.pending);
      expect(
        request(votes: {'Азамат': kAwayYes}).awaiting(),
        ['Аслан', 'Мухаммад'],
      );
      final agreed = request(votes: {for (final n in home) n: kAwayYes});
      expect(agreed.status(), AwayStatus.away);
    });

    test('one no turns it down', () {
      final r = request(votes: {'Азамат': kAwayYes, 'Аслан': kAwayNo});
      expect(r.status(), AwayStatus.rejected);
      expect(r.rejectedBy, ['Аслан']);
    });

    test('only an agreed request takes him out of the flat', () {
      expect(AwayBook({'Имран': request()}).present, hasLength(4));
      final away = AwayBook({
        'Имран': request(votes: {for (final n in home) n: kAwayYes}),
      });
      expect(away.present, home);
      expect(away.isAway('Имран'), isTrue);
      expect(AwayBook().statusOf('Имран'), AwayStatus.home);
    });

    test('a request with nobody left to ask goes through at once', () {
      final r = AwayRequest(name: 'Имран', since: _day, approvers: const []);
      expect(r.status(), AwayStatus.away);
    });

    test('someone away is not waited on for another request', () {
      final book = AwayBook({
        'Имран': request(votes: {'Азамат': kAwayYes, 'Мухаммад': kAwayYes}),
        'Аслан': AwayRequest(
          name: 'Аслан',
          since: _day,
          approvers: const ['Азамат', 'Мухаммад', 'Имран'],
          votes: const {'Азамат': kAwayYes, 'Мухаммад': kAwayYes},
        ),
      });
      // Both asking at once: each still waits on the other, who is home
      // until agreed and can vote.
      expect(book.isAway('Аслан'), isFalse);
      expect(book.awaiting(book.requests['Имран']!), ['Аслан']);

      final asl = AwayBook({
        'Аслан': AwayRequest(
          name: 'Аслан',
          since: _day,
          approvers: const ['Азамат', 'Мухаммад'],
          votes: const {'Азамат': kAwayYes, 'Мухаммад': kAwayYes},
        ),
        'Имран': request(votes: {'Азамат': kAwayYes, 'Мухаммад': kAwayYes}),
      });
      expect(asl.isAway('Аслан'), isTrue);
      expect(asl.isAway('Имран'), isTrue, reason: 'Аслан no longer decides');
      expect(asl.present, ['Азамат', 'Мухаммад']);
    });

    test('reads back from the stored document', () {
      final book = AwayBook.fromJson({
        'Имран': request(votes: {'Азамат': kAwayYes}).toJson(),
        'Незнакомец': {'approvers': <String>[]},
        'Аслан': 'мусор',
      });
      expect(book.requests.keys, ['Имран']);
      expect(book.statusOf('Имран'), AwayStatus.pending);
    });
  });

  testWidgets('names in the totals are tappable only for the admin',
      (tester) async {
    String? tapped;
    Widget card({ValueChanged<String>? onPerson}) => MaterialApp(
          home: Scaffold(
            body: SplitCard(
              pool: sharedPool([buy('Азамат', 4000)]),
              currency: AppCurrency.kzt,
              myName: 'Азамат',
              pending: const [],
              onPaid: (_) {},
              onConfirm: (_) {},
              onOffset: (_) {},
              onPerson: onPerson,
            ),
          ),
        );

    await tester.pumpWidget(card());
    expect(find.byType(InkWell), findsNothing);

    await tester.pumpWidget(card(onPerson: (name) => tapped = name));
    await tester.tap(find.text('Мухаммад').first);
    expect(tapped, 'Мухаммад');
  });

  testWidgets('the admin edits who shares a purchase, away included',
      (tester) async {
    Expense? saved;
    final original = buy('Азамат', 3000, members: home);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AddExpenseSheet(
          type: TransactionType.expense,
          currency: AppCurrency.kzt,
          existing: original,
          chooseShares: true,
          away: const {'Имран'},
          onSubmit: (e) => saved = e,
        ),
      ),
    ));
    expect(find.text('НА КОГО ДЕЛИТСЯ'), findsOneWidget);
    expect(find.text('КТО ПЛАТИЛ'), findsNothing);

    // Put it on Имран as well.
    await tester.tap(find.widgetWithText(FilterChip, 'Имран'));
    await tester.pump();
    await tester.ensureVisible(find.text('Сохранить'));
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();

    expect(saved!.id, original.id);
    expect(saved!.author, 'Азамат', reason: 'the payer never changes');
    expect(saved!.members, kRoommates);
    expect(saved!.amount, 3000);
  });

  testWidgets('nobody to split with is refused', (tester) async {
    Expense? saved;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AddExpenseSheet(
          type: TransactionType.expense,
          currency: AppCurrency.kzt,
          existing: buy('Азамат', 3000, members: const ['Азамат']),
          chooseShares: true,
          onSubmit: (e) => saved = e,
        ),
      ),
    ));
    await tester.tap(find.widgetWithText(FilterChip, 'Азамат'));
    await tester.pump();
    await tester.ensureVisible(find.text('Сохранить'));
    await tester.tap(find.text('Сохранить'));
    await tester.pump();
    expect(saved, isNull);
    expect(find.text('Отметьте хотя бы одного'), findsOneWidget);
  });

  test('a request with no approvers, as the admin sends one, is in force', () {
    final book = AwayBook({
      'Аслан': AwayRequest(name: 'Аслан', since: _day, approvers: const []),
    });
    expect(book.isAway('Аслан'), isTrue);
  });
}
