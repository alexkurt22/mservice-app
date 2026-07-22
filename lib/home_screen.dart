import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';

import 'screens/my_orders_screen.dart';
import 'screens/create_order_screen.dart';
import 'login_screen.dart';
import 'screens/support_chat_screen.dart';
import 'screens/bonus_history_screen.dart';

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
      debugPrint('Ошибка загрузки настроек лояльности: $e');
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
    } catch (e) {
      debugPrint('Ошибка обновления: $e');
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
      } catch (e) {
        debugPrint('Не удалось прочитать настройки: $e');
      }

      await docRef.set({
        'phone': _phone,
        'name': _clientName ?? 'Клиент',
        'bonus_points': welcomePoints,
        'referral_code': 'MSRV-${_phone!.substring(_phone!.length > 4 ? _phone!.length - 4 : 0)}',
        'created_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (welcomePoints > 0) {
        await _addBonusHistory(_phone!, welcomePoints, 'Приветственный бонус за регистрацию');
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
        title: const Text('Выход', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text('Вы действительно хотите выйти?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Нет', style: TextStyle(color: Colors.blueGrey))),
          TextButton(onPressed: () { Navigator.of(context).pop(true); SystemNavigator.pop(); }, child: const Text('Да', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    return shouldPop ?? false;
  }

  Future<void> _callAdmin() async {
    final url = Uri.parse('tel:+99363644925');
    if (await canLaunchUrl(url)) await launchUrl(url);
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
                subtitle: const Text('Заявка на ремонт вашей техники', style: TextStyle(fontSize: 12)),
                onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (context) => CreateOrderScreen())); },
              ),
              const SizedBox(height: 12),
              ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), tileColor: Colors.orange[50],
                leading: CircleAvatar(backgroundColor: Colors.orange[100], child: Icon(Icons.shopping_bag, color: Colors.orange[700])),
                title: const Text('Магазин товаров', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('Комплектующие и аксессуары', style: TextStyle(fontSize: 12)),
                onTap: () { Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Скоро открытие.'))); },
              ),
              const SizedBox(height: 24), 
            ],
          ),
        );
      }
    );
  }

  // --- ЛОГИКА ДИАЛОГА ДЛЯ ОТЗЫВА ---
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
                    hintText: 'Напишите пару слов (необязательно)...',
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
              TextButton(
                onPressed: () => Navigator.pop(ctx), 
                child: const Text('Отмена', style: TextStyle(color: Colors.grey))
              ),
              isSubmitting 
                ? const CircularProgressIndicator()
                : ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.blue[600], shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                    onPressed: () async {
                      setStateDialog(() => isSubmitting = true);
                      
                      String clientName = data['client_name'] ?? 'Клиент';
                      if (isAnonymous) {
                         clientName = clientName.length > 2 ? '${clientName.substring(0, 1)}***' : 'Анонимный клиент';
                      }

                      try {
                        await FirebaseFirestore.instance.collection('reviews').add({
                          'rating': rating,
                          'text': commentController.text.trim(),
                          'author_name': clientName,
                          'device_type': data['device_type'] ?? 'Устройство',
                          'created_at': FieldValue.serverTimestamp(),
                        });

                        await order.reference.update({
                          'is_reviewed': true,
                          'review_rating': rating,
                        });

                        if (mounted) {
                           Navigator.pop(ctx);
                           ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Спасибо! Ваш отзыв опубликован 🎉'), backgroundColor: Colors.green));
                        }
                      } catch(e) {
                         setStateDialog(() => isSubmitting = false);
                         if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.red));
                      }
                    },
                    child: const Text('Отправить', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
            ],
          );
        }
      ),
    );
  }

  Map<String, dynamic> _getStatusInfo(String status) {
    switch (status) {
      case 'new': return {'text': 'Заявка принята, ожидайте', 'color': Colors.blue, 'icon': Icons.access_time_filled};
      case 'awaiting_approval': return {'text': 'Требует вашего ответа!', 'color': Colors.orange, 'icon': Icons.notification_important};
      case 'in_progress': return {'text': 'Устройство в ремонте', 'color': Colors.teal, 'icon': Icons.handyman};
      case 'completed': return {'text': 'Ремонт завершен!', 'color': Colors.green, 'icon': Icons.check_circle}; // НОВЫЙ СТАТУС
      default: return {'text': 'Обработка...', 'color': Colors.grey, 'icon': Icons.info};
    }
  }

  // --- ВКЛАДКА 1: ГЛАВНАЯ (ОБНОВЛЕННАЯ С ЗЕЛЕНОЙ ПЛАШКОЙ) ---
  Widget _buildHomeTab() {
    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.only(bottom: 80), // Отступ для нижней кнопки
          children: [
            if (_phone != null)
              StreamBuilder<QuerySnapshot>(
                // Читаем все активные и выполненные заказы
                stream: FirebaseFirestore.instance.collection('orders')
                    .where('phone', isEqualTo: _phone)
                    .where('status', whereIn: ['new', 'awaiting_approval', 'in_progress', 'completed'])
                    .snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const SizedBox.shrink(); 
                  
                  // Фильтруем: не показываем выполненные, если уже есть отзыв
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
                           if (status != 'completed') {
                             Navigator.push(context, MaterialPageRoute(builder: (context) => const MyOrdersScreen()));
                           }
                        },
                        child: Container(
                          margin: const EdgeInsets.only(left: 16, right: 16, top: 16),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(colors: [(statusInfo['color'] as Color).withOpacity(0.8), statusInfo['color']], begin: Alignment.topLeft, end: Alignment.bottomRight),
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [BoxShadow(color: (statusInfo['color'] as Color).withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4))],
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
                                  if (status != 'completed')
                                    const Icon(Icons.chevron_right, color: Colors.white),
                                ],
                              ),
                              // --- КНОПКА ОТЗЫВА ПРЯМО НА ЗЕЛЕНОЙ ПЛАШКЕ ---
                              if (status == 'completed') ...[
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.white,
                                          foregroundColor: Colors.green[800],
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                        ),
                                        onPressed: () => _showReviewDialog(doc, data),
                                        icon: const Icon(Icons.star, color: Colors.orange),
                                        label: const Text('Оставить отзыв', style: TextStyle(fontWeight: FontWeight.bold)),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    IconButton(
                                      icon: const Icon(Icons.close, color: Colors.white),
                                      tooltip: 'Скрыть',
                                      onPressed: () async {
                                        // Скрываем навсегда, если клиент не хочет писать отзыв
                                        await doc.reference.update({'is_reviewed': true});
                                      },
                                    ),
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
              
              const SizedBox(height: 64),
              Icon(Icons.video_library, size: 64, color: Colors.grey[300]),
              const SizedBox(height: 16),
              Text('Скоро здесь появятся\nлайфхаки и новости', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey[500], fontSize: 16)),
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

  void _showEnterPromoDialog() {
    final codeController = TextEditingController();
    bool isProcessing = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            title: const Text('Активировать код', style: TextStyle(fontWeight: FontWeight.bold)),
            content: TextField(
              controller: codeController,
              decoration: const InputDecoration(labelText: 'Код друга (MSRV-...)', border: OutlineInputBorder()),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена', style: TextStyle(color: Colors.grey))),
              isProcessing 
                ? const Padding(padding: EdgeInsets.all(8.0), child: CircularProgressIndicator())
                : ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.orange[700]),
                    onPressed: () async {
                      String code = codeController.text.trim().toUpperCase();
                      if (code.isEmpty) return;

                      setStateDialog(() => isProcessing = true);

                      int referralBonus = 15;
                      try {
                        final settings = await FirebaseFirestore.instance.collection('settings').doc('loyalty').get();
                        if (settings.exists && settings.data()!.containsKey('referral_points')) {
                          referralBonus = settings.data()!['referral_points'];
                        }
                      } catch (e) {
                        // ignore
                      }

                      final query = await FirebaseFirestore.instance.collection('clients').where('referral_code', isEqualTo: code).get();

                      if (query.docs.isEmpty) {
                        setStateDialog(() => isProcessing = false);
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Код не найден!'), backgroundColor: Colors.red));
                        return;
                      }

                      final friendPhone = query.docs.first.id;
                      if (friendPhone == _phone) {
                        setStateDialog(() => isProcessing = false);
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Нельзя использовать свой код!'), backgroundColor: Colors.red));
                        return;
                      }

                      final myDoc = await FirebaseFirestore.instance.collection('clients').doc(_phone).get();
                      if (myDoc.data()?['invited_by'] != null) {
                        setStateDialog(() => isProcessing = false);
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Вы уже активировали код ранее!'), backgroundColor: Colors.orange));
                        return;
                      }

                      await FirebaseFirestore.instance.collection('clients').doc(_phone).update({
                        'invited_by': friendPhone,
                        'bonus_points': FieldValue.increment(referralBonus), 
                      });
                      await _addBonusHistory(_phone!, referralBonus, 'Активация промокода друга');

                      await FirebaseFirestore.instance.collection('clients').doc(friendPhone).update({
                        'bonus_points': FieldValue.increment(referralBonus), 
                      });
                      await _addBonusHistory(friendPhone, referralBonus, 'Бонус за приглашение друга');

                      if (!mounted) return;
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Промокод активирован! Вам начислено $referralBonus баллов 🎉'), backgroundColor: Colors.green));
                    },
                    child: const Text('Активировать', style: TextStyle(color: Colors.white)),
                  ),
            ],
          );
        }
      ),
    );
  }

  // --- ВКЛАДКА 2: ПРОФИЛЬ ---
  Widget _buildProfileTab() {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('clients').doc(_phone).snapshots(),
      builder: (context, snapshot) {
        int points = 0;
        String refCode = 'MSRV-XXXX';

        if (snapshot.hasData && snapshot.data!.exists) {
          final data = snapshot.data!.data() as Map<String, dynamic>;
          points = data['bonus_points'] as int? ?? 0;
          refCode = data['referral_code'] as String? ?? 'MSRV-XXXX';
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF1E293B), Color(0xFF0F172A)], begin: Alignment.topLeft, end: Alignment.bottomRight),
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
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('1 балл = 1 TMT. Скидка до $_maxDiscountPercentUI%.', style: const TextStyle(color: Colors.white54, fontSize: 11)),
                        GestureDetector(
                          onTap: () {
                            if (_phone != null) {
                              Navigator.push(context, MaterialPageRoute(builder: (_) => BonusHistoryScreen(phone: _phone!)));
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(20)),
                            child: const Row(
                              children: [
                                Text('История', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                                Icon(Icons.chevron_right, color: Colors.white, size: 16),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

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
                      const Text('Подарите бонус другу и получите бонус себе после его первого заказа!', style: TextStyle(fontSize: 13, color: Colors.brown)),
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
                              Share.share('Привет! Скачай приложение M-Service для ремонта техники и введи мой код $refCode, чтобы получить стартовый бонус на ремонт!');
                            },
                            child: const Text('Отправить'),
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
                stream: FirebaseFirestore.instance.collection('orders').where('phone', isEqualTo: _phone).where('has_unread_update', isEqualTo: true).snapshots(),
                builder: (context, snapshot) {
                  int unreadCount = snapshot.hasData ? snapshot.data!.docs.length : 0;
                  return Badge(
                    isLabelVisible: unreadCount > 0, label: Text(unreadCount.toString()), offset: const Offset(-4, -4),
                    child: _buildMenuCard(title: 'Мои заказы', subtitle: 'История ремонтов и статусы', icon: Icons.list_alt, iconColor: Colors.blueGrey[700]!, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const MyOrdersScreen()))),
                  );
                },
              ),
              const SizedBox(height: 16),
              _buildMenuCard(title: 'Служба поддержки', subtitle: 'Связь с администратором', icon: Icons.headset_mic, iconColor: Colors.teal[700]!, onTap: _callAdmin),
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
            leading: CircleAvatar(backgroundColor: iconColor.withOpacity(0.1), child: Icon(icon, color: iconColor)),
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
    if (_phone == null || _isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 0,
        title: Text(_currentIndex == 0 ? 'M-Service' : 'Профиль', style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w900, fontSize: 24)),
        actions: [if (_currentIndex == 1) IconButton(icon: const Icon(Icons.logout, color: Colors.red), onPressed: _logout, tooltip: 'Выйти')],
      ),
      body: IndexedStack(index: _currentIndex, children: [_buildHomeTab(), _buildProfileTab()]),
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

