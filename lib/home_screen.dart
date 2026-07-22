import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart'; // Для отправки промокода другу

import 'screens/my_orders_screen.dart';
import 'screens/create_order_screen.dart';
import 'login_screen.dart';
import 'screens/support_chat_screen.dart';

const String CURRENT_APP_VERSION = "1.0.0"; 

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0; 
  String? _phone;
  String? _clientName;
  bool _isLoading = true;
  StreamSubscription<DocumentSnapshot>? _userSubscription;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _checkForUpdates();
  }

  @override
  void dispose() {
    _userSubscription?.cancel();
    super.dispose();
  }

  Future<void> _checkForUpdates() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('settings').doc('app_info').get();
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        final latestVersion = data['latest_version'] as String?;
        final downloadUrl = data['download_url'] as String?;
        final forceUpdate = data['force_update'] as bool? ?? false;

        if (latestVersion != null && latestVersion != CURRENT_APP_VERSION && downloadUrl != null && downloadUrl.isNotEmpty) {
          _showUpdateDialog(downloadUrl, forceUpdate);
        }
      }
    } catch (e) {
      debugPrint('Ошибка проверки обновлений: $e');
    }
  }

  void _showUpdateDialog(String downloadUrl, bool forceUpdate) {
    showDialog(
      context: context,
      barrierDismissible: !forceUpdate,
      builder: (context) {
        return PopScope(
          canPop: !forceUpdate,
          child: AlertDialog(
            title: Row(
              children: const [
                Icon(Icons.system_update, color: Colors.blue),
                SizedBox(width: 8),
                Text('Обновление', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            content: Text(
              forceUpdate 
                ? 'Вышла важная новая версия приложения! Для продолжения работы необходимо обновиться.'
                : 'Доступна новая версия приложения с новыми функциями. Рекомендуем обновить.'
            ),
            actions: [
              if (!forceUpdate)
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Позже', style: TextStyle(color: Colors.grey)),
                ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue[600]),
                onPressed: () async {
                  final uri = Uri.parse(downloadUrl);
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
                child: const Text('Скачать обновление', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        );
      }
    );
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _phone = prefs.getString('phone');
      _clientName = prefs.getString('client_name');
      _isLoading = false;
    });

    if (_phone != null) {
      _setupPushNotifications();
      _listenToBanHammer(); 
      _checkAndInitClientDoc(); // Проверяем, есть ли документ клиента в базе для начисления баллов
    }
  }

  // --- ИНИЦИАЛИЗАЦИЯ БАЛЛОВ ПРИ ПЕРВОМ ВХОДЕ ---
  Future<void> _checkAndInitClientDoc() async {
    if (_phone == null) return;
    final docRef = FirebaseFirestore.instance.collection('clients').doc(_phone);
    final doc = await docRef.get();
    
    if (!doc.exists) {
      // Даем приветственные 10 баллов при первом входе!
      await docRef.set({
        'phone': _phone,
        'name': _clientName ?? 'Клиент',
        'bonus_points': 10,
        'referral_code': 'MSRV-${_phone!.substring(_phone!.length > 4 ? _phone!.length - 4 : 0)}',
        'created_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  void _listenToBanHammer() {
    _userSubscription = FirebaseFirestore.instance.collection('clients').doc(_phone).snapshots().listen((snapshot) {
      if (!snapshot.exists) {
        _forceLogout('Ваш аккаунт был удален администратором.');
      } else {
        final data = snapshot.data() as Map<String, dynamic>;
        if (data['is_approved'] == false) {
           _forceLogout('Ваш доступ к приложению приостановлен.');
        }
      }
    });
  }

  Future<void> _forceLogout(String message) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear(); 
    _userSubscription?.cancel(); 

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red[800], duration: const Duration(seconds: 5)),
    );
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => LoginScreen()));
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

  Future<void> _callAdmin() async {
    final url = Uri.parse('tel:+99363644925');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    }
  }

  void _showCreateActionSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 24),
                decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10)),
              ),
              const Text('Что вы хотите сделать?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 24),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                tileColor: Colors.blue[50],
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.blue[100], shape: BoxShape.circle),
                  child: Icon(Icons.build_circle, color: Colors.blue[700], size: 28),
                ),
                title: const Text('Вызвать мастера / Ремонт', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                subtitle: const Text('Заявка на ремонт вашей техники', style: TextStyle(fontSize: 12, color: Colors.blueGrey)),
                trailing: const Icon(Icons.chevron_right, color: Colors.blueGrey),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (context) => CreateOrderScreen()));
                },
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                tileColor: Colors.orange[50],
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.orange[100], shape: BoxShape.circle),
                  child: Icon(Icons.shopping_bag, color: Colors.orange[700], size: 28),
                ),
                title: const Text('Магазин товаров', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                subtitle: const Text('Комплектующие и аксессуары', style: TextStyle(fontSize: 12, color: Colors.blueGrey)),
                trailing: const Icon(Icons.chevron_right, color: Colors.blueGrey),
                onTap: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Магазин в разработке! Скоро открытие.')));
                },
              ),
              const SizedBox(height: 24), 
            ],
          ),
        );
      }
    );
  }

  Map<String, dynamic> _getStatusInfo(String status) {
    switch (status) {
      case 'new': return {'text': 'Заявка принята, ожидайте', 'color': Colors.blue, 'icon': Icons.access_time_filled};
      case 'awaiting_approval': return {'text': 'Требует вашего ответа!', 'color': Colors.orange, 'icon': Icons.notification_important};
      case 'in_progress': return {'text': 'Устройство в ремонте', 'color': Colors.teal, 'icon': Icons.handyman};
      default: return {'text': 'Обработка...', 'color': Colors.grey, 'icon': Icons.info};
    }
  }

  // --- ВКЛАДКА 1: ГЛАВНАЯ ---
  Widget _buildHomeTab() {
    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_phone != null)
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance.collection('orders')
                    .where('phone', isEqualTo: _phone)
                    .where('status', whereIn: ['new', 'awaiting_approval', 'in_progress'])
                    .snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return const SizedBox.shrink(); 
                  }
                  
                  final doc = snapshot.data!.docs.first;
                  final data = doc.data() as Map<String, dynamic>;
                  final statusInfo = _getStatusInfo(data['status'] ?? 'new');
                  
                  return GestureDetector(
                    onTap: () {
                       Navigator.push(context, MaterialPageRoute(builder: (context) => const MyOrdersScreen()));
                    },
                    child: Container(
                      margin: const EdgeInsets.all(16),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [(statusInfo['color'] as Color).withOpacity(0.8), statusInfo['color']],
                          begin: Alignment.topLeft, end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [BoxShadow(color: (statusInfo['color'] as Color).withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4))],
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: const BoxDecoration(color: Colors.white24, shape: BoxShape.circle),
                            child: Icon(statusInfo['icon'], color: Colors.white, size: 28),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(data['device_type'] ?? 'Устройство', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                                const SizedBox(height: 4),
                                Text(statusInfo['text'], style: const TextStyle(color: Colors.white, fontSize: 13)),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right, color: Colors.white),
                        ],
                      ),
                    ),
                  );
                },
              ),
              
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.video_library, size: 64, color: Colors.grey[300]),
                      const SizedBox(height: 16),
                      Text('Скоро здесь появятся\nлайфхаки и новости', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey[500], fontSize: 16)),
                    ],
                  ),
                ),
              ),
          ],
        ),

        if (_phone != null)
          Positioned(
            bottom: 16,
            right: 16,
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('chat_rooms')
                  .where('participants', arrayContains: _phone)
                  .snapshots(),
              builder: (context, snapshot) {
                int totalUnreadMessages = 0; 
                if (snapshot.hasData) {
                  for (var doc in snapshot.data!.docs) {
                    final data = doc.data() as Map<String, dynamic>;
                    int count = data['unread_count'] as int? ?? 0;
                    if (count > 0 && data['last_sender'] != _phone) {
                      totalUnreadMessages += count;
                    }
                  }
                }

                return Badge(
                  isLabelVisible: totalUnreadMessages > 0,
                  label: Text(totalUnreadMessages.toString(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  backgroundColor: Colors.red,
                  offset: const Offset(-4, -4),
                  child: FloatingActionButton(
                    heroTag: 'chat_btn',
                    onPressed: () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const SupportChatScreen()));
                    },
                    backgroundColor: Colors.blueGrey[900],
                    elevation: 4,
                    child: const Icon(Icons.chat, color: Colors.white),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  // --- ДИАЛОГ ВВОДА ПРОМОКОДА ---
  void _showEnterPromoDialog() {
    final codeController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Активировать промокод', style: TextStyle(fontWeight: FontWeight.bold)),
        content: TextField(
          controller: codeController,
          decoration: const InputDecoration(
            labelText: 'Введите код друга (напр. MSRV-1234)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange[700]),
            onPressed: () async {
              String code = codeController.text.trim().toUpperCase();
              if (code.isEmpty) return;

              // Ищем пользователя с таким промокодом
              final query = await FirebaseFirestore.instance.collection('clients')
                  .where('referral_code', isEqualTo: code)
                  .get();

              if (query.docs.isEmpty) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Промокод не найден!'), backgroundColor: Colors.red));
                return;
              }

              final friendPhone = query.docs.first.id;
              if (friendPhone == _phone) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Нельзя использовать свой собственный код!'), backgroundColor: Colors.red));
                return;
              }

              // Проверяем, не вводил ли уже этот пользователь промокод
              final myDoc = await FirebaseFirestore.instance.collection('clients').doc(_phone).get();
              if (myDoc.data()?['invited_by'] != null) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Вы уже активировали чужой промокод ранее!'), backgroundColor: Colors.orange));
                return;
              }

              // Начисляем бонус обоим
              await FirebaseFirestore.instance.collection('clients').doc(_phone).update({
                'invited_by': friendPhone,
                'bonus_points': FieldValue.increment(15), // Новичку +15 баллов
              });

              await FirebaseFirestore.instance.collection('clients').doc(friendPhone).update({
                'bonus_points': FieldValue.increment(15), // Другу +15 баллов
              });

              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Промокод успешно активирован! Вам начислено 15 баллов 🎉'), backgroundColor: Colors.green));
            },
            child: const Text('Активировать', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // --- ВКЛАДКА 2: ПРОФИЛЬ С КАРТОЧКОЙ ЛОЯЛЬНОСТИ И РЕФЕРАЛКОЙ ---
  Widget _buildProfileTab() {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('clients').doc(_phone).snapshots(),
      builder: (context, snapshot) {
        int points = 10;
        String refCode = 'MSRV-XXXX';

        if (snapshot.hasData && snapshot.data!.exists) {
          final data = snapshot.data!.data() as Map<String, dynamic>;
          points = data['bonus_points'] as int? ?? 10;
          refCode = data['referral_code'] as String? ?? 'MSRV-XXXX';
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. БАНКОВСКАЯ КАРТА ЛОЯЛЬНОСТИ (БАЛЛЫ)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 10, offset: const Offset(0, 5))],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('M-SERVICE BONUS', style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold, letterSpacing: 1.5, fontSize: 12)),
                        Icon(Icons.stars_rounded, color: Colors.orangeAccent[400], size: 28),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const Text('Ваш баланс баллов:', style: TextStyle(color: Colors.white70, fontSize: 13)),
                    const SizedBox(height: 4),
                    Text('$points баллов', style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 12),
                    const Text('1 балл = 1 TMT. Скидка до 30% на ремонт.', style: TextStyle(color: Colors.white38, fontSize: 11)),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // 2. БЛОК РЕФЕРАЛЬНОЙ ПРОГРАММЫ
              Card(
                elevation: 0,
                color: Colors.orange[50],
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.orange.shade200)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.card_giftcard, color: Colors.deepOrange),
                          SizedBox(width: 8),
                          Text('Пригласи друга', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.deepOrange)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text('Дарите друзьям 15 баллов и получайте 15 баллов себе после их заказа!', style: TextStyle(fontSize: 13, color: Colors.brown)),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.orange.shade300)),
                              child: Text(refCode, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 1.2)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange, foregroundColor: Colors.white),
                            onPressed: () {
                              Share.share('Привет! Скачай приложение M-Service для ремонта техники и введи мой код $refCode, чтобы получить стартовый бонус!');
                            },
                            child: const Text('Поделиться'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: TextButton.icon(
                          onPressed: _showEnterPromoDialog,
                          icon: const Icon(Icons.input, size: 18),
                          label: const Text('У меня есть промокод от друга'),
                        ),
                      )
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              const Text('МОЙ АККАУНТ', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blueGrey, letterSpacing: 1.2)),
              const SizedBox(height: 12),
              
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
                      subtitle: 'История ремонтов и статусы',
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
                title: 'Служба поддержки',
                subtitle: 'Связь с администратором',
                icon: Icons.headset_mic,
                iconColor: Colors.teal[700]!,
                onTap: _callAdmin,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMenuCard({required String title, required String subtitle, required IconData icon, required Color iconColor, required VoidCallback onTap}) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16.0),
          child: ListTile(
            leading: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: iconColor.withOpacity(0.1), shape: BoxShape.circle),
              child: Icon(icon, size: 28, color: iconColor),
            ),
            title: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
            subtitle: Text(subtitle, style: TextStyle(color: Colors.blueGrey[400], fontSize: 13)),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_phone == null || _isLoading) {
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
          backgroundColor: Colors.white,
          elevation: 0,
          title: Text(
            _currentIndex == 0 ? 'M-Service' : 'Профиль',
            style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w900, fontSize: 24),
          ),
          centerTitle: false,
          actions: [
            if (_currentIndex == 1) 
              IconButton(icon: const Icon(Icons.logout, color: Colors.red), onPressed: _logout, tooltip: 'Выйти'),
          ],
        ),
        
        body: IndexedStack(
          index: _currentIndex,
          children: [
            _buildHomeTab(),
            _buildProfileTab(),
          ],
        ),

        floatingActionButton: FloatingActionButton(
          heroTag: 'create_btn',
          backgroundColor: Colors.blueGrey[900],
          elevation: 4,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          onPressed: _showCreateActionSheet,
          child: const Icon(Icons.add, color: Colors.white, size: 32),
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerDockData ?? FloatingActionButtonLocation.centerDocked,

        bottomNavigationBar: BottomAppBar(
          shape: const CircularNotchedRectangle(),
          notchMargin: 8.0,
          color: Colors.white,
          elevation: 20,
          child: SizedBox(
            height: 60,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                MaterialButton(
                  minWidth: 60,
                  onPressed: () => setState(() => _currentIndex = 0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.home_filled, color: _currentIndex == 0 ? Colors.blueGrey[900] : Colors.grey[400]),
                      Text('Главная', style: TextStyle(fontSize: 10, color: _currentIndex == 0 ? Colors.blueGrey[900] : Colors.grey[400], fontWeight: _currentIndex == 0 ? FontWeight.bold : FontWeight.normal)),
                    ],
                  ),
                ),
                
                const SizedBox(width: 48), 
                
                MaterialButton(
                  minWidth: 60,
                  onPressed: () => setState(() => _currentIndex = 1),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.person, color: _currentIndex == 1 ? Colors.blueGrey[900] : Colors.grey[400]),
                      Text('Профиль', style: TextStyle(fontSize: 10, color: _currentIndex == 1 ? Colors.blueGrey[900] : Colors.grey[400], fontWeight: _currentIndex == 1 ? FontWeight.bold : FontWeight.normal)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

