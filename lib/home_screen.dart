import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';

import 'screens/my_orders_screen.dart';
import 'screens/create_order_screen.dart';
import 'login_screen.dart';
import 'screens/support_chat_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/notifications_screen.dart';
import 'screens/store_screen.dart'; 

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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      barrierDismissible: !forceUpdate,
      builder: (context) {
        return PopScope(
          canPop: !forceUpdate,
          child: AlertDialog(
            backgroundColor: Theme.of(context).cardColor,
            title: Row(children: [Icon(Icons.system_update, color: isDark ? Colors.blue[300] : Colors.blue), const SizedBox(width: 8), Text('Обновление', style: TextStyle(color: isDark ? Colors.white : Colors.black87))]),
            content: Text(forceUpdate ? 'Вышла важная новая версия!' : 'Доступна новая версия приложения.', style: TextStyle(color: isDark ? Colors.white70 : Colors.black54)),
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
      int welcomePoints = 0; 
      try {
        final settings = await FirebaseFirestore.instance.collection('settings').doc('loyalty').get();
        if (settings.exists && settings.data()!.containsKey('welcome_points') && settings.data()!['is_welcome_bonus_enabled'] == true) {
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
        await _addBonusHistory(_phone!, welcomePoints, 'Приветственный бонус 🎁');
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
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const LoginScreen()));
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 24), decoration: BoxDecoration(color: isDark ? Colors.grey[700] : Colors.grey[300], borderRadius: BorderRadius.circular(10))),
                Text('Что вы хотите сделать?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87)),
                const SizedBox(height: 24),
                
                ListTile(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), tileColor: isDark ? Colors.red[900]?.withOpacity(0.3) : Colors.red[50],
                  leading: CircleAvatar(backgroundColor: isDark ? Colors.red[900]?.withOpacity(0.5) : Colors.red[100], child: Icon(Icons.sos, color: isDark ? Colors.red[300] : Colors.red[700])),
                  title: Text('Вызвать мастера / SOS', style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87)),
                  subtitle: Text('Сломалось устройство? Оставьте заявку', style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.black54)),
                  onTap: () { 
                    Navigator.pop(context); 
                    Navigator.push(context, MaterialPageRoute(builder: (context) => const CreateOrderScreen())); 
                  },
                ),
                const SizedBox(height: 12),

                ListTile(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), tileColor: isDark ? Colors.orange[900]?.withOpacity(0.3) : Colors.orange[50],
                  leading: CircleAvatar(backgroundColor: isDark ? Colors.orange[900]?.withOpacity(0.5) : Colors.orange[100], child: Icon(Icons.shopping_bag, color: isDark ? Colors.orange[300] : Colors.orange[700])),
                  title: Text('Магазин техники', style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87)),
                  subtitle: Text('Новые и Б/У устройства', style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.black54)),
                  onTap: () { 
                    Navigator.pop(context); 
                    Navigator.push(context, MaterialPageRoute(builder: (context) => const StoreScreen())); 
                  },
                ),
              ],
            ),
          ),
        );
      }
    );
  }

  void _showReviewDialog(QueryDocumentSnapshot order, Map<String, dynamic> data) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
            backgroundColor: Theme.of(context).cardColor,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text('Оцените работу', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: isDark ? Colors.white : Colors.black87), textAlign: TextAlign.center),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Насколько вы довольны ремонтом?', style: TextStyle(fontSize: 13, color: isDark ? Colors.white70 : Colors.blueGrey)),
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
                  style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                  decoration: InputDecoration(
                    hintText: 'Напишите пару слов...',
                    hintStyle: TextStyle(color: isDark ? Colors.white54 : Colors.black54),
                    filled: true, fillColor: isDark ? Colors.grey[800] : Colors.grey[100],
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 12),
                CheckboxListTile(
                  title: Text('Оставить анонимно', style: TextStyle(fontSize: 13, color: isDark ? Colors.white : Colors.black87)),
                  value: isAnonymous, dense: true, contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading, activeColor: isDark ? Colors.blueGrey[300] : Colors.blueGrey,
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

  // --- ЛОГИКА ЛАЙКОВ ---
  Future<void> _toggleLike(String docId, List<dynamic> likedBy) async {
    if (_phone == null) return;
    
    final docRef = FirebaseFirestore.instance.collection('news_feed').doc(docId);
    if (likedBy.contains(_phone)) {
      await docRef.update({
        'liked_by': FieldValue.arrayRemove([_phone]),
        'likes_count': FieldValue.increment(-1),
      });
    } else {
      await docRef.update({
        'liked_by': FieldValue.arrayUnion([_phone]),
        'likes_count': FieldValue.increment(1),
      });
    }
  }

  // --- ЛОГИКА ОПРОСОВ ---
  Future<void> _voteInPoll(String docId, Map<String, dynamic> pollData, int optionIndex) async {
    if (_phone == null) return;
    List<dynamic> votedUsers = pollData['voted_users'] ?? [];
    if (votedUsers.contains(_phone)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Вы уже проголосовали!')));
      return; 
    }

    List<dynamic> options = pollData['options'];
    options[optionIndex]['votes'] = (options[optionIndex]['votes'] ?? 0) + 1;
    votedUsers.add(_phone);

    await FirebaseFirestore.instance.collection('news_feed').doc(docId).update({
      'poll.options': options,
      'poll.voted_users': votedUsers,
      'poll.total_votes': FieldValue.increment(1),
    });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ваш голос учтен!'), backgroundColor: Colors.green));
  }

  // --- ИСПРАВЛЕННАЯ ЛЕНТА НОВОСТЕЙ (БЕЗ ЖЕСТКИХ ФИЛЬТРОВ БД) ---
  Widget _buildNewsFeed(bool isDark) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('news_feed').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()));
        }
        
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const SizedBox.shrink(); 
        }

        // 1. Получаем все документы
        List<QueryDocumentSnapshot> rawDocs = snapshot.data!.docs;

        // 2. Сортируем локально (новые сверху). Если даты нет, кидаем вниз.
        rawDocs.sort((a, b) {
          final dataA = a.data() as Map<String, dynamic>;
          final dataB = b.data() as Map<String, dynamic>;
          Timestamp? timeA = dataA['created_at'] as Timestamp?;
          Timestamp? timeB = dataB['created_at'] as Timestamp?;
          
          if (timeA == null && timeB == null) return 0;
          if (timeA == null) return 1;
          if (timeB == null) return -1;
          
          return timeB.compareTo(timeA); // descending
        });

        // 3. Фильтруем скрытые (где явно стоит is_active = false)
        final docs = rawDocs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          if (data.containsKey('is_active') && data['is_active'] == false) {
            return false; 
          }
          return true; 
        }).toList();
        
        if (docs.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Text('События и Акции', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isDark ? Colors.white70 : Colors.blueGrey)),
            ),
            const SizedBox(height: 12),
            ...docs.map((doc) {
              final data = doc.data() as Map<String, dynamic>;
              final type = data['type'] ?? 'Новость';
              final title = data['title'] ?? 'Без заголовка';
              final content = data['content'] ?? '';
              final imageBase64 = data['image_base64'];
              
              final allowLikes = data['allow_likes'] ?? true;
              final allowComments = data['allow_comments'] ?? true;
              
              final likesCount = data['likes_count'] ?? 0;
              final likedBy = data['liked_by'] as List<dynamic>? ?? [];
              final isLikedByMe = _phone != null && likedBy.contains(_phone);
              
              final poll = data['poll'] as Map<String, dynamic>?;
              final hasPoll = poll != null;
              final hasVoted = hasPoll && _phone != null && (poll['voted_users'] as List<dynamic>? ?? []).contains(_phone);

              String dateStr = 'Недавно';
              if (data['created_at'] != null) {
                final dt = (data['created_at'] as Timestamp).toDate();
                dateStr = DateFormat('dd.MM').format(dt);
              }

              return Container(
                margin: const EdgeInsets.only(left: 16, right: 16, bottom: 20),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 5))],
                  border: Border.all(color: isDark ? Colors.grey[800]! : Colors.transparent)
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Шапка карточки
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: type == 'Акция' ? Colors.orange[100] : (type == 'Конкурс' ? Colors.pink[100] : Colors.blue[100]),
                              borderRadius: BorderRadius.circular(8)
                            ),
                            child: Text(type, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: type == 'Акция' ? Colors.orange[900] : (type == 'Конкурс' ? Colors.pink[900] : Colors.blue[900]))),
                          ),
                          Text(dateStr, style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                        ],
                      ),
                    ),

                    // Картинка
                    if (imageBase64 != null && imageBase64.toString().isNotEmpty)
                      Image.memory(base64Decode(imageBase64), width: double.infinity, height: 200, fit: BoxFit.cover, errorBuilder: (context, error, stackTrace) => const SizedBox(height: 50, child: Center(child: Text('Ошибка фото')))),
                    
                    // Заголовок и Текст
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87)),
                          const SizedBox(height: 8),
                          Text(content, maxLines: 4, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, height: 1.4, color: isDark ? Colors.grey[300] : Colors.black87)),
                        ],
                      ),
                    ),

                    // ОПРОС
                    if (hasPoll)
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: isDark ? Colors.grey[800] : Colors.grey[100], borderRadius: BorderRadius.circular(12)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(poll['question'] ?? 'Опрос', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: isDark ? Colors.white : Colors.black87)),
                            const SizedBox(height: 12),
                            ...(poll['options'] as List<dynamic>).asMap().entries.map((entry) {
                              int idx = entry.key;
                              Map<String, dynamic> opt = entry.value;
                              int votes = opt['votes'] ?? 0;
                              int total = poll['total_votes'] ?? 0;
                              double percent = total == 0 ? 0 : votes / total;

                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8.0),
                                child: hasVoted
                                  ? Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(opt['text'], style: TextStyle(fontSize: 13, color: isDark ? Colors.white70 : Colors.black87)),
                                            Text('${(percent * 100).toStringAsFixed(1)}%', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        LinearProgressIndicator(value: percent, backgroundColor: Colors.grey[300], color: Colors.deepPurple, borderRadius: BorderRadius.circular(4)),
                                      ],
                                    )
                                  : OutlinedButton(
                                      style: OutlinedButton.styleFrom(
                                        minimumSize: const Size(double.infinity, 40),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                      ),
                                      onPressed: () => _voteInPoll(doc.id, poll, idx),
                                      child: Text(opt['text']),
                                    ),
                              );
                            }).toList(),
                            if (hasVoted)
                              Padding(
                                padding: const EdgeInsets.only(top: 8.0),
                                child: Text('Всего голосов: ${poll['total_votes']}', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                              )
                          ],
                        ),
                      ),

                    // ЛАЙКИ И КОММЕНТАРИИ (ИСПРАВЛЕНО!)
                    Container(
                      decoration: BoxDecoration(border: Border(top: BorderSide(color: isDark ? Colors.grey[800]! : Colors.grey[200]!))),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          if (allowLikes)
                            TextButton.icon(
                              onPressed: () => _toggleLike(doc.id, likedBy),
                              icon: Icon(isLikedByMe ? Icons.favorite : Icons.favorite_border, color: isLikedByMe ? Colors.red : Colors.grey),
                              label: Text('$likesCount', style: TextStyle(color: isLikedByMe ? Colors.red : Colors.grey, fontWeight: FontWeight.bold)),
                            )
                          else
                            const SizedBox.shrink(),

                          if (allowComments)
                            TextButton.icon(
                              onPressed: () {
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Комментарии откроются в следующем обновлении!')));
                              },
                              icon: const Icon(Icons.chat_bubble_outline, color: Colors.blue),
                              label: const Text('Обсудить', style: TextStyle(color: Colors.blue)),
                            )
                          else
                            const SizedBox.shrink(),
                        ],
                      ),
                    )
                  ],
                ),
              );
            }).toList(),
          ],
        );
      },
    );
  }

  Widget _buildReviewsCarousel(bool isDark) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('reviews').where('is_approved', isEqualTo: true).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Column(
            children: [
              Icon(Icons.forum, size: 64, color: isDark ? Colors.grey[700] : Colors.grey[300]),
              const SizedBox(height: 16),
              Text('Здесь будут отзывы', textAlign: TextAlign.center, style: TextStyle(color: isDark ? Colors.white54 : Colors.grey[500], fontSize: 16)),
            ],
          );
        }

        var docs = snapshot.data!.docs;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Text('Отзывы клиентов', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isDark ? Colors.white70 : Colors.blueGrey)),
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
                      color: Theme.of(context).cardColor, 
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: isDark ? Colors.grey[800]! : Colors.grey.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(data['author_name'] ?? 'Клиент', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: isDark ? Colors.white : Colors.black87)),
                            Row(children: List.generate(5, (starIdx) => Icon(starIdx < (data['rating'] ?? 5) ? Icons.star_rounded : Icons.star_border_rounded, color: Colors.orangeAccent, size: 16)))
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(data['device_type'] ?? '', style: TextStyle(color: isDark ? Colors.white54 : Colors.grey[500], fontSize: 11)),
                        const SizedBox(height: 8),
                        Expanded(child: Text(data['text'] ?? '', maxLines: 4, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: isDark ? Colors.white : Colors.black87))),
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

  Widget _buildHomeTab(bool isDark) {
    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.only(bottom: 100), 
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
              
              const SizedBox(height: 24),
              _buildNewsFeed(isDark), // Вызов исправленной ленты

              const SizedBox(height: 40),
              _buildReviewsCarousel(isDark), // Карусель отзывов под лентой
              const SizedBox(height: 40),
          ],
        ),
        if (_phone != null)
          Positioned(
            bottom: 24, 
            right: 16,
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
                  child: FloatingActionButton(
                    heroTag: 'chat_btn', 
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SupportChatScreen())), 
                    backgroundColor: isDark ? Colors.blueGrey[700] : Colors.blueGrey[900], 
                    child: const Icon(Icons.chat, color: Colors.white)
                  ),
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
    
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).cardColor, 
        elevation: 1,
        title: Text(_currentIndex == 0 ? 'M-Service' : 'Профиль', style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.w900, fontSize: 24)),
        actions: [
          IconButton(
            icon: Icon(Icons.notifications_none, color: isDark ? Colors.white : Colors.blueGrey[900]),
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => const NotificationsScreen())); 
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: IndexedStack(
        index: _currentIndex, 
        children: [
          _buildHomeTab(isDark), 
          ProfileScreen(phone: _phone!, maxDiscountPercent: _maxDiscountPercentUI),
        ]
      ),
      
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          boxShadow: [BoxShadow(color: isDark ? Colors.black38 : Colors.black12, blurRadius: 10, offset: const Offset(0, -2))]
        ),
        child: SafeArea( 
          child: SizedBox(
            height: 60,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _currentIndex = 0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.home_filled, color: _currentIndex == 0 ? (isDark ? Colors.blue[300] : Colors.blueGrey[900]) : Colors.grey[500]),
                        Text('Главная', style: TextStyle(fontSize: 10, color: _currentIndex == 0 ? (isDark ? Colors.blue[300] : Colors.blueGrey[900]) : Colors.grey[500], fontWeight: _currentIndex == 0 ? FontWeight.bold : FontWeight.normal)),
                      ]
                    ),
                  ),
                ),
                
                Expanded(
                  child: Center(
                    child: InkWell(
                      onTap: _showCreateActionSheet,
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: isDark ? Colors.blueGrey[700] : Colors.blueGrey[900],
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [BoxShadow(color: (isDark ? Colors.black : Colors.blueGrey).withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 4))]
                        ),
                        child: const Icon(Icons.add, color: Colors.white, size: 28),
                      ),
                    ),
                  ),
                ),

                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _currentIndex = 1),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.person, color: _currentIndex == 1 ? (isDark ? Colors.blue[300] : Colors.blueGrey[900]) : Colors.grey[500]),
                        Text('Профиль', style: TextStyle(fontSize: 10, color: _currentIndex == 1 ? (isDark ? Colors.blue[300] : Colors.blueGrey[900]) : Colors.grey[500], fontWeight: _currentIndex == 1 ? FontWeight.bold : FontWeight.normal)),
                      ]
                    ),
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

