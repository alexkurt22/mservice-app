import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart'; // <--- ВОТ ТА САМАЯ ПОТЕРЯННАЯ СТРОЧКА!
import 'login_screen.dart';
import 'home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Запускаем Firebase ПРАВИЛЬНО, с передачей твоих ключей!
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Проверяем память телефона на наличие сохраненного входа
  final prefs = await SharedPreferences.getInstance();
  final phone = prefs.getString('phone');

  // Если номер есть — кидаем на главный экран, если нет — на вход
  Widget initialScreen = (phone != null && phone.isNotEmpty) ? HomeScreen() : LoginScreen();

  runApp(MyApp(initialScreen: initialScreen));
}

class MyApp extends StatelessWidget {
  final Widget initialScreen;

  const MyApp({super.key, required this.initialScreen});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'M-Service',
      theme: ThemeData(
        primarySwatch: Colors.blueGrey,
      ),
      home: initialScreen,
      debugShowCheckedModeBanner: false,
    );
  }
}
