import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart'; 
import 'login_screen.dart';
import 'home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Запускаем Firebase ПРАВИЛЬНО
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Проверяем память телефона на наличие сохраненного входа
  final prefs = await SharedPreferences.getInstance();
  final phone = prefs.getString('phone');

  // Если номер есть — кидаем на главный экран, если нет — на вход
  Widget initialScreen = (phone != null && phone.isNotEmpty) ? const HomeScreen() : const LoginScreen();

  runApp(MyApp(initialScreen: initialScreen));
}

class MyApp extends StatelessWidget {
  final Widget initialScreen;

  const MyApp({super.key, required this.initialScreen});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'M-Service',
      
      // --- СВЕТЛАЯ ТЕМА ---
      theme: ThemeData(
        brightness: Brightness.light,
        primarySwatch: Colors.blueGrey,
        scaffoldBackgroundColor: Colors.grey[50],
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.blueGrey[900],
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        cardColor: Colors.white,
      ),

      // --- ТЁМНАЯ ТЕМА ---
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.blueGrey,
        scaffoldBackgroundColor: const Color(0xFF121212), // Глубокий темный фон
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.grey[900],
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        cardColor: const Color(0xFF1E1E1E), // Цвет карточек в темной теме
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Color(0xFF1E1E1E),
          unselectedItemColor: Colors.grey,
        ),
      ),

      // Автоматическое переключение в зависимости от настроек телефона!
      themeMode: ThemeMode.system, 
      
      home: initialScreen,
      debugShowCheckedModeBanner: false,
    );
  }
}
