import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:image_picker/image_picker.dart';

import '../data/scan_service.dart';
import '../models/currency.dart';
import '../models/expense.dart';
import '../models/scanned_transaction.dart';
import '../theme.dart';
import '../widgets/ai_scan_icon.dart';
import '../widgets/glass.dart';
import '../widgets/scan_review_sheet.dart';
import 'camera_capture_screen.dart';

/// Where the snapshot comes from.
enum ScanSource { camera, gallery }

/// Picks snapshots, reads them, and offers what was read for confirmation.
///
/// Written as one function rather than folded into the home screen: it is a
/// sequence of four modal steps with nothing to keep between them, and the
/// home screen is long enough already. The picker and the service are
/// injectable so the whole sequence can be driven in a test without a
/// camera or a network.
class ScanFlow {
  final ScanService service;

  /// Gets the snapshots: the camera, open straight away, with the gallery
  /// in its corner. An empty list means the user closed it.
  final Future<List<Uint8List>> Function(BuildContext context) capture;

  ScanFlow({ScanService? service, this.capture = captureReceipt})
      : service = service ?? ScanService();

  Future<void> run(
    BuildContext context, {
    required AppCurrency currency,
    required List<Expense> existing,
    required Future<void> Function(List<Expense> expenses, Uint8List photo)
        onAdd,
    required Future<void> Function(Uint8List photo) onManual,
    bool recognize = true,
  }) async {
    // Drops focus from whatever field was last typed into -- adding an
    // expense, naming the budget. On the web this also blurs the hidden
    // input element Flutter keeps around for IME support; left focused,
    // some Android browsers keep drawing that field's own spellcheck or
    // autocomplete underline at its last position, which can land right
    // on top of text this flow draws over it.
    FocusScope.of(context).unfocus();

    final List<Uint8List> raw;
    try {
      raw = await capture(context);
    } catch (_) {
      if (context.mounted) {
        _toast(context, 'Не удалось открыть снимок');
      }
      return;
    }
    if (raw.isEmpty || !context.mounted) return;

    // The photo kept with the records is the first snapshot only: a long
    // statement is still read in full, but it is saved as one picture.
    // Every record needs its receipt, so no photo means no record.
    final photo = await compute(prepareReceiptPhoto, raw.first);
    if (!context.mounted) return;
    if (photo == null) {
      _toast(context, 'Не удалось прочитать фото чека');
      return;
    }
    // With nothing to read the receipt, it is typed in by hand -- with the
    // photo still attached.
    if (!recognize) {
      await onManual(photo);
      return;
    }

    _showProgress(context);

    // Cutting and re-encoding takes long enough to drop frames, and the
    // spinner is already on screen -- so it happens off the thread that
    // draws. Each snapshot gets an equal share of the tile budget, so one
    // long screenshot cannot use it all and leave the next with none.
    final share = (kScanMaxTiles / raw.length).floor().clamp(1, kScanMaxTiles);
    final images = <ScanImage>[];
    for (final bytes in raw) {
      images.addAll(
        await compute(prepareScanImages, (bytes: bytes, maxTiles: share)),
      );
      if (images.length >= kScanMaxTiles) break;
    }
    if (images.length > kScanMaxTiles) {
      images.removeRange(kScanMaxTiles, images.length);
    }
    if (!context.mounted) return;
    ScanResult result;
    try {
      result = await service.scan(images: images, currency: currency);
    } on ScanException catch (error) {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        _toast(context, '${error.message}. Заполните вручную');
        await onManual(photo);
      }
      return;
    } catch (_) {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        _toast(context, 'Не удалось разобрать снимок. Заполните вручную');
        await onManual(photo);
      }
      return;
    }
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => GlassSheet(
        child: ScanReviewSheet(
          result: result,
          currency: currency,
          duplicates: findDuplicates(result.transactions, existing),
          onConfirm: (expenses) async {
            if (expenses.isEmpty) return;
            await onAdd(expenses, photo);
          },
        ),
      ),
    );
  }

  /// Closes the underlying HTTP client. Called when the screen holding
  /// the flow goes away: a client left open keeps its connections alive.
  void dispose() => service.dispose();

  void _showProgress(BuildContext context) {
    // Spoken once, rather than left as a standing label on the text below:
    // see the note on ExcludeSemantics inside ScanProgressContent for why.
    SemanticsService.sendAnnouncement(
      View.of(context),
      'Читаю снимок…',
      Directionality.of(context),
    );

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: ScanProgressContent()),
    );
  }

  void _toast(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..removeCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

/// The "Читаю снимок…" dialog's contents, pulled out to its own widget so
/// a test can pump it directly rather than driving the whole
/// pick-tile-upload sequence just to reach it.
@visibleForTesting
class ScanProgressContent extends StatelessWidget {
  const ScanProgressContent({super.key});

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      radius: 20,
      blur: 8,
      elevated: true,
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 34,
            height: 34,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // A ring with no track behind it is only ever the moving
                // arc, and an indeterminate spinner spends part of its
                // cycle with that arc a few degrees long -- which reads
                // not as a stalled circle but as a short stray gold dash.
                // The track keeps a full ring on screen at every frame, so
                // what moves around it is unmistakably a spinner.
                CircularProgressIndicator(
                  strokeWidth: 2.5,
                  backgroundColor: goldFor(context).withValues(alpha: 0.16),
                  color: goldFor(context),
                ),
                // The scanner's own mark at the centre, rather than an
                // empty ring: this dialog is the one moment the app asks
                // you to wait on the scanner specifically, and nothing
                // about a bare spinner says which of the app's several
                // loading states this one is.
                AiScanIcon(size: 15, color: goldFor(context)),
              ],
            ),
          ),
          const SizedBox(height: 18),
          // Flutter gives every piece of text its own touch-exploration
          // target on the web -- an absolutely positioned, hit-testable DOM
          // node sitting exactly over the glyphs it labels, there so a
          // screen reader's touch model can find it. On at least one
          // Android browser (Yandex, reported against this dialog),
          // something reads that node as a fillable field and draws its
          // own autocomplete-style underline across it, independent of
          // anything this app paints. Confirmed by rebuilding this exact
          // dialog as a standalone web build and forcing Flutter's
          // accessibility bridge open in a real browser: the node is a
          // transparent, absolutely positioned, hit-testable <span> sized
          // to the text, sitting under it -- and it disappears once this
          // widget is wrapped in ExcludeSemantics.
          //
          // SemanticsService.sendAnnouncement, called once when this
          // dialog opens (see ScanFlow._showProgress), still speaks the
          // message for a screen reader, through a channel with no
          // standing node to misread.
          ExcludeSemantics(
            child: Text(
              'Читаю снимок…',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: accentForeground(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The real capture: the camera screen, pushed full screen.
Future<List<Uint8List>> captureReceipt(BuildContext context) async {
  final shots = await Navigator.of(context).push<List<Uint8List>>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (context) => const CameraCaptureScreen(),
    ),
  );
  return shots ?? const [];
}

/// The real picker.
///
/// Width is capped and height deliberately is not. Capping both is what
/// ruins a statement: it fits a tall screenshot into a square and the
/// columns collapse to nothing. Narrowing to the tile width costs no
/// detail, and the platform's own resizer does it far faster than Dart.
Future<List<Uint8List>> pickScanImages(ScanSource source) async {
  final picker = ImagePicker();
  if (source == ScanSource.camera) {
    final file = await picker.pickImage(
      source: ImageSource.camera,
      maxWidth: kScanTileWidth.toDouble(),
      imageQuality: 90,
    );
    return file == null ? const [] : [await file.readAsBytes()];
  }
  final files = await picker.pickMultiImage(
    limit: kMaxScanSnapshots,
    maxWidth: kScanTileWidth.toDouble(),
    imageQuality: 90,
  );
  return Future.wait(
    files.take(kMaxScanSnapshots).map((f) => f.readAsBytes()),
  );
}

/// How many snapshots may be picked at once. Each becomes one to three
/// tiles, so this sits below the tile ceiling.
const int kMaxScanSnapshots = 4;
