// lib/home_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'screens/my_orders_screen.dart';
import 'screens/create_order_screen.dart';
import 'login_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? _phone;
  String? _clientName;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _phone = prefs.getString('phone');
      _clientName = prefs.getString('client_name'); // Достаем имя клиента
    });

    if (_phone != null) {
      _setupPushNotifications();
    }
  }

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
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_phone == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        // Приветствие пользователя
        title: Text('Добро пожаловать, ${_clientName ?? "Клиент"}!'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _logout,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('orders')
                  .where('phone', isEqualTo: _phone)
                  .where('has_unread_update', isEqualTo: true)
                  .snapshots(),
              builder: (context, snapshot) {
                int unreadCount = 0;
                if (snapshot.hasData) {
                  unreadCount = snapshot.data!.docs.length;
                }

                return Badge(
                  isLabelVisible: unreadCount > 0,
                  label: Text(unreadCount.toString()),
                  child: Card(
                    elevation: 4,
                    child: ListTile(
                      leading: const Icon(Icons.build, size: 40, color: Colors.blue),
                      title: const Text('Мои ремонты', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      subtitle: const Text('История и согласование статуса'),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const MyOrdersScreen(),
                          ),
                        );
                      },
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            Card(
              elevation: 4,
              child: ListTile(
                leading: const Icon(Icons.add_circle, size: 40, color: Colors.green),
                title: const Text('Новая заявка', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                subtitle: const Text('Создать заявку на ремонт'),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => CreateOrderScreen(),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
