import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:url_launcher/url_launcher.dart';
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
      _clientName = prefs.getString('client_name');
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

  Future<void> _callAdmin() async {
    final url = Uri.parse('tel:+99363644925'); // Твой номер
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_phone == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        await _onWillPop();
      },
      child: Scaffold(
        backgroundColor: Colors.grey[50],
        appBar: AppBar(
          backgroundColor: Colors.blueGrey[900],
          foregroundColor: Colors.white,
          title: Text(
            'Добро пожаловать, ${_clientName ?? "Клиент"}!',
            style: const TextStyle(fontSize: 18),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: _logout,
              tooltip: 'Сменить аккаунт',
            ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              
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
                    offset: const Offset(-4, -4),
                    child: _buildMenuCard(
                      title: 'Мои заказы',
                      subtitle: 'История и согласование статуса',
                      icon: Icons.list_alt,
                      iconColor: Colors.blueGrey[700]!,
                      onTap: () {
                        Navigator.push(context, MaterialPageRoute(builder: (context) => const MyOrdersScreen()));
                      },
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              
              _buildMenuCard(
                title: 'Оформить заказ',
                subtitle: 'Создать новый заказ на ремонт',
                icon: Icons.add_circle_outline,
                iconColor: Colors.blueGrey[700]!,
                onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder: (context) => CreateOrderScreen()));
                },
              ),
              
              const SizedBox(height: 48),
              
              // Второстепенная кнопка связи с админом (внизу)
              Center(
                child: TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.blueGrey[400],
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  onPressed: _callAdmin,
                  icon: const Icon(Icons.support_agent, size: 20),
                  label: const Text('Связаться с администратором', style: TextStyle(fontSize: 14)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMenuCard({required String title, required String subtitle, required IconData icon, required Color iconColor, required VoidCallback onTap}) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12.0),
          child: ListTile(
            leading: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: iconColor.withOpacity(0.1), shape: BoxShape.circle),
              child: Icon(icon, size: 32, color: iconColor),
            ),
            title: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
            subtitle: Text(subtitle, style: TextStyle(color: Colors.blueGrey[400])),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
          ),
        ),
      ),
    );
  }
}

