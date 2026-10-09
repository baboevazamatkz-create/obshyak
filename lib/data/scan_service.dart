import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

import '../models/currency.dart';
import '../models/scanned_transaction.dart';

/// A snapshot on its way to the scanner.
class ScanImage {
  final Uint8List bytes;
  final String mime;

  const ScanImage({required this.bytes, required this.mime});

  Map<String, dynamic> toJson() => {'data': base64Encode(bytes), 'mime': mime};
}

/// Something the user needs to be told, in words they can act on.
class ScanException implements Exception {
  final String message;
  const ScanException(this.message);

  @override
  String toString() => message;
}

/// Reads snapshots through the Cloudflare worker in worker/.
///
/// The address arrives at build time rather than living in the source:
/// it is not a secret, but it changes per deployment, and an unset one has
/// to mean "the scanner is not set up" rather than "the app is broken".
class ScanService {
  /// Set with --dart-define=SCAN_ENDPOINT=..., which both workflows pass
  /// from the repository variable of the same name.
  static const endpoint = String.fromEnvironment('SCAN_ENDPOINT');

  static bool get isConfigured => endpoint.isNotEmpty;

  /// Beyond this the worker refuses the request. One long screenshot
  /// becomes two or three tiles (see [prepareScanImages]), so this is a
  /// ceiling on tiles rather than on snapshots picked.
  static const maxImages = kScanMaxTiles;

  final http.Client _client;
  final Future<String?> Function() _token;
  final String _endpoint;

  /// [endpoint] and [token] exist so the whole request can be driven in a
  /// test: a compile-time constant cannot be set from one, and the real
  /// token comes from Firebase.
  ScanService({
    http.Client? client,
    Future<String?> Function()? token,
    String? endpoint,
  })  : _client = client ?? http.Client(),
        _token = token ?? _firebaseToken,
        _endpoint = endpoint ?? ScanService.endpoint;

  static Future<String?> _firebaseToken() =>
      FirebaseAuth.instance.currentUser?.getIdToken() ?? Future.value(null);

  Future<ScanResult> scan({
    required List<ScanImage> images,
    required AppCurrency currency,
    DateTime? today,
  }) async {
    if (_endpoint.isEmpty) {
      throw const ScanException('Сканер не настроен');
    }
    if (images.isEmpty || images.length > maxImages) {
      throw const ScanException('Слишком много снимков за раз');
    }

    final token = await _token();
    if (token == null || token.isEmpty) {
      throw const ScanException(
          'Нет связи с аккаунтом, перезапустите приложение');
    }

    final now = today ?? DateTime.now();
    http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse(_endpoint),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'images': images.map((i) => i.toJson()).toList(),
              'currency': currency.storageKey,
              'today': _isoDate(now),
            }),
          )
          .timeout(const Duration(seconds: 60));
    } catch (_) {
      throw const ScanException(
          'Не удалось связаться со сканером. Проверьте интернет');
    }

    Map<String, dynamic>? body;
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, dynamic>) body = decoded;
    } catch (_) {
      body = null;
    }

    if (response.statusCode != 200) {
      final message = body?['error'];
      throw ScanException(
        message is String && message.isNotEmpty
            ? message
            : 'Сканер ответил ошибкой (${response.statusCode})',
      );
    }
    if (body == null) {
      throw const ScanException('Сканер вернул непонятный ответ');
    }

    return ScanResult.fromJson(body, fallbackCurrency: currency);
  }

  void dispose() => _client.close();
}

String _isoDate(DateTime value) => '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

/// How wide a snapshot is sent.
///
/// This is the number that decides whether a statement can be read at all.
/// A model scales an image down to roughly 1.1 megapixels before looking
/// at it, so a tall screenshot sent whole loses most of its width: a
/// 1080x2400 phone screenshot fitted into that budget comes out about 700
/// pixels wide, and a four-column table of small type stops being legible.
/// Cutting the same screenshot into squarish tiles keeps every pixel of
/// width instead.
const int kScanTileWidth = 1100;

/// The pixel budget one tile is allowed, just under what a model resizes
/// at. Tile height follows from it: 1100 wide gives roughly 1000 tall.
const int kScanTilePixels = 1100 * 1000;

