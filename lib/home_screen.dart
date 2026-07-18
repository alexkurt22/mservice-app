import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:url_launcher/url_launcher.dart';
import 'screens/my_orders_screen.dart';
import 'screens/create_order_screen.dart';
import 'login_screen.dart';
import 'support_chat_screen.dart'; // ❗ ДОБАВЛЕН ИМПОРТ ЧАТА

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? _phone;
  String? _clientName;
  StreamSubscription<DocumentSnapshot>? _userSubscription;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  @override
  void dispose() {
    _userSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _phone = prefs.getString('phone');
      _clientName = prefs.getString('client_name');
    });

    if (_phone != null) {
      _setupPushNotifications();
      _listenToBanHammer(); // Запускаем шпиона безопасности
    }
  }

  // --- ТОТ САМЫЙ "ШПИОН" БЕЗОПАСНОСТИ ---
  void _listenToBanHammer() {
    _userSubscription = FirebaseFirestore.instance.collection('clients').doc(_phone).snapshots().listen((snapshot) {
      if (!snapshot.exists) {
        // Если документа больше нет в базе (админ удалил)
        _forceLogout('Ваш аккаунт был удален администратором.');
      } else {
        // Если документ есть, но админ снял галочку "одобрено"
        final data = snapshot.data() as Map<String, dynamic>;
        if (data['is_approved'] == false) {
           _forceLogout('Ваш доступ к приложению приостановлен.');
        }
      }
    });
  }

  Future<void> _forceLogout(String message) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear(); // Стираем кэш
    _userSubscription?.cancel(); // Убиваем слушателя

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red[800], duration: const Duration(seconds: 5)),
    );
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => LoginScreen()));
  }
  // ----------------------------------------

  Future<void> _setupPushNotifications() async {
    FirebaseMessaging messaging = FirebaseMessaging.instance;
    await messaging.requestPermission();
    
    String? token = await messaging.getToken();
    if (token != null && _phone != null) {
      await FirebaseFirestore.instance.collection('clients').doc(_phone).set(
        {'fcm_token': token},
        SetOptions(merge: true),
      );
    }

    await messaging.subscribeToTopic('all_users');

    messaging.onTokenRefresh.listen((newToken) async {
      if (_phone != null) {
        await FirebaseFirestore.instance.collection('clients').doc(_phone).set(
          {'fcm_token': newToken},
          SetOptions(merge: true),
        );
      }
    });
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    _userSubscription?.cancel();
    if (!mounted) return;
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => LoginScreen()));
  }

  Future<bool> _onWillPop() async {
    final shouldPop = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Выход из приложения', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text('Вы действительно хотите выйти?'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Нет', style: TextStyle(color: Colors.blueGrey)),
          ),
          TextButton(
            onPressed: () {
               Navigator.of(context).pop(true);
               SystemNavigator.pop();
            },
            child: const Text('Да', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    return shouldPop ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      // 👇 ВОТ ОН - ТОТ САМЫЙ SCAFFOLD!
      child: Scaffold(
        backgroundColor: Colors.grey[50],
        appBar: AppBar(
          backgroundColor: Colors.blue[800],
          foregroundColor: Colors.white,
          title: Text('Привет, ${_clientName ?? 'Клиент'}!', style: const TextStyle(fontWeight: FontWeight.bold)),
          actions: [
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: _logout,
              tooltip: 'Выйти',
            ),
          ],
        ),
        
        // 👇 А ВОТ И КНОПКА ЧАТА, ВСТАВЛЕННАЯ ПРЯМО В SCAFFOLD
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const SupportChatScreen()));
          },
          backgroundColor: Colors.blue[800],
          icon: const Icon(Icons.chat_bubble, color: Colors.white),
          label: const Text('Поддержка', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ),

        // 👇 ОСТАЛЬНОЕ ТЕЛО ЭКРАНА С ДВУМЯ КНОПКАМИ (ОСТАВИТЬ ЗАЯВКУ И ИСТОРИЯ)
        body: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder: (context) => const CreateOrderScreen()));
                },
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 30,
                        backgroundColor: Colors.blue[100],
                        child: Icon(Icons.add_circle_outline, size: 32, color: Colors.blue[800]),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Оставить заявку', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blueGrey[900])),
                            const SizedBox(height: 4),
                            Text('Заявка на ремонт или обслуживание', style: TextStyle(color: Colors.blueGrey[400], fontSize: 13)),
                          ],
                        ),
                      ),
                      const Icon(Icons.arrow_forward_ios, color: Colors.blueGrey),
                    ],
                  ),
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder: (context) => const MyOrdersScreen()));
                },
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 30,
                        backgroundColor: Colors.orange[100],
                        child: Icon(Icons.history, size: 32, color: Colors.orange[800]),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Мои ремонты', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blueGrey[900])),
                            const SizedBox(height: 4),
                            Text('История и статус ремонтов', style: TextStyle(color: Colors.blueGrey[400], fontSize: 13)),
                          ],
                        ),
                      ),
                      const Icon(Icons.arrow_forward_ios, color: Colors.blueGrey),
                    ],
                  ),
                ),
              ),
            ),
            
          ],
        ),
      ),
    );
  }
}

