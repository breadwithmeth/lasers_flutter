import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'src/screens/login_screen.dart';
import 'src/screens/map_screen.dart';
import 'src/services/api_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final token = prefs.getString('auth_token');
  runApp(MyApp(initialToken: token));
}

class MyApp extends StatelessWidget {
  final String? initialToken;
  const MyApp({super.key, this.initialToken});

  @override
  Widget build(BuildContext context) {
    final api = ApiService(baseUrl: 'https://lasers.drawbridge.kz/api/v1');
    if (initialToken != null) {
      api.setToken(initialToken!);
    }

    final theme = ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF2F6BFF),
        brightness: Brightness.light,
      ),
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xFFF5F7FA),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: Color(0xFF1F2430),
        ),
      ),
      dividerColor: const Color(0xFFE2E6EC),
      iconTheme: const IconThemeData(color: Color(0xFF475569)),
      cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: Color(0xFFE5E9F0)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: const Color(0xFF2F6BFF),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          textStyle: const TextStyle(fontWeight: FontWeight.w500),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF2F6BFF),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE1E5EB)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE1E5EB)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF2F6BFF), width: 1.6),
        ),
        labelStyle: const TextStyle(color: Color(0xFF6B7280)),
        hintStyle: const TextStyle(color: Color(0xFF9CA3AF)),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: Colors.black87,
        contentTextStyle: TextStyle(color: Colors.white),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titleTextStyle: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: Color(0xFF1F2430),
        ),
      ),
      popupMenuTheme: const PopupMenuThemeData(
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.all(const Color(0xFFCBD5E1)),
        radius: const Radius.circular(20),
        thickness: WidgetStateProperty.all(8.0),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: Color(0xFF475569),
        textColor: Color(0xFF1F2430),
        dense: true,
      ),
    );

    return ApiProvider(
      api: api,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Lasers',
        theme: theme,
        home: initialToken == null
            ? LoginScreen(
                onLoggedIn: (token) async {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setString('auth_token', token);
                },
              )
            : const MapScreen(),
      ),
    );
  }
}

class ApiProvider extends InheritedWidget {
  final ApiService api;
  const ApiProvider({super.key, required this.api, required super.child});

  static ApiService of(BuildContext context) {
    final p = context.dependOnInheritedWidgetOfExactType<ApiProvider>();
    assert(p != null, 'ApiProvider not found in context');
    return p!.api;
  }

  @override
  bool updateShouldNotify(covariant ApiProvider oldWidget) =>
      api != oldWidget.api;
}

// Legacy MyHomePage removed.
