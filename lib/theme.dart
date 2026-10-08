import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The palette is built as two matched rooms rather than one set of colours
/// with a switch: "Ivory" (light) is warm paper, "Obsidian" (dark) is deep
/// warm black. Both share the same champagne accent, which is what carries
/// the premium feel -- a metallic tone reads as expensive where a saturated
/// brand colour reads as an app store icon.

/// Rich, warm near-black -- the ink everything is written in on Ivory, and
/// the material the hero card is cut from in both themes.
const Color kAccentColor = Color(0xFF1B1813);

/// Champagne. Deep enough to stay legible as text on paper, and the same
/// family as [kChampagne], which is the version used on dark surfaces.
const Color kGoldDeep = Color(0xFF9A7B44);
const Color kChampagne = Color(0xFFC8A86B);

/// Money colours, deliberately desaturated: a jewel-toned emerald and a
/// muted terracotta rather than traffic-light green and red.
const Color kIncomeColor = Color(0xFF44705B);
const Color kExpenseColor = Color(0xFFA4534A);

/// The one loud colour in the palette, kept for exactly one job: a budget
/// that has been blown. Everywhere else spending is the muted terracotta.
const Color kOverBudgetColor = Color(0xFFE23B2E);
const Color kOverBudgetColorDark = Color(0xFFFF5247);

Color overBudgetColor(BuildContext context) =>
    _isDark(context) ? kOverBudgetColorDark : kOverBudgetColor;

/// Their dark-theme counterparts -- the same hues lifted, because a deep
/// jewel tone goes muddy against near-black.
const Color kIncomeColorDark = Color(0xFF6FA083);
const Color kExpenseColorDark = Color(0xFFC07D6C);

/// The tone the background texture is drawn in — always at a very low
/// opacity. It should read as the grain of the paper, never as content.
const Color kPatternColor = kChampagne;

const _ivoryTop = Color(0xFFF6F2EA);
const _ivoryBottom = Color(0xFFEDE6DA);
const _obsidianTop = Color(0xFF141318);
const _obsidianBottom = Color(0xFF0C0C0F);

bool _isDark(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark;

/// [kAccentColor] is a near-black ink tone: right on Ivory, invisible on
/// Obsidian. Anything that paints the accent *on* the background — an icon,
/// a tint, a hairline — has to flip with the theme so it reads on both.
Color accentForeground(BuildContext context) =>
    _isDark(context) ? const Color(0xFFF2EFE9) : kAccentColor;

/// The champagne at the weight that survives the current background: deeper
/// on paper, lighter on black.
Color goldFor(BuildContext context) =>
    _isDark(context) ? kChampagne : kGoldDeep;

Color incomeColor(BuildContext context) =>
    _isDark(context) ? kIncomeColorDark : kIncomeColor;

Color expenseColor(BuildContext context) =>
    _isDark(context) ? kExpenseColorDark : kExpenseColor;

/// The hairline that draws a surface's edge. Everything is separated by one
/// of these rather than by a heavy border or a filled divider.
Color _hairlineFor(bool isDark) => (isDark ? Colors.white : kAccentColor)
    .withValues(alpha: isDark ? 0.10 : 0.09);

Color hairlineColor(BuildContext context) => _hairlineFor(_isDark(context));

/// The page itself is a soft vertical wash rather than one flat fill —
/// the cheapest way to stop a screen looking like a default template.
LinearGradient pageGradient(BuildContext context) {
  final isDark = _isDark(context);
  return LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: isDark
        ? const [_obsidianTop, _obsidianBottom]
        : const [_ivoryTop, _ivoryBottom],
  );
}

/// The hero card is cut from whichever material the room is made of --
/// pale on Ivory, obsidian on Obsidian -- and it is the most transparent
/// surface in the app: a thin sheet of glass over the page's own light and
/// grain, held together by its champagne rim rather than by its fill.
LinearGradient heroGradientFor(BuildContext context) {
  if (_isDark(context)) {
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        const Color(0xFF2A2831).withValues(alpha: 0.40),
        const Color(0xFF171620).withValues(alpha: 0.48),
        const Color(0xFF101014).withValues(alpha: 0.48),
      ],
      stops: const [0.0, 0.55, 1.0],
    );
  }
  return LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Colors.white.withValues(alpha: 0.52),
      Colors.white.withValues(alpha: 0.40),
      const Color(0xFFF3ECDF).withValues(alpha: 0.40),
    ],
    stops: const [0.0, 0.55, 1.0],
  );
}

/// What is written on that card: ink on the pale version, warm white on the
/// dark one.
Color heroForeground(BuildContext context) =>
    _isDark(context) ? const Color(0xFFF4F1EA) : kAccentColor;

/// The body of a pane of glass: one even translucent fill. It used to be a
/// gradient, which on a list of rows read as each row being lit from its own
/// corner -- busy, and the thing that made the list look tilted.
///
/// On Obsidian the fill is a dark tone rather than a wash of white: a few
/// percent of white over near-black is barely a surface at all, and a
/// column of rows made of it read as too thin to hold anything.
Color glassFill(BuildContext context) => _isDark(context)
    ? const Color(0xFF1D1C23).withValues(alpha: 0.86)
    : Colors.white.withValues(alpha: 0.58);

