import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:intl/date_symbol_data_local.dart';

import 'package:expense_tracker/data/scan_service.dart';
import 'package:expense_tracker/models/currency.dart';
import 'package:expense_tracker/models/expense.dart';
import 'package:expense_tracker/models/expense_category.dart';
import 'package:expense_tracker/models/scanned_transaction.dart';
import 'package:expense_tracker/models/transaction_type.dart';
import 'package:expense_tracker/screens/scan_flow.dart';
import 'package:expense_tracker/theme.dart';
import 'package:expense_tracker/widgets/scan_review_sheet.dart';

const _endpoint = 'https://scan.example.test';

/// The shape worker/src/index.js answers with. Kept here verbatim so a
/// change on either side shows up as a failing test rather than as an
/// empty review sheet on someone's phone.
const _workerAnswer = {
  'document': 'statement',
  'transactions': [
    {
      'type': 'expense',
      'amount': 1234.5,
      'currency': 'rub',
      'date': '2026-09-12',
      'note': 'Магнит',
      'category': 'food',
      'confidence': 0.93,
    },
    {
      'type': 'income',
      'amount': 50000,
      'currency': 'rub',
      'date': '2026-09-10',
      'note': 'Зарплата',
      'category': 'other',
      'confidence': 0.99,
    },
  ],
};

ScanService _service(
  Future<http.Response> Function(http.Request request) handler, {
  String? token = 'test-token',
}) =>
    ScanService(
      endpoint: _endpoint,
      token: () async => token,
      client: MockClient(handler),
    );

Expense _expense({
  required double amount,
  required DateTime date,
  TransactionType type = TransactionType.expense,
}) =>
    Expense(
      id: '${type.name}-$amount-${date.day}',
      amount: amount,
      date: date,
      type: type,
      category: ExpenseCategory.food,
    );