/// A tall snapshot is cut with this much of each tile repeated on the next
/// one, so a table row is never sliced in half and lost. Rows that appear
/// twice are the model's to reconcile -- the prompt says so.
const double kScanTileOverlap = 0.12;

/// The ceiling on tiles per pass, across every snapshot picked. Twelve
/// tiles is around four full phone screenshots, which is more statement
/// than anyone scans at once.
const int kScanMaxTiles = 12;

/// Cuts a picked snapshot into what should actually be uploaded.
///
/// Pure and synchronous so it can be tested without a picker, and small
/// enough to hand to [compute]: decoding and re-encoding a screenshot
/// takes long enough to drop frames on the thread that draws.
List<ScanImage> prepareScanImages(({Uint8List bytes, int maxTiles}) input) {
  final raw = input.bytes;
  final decoded = img.decodeImage(raw);
  if (decoded == null) {
    // Unreadable here does not mean unreadable by the model -- an exotic
    // but valid JPEG, say -- so send it on rather than refusing.
    return [ScanImage(bytes: raw, mime: _sniffMime(raw) ?? 'image/jpeg')];
  }

  final image = decoded.width > kScanTileWidth
      ? img.copyResize(
          decoded,
          width: kScanTileWidth,
          interpolation: img.Interpolation.average,
        )
      : decoded;

  final tileHeight = kScanTilePixels ~/ image.width;
  if (image.height <= tileHeight) {
    return [_encode(image)];
  }

  final overlap = (tileHeight * kScanTileOverlap).round();
  final step = tileHeight - overlap;
  final tiles = <ScanImage>[];
  for (var top = 0;
      top < image.height && tiles.length < input.maxTiles;
      top += step) {
    final height = math.min(tileHeight, image.height - top);
    // The last step can leave a sliver the previous tile's overlap already
    // covered in full; another tile of it would only cost tokens.
    if (tiles.isNotEmpty && height <= overlap) break;
    tiles.add(_encode(
      img.copyCrop(image, x: 0, y: top, width: image.width, height: height),
    ));
  }
  return tiles;
}

/// Width the kept receipt photo is shrunk to. Enough to read the lines of a
/// receipt when it is opened; the model never sees this copy.
const int kReceiptWidth = 800;

/// A Firestore document holds one megabyte, and the photo is stored as
/// base64, which adds a third. Past this the photo is not kept at all rather
/// than making the record it belongs to fail to save.
const int kReceiptMaxBytes = 600 * 1024;

/// A small JPEG of the snapshot, kept beside the records it produced so the
/// original can be looked at later. Null when it cannot be decoded or is
/// still too large after shrinking.
Uint8List? prepareReceiptPhoto(Uint8List bytes) {
  // The decoder throws rather than returning null on some truncated input,
  // and a receipt photo is optional, so any failure just means no photo.
  final img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } catch (_) {
    return null;
  }
  if (decoded == null) return null;
  // A very long screenshot can still be too big at the usual size, so
  // step down until it fits rather than keep no photo at all.
  for (final (width, quality) in const [
    (kReceiptWidth, 70),
    (640, 60),
    (480, 50),
  ]) {
    final image = decoded.width > width
        ? img.copyResize(
            decoded,
            width: width,
            interpolation: img.Interpolation.average,
          )
        : decoded;
    final jpeg = Uint8List.fromList(img.encodeJpg(image, quality: quality));
    if (jpeg.length <= kReceiptMaxBytes) return jpeg;
  }
  return null;
}

ScanImage _encode(img.Image image) => ScanImage(
      // 85 rather than the usual 80: the subject is small type, and the
      // artefacts of a harder compression land exactly on the digits.
      bytes: Uint8List.fromList(img.encodeJpg(image, quality: 85)),
      mime: 'image/jpeg',
    );

String? _sniffMime(Uint8List bytes) {
  if (bytes.length >= 3 &&
      bytes[0] == 0xFF &&
      bytes[1] == 0xD8 &&
      bytes[2] == 0xFF) {
    return 'image/jpeg';
  }
  if (bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47) {
    return 'image/png';
  }
  if (bytes.length >= 12 &&
      bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x46 &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x45 &&
      bytes[10] == 0x42 &&
      bytes[11] == 0x50) {
    return 'image/webp';
  }
  return null;
}
