import 'package:flutter/material.dart';

class WakulimaColors {
  // Primary — deep dairy green
  static const Color primary900 = Color(0xFF0A3D1F);
  static const Color primary800 = Color(0xFF0D5C2E);
  static const Color primary700 = Color(0xFF14742A); // main brand
  static const Color primary600 = Color(0xFF1A8F33);
  static const Color primary500 = Color(0xFF22A83C);
  static const Color primary400 = Color(0xFF4DC469);
  static const Color primary200 = Color(0xFFA8E6B8);
  static const Color primary100 = Color(0xFFD4F5DF);
  static const Color primary50  = Color(0xFFEAF9EF);

  // Accent — warm gold (milk / sunshine)
  static const Color gold700 = Color(0xFF9A6B00);
  static const Color gold500 = Color(0xFFC8930A);
  static const Color gold400 = Color(0xFFE8AB20);
  static const Color gold100 = Color(0xFFFEF3CD);
  static const Color gold50  = Color(0xFFFFFAE6);

  // Semantic
  static const Color success  = Color(0xFF1A8F33);
  static const Color warning  = Color(0xFFC8930A);
  static const Color error    = Color(0xFFD32F2F);
  static const Color info     = Color(0xFF1565C0);

  // Neutral
  static const Color ink      = Color(0xFF0E1A12);
  static const Color inkMid   = Color(0xFF2C3D31);
  static const Color inkSoft  = Color(0xFF5A6E5F);
  static const Color inkMuted = Color(0xFF8FA498);
  static const Color border   = Color(0xFFE0EBE3);
  static const Color surface  = Color(0xFFF7FBF8);
  static const Color cream    = Color(0xFFFAF8F3);
  static const Color white    = Color(0xFFFFFFFF);

  // Module colors
  static const Color sales          = Color(0xFF1A8F33); // green
  static const Color inventory      = Color(0xFFC8930A); // gold
  static const Color dairy          = Color(0xFF1565C0); // blue
  static const Color collectionLite = Color(0xFF0097A7); // teal
  static const Color dispatch       = Color(0xFF7B1FA2); // purple
  static const Color driver         = Color(0xFF0288D1); // light blue
  static const Color merchandising  = Color(0xFF388E3C); // green2
  static const Color manufacturing  = Color(0xFF546E7A); // blue-grey
  static const Color purchases      = Color(0xFF1A237E); // indigo
  static const Color location       = Color(0xFF9E9E9E); // grey (locked)
  static const Color dairyAdmin     = Color(0xFF1565C0); // blue
  static const Color salesMgmt      = Color(0xFF9E9E9E); // grey (locked)
  static const Color analytics      = Color(0xFF00695C); // teal dark
  static const Color quality        = Color(0xFF2E7D32); // dark green
  static const Color esp            = Color(0xFF8D6E63); // brown (agrovet/services)
}

class WakulimaTheme {
  static ThemeData get light => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: WakulimaColors.primary700,
      brightness: Brightness.light,
      primary: WakulimaColors.primary700,
      onPrimary: WakulimaColors.white,
      secondary: WakulimaColors.gold500,
      surface: WakulimaColors.white,
      background: WakulimaColors.cream,
      error: WakulimaColors.error,
    ),
    scaffoldBackgroundColor: WakulimaColors.cream,
    fontFamily: 'Poppins',

    appBarTheme: const AppBarTheme(
      backgroundColor: WakulimaColors.white,
      foregroundColor: WakulimaColors.ink,
      elevation: 0,
      scrolledUnderElevation: 1,
      shadowColor: Color(0x14000000),
      titleTextStyle: TextStyle(
        fontFamily: 'Poppins',
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: WakulimaColors.ink,
        letterSpacing: -0.2,
      ),
    ),

    cardTheme: CardThemeData(
      color: WakulimaColors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: WakulimaColors.border, width: 1),
      ),
      margin: EdgeInsets.zero,
    ),
//  cardTheme: CardTheme(
//       color: WakulimaColors.white,
//       elevation: 0,
//       shape: RoundedRectangleBorder(
//         borderRadius: BorderRadius.circular(16),
//         side: const BorderSide(color: WakulimaColors.border, width: 1),
//       ),
//       margin: EdgeInsets.zero,
//     )
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: WakulimaColors.primary700,
        foregroundColor: WakulimaColors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(
          fontFamily: 'Poppins',
          fontSize: 15,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: WakulimaColors.primary700,
        side: const BorderSide(color: WakulimaColors.primary700, width: 1.5),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(
          fontFamily: 'Poppins',
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: WakulimaColors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: WakulimaColors.border, width: 1.5),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: WakulimaColors.border, width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: WakulimaColors.primary700, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: WakulimaColors.error, width: 1.5),
      ),
      labelStyle: const TextStyle(
        fontFamily: 'Poppins',
        fontSize: 14,
        color: WakulimaColors.inkSoft,
      ),
      hintStyle: const TextStyle(
        fontFamily: 'Poppins',
        fontSize: 14,
        color: WakulimaColors.inkMuted,
      ),
    ),

    textTheme: const TextTheme(
      displayLarge:  TextStyle(fontFamily: 'Poppins', fontSize: 32, fontWeight: FontWeight.w700, color: WakulimaColors.ink, letterSpacing: -1),
      displayMedium: TextStyle(fontFamily: 'Poppins', fontSize: 26, fontWeight: FontWeight.w700, color: WakulimaColors.ink, letterSpacing: -0.5),
      displaySmall:  TextStyle(fontFamily: 'Poppins', fontSize: 22, fontWeight: FontWeight.w600, color: WakulimaColors.ink),
      headlineMedium:TextStyle(fontFamily: 'Poppins', fontSize: 18, fontWeight: FontWeight.w600, color: WakulimaColors.ink),
      headlineSmall: TextStyle(fontFamily: 'Poppins', fontSize: 16, fontWeight: FontWeight.w600, color: WakulimaColors.ink),
      titleLarge:    TextStyle(fontFamily: 'Poppins', fontSize: 15, fontWeight: FontWeight.w600, color: WakulimaColors.ink),
      titleMedium:   TextStyle(fontFamily: 'Poppins', fontSize: 14, fontWeight: FontWeight.w500, color: WakulimaColors.ink),
      titleSmall:    TextStyle(fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w500, color: WakulimaColors.inkMid),
      bodyLarge:     TextStyle(fontFamily: 'Poppins', fontSize: 15, fontWeight: FontWeight.w400, color: WakulimaColors.ink),
      bodyMedium:    TextStyle(fontFamily: 'Poppins', fontSize: 14, fontWeight: FontWeight.w400, color: WakulimaColors.inkMid),
      bodySmall:     TextStyle(fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w400, color: WakulimaColors.inkSoft),
      labelLarge:    TextStyle(fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w600, color: WakulimaColors.ink, letterSpacing: 0.2),
      labelSmall:    TextStyle(fontFamily: 'Poppins', fontSize: 10, fontWeight: FontWeight.w600, color: WakulimaColors.inkSoft, letterSpacing: 0.8),
    ),

    dividerTheme: const DividerThemeData(
      color: WakulimaColors.border,
      thickness: 1,
      space: 0,
    ),

    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: WakulimaColors.white,
      selectedItemColor: WakulimaColors.primary700,
      unselectedItemColor: WakulimaColors.inkMuted,
      elevation: 0,
      type: BottomNavigationBarType.fixed,
    ),
  );
}