Future<void> _pumpSheet(
  WidgetTester tester, {
  required ScanResult result,
  required Set<int> duplicates,
  required void Function(List<Expense>) onConfirm,
  Brightness brightness = Brightness.light,
  double textScale = 1.0,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(brightness),
      builder: (context, inner) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: inner!,
      ),
      home: Scaffold(
        body: ScanReviewSheet(
          result: result,
          currency: AppCurrency.rub,
          duplicates: duplicates,
          onConfirm: onConfirm,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  group('Reading the worker answer', () {
    test('a statement becomes one row per operation', () {
      final result = ScanResult.fromJson(
        Map<String, dynamic>.from(_workerAnswer),
        fallbackCurrency: AppCurrency.rub,
      );

      expect(result.document, ScanDocument.statement);
      expect(result.transactions, hasLength(2));
      expect(result.transactions.first.amount, 1234.5);
      expect(result.transactions.first.category, ExpenseCategory.food);
      expect(result.transactions.first.date, DateTime(2026, 9, 12));
      expect(result.transactions.last.type, TransactionType.income);
    });

    test('a row without a usable amount is dropped, not written as zero', () {
      final result = ScanResult.fromJson(
        {
          'document': 'receipt',
          'transactions': [
            {'type': 'expense', 'amount': 0, 'date': '2026-09-12'},
            {'type': 'expense', 'date': '2026-09-12'},
            {'type': 'expense', 'amount': 40, 'date': '2026-09-12'},
          ],
        },
        fallbackCurrency: AppCurrency.rub,
      );

      expect(result.transactions, hasLength(1));
      expect(result.transactions.single.amount, 40);
    });

    test('a statement’s minus is a direction, not an amount', () {
      // "- 1 920,00 ₸" read literally would have dropped every expense on
      // the page and left the sheet saying nothing was found.
      final result = ScanResult.fromJson(
        {
          'document': 'statement',
          'transactions': [
            {
              'type': 'expense',
              'amount': -1920,
              'date': '2026-09-08',
              'note': 'YANDEX.GO',
              'category': 'transport',
            },
          ],
        },
        fallbackCurrency: AppCurrency.kzt,
      );

      expect(result.transactions.single.amount, 1920);
      expect(result.transactions.single.type, TransactionType.expense);
    });

    test(
        'an unknown category falls back to other, an unseen currency to '
        'the budget’s own', () {
      final result = ScanResult.fromJson(
        {
          'document': 'nonsense',
          'transactions': [
            {
              'type': 'sideways',
              'amount': 10,
              'date': 'вчера',
              'category': 'crypto',
            },
          ],
        },
        fallbackCurrency: AppCurrency.kzt,
      );

      final row = result.transactions.single;
      expect(result.document, ScanDocument.other);
      expect(row.category, ExpenseCategory.other);
      expect(row.currency, AppCurrency.kzt);
      expect(row.type, TransactionType.expense);
      // An unparseable date becomes today rather than nothing.
      expect(row.date.day, DateTime.now().day);
    });

    test('a low confidence is what marks a row as worth checking', () {
      final result = ScanResult.fromJson(
        {
          'document': 'receipt',
          'transactions': [
            {
              'type': 'expense',
              'amount': 10,
              'date': '2026-09-12',
              'confidence': 0.4
            },
            {
              'type': 'expense',
              'amount': 11,
              'date': '2026-09-12',
              'confidence': 0.8
            },
          ],
        },
        fallbackCurrency: AppCurrency.rub,
      );

      expect(result.transactions.first.isUncertain, isTrue);
      expect(result.transactions.last.isUncertain, isFalse);
    });
  });

  group('Talking to the worker', () {
    test('the request carries the token, the snapshots and today', () async {
      late http.Request seen;
      final service = _service((request) async {
        seen = request;
        return http.Response(jsonEncode(_workerAnswer), 200,
            headers: {'content-type': 'application/json; charset=utf-8'});
      });

      await service.scan(
        images: [
          ScanImage(bytes: Uint8List.fromList([1, 2, 3]), mime: 'image/jpeg'),
        ],
        currency: AppCurrency.kzt,
        today: DateTime(2026, 9, 13),
      );

      expect(seen.url.toString(), _endpoint);
      expect(seen.headers['Authorization'], 'Bearer test-token');

      final body = jsonDecode(seen.body) as Map<String, dynamic>;
      expect(body['currency'], 'kzt');
      expect(body['today'], '2026-09-13');
      final images = body['images'] as List;
      expect(images, hasLength(1));
      expect((images.single as Map)['mime'], 'image/jpeg');
      expect(base64Decode((images.single as Map)['data'] as String), [1, 2, 3]);
    });

    test('the worker’s own wording is what the user is shown', () async {
      final service = _service((_) async => http.Response(
            jsonEncode({'error': 'На сегодня разборов больше нет'}),
            429,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ));

      expect(
        () => service.scan(
          images: [
            ScanImage(bytes: Uint8List.fromList([1]), mime: 'image/jpeg'),
          ],
          currency: AppCurrency.rub,
        ),
        throwsA(isA<ScanException>().having(
            (e) => e.message, 'message', 'На сегодня разборов больше нет')),
      );
    });

    test('a wordless failure still says something in Russian', () async {
      final service = _service((_) async => http.Response('<html>', 500));

      expect(
        () => service.scan(
          images: [
            ScanImage(bytes: Uint8List.fromList([1]), mime: 'image/jpeg'),
          ],
          currency: AppCurrency.rub,
        ),
        throwsA(isA<ScanException>()
            .having((e) => e.message, 'message', contains('500'))),
      );
    });

    test('without a signed-in user nothing is uploaded', () async {
      var called = false;
      final service = _service(
        (_) async {
          called = true;
          return http.Response('{}', 200);
        },
        token: null,
      );

      await expectLater(
        service.scan(
          images: [
            ScanImage(bytes: Uint8List.fromList([1]), mime: 'image/jpeg'),
          ],
          currency: AppCurrency.rub,
        ),
        throwsA(isA<ScanException>()),
      );
      expect(called, isFalse);
    });

    test('an unconfigured scanner refuses before any request', () async {
      final service = ScanService(
        endpoint: '',
        token: () async => 'token',
        client: MockClient((_) async => http.Response('{}', 200)),
      );

      expect(
        () => service.scan(
          images: [
            ScanImage(bytes: Uint8List.fromList([1]), mime: 'image/jpeg'),
          ],
          currency: AppCurrency.rub,
        ),
        throwsA(isA<ScanException>()),
      );
    });
  });

  group('The flow', () {
    Future<Uint8List?> runFlow(
      WidgetTester tester, {
      required bool recognize,
      required List<Uint8List> picked,
    }) async {
      Uint8List? manualPhoto;
      var added = false;
      final flow = ScanFlow(capture: (_) async => picked);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(Brightness.dark),
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => flow.run(
                  context,
                  currency: AppCurrency.kzt,
                  existing: const [],
                  recognize: recognize,
                  onAdd: (_, __) async => added = true,
                  onManual: (photo) async => manualPhoto = photo,
                ),
                child: const Text('scan'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('scan'));
      // The spinner's first frame, which the flow waits for before it
      // starts on the picture; then real time for the picture work.
      await tester.pump();
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(
            const Duration(milliseconds: 500),
          ));
      await tester.pumpAndSettle();
      expect(added, isFalse);
      return manualPhoto;
    }

    testWidgets('without the scanner, the receipt goes to the form by hand',
        (tester) async {
      final receipt = Uint8List.fromList(
        img.encodePng(img.Image(width: 300, height: 600)),
      );
      final photo = await runFlow(tester, recognize: false, picked: [receipt]);
      expect(photo, isNotNull, reason: 'the photo stays with the record');
      expect(img.decodeJpg(photo!), isNotNull);
    });

    testWidgets('a receipt that cannot be read as an image adds nothing',
        (tester) async {
      final photo = await runFlow(
        tester,
        recognize: false,
        picked: [
          Uint8List.fromList([1, 2, 3, 4])
        ],
      );
      expect(photo, isNull);
      expect(find.text('Не удалось прочитать фото чека'), findsOneWidget);
    });

    testWidgets('drops focus from whatever field was last typed into',
        (tester) async {
      final focusNode = FocusNode();
      addTearDown(focusNode.dispose);
      final flow = ScanFlow(
        capture: (_) async => [],
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(Brightness.light),
          home: Scaffold(
            body: Builder(
              builder: (context) => Column(
                children: [
                  TextField(focusNode: focusNode, autofocus: true),
                  ElevatedButton(
                    onPressed: () => flow.run(
                      context,
                      currency: AppCurrency.rub,
                      existing: const [],
                      onAdd: (_, __) async {},
                      onManual: (_) async {},
                    ),
                    child: const Text('scan'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(focusNode.hasFocus, isTrue);

      await tester.tap(find.text('scan'));
      await tester.pump();

      // Dropped as soon as the flow starts, before the camera even opens
      // -- a lingering focused field is what leaves
      // the browser's own hidden input, and whatever decoration it
      // carries, sitting at its old position.
      expect(focusNode.hasFocus, isFalse);

      // Let the empty capture settle so the test does not leave a pending
      // timer behind.
      await tester.pumpAndSettle();
    });

    testWidgets(
        'the loading message has no touch-exploration target for a '
        'browser to mistake for a form field', (tester) async {
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(Brightness.light),
          home: const Scaffold(
            body: Center(child: ScanProgressContent()),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Читаю снимок…'), findsOneWidget);
      // On the web this is the node a browser found and drew its own
      // underline on, reported against Yandex on Android -- ExcludeSemantics
      // is what removes it while SemanticsService.sendAnnouncement (called
      // from ScanFlow, not exercised by this widget alone) still speaks the
      // message.
      expect(find.bySemanticsLabel('Читаю снимок…'), findsNothing);

      handle.dispose();
    });
  });

  group('Preparing a snapshot', () {
    Uint8List screenshot(int width, int height) {
      final image = img.Image(width: width, height: height);
      for (var x = 0; x < width; x += 3) {
        for (var y = 0; y < height; y += 3) {
          image.setPixelRgb(x, y, x % 255, y % 255, 120);
        }
      }
      return Uint8List.fromList(img.encodePng(image));
    }

    test('a phone screenshot is cut into tiles, not squeezed into a square',
        () {
      // 1080x2400 is an ordinary phone screenshot. Fitted whole into what
      // a model reads at, it would come back about 700 pixels wide and a
      // four-column table would stop being legible; tiling keeps the width.
      final tiles = prepareScanImages(
        (bytes: screenshot(1080, 2400), maxTiles: kScanMaxTiles),
      );

      expect(tiles.length, greaterThan(1));
      for (final tile in tiles) {
        final decoded = img.decodeImage(tile.bytes)!;
        expect(decoded.width, 1080);
        expect(
            decoded.width * decoded.height, lessThanOrEqualTo(kScanTilePixels));
        expect(tile.mime, 'image/jpeg');
      }
    });

    test('the tiles overlap, so no row falls between them', () {
      final tiles = prepareScanImages(
        (bytes: screenshot(1080, 2400), maxTiles: kScanMaxTiles),
      );

      final covered = tiles
          .map((t) => img.decodeImage(t.bytes)!.height)
          .reduce((a, b) => a + b);
      // More pixels of height across the tiles than the original had:
      // that surplus is the overlap.
      expect(covered, greaterThan(2400));
    });

    test('a snapshot that already fits is left as one image', () {
      final tiles = prepareScanImages(
        (bytes: screenshot(900, 700), maxTiles: kScanMaxTiles),
      );

      expect(tiles, hasLength(1));
      final decoded = img.decodeImage(tiles.single.bytes)!;
      expect(decoded.width, 900);
      expect(decoded.height, 700);
    });

    test('a wide photo is narrowed to the tile width', () {
      final tiles = prepareScanImages(
        (bytes: screenshot(3000, 2000), maxTiles: kScanMaxTiles),
      );

      expect(img.decodeImage(tiles.first.bytes)!.width, kScanTileWidth);
    });

    test('the tile budget is respected', () {
      final tiles = prepareScanImages(
        (bytes: screenshot(1080, 20000), maxTiles: 3),
      );

      expect(tiles, hasLength(3));
    });

    test('bytes that are not an image at all are passed on, not thrown away',
        () {
      final junk = Uint8List.fromList(List.filled(600 * 1024, 7));
      final tiles = prepareScanImages((bytes: junk, maxTiles: kScanMaxTiles));

      expect(tiles.single.bytes, same(junk));
      expect(tiles.single.mime, 'image/jpeg');
    });
  });

  group('Finding what is already there', () {
    test('same direction, same day and same sum reads as a duplicate', () {
      final scanned = ScanResult.fromJson(
        Map<String, dynamic>.from(_workerAnswer),
        fallbackCurrency: AppCurrency.rub,
      ).transactions;

      final duplicates = findDuplicates(scanned, [
        _expense(amount: 1234.5, date: DateTime(2026, 9, 12, 19, 30)),
      ]);

      expect(duplicates, {0});
    });

    test('a different day, sum or direction is not a duplicate', () {
      final scanned = ScanResult.fromJson(
        Map<String, dynamic>.from(_workerAnswer),
        fallbackCurrency: AppCurrency.rub,
      ).transactions;

      expect(
        findDuplicates(scanned, [
          _expense(amount: 1234.5, date: DateTime(2026, 9, 11)),
          _expense(amount: 1234.0, date: DateTime(2026, 9, 12)),
          _expense(
            amount: 1234.5,
            date: DateTime(2026, 9, 12),
            type: TransactionType.income,
          ),
        ]),
        isEmpty,
      );
    });

    test('a statement may hold the same sum twice in a day, and both stand',
        () {
      final scanned = ScanResult.fromJson(
        {
          'document': 'statement',
          'transactions': [
            {'type': 'expense', 'amount': 500, 'date': '2026-09-07'},
            {'type': 'expense', 'amount': 500, 'date': '2026-09-07'},
          ],
        },
        fallbackCurrency: AppCurrency.rub,
      ).transactions;

      // Nothing in the budget yet: two real purchases, both offered.
      expect(findDuplicates(scanned, const []), isEmpty);

      // One of them already recorded: only one of the two is a repeat.
      expect(
        findDuplicates(scanned, [
          _expense(amount: 500, date: DateTime(2026, 9, 7)),
        ]),
        {0},
      );
    });
  });

  test('a personal part set while reviewing reaches the record', () {
    final row = ScannedTransaction(
      type: TransactionType.expense,
      amount: 5000,
      currency: AppCurrency.kzt,
      date: DateTime(2026, 10, 1),
      note: 'Магнум',
      category: ExpenseCategory.food,
    ).copyWith(personal: 1200);
    final expense = row.toExpense(householdCurrency: AppCurrency.kzt);
    expect(expense.personal, 1200);
    expect(expense.sharedAmount, 3800);
  });

  group('The review sheet', () {
    ScanResult parsed() => ScanResult.fromJson(
          Map<String, dynamic>.from(_workerAnswer),
          fallbackCurrency: AppCurrency.rub,
        );

    testWidgets('every read row is listed and ticked', (tester) async {
      await _pumpSheet(
        tester,
        result: parsed(),
        duplicates: const {},
        onConfirm: (_) {},
      );

      // The title and the editable name both show it.
      expect(find.text('Магнит'), findsWidgets);
      expect(find.text('Зарплата'), findsWidgets);
      expect(find.text('ВЫБРАНО 2 ИЗ 2'), findsOneWidget);
      expect(find.text('Добавить 2 записи'), findsOneWidget);
    });

    testWidgets('a row that looks to be there already is offered unticked',
        (tester) async {
      List<Expense>? confirmed;
      await _pumpSheet(
        tester,
        result: parsed(),
        duplicates: const {0},
        onConfirm: (expenses) => confirmed = expenses,
      );

      expect(find.text('ВЫБРАНО 1 ИЗ 2'), findsOneWidget);
      expect(find.textContaining('похоже, уже есть'), findsOneWidget);

      await tester.tap(find.text('Добавить запись'));
      await tester.pumpAndSettle();

      expect(confirmed, hasLength(1));
      expect(confirmed!.single.amount, 50000);
      expect(confirmed!.single.type, TransactionType.income);
    });

    testWidgets('an unticked row can be taken back', (tester) async {
      List<Expense>? confirmed;
      await _pumpSheet(
        tester,
        result: parsed(),
        duplicates: const {0},
        onConfirm: (expenses) => confirmed = expenses,
      );

      await tester.tap(find.text('Магнит').first);
      await tester.pumpAndSettle();
      expect(find.text('ВЫБРАНО 2 ИЗ 2'), findsOneWidget);

      await tester.tap(find.text('Добавить 2 записи'));
      await tester.pumpAndSettle();
      expect(confirmed, hasLength(2));
    });

    testWidgets('a row opens in place and its personal part reaches the record',
        (tester) async {
      List<Expense>? confirmed;
      await _pumpSheet(
        tester,
        result: parsed(),
        duplicates: const {},
        onConfirm: (expenses) => confirmed = expenses,
      );

      // The fields are always open under each row: no menu, no form.
      expect(find.text('Лично, не в общак'), findsWidgets);
      expect(find.byIcon(Icons.more_vert_rounded), findsNothing);
      expect(find.text('Изменить'), findsNothing);
      expect(find.text('Это доход'), findsNothing);

      // The editor's fields in order: amount, personal part, note.
      final amountField = find.byType(TextField).at(0);
      final personalField =
          find.widgetWithText(TextField, 'Лично, не в общак').first;
      await tester.enterText(amountField, '2000');
      await tester.enterText(personalField, '500');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Добавить 2 записи'));
      await tester.pumpAndSettle();

      expect(confirmed!.first.amount, 2000);
      expect(confirmed!.first.personal, 500);
      expect(confirmed!.first.sharedAmount, 1500);
    });

    testWidgets(
        'amounts in a scanned row are grouped in thousands, whole tenge',
        (tester) async {
      await _pumpSheet(
        tester,
        result: parsed(),
        duplicates: const {},
        onConfirm: (_) {},
      );
      await tester.enterText(find.byType(TextField).at(0), '1234567');
      await tester.pumpAndSettle();
      expect(find.text('1 234 567'), findsOneWidget);

      await tester.enterText(find.byType(TextField).at(0), '1234,5');
      await tester.pumpAndSettle();
      // No hundredths: the decimal part is not taken.
      expect(find.text('1 234'), findsOneWidget);
    });

    testWidgets('a personal part above the amount cannot be added',
        (tester) async {
      await _pumpSheet(
        tester,
        result: parsed(),
        duplicates: const {},
        onConfirm: (_) => fail('an invalid personal part must not save'),
      );

      await tester.enterText(
        find.widgetWithText(TextField, 'Лично, не в общак').first,
        '99999999',
      );
      await tester.pumpAndSettle();

      expect(find.text('Не больше суммы чека'), findsOneWidget);
      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Добавить 2 записи'),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('nothing found says so and offers only a way out',
        (tester) async {
      await _pumpSheet(
        tester,
        result: const ScanResult(
          document: ScanDocument.other,
          transactions: [],
        ),
        duplicates: const {},
        onConfirm: (_) => fail('nothing to confirm'),
      );

      expect(find.text('НИЧЕГО НЕ НАЙДЕНО'), findsOneWidget);
      expect(find.text('Закрыть'), findsOneWidget);
      expect(find.textContaining('Добавить'), findsNothing);
    });

    testWidgets('a whole statement can be dropped or taken in one tap',
        (tester) async {
      List<Expense>? confirmed;
      await _pumpSheet(
        tester,
        result: parsed(),
        duplicates: const {},
        onConfirm: (expenses) => confirmed = expenses,
      );

      await tester.tap(find.text('СНЯТЬ ВСЕ'));
      await tester.pumpAndSettle();
      expect(find.text('ВЫБРАНО 0 ИЗ 2'), findsOneWidget);

      await tester.tap(find.text('ВЫБРАТЬ ВСЕ'));
      await tester.pumpAndSettle();
      expect(find.text('ВЫБРАНО 2 ИЗ 2'), findsOneWidget);

      await tester.tap(find.text('Добавить 2 записи'));
      await tester.pumpAndSettle();
      expect(confirmed, hasLength(2));
    });

    testWidgets('a forty-row statement fits a small phone', (tester) async {
      final many = ScanResult.fromJson(
        {
          'document': 'statement',
          'transactions': [
            for (var i = 0; i < 40; i++)
              {
                'type': i.isEven ? 'expense' : 'income',
                'amount': 100 + i * 37,
                'date': '2026-09-0${1 + i % 9}',
                'note': 'Операция номер $i, довольно длинное описание',
                'category': 'food',
              },
          ],
        },
        fallbackCurrency: AppCurrency.rub,
      );

      tester.view.physicalSize = const Size(320, 534);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await _pumpSheet(
        tester,
        result: many,
        duplicates: const {},
        onConfirm: (_) {},
      );

      expect(tester.takeException(), isNull);
      expect(find.text('ВЫБРАНО 40 ИЗ 40'), findsOneWidget);
    });

    testWidgets('…and the same phone at the largest system font',
        (tester) async {
      final many = ScanResult.fromJson(
        {
          'document': 'statement',
          'transactions': [
            for (var i = 0; i < 12; i++)
              {
                'type': 'expense',
                'amount': 1000 + i * 137,
                'date': '2026-09-08',
                'note': 'Операция номер $i, довольно длинное описание',
                'category': 'food',
              },
          ],
        },
        fallbackCurrency: AppCurrency.rub,
      );

      tester.view.physicalSize = const Size(320, 534);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await _pumpSheet(
        tester,
        result: many,
        duplicates: const {},
        onConfirm: (_) {},
        textScale: 1.25,
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('the sheet survives the dark theme', (tester) async {
      await _pumpSheet(
        tester,
        result: parsed(),
        duplicates: const {1},
        onConfirm: (_) {},
        brightness: Brightness.dark,
      );
      expect(tester.takeException(), isNull);
    });
  });
}
