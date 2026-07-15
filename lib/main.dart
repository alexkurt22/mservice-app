import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'login_screen.dart';
import 'home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  // Проверяем, есть ли сохраненный номер телефона в памяти
  final prefs = await SharedPreferences.getInstance();
  final phone = prefs.getString('phone');

  // Если номер есть — сразу кидаем на главный экран, если нет — на экран входа
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
      theme: ThemeData(primarySwatch: Colors.blueGrey),
      home: initialScreen,
      debugShowCheckedModeBanner: false,
    );
  }
}
