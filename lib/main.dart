import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart'; 
import 'login_screen.dart';
import 'home_screen.dart';

// Глобальный контроллер темы для ручного переключения
final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.light);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  final prefs = await SharedPreferences.getInstance();
  final phone = prefs.getString('phone');
  
  // Считываем сохранённую тему (по умолчанию - светлая)
  final isDark = prefs.getBool('is_dark_theme') ?? false;
  themeNotifier.value = isDark ? ThemeMode.dark : ThemeMode.light;

  Widget initialScreen = (phone != null && phone.isNotEmpty) ? const HomeScreen() : const LoginScreen();

  runApp(MyApp(initialScreen: initialScreen));
}

class MyApp extends StatelessWidget {
  final Widget initialScreen;

  const MyApp({super.key, required this.initialScreen});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (_, currentMode, __) {
        return MaterialApp(
          title: 'M-Service',
          
          // --- ЧИСТАЯ СВЕТЛАЯ ТЕМА ---
          theme: ThemeData(
            brightness: Brightness.light,
            primarySwatch: Colors.blueGrey,
            scaffoldBackgroundColor: const Color(0xFFF8FAFC),
            cardColor: Colors.white,
            appBarTheme: AppBarTheme(
              backgroundColor: Colors.blueGrey[900],
              foregroundColor: Colors.white,
              elevation: 0,
            ),
          ),

          // --- СТРОГАЯ ТЁМНАЯ ТЕМА (ДЛЯ БУДУЩЕГО ТУМБЛЕРА) ---
          darkTheme: ThemeData(
            brightness: Brightness.dark,
            primarySwatch: Colors.blueGrey,
            scaffoldBackgroundColor: const Color(0xFF0F172A),
            cardColor: const Color(0xFF1E293B),
            appBarTheme: const AppBarTheme(
              backgroundColor: Color(0xFF0F172A),
              foregroundColor: Colors.white,
              elevation: 0,
            ),
          ),

          // Строго завязано на ручной выбор пользователя!
          themeMode: currentMode, 
          
          home: initialScreen,
          debugShowCheckedModeBanner: false,
        );
      },
    );
  }
}
