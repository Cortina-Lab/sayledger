import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// SayLedger look: ledger-paper cream + maroon (the red cloth of a shop's
// account book), one simple sans font. Dark mode keeps the maroon on near-black.

@immutable
class Ledger extends ThemeExtension<Ledger> {
  const Ledger({
    required this.paper,
    required this.card,
    required this.line,
    required this.ink,
    required this.inkSoft,
    required this.inkFaint,
    required this.accent,
    required this.accentSoft,
    required this.owes,
    required this.advance,
    required this.doubt,
    required this.doubtSoft,
  });

  final Color paper, card, line, ink, inkSoft, inkFaint, accent, accentSoft, owes, advance, doubt, doubtSoft;

  static const light = Ledger(
    paper: Color(0xFFF3EFE7),
    card: Color(0xFFFFFCF7),
    line: Color(0xFFDDD5C7),
    ink: Color(0xFF1C1915),
    inkSoft: Color(0xFF5B544A),
    inkFaint: Color(0xFF8C8478),
    accent: Color(0xFF7B1E2C),
    accentSoft: Color(0xFFF3E3E3),
    owes: Color(0xFF9E2A2B),
    advance: Color(0xFF2E7A4F),
    doubt: Color(0xFFB45309),
    doubtSoft: Color(0xFFFFF6E5),
  );

  static const dark = Ledger(
    paper: Color(0xFF0D0C0C),
    card: Color(0xFF181616),
    line: Color(0xFF2F2626),
    ink: Color(0xFFF4F1EC),
    inkSoft: Color(0xFFBDB5AA),
    inkFaint: Color(0xFF8E867C),
    accent: Color(0xFFC0485A),
    accentSoft: Color(0xFF2A1519),
    owes: Color(0xFFFF7A7F),
    advance: Color(0xFF5FD08F),
    doubt: Color(0xFFF5B54A),
    doubtSoft: Color(0xFF2B2010),
  );

  @override
  Ledger copyWith() => this;

  @override
  Ledger lerp(ThemeExtension<Ledger>? other, double t) => t < 0.5 ? this : (other as Ledger? ?? this);
}

extension LedgerX on BuildContext {
  Ledger get c => Theme.of(this).extension<Ledger>()!;
}

/// Headings and big amounts: same simple sans as the body, just bolder.
TextStyle display(BuildContext context, double size, {Color? color, FontWeight weight = FontWeight.w700}) =>
    GoogleFonts.sourceSans3(fontSize: size, fontWeight: weight, color: color ?? context.c.ink, height: 1.1, letterSpacing: -0.3);

ThemeData buildTheme(Brightness b) {
  final l = b == Brightness.light ? Ledger.light : Ledger.dark;
  final base = ThemeData(brightness: b, useMaterial3: true);
  final text = GoogleFonts.sourceSans3TextTheme(base.textTheme).apply(bodyColor: l.ink, displayColor: l.ink);
  final scheme = ColorScheme.fromSeed(
    seedColor: l.accent,
    brightness: b,
    primary: l.accent,
    onPrimary: Colors.white,
    surface: l.paper,
    onSurface: l.ink,
  );
  OutlineInputBorder border(Color c, [double w = 1]) =>
      OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: c, width: w));

  return base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: l.paper,
    textTheme: text,
    extensions: [l],
    appBarTheme: AppBarTheme(
      backgroundColor: l.paper,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      foregroundColor: l.ink,
      titleTextStyle: GoogleFonts.sourceSans3(fontSize: 23, fontWeight: FontWeight.w700, color: l.ink),
    ),
    cardTheme: CardThemeData(
      color: l.card,
      elevation: 0,
      margin: EdgeInsets.zero,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22), side: BorderSide(color: l.line)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: l.accent,
        foregroundColor: Colors.white,
        minimumSize: const Size(64, 54),
        shape: const StadiumBorder(),
        textStyle: GoogleFonts.sourceSans3(fontSize: 17, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: l.ink,
        backgroundColor: l.card,
        minimumSize: const Size(64, 52),
        shape: const StadiumBorder(),
        side: BorderSide(color: l.line),
        textStyle: GoogleFonts.sourceSans3(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: l.accent, textStyle: GoogleFonts.sourceSans3(fontSize: 16, fontWeight: FontWeight.w700)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: l.card,
      labelStyle: TextStyle(color: l.inkFaint),
      border: border(l.line),
      enabledBorder: border(l.line),
      focusedBorder: border(l.accent, 1.6),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: l.ink,
      contentTextStyle: GoogleFonts.sourceSans3(color: l.paper, fontSize: 15),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? l.accent : l.card),
        foregroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : l.ink),
        side: WidgetStatePropertyAll(BorderSide(color: l.line)),
        minimumSize: const WidgetStatePropertyAll(Size(64, 50)),
        textStyle: WidgetStatePropertyAll(GoogleFonts.sourceSans3(fontSize: 16, fontWeight: FontWeight.w700)),
      ),
    ),
    dividerColor: l.line,
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? l.accent : Colors.transparent),
    ),
  );
}
