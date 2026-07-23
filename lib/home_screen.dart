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
import 'screens/support_chat_screen.dart';
import 'screens/services_catalog_screen.dart';
import 'screens/profile_screen.dart'; // <--- ПОДКЛЮЧИЛИ НОВЫЙ ЧИСТЫЙ ПРОФИЛЬ

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
  int _maxDiscountPercentUI = 30; 

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _checkForUpdates();
    _fetchLoyaltyConfig(); 
  }

  @override
  void dispose() {
    _userSubscription?.cancel();
    super.dispose();
  }

  Future<void> _fetchLoyaltyConfig() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('settings').doc('loyalty').get();
      if (doc.exists && doc.data()!.containsKey('max_discount_percent')) {
        setState(() {
          _maxDiscountPercentUI = doc.data()!['max_discount_percent'];
        });
      }
    } catch (e) {
      debugPrint('Ошибка загрузки настроек: $e');
    }
  }

  Future<void> _addBonusHistory(String phone, int amount, String description) async {
    await FirebaseFirestore.instance.collection('clients').doc(phone).collection('bonus_history').add({
      'amount': amount,
      'description': description,
      'created_at': FieldValue.serverTimestamp(),
    });
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
    } catch (e) {}
  }

  void _showUpdateDialog(String downloadUrl, bool forceUpdate) {
    showDialog(
      context: context,
      barrierDismissible: !forceUpdate,
      builder: (context) {
        return PopScope(
          canPop: !forceUpdate,
          child: AlertDialog(
            title: Row(children: const [Icon(Icons.system_update, color: Colors.blue), SizedBox(width: 8), Text('Обновление')]),
            content: Text(forceUpdate ? 'Вышла важная новая версия!' : 'Доступна новая версия приложения.'),
            actions: [
              if (!forceUpdate) TextButton(onPressed: () => Navigator.pop(context), child: const Text('Позже', style: TextStyle(color: Colors.grey))),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue[600]),
                onPressed: () async {
                  final uri = Uri.parse(downloadUrl);
                  if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
                },
                child: const Text('Скачать', style: TextStyle(color: Colors.white)),
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
      _checkAndInitClientDoc(); 
    }
  }

  Future<void> _checkAndInitClientDoc() async {
    if (_phone == null) return;
    final docRef = FirebaseFirestore.instance.collection('clients').doc(_phone);
    final doc = await docRef.get();
    
    if (!doc.exists) {
      int welcomePoints = 10;
      try {
        final settings = await FirebaseFirestore.instance.collection('settings').doc('loyalty').get();
        if (settings.exists && settings.data()!.containsKey('welcome_points')) {
          welcomePoints = settings.data()!['welcome_points'];
        }
      } catch (e) {}

      await docRef.set({
        'phone': _phone,
        'name': _clientName ?? 'Клиент',
        'bonus_points': welcomePoints,
        'created_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (welcomePoints > 0) {
        await _addBonusHistory(_phone!, welcomePoints, 'Приветственный бонус');
      }
    }
  }

  void _listenToBanHammer() {
    _userSubscription = FirebaseFirestore.instance.collection('clients').doc(_phone).snapshots().listen((snapshot) {
      if (!snapshot.exists) {
        _forceLogout('Ваш аккаунт был удален.');
      } else {
        final data = snapshot.data() as Map<String, dynamic>;
        if (data['is_approved'] == false) _forceLogout('Ваш доступ приостановлен.');
      }
    });
  }

  Future<void> _forceLogout(String message) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear(); 
    _userSubscription?.cancel(); 
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), backgroundColor: Colors.red[800]));
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => LoginScreen()));
  }

  Future<void> _setupPushNotifications() async {
    FirebaseMessaging messaging = FirebaseMessaging.instance;
    await messaging.requestPermission();
    String? token = await messaging.getToken();
    if (token != null && _phone != null) {
      await FirebaseFirestore.instance.collection('clients').doc(_phone).set({'fcm_token': token}, SetOptions(merge: true));
    }
    await messaging.subscribeToTopic('all_users');
  }

  void _showCreateActionSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 24), decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
              const Text('Что вы хотите сделать?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 24),
              ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), tileColor: Colors.blue[50],
                leading: CircleAvatar(backgroundColor: Colors.blue[100], child: Icon(Icons.build_circle, color: Colors.blue[700])),
                title: const Text('Вызвать мастера / Ремонт', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('Сразу прямая форма заказа', style: TextStyle(fontSize: 12)),
                onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (context) => CreateOrderScreen())); },
              ),
              const SizedBox(height: 12),
              ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), tileColor: Colors.purple[50],
                leading: CircleAvatar(backgroundColor: Colors.purple[100], child: Icon(Icons.layers, color: Colors.purple[700])),
                title: const Text('Каталог наших услуг', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('Витрина услуг перед заказом', style: TextStyle(fontSize: 12)),
                onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (context) => const ServicesCatalogScreen())); },
              ),
            ],
          ),
        );
      }
    );
  }

  void _showReviewDialog(QueryDocumentSnapshot order, Map<String, dynamic> data) {
    int rating = 5;
    bool isAnonymous = false;
    final commentController = TextEditingController();
    bool isSubmitting = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('Оцените работу', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18), textAlign: TextAlign.center),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Насколько вы довольны ремонтом?', style: TextStyle(fontSize: 13, color: Colors.blueGrey)),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (index) {
                    return IconButton(
                      iconSize: 36,
                      icon: Icon(index < rating ? Icons.star_rounded : Icons.star_border_rounded, color: Colors.orangeAccent),
                      onPressed: () => setStateDialog(() => rating = index + 1),
                    );
                  }),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: commentController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: 'Напишите пару слов...',
                    filled: true, fillColor: Colors.grey[100],
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 12),
                CheckboxListTile(
                  title: const Text('Оставить анонимно', style: TextStyle(fontSize: 13)),
                  value: isAnonymous, dense: true, contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading, activeColor: Colors.blueGrey,
                  onChanged: (val) => setStateDialog(() => isAnonymous = val ?? false),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена', style: TextStyle(color: Colors.grey))),
              isSubmitting 
                ? const CircularProgressIndicator()
                : ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.blue[600]),
                    onPressed: () async {
                      setStateDialog(() => isSubmitting = true);
                      
                      String clientName = data['client_name'] ?? 'Клиент';
                      if (isAnonymous) {
                         clientName = clientName.length > 2 ? '${clientName.substring(0, 1)}***' : 'Аноним';
                      }

                      try {
                        await FirebaseFirestore.instance.collection('reviews').add({
                          'rating': rating,
                          'text': commentController.text.trim(),
                          'author_name': clientName,
                          'device_type': data['device_type'] ?? 'Устройство',
                          'created_at': FieldValue.serverTimestamp(),
                          'is_approved': false, 
                        });

                        await order.reference.update({'is_reviewed': true, 'review_rating': rating});

                        if (mounted) {
                           Navigator.pop(ctx);
                           ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Отзыв отправлен!'), backgroundColor: Colors.green));
                        }
                      } catch(e) {
                         setStateDialog(() => isSubmitting = false);
                         if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.red));
                      }
                    },
                    child: const Text('Отправить', style: TextStyle(color: Colors.white)),
                  ),
            ],
          );
        }
      ),
    );
  }

  Map<String, dynamic> _getStatusInfo(String status) {
    switch (status) {
      case 'new': return {'text': 'Принята, ожидайте', 'color': Colors.blue, 'icon': Icons.access_time_filled};
      case 'awaiting_approval': return {'text': 'Требует ответа!', 'color': Colors.orange, 'icon': Icons.notification_important};
      case 'in_progress': return {'text': 'В ремонте', 'color': Colors.teal, 'icon': Icons.handyman};
      case 'completed': return {'text': 'Завершен!', 'color': Colors.green, 'icon': Icons.check_circle};
      default: return {'text': 'Обработка...', 'color': Colors.grey, 'icon': Icons.info};
    }
  }

  Widget _buildReviewsCarousel() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('reviews').where('is_approved', isEqualTo: true).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Column(
            children: [
              Icon(Icons.forum, size: 64, color: Colors.grey[300]),
              const SizedBox(height: 16),
              Text('Здесь будут отзывы', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey[500], fontSize: 16)),
            ],
          );
        }

        var docs = snapshot.data!.docs;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.0),
              child: Text('Отзывы клиентов', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 160,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final data = docs[index].data() as Map<String, dynamic>;
                  return Container(
                    width: 280, 
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white, borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(data['author_name'] ?? 'Клиент', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                            Row(children: List.generate(5, (starIdx) => Icon(starIdx < (data['rating'] ?? 5) ? Icons.star_rounded : Icons.star_border_rounded, color: Colors.orangeAccent, size: 16)))
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(data['device_type'] ?? '', style: TextStyle(color: Colors.grey[500], fontSize: 11)),
                        const SizedBox(height: 8),
                        Expanded(child: Text(data['text'] ?? '', maxLines: 4, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildHomeTab() {
    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.only(bottom: 80),
          children: [
            if (_phone != null)
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance.collection('orders').where('phone', isEqualTo: _phone).where('status', whereIn: ['new', 'awaiting_approval', 'in_progress', 'completed']).snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const SizedBox.shrink(); 
                  final docs = snapshot.data!.docs.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    if (data['status'] == 'completed' && data['is_reviewed'] == true) return false;
                    return true;
                  }).toList();
                  if (docs.isEmpty) return const SizedBox.shrink();

                  return Column(
                    children: docs.map((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      String status = data['status'] ?? 'new';
                      final statusInfo = _getStatusInfo(status);

                      return GestureDetector(
                        onTap: () {
                           if (status != 'completed') Navigator.push(context, MaterialPageRoute(builder: (context) => const MyOrdersScreen()));
                        },
                        child: Container(
                          margin: const EdgeInsets.only(left: 16, right: 16, top: 16),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(colors: [(statusInfo['color'] as Color).withOpacity(0.8), statusInfo['color']], begin: Alignment.topLeft, end: Alignment.bottomRight),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  CircleAvatar(backgroundColor: Colors.white24, child: Icon(statusInfo['icon'], color: Colors.white)),
                                  const SizedBox(width: 16),
                                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text(data['device_type'] ?? 'Устройство', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                                    Text(statusInfo['text'], style: const TextStyle(color: Colors.white, fontSize: 13)),
                                  ])),
                                  if (status != 'completed') const Icon(Icons.chevron_right, color: Colors.white),
                                ],
                              ),
                              if (status == 'completed') ...[
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.green[800], shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                                        onPressed: () => _showReviewDialog(doc, data), icon: const Icon(Icons.star, color: Colors.orange), label: const Text('Оставить отзыв'),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () async { await doc.reference.update({'is_reviewed': true}); }),
                                  ],
                                )
                              ]
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
              const SizedBox(height: 40),
              _buildReviewsCarousel(),
              const SizedBox(height: 40),
          ],
        ),
        if (_phone != null)
          Positioned(
            bottom: 16, right: 16,
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('chat_rooms').where('participants', arrayContains: _phone).snapshots(),
              builder: (context, snapshot) {
                int unread = 0; 
                if (snapshot.hasData) {
                  for (var doc in snapshot.data!.docs) {
                    final data = doc.data() as Map<String, dynamic>;
                    if ((data['unread_count'] as int? ?? 0) > 0 && data['last_sender'] != _phone) unread += (data['unread_count'] as int);
                  }
                }
                return Badge(
                  isLabelVisible: unread > 0, label: Text(unread.toString()), offset: const Offset(-4, -4), backgroundColor: Colors.red,
                  child: FloatingActionButton(heroTag: 'chat_btn', onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SupportChatScreen())), backgroundColor: Colors.blueGrey[900], child: const Icon(Icons.chat, color: Colors.white)),
                );
              },
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_phone == null || _isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 0,
        title: Text(_currentIndex == 0 ? 'M-Service' : 'Профиль', style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w900, fontSize: 24)),
      ),
      // 🔥 ЗДЕСЬ МЫ ВЫЗЫВАЕМ НАШ НОВЫЙ ЧИСТЫЙ ЭКРАН ПРОФИЛЯ! 🔥
      body: IndexedStack(
        index: _currentIndex, 
        children: [
          _buildHomeTab(), 
          ProfileScreen(phone: _phone!, maxDiscountPercent: _maxDiscountPercentUI),
        ]
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'create_btn', backgroundColor: Colors.blueGrey[900], elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        onPressed: _showCreateActionSheet, child: const Icon(Icons.add, color: Colors.white, size: 32),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(), notchMargin: 8.0, color: Colors.white, elevation: 20,
        child: SizedBox(
          height: 60,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              MaterialButton(
                minWidth: 60, onPressed: () => setState(() => _currentIndex = 0),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.home_filled, color: _currentIndex == 0 ? Colors.blueGrey[900] : Colors.grey[400]),
                  Text('Главная', style: TextStyle(fontSize: 10, color: _currentIndex == 0 ? Colors.blueGrey[900] : Colors.grey[400], fontWeight: _currentIndex == 0 ? FontWeight.bold : FontWeight.normal)),
                ]),
              ),
              const SizedBox(width: 48), 
              MaterialButton(
                minWidth: 60, onPressed: () => setState(() => _currentIndex = 1),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.person, color: _currentIndex == 1 ? Colors.blueGrey[900] : Colors.grey[400]),
                  Text('Профиль', style: TextStyle(fontSize: 10, color: _currentIndex == 1 ? Colors.blueGrey[900] : Colors.grey[400], fontWeight: _currentIndex == 1 ? FontWeight.bold : FontWeight.normal)),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

