import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'login_screen.dart';
import 'screens/create_order_screen.dart';
import 'screens/my_orders_screen.dart';

class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? _phone;
  String? _clientName;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _phone = prefs.getString('phone');
      _clientName = prefs.getString('client_name');
    });

    if (_phone != null) {
      await _setupPushNotifications();
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
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_phone == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
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
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(20)),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => CreateOrderScreen()),
                );
              },
              child: const Text('Создать заявку', style: TextStyle(fontSize: 18)),
            ),
            const SizedBox(height: 16),
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
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.all(20),
                      minimumSize: const Size.fromHeight(60),
                    ),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => MyOrdersScreen()),
                      );
                    },
                    child: const Text('Мои ремонты', style: TextStyle(fontSize: 18)),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(20)),
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('В разработке')),
                );
              },
              child: const Text('Бонусы и Профиль', style: TextStyle(fontSize: 18)),
            ),
          ],
        ),
      ),
    );
  }
}
