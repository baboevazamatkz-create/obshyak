import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:expense_tracker/models/away.dart';
import 'package:expense_tracker/models/currency.dart';
import 'package:expense_tracker/models/expense.dart';
import 'package:expense_tracker/models/fines.dart';
import 'package:expense_tracker/models/shared_split.dart';
import 'package:expense_tracker/models/transaction_type.dart';
import 'package:expense_tracker/widgets/away_banner.dart';

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
  });

  group('the away request', () {
    test('waits until everyone home agrees', () {
      expect(request().status, AwayStatus.pending);
      expect(
        request(votes: {'Азамат': kAwayYes}).awaiting,
        ['Аслан', 'Мухаммад'],
      );
      final agreed = request(votes: {for (final n in home) n: kAwayYes});
      expect(agreed.status, AwayStatus.away);
    });

    test('one no turns it down', () {
      final r = request(votes: {'Азамат': kAwayYes, 'Аслан': kAwayNo});
      expect(r.status, AwayStatus.rejected);
      expect(r.rejectedBy, ['Аслан']);
    });

    test('only an agreed request takes him out of the flat', () {
      expect(AwayBook({'Имран': request()}).present, hasLength(4));
      final away = AwayBook({
        'Имран': request(votes: {for (final n in home) n: kAwayYes}),
      });
      expect(away.present, home);
      expect(away.isAway('Имран'), isTrue);
      expect(const AwayBook().statusOf('Имран'), AwayStatus.home);
    });

    test('a request with nobody left to ask goes through at once', () {
      final r = AwayRequest(name: 'Имран', since: _day, approvers: const []);
      expect(r.status, AwayStatus.away);
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

  testWidgets('an approver can agree or refuse; the one asking just waits',
      (tester) async {
    String? vote;
    Widget banner(String me) => MaterialApp(
          home: Scaffold(
            body: AwayBanner(
              request: request(),
              myName: me,
              onVote: (v) => vote = v,
              onDismiss: () {},
            ),
          ),
        );

    await tester.pumpWidget(banner('Аслан'));
    expect(find.text('Имран уезжает и просит отпуск'), findsOneWidget);
    await tester.tap(find.text('Согласовать'));
    expect(vote, kAwayYes);

    await tester.pumpWidget(banner('Имран'));
    expect(find.text('Согласовать'), findsNothing);
    expect(find.text('Ждём: Азамат, Аслан, Мухаммад'), findsOneWidget);
  });

  testWidgets('the button shows where the flatmate stands', (tester) async {
    for (final (status, label) in [
      (AwayStatus.home, 'Отпуск'),
      (AwayStatus.pending, 'Ждём'),
      (AwayStatus.away, 'В отпуске'),
    ]) {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: AwayButton(status: status, onPressed: () {})),
      ));
      expect(find.text(label), findsOneWidget);
    }
  });
}
