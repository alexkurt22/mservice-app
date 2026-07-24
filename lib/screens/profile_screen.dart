import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'my_orders_screen.dart';
import 'bonus_history_screen.dart';
import '../login_screen.dart'; 
import '../main.dart'; // Подключаем main.dart для доступа к themeNotifier

class ProfileScreen extends StatefulWidget {
  final String phone;
  final int maxDiscountPercent;

  const ProfileScreen({
    Key? key,
    required this.phone,
    required this.maxDiscountPercent,
  }) : super(key: key);

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  
  // --- ЛОГИКА ВЫХОДА С ПОДТВЕРЖДЕНИЕМ ---
  Future<void> _logout() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Theme.of(context).cardColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.logout, color: Colors.redAccent),
              SizedBox(width: 8),
              Text('Выход', style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          content: Text('Вы точно хотите выйти из своего аккаунта?', style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Отмена', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Выйти', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const LoginScreen()),
      (route) => false,
    );
  }

  Future<void> _callAdmin() async {
    final url = Uri.parse('tel:+99363644925');
    if (await canLaunchUrl(url)) await launchUrl(url);
  }

  // --- ЛОГИКА ПЕРЕВОДА БОНУСОВ ---
  void _showTransferDialog(int currentBalance) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final phoneController = TextEditingController(text: '+993');
    final amountController = TextEditingController();
    bool isTransferring = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            backgroundColor: Theme.of(context).cardColor,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text('Поделиться бонусами', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: isDark ? Colors.white : Colors.black87)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Бонусы будут зачислены другу. Если у него нет приложения, они будут "в ожидании" до регистрации.', style: TextStyle(fontSize: 12, color: isDark ? Colors.white54 : Colors.blueGrey)),
                const SizedBox(height: 16),
                TextField(
                  controller: phoneController,
                  keyboardType: TextInputType.phone,
                  style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                  decoration: InputDecoration(
                    labelText: 'Номер телефона (+993...)',
                    labelStyle: TextStyle(color: isDark ? Colors.white54 : Colors.grey[700]),
                    filled: true, fillColor: isDark ? Colors.grey[800] : Colors.grey[100],
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    prefixIcon: Icon(Icons.phone, color: isDark ? Colors.white54 : Colors.grey[600]),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amountController,
                  keyboardType: TextInputType.number,
                  style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                  decoration: InputDecoration(
                    labelText: 'Количество бонусов',
                    labelStyle: TextStyle(color: isDark ? Colors.white54 : Colors.grey[700]),
                    filled: true, fillColor: isDark ? Colors.grey[800] : Colors.grey[100],
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    prefixIcon: const Icon(Icons.stars_rounded, color: Colors.orange),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена', style: TextStyle(color: Colors.grey))),
              isTransferring
                  ? const CircularProgressIndicator()
                  : ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.blue[600]),
                      onPressed: () async {
                        final recipientPhone = phoneController.text.trim();
                        final amount = int.tryParse(amountController.text.trim()) ?? 0;

                        if (recipientPhone.length < 8 || amount <= 0) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Проверьте номер и сумму'), backgroundColor: Colors.red));
                          return;
                        }
                        if (amount > currentBalance) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Недостаточно бонусов'), backgroundColor: Colors.red));
                          return;
                        }
                        if (recipientPhone == widget.phone) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Нельзя отправить бонусы самому себе'), backgroundColor: Colors.red));
                          return;
                        }

                        setStateDialog(() => isTransferring = true);
                        await _processTransaction(recipientPhone, amount, ctx);
                      },
                      child: const Text('Отправить', style: TextStyle(color: Colors.white)),
                    ),
            ],
          );
        }
      ),
    );
  }

  Future<void> _processTransaction(String recipientPhone, int amount, BuildContext dialogContext) async {
    final db = FirebaseFirestore.instance;
    final senderRef = db.collection('clients').doc(widget.phone);
    final recipientRef = db.collection('clients').doc(recipientPhone);
    final transactionRef = db.collection('bonus_transactions').doc();
    final senderHistoryRef = senderRef.collection('bonus_history').doc();

    try {
      String statusText = '';
      bool isPending = false;

      await db.runTransaction((transaction) async {
        final senderDoc = await transaction.get(senderRef);
        final recipientDoc = await transaction.get(recipientRef);
        
        int currentBalance = senderDoc.data()?['bonus_points'] ?? 0;
        if (currentBalance < amount) throw Exception('Недостаточно бонусов');

        transaction.update(senderRef, {'bonus_points': currentBalance - amount});
        transaction.set(senderHistoryRef, {
          'amount': -amount,
          'description': 'Перевод другу: $recipientPhone',
          'created_at': FieldValue.serverTimestamp(),
        });

        if (recipientDoc.exists) {
          int recipientBalance = recipientDoc.data()?['bonus_points'] ?? 0;
          transaction.update(recipientRef, {'bonus_points': recipientBalance + amount});
          
          final recipientHistoryRef = recipientRef.collection('bonus_history').doc();
          transaction.set(recipientHistoryRef, {
            'amount': amount,
            'description': 'Подарок от ${widget.phone}',
            'created_at': FieldValue.serverTimestamp(),
          });

          transaction.set(transactionRef, {
            'sender_phone': widget.phone,
            'recipient_phone': recipientPhone,
            'amount': amount,
            'status': 'completed',
            'type': 'internal',
            'created_at': FieldValue.serverTimestamp(),
          });
          statusText = 'Бонусы успешно переведены!';
        } else {
          isPending = true;
          transaction.set(transactionRef, {
            'sender_phone': widget.phone,
            'recipient_phone': recipientPhone,
            'amount': amount,
            'status': 'pending',
            'type': 'referral',
            'created_at': FieldValue.serverTimestamp(),
          });
          statusText = 'Бонусы заморожены. Друг получит их после скачивания!';
        }
      });

      if (mounted) {
        Navigator.pop(dialogContext); 
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(statusText), backgroundColor: Colors.green));
        
        if (isPending) {
           final smsUrl = Uri.parse('sms:$recipientPhone?body=Я отправил тебе $amount бонусов на ремонт техники! Скачай приложение M-Service, чтобы забрать их.');
           if (await canLaunchUrl(smsUrl)) {
             await launchUrl(smsUrl);
           }
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(dialogContext);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка перевода: $e'), backgroundColor: Colors.red));
      }
    }
  }

  // --- ОКНО ВВОДА ДАННЫХ ПРОФИЛЯ ---
  Future<void> _showProfileForm() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    String? selectedGender;
    DateTime? selectedDate;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            backgroundColor: Theme.of(context).cardColor,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text('Личные данные', style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Укажите данные для получения подарков на День Рождения. Внимание: изменить их позже нельзя!', style: TextStyle(fontSize: 12, color: isDark ? Colors.white54 : Colors.blueGrey)),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  dropdownColor: Theme.of(context).cardColor,
                  style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                  decoration: InputDecoration(
                    labelText: 'Ваш пол', 
                    labelStyle: TextStyle(color: isDark ? Colors.white54 : Colors.grey[700]),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: isDark ? Colors.grey[700]! : Colors.grey[400]!)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12)
                  ),
                  value: selectedGender,
                  items: const [
                    DropdownMenuItem(value: 'Мужской', child: Text('Мужской')),
                    DropdownMenuItem(value: 'Женский', child: Text('Женский')),
                  ],
                  onChanged: (val) => setStateDialog(() => selectedGender = val),
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: DateTime(2000),
                      firstDate: DateTime(1930),
                      lastDate: DateTime.now(),
                    );
                    if (date != null) setStateDialog(() => selectedDate = date);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    decoration: BoxDecoration(
                      border: Border.all(color: isDark ? Colors.grey[700]! : Colors.grey.shade400),
                      borderRadius: BorderRadius.circular(12)
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(selectedDate == null ? 'Дата рождения' : '${selectedDate!.day.toString().padLeft(2,'0')}.${selectedDate!.month.toString().padLeft(2,'0')}.${selectedDate!.year}', style: TextStyle(fontSize: 16, color: selectedDate == null ? (isDark ? Colors.white54 : Colors.grey[600]) : (isDark ? Colors.white : Colors.black87))),
                        Icon(Icons.calendar_today, color: isDark ? Colors.white54 : Colors.blueGrey),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Позже', style: TextStyle(color: Colors.grey))),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue[600]),
                onPressed: (selectedGender != null && selectedDate != null) ? () async {
                  final formattedDate = '${selectedDate!.day.toString().padLeft(2,'0')}.${selectedDate!.month.toString().padLeft(2,'0')}.${selectedDate!.year}';
                  await FirebaseFirestore.instance.collection('clients').doc(widget.phone).set({
                    'gender': selectedGender,
                    'birth_date': formattedDate,
                  }, SetOptions(merge: true));
                  if (mounted) Navigator.pop(ctx);
                } : null,
                child: const Text('Сохранить', style: TextStyle(color: Colors.white)),
              )
            ],
          );
        }
      ),
    );
  }

  // --- ОКНО ПРАВИЛ И ЦЕН ---
  void _showRulesDialog() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.gavel, color: isDark ? Colors.white70 : Colors.blueGrey),
            const SizedBox(width: 8),
            Expanded(child: Text('Правила сервиса', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: isDark ? Colors.white : Colors.black87))),
          ],
        ),
        content: SingleChildScrollView(
          child: Text(
            '1. Бонусная система\n'
            '1 бонус = 1 манат. Бонусами можно оплатить до 30% от стоимости услуг. Бонусы нельзя обменять на наличные.\n\n'
            '2. Сроки и диагностика\n'
            'Диагностика проводится бесплатно при согласии на ремонт. Сроки ремонта зависят от сложности и наличия деталей.\n\n'
            '3. Гарантия\n'
            'Мы предоставляем гарантию на выполненные работы и установленные запчасти. Точный срок гарантии указывается в квитанции.',
            style: TextStyle(fontSize: 14, height: 1.5, color: isDark ? Colors.white70 : Colors.black87),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Понятно', style: TextStyle(color: isDark ? Colors.blue[300] : Colors.blue)),
          ),
        ],
      ),
    );
  }

  // --- ВИДЖЕТ PUNCH-КАРТЫ ---
  Widget _buildPunchCard(int refills, bool isDark) {
    int progress = refills % 5;
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.print, color: isDark ? Colors.white70 : Colors.blueGrey),
                const SizedBox(width: 8),
                Text('Заправка картриджей', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isDark ? Colors.white : Colors.black87)),
              ],
            ),
            const SizedBox(height: 8),
            Text('Каждая 5-я заправка — БЕСПЛАТНО!', style: TextStyle(fontSize: 12, color: isDark ? Colors.white54 : Colors.grey)),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List.generate(5, (index) {
                bool isFilled = index < progress;
                bool isLast = index == 4;
                return Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isFilled ? Colors.orange : (isDark ? Colors.grey[800] : Colors.grey[100]),
                    shape: BoxShape.circle,
                    border: isLast ? Border.all(color: Colors.orange, width: 2) : null,
                  ),
                  child: Center(
                    child: isLast 
                        ? Icon(Icons.card_giftcard, color: isFilled ? Colors.white : Colors.orange, size: 20)
                        : Icon(Icons.check, color: isFilled ? Colors.white : Colors.transparent, size: 20),
                  ),
                );
              }),
            ),
            const SizedBox(height: 12),
            Text('Заправлено: $refills шт.', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isDark ? Colors.white70 : Colors.blueGrey)),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuCard({required String title, required String subtitle, required IconData icon, required Color iconColor, required VoidCallback onTap, required bool isDark}) {
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
            title: Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87)),
            subtitle: Text(subtitle, style: TextStyle(color: isDark ? Colors.white54 : Colors.blueGrey[400], fontSize: 13)),
            trailing: Icon(Icons.arrow_forward_ios, size: 16, color: isDark ? Colors.white24 : Colors.grey),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Получаем текущую тему, чтобы правильно раскрасить элементы
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('clients').doc(widget.phone).snapshots(),
      builder: (context, snapshot) {
        int points = 0;
        int cartridgeRefills = 0;
        String? gender;
        String? birthDate;

        if (snapshot.hasData && snapshot.data!.exists) {
          final data = snapshot.data!.data() as Map<String, dynamic>;
          points = data['bonus_points'] as int? ?? 0;
          cartridgeRefills = data['cartridge_refills'] as int? ?? 0;
          gender = data['gender'] as String?;
          birthDate = data['birth_date'] as String?;
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // КАРТОЧКА БАЛАНСА БОНУСОВ
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
                    const Text('Ваш баланс бонусов:', style: TextStyle(color: Colors.white70, fontSize: 13)),
                    const SizedBox(height: 4),
                    Text('$points бонусов', style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Скидка до ${widget.maxDiscountPercent}%.', style: const TextStyle(color: Colors.white54, fontSize: 11)),
                        Row(
                          children: [
                            GestureDetector(
                              onTap: () => _showTransferDialog(points),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                margin: const EdgeInsets.only(right: 8), 
                                decoration: BoxDecoration(color: Colors.blue[600], borderRadius: BorderRadius.circular(12)),
                                child: const Row(
                                  children: [
                                    Icon(Icons.card_giftcard, color: Colors.white, size: 14),
                                    SizedBox(width: 4),
                                    Text('Перевести', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ),
                            ),
                            GestureDetector(
                              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => BonusHistoryScreen(phone: widget.phone))),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(12)),
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
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // PUNCH-КАРТА (ГЕЙМИФИКАЦИЯ)
              _buildPunchCard(cartridgeRefills, isDark),
              const SizedBox(height: 16),

              // БЛОК ОЖИДАЮЩИХ ПЕРЕВОДОВ (Замороженные бонусы)
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance.collection('bonus_transactions')
                    .where('sender_phone', isEqualTo: widget.phone)
                    .where('status', isEqualTo: 'pending')
                    .snapshots(),
                builder: (context, pendingSnapshot) {
                  if (!pendingSnapshot.hasData || pendingSnapshot.data!.docs.isEmpty) return const SizedBox.shrink();
                  
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Бонусы в пути (Ждут регистрации друга):', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 12)),
                      const SizedBox(height: 8),
                      ...pendingSnapshot.data!.docs.map((doc) {
                        final data = doc.data() as Map<String, dynamic>;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: isDark ? Colors.orange[900]?.withOpacity(0.2) : Colors.orange[50], borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.orange[200]!)),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.access_time_filled, color: Colors.orange, size: 18),
                                  const SizedBox(width: 8),
                                  Text('Для ${data['recipient_phone']}', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: isDark ? Colors.white : Colors.black87)),
                                ],
                              ),
                              Text('${data['amount']} бонусов', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange, fontSize: 14)),
                            ],
                          ),
                        );
                      }).toList(),
                      const SizedBox(height: 16),
                    ],
                  );
                },
              ),

              Text('ЛИЧНЫЕ ДАННЫЕ', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: isDark ? Colors.white70 : Colors.blueGrey, letterSpacing: 1.2)),
              const SizedBox(height: 12),
              
              // РАСШИРЕННЫЙ ПРОФИЛЬ
              if (gender == null || birthDate == null)
                Card(
                  color: isDark ? Colors.orange.withOpacity(0.1) : Colors.orange[50],
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: isDark ? Colors.orange.withOpacity(0.3) : Colors.orange[200]!)),
                  child: ListTile(
                    leading: const Icon(Icons.person_add_alt_1, color: Colors.orange),
                    title: Text('Заполнить профиль', style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87)),
                    subtitle: Text('Укажите ДР для получения подарков', style: TextStyle(fontSize: 12, color: isDark ? Colors.white54 : Colors.black54)),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.orange),
                    onTap: _showProfileForm,
                  ),
                )
              else
                Card(
                  elevation: 1,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Icon(Icons.person, color: isDark ? Colors.white70 : Colors.blueGrey, size: 20),
                            const SizedBox(width: 12),
                            Text('Пол: $gender', style: TextStyle(fontSize: 15, color: isDark ? Colors.white : Colors.black87)),
                            const Spacer(),
                            const Icon(Icons.lock, size: 16, color: Colors.grey), 
                          ],
                        ),
                        Divider(height: 24, color: isDark ? Colors.grey[800] : Colors.grey[200]),
                        Row(
                          children: [
                            Icon(Icons.cake, color: isDark ? Colors.white70 : Colors.blueGrey, size: 20),
                            const SizedBox(width: 12),
                            Text('Дата рождения: $birthDate', style: TextStyle(fontSize: 15, color: isDark ? Colors.white : Colors.black87)),
                            const Spacer(),
                            const Icon(Icons.lock, size: 16, color: Colors.grey), 
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 24),

              Text('МОЙ АККАУНТ', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: isDark ? Colors.white70 : Colors.blueGrey, letterSpacing: 1.2)),
              const SizedBox(height: 12),

              // 🔥 ПЕРЕКЛЮЧАТЕЛЬ ТЁМНОЙ ТЕМЫ 🔥
              Card(
                elevation: 1,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: SwitchListTile(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  title: Text('Тёмная тема', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isDark ? Colors.white : Colors.black87)),
                  subtitle: Text('Внешний вид приложения', style: TextStyle(color: isDark ? Colors.white54 : Colors.blueGrey[400], fontSize: 13)),
                  secondary: CircleAvatar(
                    backgroundColor: isDark ? Colors.blueGrey.withOpacity(0.2) : Colors.orange.withOpacity(0.1),
                    child: Icon(isDark ? Icons.dark_mode : Icons.light_mode, color: isDark ? Colors.blue[300] : Colors.orange),
                  ),
                  value: isDark,
                  activeColor: Colors.blue[300],
                  onChanged: (val) async {
                    // Переключаем глобальную тему и сохраняем настройку
                    themeNotifier.value = val ? ThemeMode.dark : ThemeMode.light;
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setBool('is_dark_theme', val);
                  },
                ),
              ),
              const SizedBox(height: 8),
              
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance.collection('orders').where('phone', isEqualTo: widget.phone).where('has_unread_update', isEqualTo: true).snapshots(),
                builder: (context, snapshot) {
                  int unreadCount = snapshot.hasData ? snapshot.data!.docs.length : 0;
                  return Badge(
                    isLabelVisible: unreadCount > 0, label: Text(unreadCount.toString()), offset: const Offset(-4, -4),
                    child: _buildMenuCard(title: 'Мои заказы', subtitle: 'История ремонтов и статусы', icon: Icons.list_alt, iconColor: Colors.blueGrey[700]!, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const MyOrdersScreen())), isDark: isDark),
                  );
                },
              ),
              const SizedBox(height: 8),
              _buildMenuCard(title: 'Служба поддержки', subtitle: 'Связь с администратором', icon: Icons.headset_mic, iconColor: Colors.teal[700]!, onTap: _callAdmin, isDark: isDark),
              const SizedBox(height: 8),
              
              // КНОПКА ПРАВИЛ И ЦЕН
              _buildMenuCard(title: 'Актуальность цен и правила', subtitle: 'Условия работы и гарантии', icon: Icons.gavel, iconColor: Colors.purple[700]!, onTap: _showRulesDialog, isDark: isDark),
              
              const SizedBox(height: 32),
              Center(
                child: TextButton.icon(
                  onPressed: _logout,
                  icon: const Icon(Icons.logout, color: Colors.redAccent),
                  label: const Text('Выйти из аккаунта', style: TextStyle(color: Colors.redAccent)),
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        );
      },
    );
  }
}