/// The edge around a pane: one even hairline. It used to be a gradient rim,
/// bright in one corner and dark in the other -- which is what still read as
/// a gradient on a list of rows even after their fill was flattened.
Color glassEdge(BuildContext context) => _isDark(context)
    ? Colors.white.withValues(alpha: 0.13)
    : Colors.white.withValues(alpha: 0.85);

/// A sheet is solid. It was glass for a while and read as muddy: a sheet
/// covers the screen precisely so you can stop looking at the screen, and
/// the form on it has small text and small controls that want a settled
/// background rather than a moving one.
Color sheetSurface(BuildContext context) =>
    _isDark(context) ? const Color(0xFF1B1A21) : const Color(0xFFFBF8F2);

/// The app bar floats over the scrolling list, so it is the one surface
/// that genuinely needs frosting rather than translucency alone.
Color appBarGlassTint(BuildContext context) => _isDark(context)
    ? const Color(0xFF141318).withValues(alpha: 0.58)
    : const Color(0xFFF6F2EA).withValues(alpha: 0.62);

/// Small, letterspaced, uppercase — the label style that does most of the
/// work in making a layout feel considered rather than default.
/// Something waiting on someone else: a transfer the payer marked as sent
/// that the recipient has not confirmed yet.
const Color kPendingColor = Color(0xFFE2B33C);

TextStyle microLabel(BuildContext context,
        {Color? color, double size = 10.5}) =>
    TextStyle(
      fontSize: size,
      fontWeight: FontWeight.w600,
      letterSpacing: 1.3,
      color: color ?? accentForeground(context).withValues(alpha: 0.58),
    );

/// The wordmark, and nothing else.
///
/// Set in the same sans as the rest of the interface, only heavier and
/// spaced out, so the name reads as a mark rather than body text. Semibold
/// keeps it from thinning at display sizes.
TextStyle wordmark(BuildContext context,
        {required double size, Color? color}) =>
    TextStyle(
      fontFamily: 'Onest',
      fontSize: size,
      fontWeight: FontWeight.w600,
      // Wide enough to space a short all-caps word, narrow enough that the
      // serifs still group into a single shape.
      letterSpacing: size * 0.12,
      color: color ?? goldFor(context),
    );

/// Figures are always tabular: money that shifts sideways as the digits
/// change is the detail that gives a finance app away.
const List<FontFeature> kTabularFigures = [FontFeature.tabularFigures()];

TextStyle moneyStyle({
  required double size,
  required Color color,
  FontWeight weight = FontWeight.w500,
  double letterSpacing = -0.2,
}) =>
    TextStyle(
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: letterSpacing,
      fontFeatures: kTabularFigures,
    );

/// How the phone paints its own status and navigation bars for a theme.
///
/// Both stay transparent: the page already runs edge to edge, so the room's
/// own background shows through them and they are the theme's colour by
/// construction rather than by a second copy of it. What does have to be
/// said out loud is the icon brightness -- left alone, Flutter guesses it
/// from the app bar's background colour, and a transparent bar reads as
/// dark, which put white status icons on Ivory's paper.
SystemUiOverlayStyle systemOverlayStyleFor(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final icons = isDark ? Brightness.light : Brightness.dark;
  return SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    // Android reads the icon brightness; iOS reads the background's.
    statusBarIconBrightness: icons,
    statusBarBrightness: brightness,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: icons,
    systemNavigationBarDividerColor: Colors.transparent,
  );
}

