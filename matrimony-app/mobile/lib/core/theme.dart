import 'package:google_fonts/google_fonts.dart';
import 'package:material_ui/material_ui.dart';

/// Same palette as the web app: rani pink / maroon, marigold, warm ivory.
class C {
  static const brand50 = Color(0xFFFFF1F5);
  static const brand100 = Color(0xFFFFE1EA);
  static const brand200 = Color(0xFFFFC4D6);
  static const brand400 = Color(0xFFF45D8C);
  static const brand500 = Color(0xFFE2336B);
  static const brand600 = Color(0xFFC2185B);
  static const brand700 = Color(0xFF9D174D);
  static const brand800 = Color(0xFF831843);
  static const brand950 = Color(0xFF3B0A20);
  static const gold50 = Color(0xFFFFF9EB);
  static const gold100 = Color(0xFFFDEFC8);
  static const gold200 = Color(0xFFFBDC8C);
  static const gold300 = Color(0xFFF8C451);
  static const gold400 = Color(0xFFF5A623);
  static const gold500 = Color(0xFFE8890C);
  static const gold600 = Color(0xFFC86A07);
  static const ivory = Color(0xFFFFFAF6);
  static const sand = Color(0xFFF7EFE8);
  static const ink = Color(0xFF2B1A22);
  static const muted = Color(0xFF7B6870);
  static const line = Color(0xFFEFE3E7);
  static const green = Color(0xFF047857);
  static const greenBg = Color(0xFFECFDF5);
  static const amber = Color(0xFF92400E);
  static const amberBg = Color(0xFFFFFBEB);
  static const red = Color(0xFFB91C1C);
  static const redBg = Color(0xFFFEF2F2);
  static const teal = Color(0xFF0F766E);
  static const tealBg = Color(0xFFF0FDFA);
  static const violet = Color(0xFF6D28D9);
  static const violetBg = Color(0xFFF5F3FF);
  static const sky = Color(0xFF0369A1);
  static const skyBg = Color(0xFFF0F9FF);

  static const heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [brand950, brand800, brand600],
    stops: [0, .45, 1],
  );
  static const buttonGradient = LinearGradient(colors: [brand600, brand700]);
  static const goldGradient = LinearGradient(colors: [gold300, gold400]);
}

TextStyle display(double size, {Color color = C.ink, FontWeight weight = FontWeight.w600, FontStyle? style}) =>
    GoogleFonts.fraunces(fontSize: size, fontWeight: weight, color: color, fontStyle: style, height: 1.15);

ThemeData buildTheme() {
  final base = ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: C.brand600, surface: Colors.white));
  final text = GoogleFonts.plusJakartaSansTextTheme(base.textTheme).apply(bodyColor: C.ink, displayColor: C.ink);
  OutlineInputBorder border(Color c, [double w = 1]) =>
      OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: c, width: w));
  return base.copyWith(
    scaffoldBackgroundColor: C.ivory,
    textTheme: text,
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: C.ink,
      elevation: 0,
      scrolledUnderElevation: .5,
      centerTitle: false,
      titleTextStyle: display(20, color: C.brand800),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: border(C.line),
      enabledBorder: border(C.line),
      focusedBorder: border(C.brand500, 2),
      errorBorder: border(C.red),
      hintStyle: const TextStyle(color: Color(0x997B6870)),
    ),
    dividerColor: C.line,
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: C.ink,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.white,
      showDragHandle: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      indicatorColor: C.brand50,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: s.contains(WidgetState.selected) ? C.brand600 : C.muted),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(color: s.contains(WidgetState.selected) ? C.brand600 : C.muted),
      ),
    ),
  );
}