ThemeData buildAppTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final ink = isDark ? const Color(0xFFF2EFE9) : kAccentColor;
  final hairline = _hairlineFor(isDark);
  final colorScheme = ColorScheme.fromSeed(
    seedColor: kGoldDeep,
    brightness: brightness,
    primary: isDark ? kChampagne : kGoldDeep,
    surface: isDark ? const Color(0xFF16151B) : const Color(0xFFFCFAF6),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: colorScheme,
    fontFamily: 'Onest',
    // Matches the top of the page gradient the body paints, so the strip
    // behind the (transparent) app bar continues it seamlessly.
    scaffoldBackgroundColor: isDark ? _obsidianTop : _ivoryTop,
    appBarTheme: AppBarTheme(
      systemOverlayStyle: systemOverlayStyleFor(brightness),
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      foregroundColor: ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: 'Onest',
        color: ink,
        fontSize: 19,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
      ),
      iconTheme: IconThemeData(color: ink.withValues(alpha: 0.78), size: 21),
      actionsIconTheme:
          IconThemeData(color: ink.withValues(alpha: 0.78), size: 21),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: isDark ? kChampagne : kAccentColor,
      foregroundColor: isDark ? kAccentColor : const Color(0xFFF6F2EA),
      elevation: 3,
      focusElevation: 3,
      hoverElevation: 4,
      highlightElevation: 6,
      shape: const CircleBorder(),
    ),
    // Icons sit tighter than Material's default 48pt tap slabs: five of them
    // at full width left the app bar title truncated on a phone.
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        padding: const EdgeInsets.all(5),
        minimumSize: const Size(34, 34),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      // Already translucent: rows are glass over the page wash, and the
      // grain behind them should stay faintly visible through the stack.
      color: (isDark ? const Color(0xFF1F1E26) : Colors.white)
          .withValues(alpha: isDark ? 0.55 : 0.72),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: hairline, width: 1),
      ),
      margin: EdgeInsets.zero,
    ),
    textTheme: Typography.material2021(platform: TargetPlatform.android)
        .black
        .apply(fontFamily: 'Onest', bodyColor: ink, displayColor: ink),
    dividerTheme: DividerThemeData(color: hairline, thickness: 1, space: 1),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: (isDark ? Colors.white : kAccentColor)
          .withValues(alpha: isDark ? 0.05 : 0.035),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: hairline, width: 1),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: hairline, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color: (isDark ? kChampagne : kGoldDeep).withValues(alpha: 0.55),
          width: 1.2,
        ),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      hintStyle: TextStyle(color: ink.withValues(alpha: 0.42)),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        // Champagne on black, obsidian on paper: in both cases the primary
        // action is the one solid, confident block on the screen.
        backgroundColor: isDark ? kChampagne : kAccentColor,
        foregroundColor: isDark ? kAccentColor : const Color(0xFFF6F2EA),
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 17),
        textStyle: const TextStyle(
          fontFamily: 'Onest',
          fontSize: 15,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.1,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: ink.withValues(alpha: 0.7),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        textStyle: const TextStyle(
          fontFamily: 'Onest',
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor:
          isDark ? const Color(0xFF16151B) : const Color(0xFFFBF8F2),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor:
          isDark ? const Color(0xFF1B1A21) : const Color(0xFFFBF8F2),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: hairline, width: 1),
      ),
      titleTextStyle: TextStyle(
        fontFamily: 'Onest',
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: ink,
      ),
      contentTextStyle: TextStyle(
        fontFamily: 'Onest',
        fontSize: 14,
        color: ink.withValues(alpha: 0.7),
        height: 1.4,
      ),
    ),
    datePickerTheme: DatePickerThemeData(
      backgroundColor:
          isDark ? const Color(0xFF1B1A21) : const Color(0xFFFBF8F2),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: hairline),
      ),
      headerBackgroundColor: isDark ? const Color(0xFF24232B) : kAccentColor,
      headerForegroundColor: const Color(0xFFF6F2EA),
      headerHeadlineStyle: const TextStyle(
        fontFamily: 'Onest',
        fontSize: 27,
        fontWeight: FontWeight.w300,
        letterSpacing: -0.5,
      ),
      headerHelpStyle: const TextStyle(
        fontFamily: 'Onest',
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.3,
      ),
      weekdayStyle: TextStyle(
        fontFamily: 'Onest',
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.6,
        color: ink.withValues(alpha: 0.6),
      ),
      dayStyle: const TextStyle(
        fontFamily: 'Onest',
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
      dayForegroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return isDark ? kAccentColor : const Color(0xFFF6F2EA);
        }
        if (states.contains(WidgetState.disabled)) {
          return ink.withValues(alpha: 0.28);
        }
        return ink;
      }),
      dayBackgroundColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected)
              ? (isDark ? kChampagne : kGoldDeep)
              : null),
      todayForegroundColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected)
              ? (isDark ? kAccentColor : const Color(0xFFF6F2EA))
              : (isDark ? kChampagne : kGoldDeep)),
      todayBorder: BorderSide(color: isDark ? kChampagne : kGoldDeep),
      yearStyle: const TextStyle(
        fontFamily: 'Onest',
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
      yearForegroundColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected)
              ? (isDark ? kAccentColor : const Color(0xFFF6F2EA))
              : ink),
      yearBackgroundColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected)
              ? (isDark ? kChampagne : kGoldDeep)
              : null),
      dividerColor: hairline,
      cancelButtonStyle: TextButton.styleFrom(
        foregroundColor: ink.withValues(alpha: 0.7),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        textStyle: const TextStyle(
          fontFamily: 'Onest',
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
      confirmButtonStyle: TextButton.styleFrom(
        foregroundColor: isDark ? kChampagne : kGoldDeep,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        textStyle: const TextStyle(
          fontFamily: 'Onest',
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: isDark ? const Color(0xFF26242D) : kAccentColor,
      contentTextStyle: const TextStyle(
        fontFamily: 'Onest',
        color: Color(0xFFF2EFE9),
        fontSize: 14,
      ),
      // Pinned to the very bottom rather than floating: a floating bar gets
      // lifted above the action buttons and lands in the middle of the
      // list, on top of the rows it is talking about.
      behavior: SnackBarBehavior.fixed,
    ),
  );
}
