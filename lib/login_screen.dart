import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isLogin = true;
  bool _isLoading = false;

  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  String? _currentCheckingPhone;

  // --- ЛОГИКА ЗАХВАТА ОЖИДАЮЩИХ БАЛЛОВ ---
  Future<void> _capturePendingBonuses(String phone) async {
    try {
      final db = FirebaseFirestore.instance;
      final pendingSnapshot = await db
          .collection('bonus_transactions')
          .where('recipient_phone', isEqualTo: phone)
          .where('status', isEqualTo: 'pending')
          .get();

      if (pendingSnapshot.docs.isEmpty) return; 

      int totalBonus = 0;
      final batch = db.batch();
      final clientRef = db.collection('clients').doc(phone);

      for (var doc in pendingSnapshot.docs) {
        final data = doc.data();
        final amount = data['amount'] as int? ?? 0;
        final senderPhone = data['sender_phone'] ?? 'Друг';
        
        totalBonus += amount;

        batch.update(doc.reference, {'status': 'completed'});

        final historyRef = clientRef.collection('bonus_history').doc();
        batch.set(historyRef, {
          'amount': amount,
          'description': 'Подарок от $senderPhone',
          'created_at': FieldValue.serverTimestamp(),
        });
      }

      batch.set(clientRef, {
        'bonus_points': FieldValue.increment(totalBonus)
      }, SetOptions(merge: true));

      await batch.commit();

      if (mounted && totalBonus > 0) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Вам зачислено $totalBonus подарочных баллов от друзей! 🎉'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 5),
        ));
      }
    } catch (e) {
      debugPrint('Ошибка при начислении ожидающих баллов: $e');
    }
  }

  Future<void> _submit() async {
    setState(() => _isLoading = true);
    FocusScope.of(context).unfocus();

    try {
      final rawPhone = _phoneController.text.trim().replaceAll(' ', '');
      final password = _passwordController.text.trim();

      if (rawPhone.isEmpty || password.isEmpty) {
        _showError('Заполните все обязательные поля');
        setState(() => _isLoading = false);
        return;
      }

      final validPrefixes = ['60', '61', '62', '63', '64', '65', '71', '72'];
      if (rawPhone.length != 8 || !validPrefixes.any((p) => rawPhone.startsWith(p))) {
        _showError('Введите 8 цифр корректного номера (коды: 60-65, 71, 72)');
        setState(() => _isLoading = false);
        return;
      }

      final fullPhone = '+993$rawPhone';

      if (_isLogin) {
        final doc = await FirebaseFirestore.instance.collection('clients').doc(fullPhone).get();
        if (doc.exists) {
          final data = doc.data() as Map<String, dynamic>;
          if (data['password'].toString() == password) {
            if (data['is_approved'] == true) {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('phone', fullPhone);
              await prefs.setString('client_name', data['name'] ?? 'Клиент');
              
              await _capturePendingBonuses(fullPhone);

              if (mounted) {
                Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomeScreen()));
              }
            } else {
              setState(() {
                _currentCheckingPhone = fullPhone;
              });
            }
          } else {
            _showError('Неверный пароль');
          }
        } else {
          _showError('Пользователь не найден');
        }
      } else {
        final name = _nameController.text.trim();
        final confirm = _confirmPasswordController.text.trim();

        if (name.isEmpty || confirm.isEmpty) {
          _showError('Заполните все поля');
          setState(() => _isLoading = false);
          return;
        }
        if (password != confirm) {
          _showError('Пароли не совпадают!');
          setState(() => _isLoading = false);
          return;
        }
        if (password.length < 6) {
          _showError('Пароль должен содержать минимум 6 символов');
          setState(() => _isLoading = false);
          return;
        }

        final doc = await FirebaseFirestore.instance.collection('clients').doc(fullPhone).get();
        
        if (doc.exists) {
          final data = doc.data() as Map<String, dynamic>;
          if (data['is_approved'] == true || data['rejection_reason'] == null) {
             _showError('Пользователь уже зарегистрирован или ожидает подтверждения');
             setState(() => _isLoading = false);
             return;
          }
        }

        int welcomeBonus = 10; 
        try {
          final loyaltyDoc = await FirebaseFirestore.instance
              .collection('settings')
              .doc('loyalty')
              .get();
              
          if (loyaltyDoc.exists && loyaltyDoc.data() != null) {
            final data = loyaltyDoc.data()!;
            if (data.containsKey('welcome_points')) {
              welcomeBonus = (data['welcome_points'] as num).toInt();
            }
          }
        } catch (e) {
          debugPrint('Ошибка при получении бонуса за регистрацию: $e');
        }

        final String generatedCode = (Random().nextInt(9000) + 1000).toString();

        final db = FirebaseFirestore.instance;
        final batch = db.batch();
        final newClientRef = db.collection('clients').doc(fullPhone);

        batch.set(newClientRef, {
          'name': name,
          'phone': fullPhone,
          'password': password,
          'created_at': FieldValue.serverTimestamp(),
          'is_approved': false,
          'sms_code': generatedCode,
          'rejection_reason': null,
          'bonus_points': welcomeBonus, 
        });

        if (welcomeBonus > 0) {
          final historyRef = newClientRef.collection('bonus_history').doc();
          batch.set(historyRef, {
            'amount': welcomeBonus,
            'description': 'Бонус за регистрацию 🎁',
            'created_at': FieldValue.serverTimestamp(),
          });
        }

        await batch.commit();

        setState(() {
          _currentCheckingPhone = fullPhone;
        });
      }
    } catch (e) {
      _showError('Ошибка: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red[800]),
    );
  }

  Future<void> _sendSms(String code) async {
    final Uri smsUri = Uri(
      scheme: 'sms',
      path: '+99363644925',
      queryParameters: <String, String>{
        'body': code,
      },
    );
    if (await canLaunchUrl(smsUri)) {
      await launchUrl(smsUri);
    } else {
      final Uri smsUriFallback = Uri.parse('sms:+99363644925?body=$code');
      if (await canLaunchUrl(smsUriFallback)) {
        await launchUrl(smsUriFallback);
      }
    }
  }

  // --- ИСПРАВЛЕНО: ОКНО "ЗАБЫЛИ ПАРОЛЬ" С ПОДПИСЯМИ ---
  void _showForgotPasswordDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Восстановление пароля', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text('Свяжитесь с администратором удобным для вас способом:'),
        contentPadding: const EdgeInsets.only(top: 16, left: 24, right: 24),
        actionsPadding: const EdgeInsets.all(16),
        actions: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.phone, color: Colors.green),
                title: const Text('Позвонить'),
                onTap: () async {
                  Navigator.pop(ctx);
                  final url = Uri.parse('tel:+99363644925');
                  if (await canLaunchUrl(url)) await launchUrl(url);
                },
              ),
              ListTile(
                leading: const Icon(Icons.sms, color: Colors.blue),
                title: const Text('Написать SMS'),
                onTap: () async {
                  Navigator.pop(ctx);
                  final url = Uri.parse('sms:+99363644925?body=Здравствуйте, я забыл пароль от аккаунта M-Service. Помогите восстановить.');
                  if (await canLaunchUrl(url)) await launchUrl(url);
                },
              ),
              ListTile(
                leading: const Icon(Icons.chat, color: Colors.orange),
                title: const Text('Чат с поддержкой'),
                onTap: () {
                  Navigator.pop(ctx);
                  _openGuestChat();
                },
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.pop(ctx), 
                child: const Text('Отмена', style: TextStyle(color: Colors.grey))
              )
            ],
          )
        ],
      ),
    );
  }

  // --- ИСПРАВЛЕНО: ЛОГИКА ГОСТЕВОГО ЧАТА (ВРЕМЯ УВЕДОМЛЕНИЯ И ЦВЕТ) ---
  void _openGuestChat() {
    final rawPhone = _phoneController.text.trim().replaceAll(' ', '');
    if (rawPhone.length < 8 && _currentCheckingPhone == null) {
       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
         content: Text('Укажите ваш номер в поле логина (8 цифр), чтобы мы знали, кому отвечать в чате 🤝', style: TextStyle(fontSize: 15)),
         backgroundColor: Colors.blueGrey,
         duration: Duration(seconds: 6), // Висит 6 секунд
       ));
       return;
    }
    
    final chatPhone = _currentCheckingPhone ?? '+993$rawPhone';
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          height: MediaQuery.of(context).size.height * 0.75,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))
          ),
          child: GuestChatWidget(phone: chatPhone),
        ),
      ),
    );
  }

  Widget _buildVerificationScreen() {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('clients').doc(_currentCheckingPhone).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        
        final data = snapshot.data!.data() as Map<String, dynamic>?;
        if (data == null) return const Center(child: Text('Ошибка данных'));

        final bool isApproved = data['is_approved'] ?? false;
        final String? rejectionReason = data['rejection_reason'];
        final String smsCode = data['sms_code'] ?? '';
        final int userPoints = data['bonus_points'] ?? 0;

        return SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (isApproved) ...[
                    const Icon(Icons.check_circle, size: 80, color: Colors.green),
                    const SizedBox(height: 24),
                    const Text('Спасибо за регистрацию!', textAlign: TextAlign.center, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    const Text('Ваш аккаунт успешно подтвержден.', textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: Colors.grey)),
                    const SizedBox(height: 32),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.green[700], padding: const EdgeInsets.symmetric(vertical: 16)),
                      onPressed: () async {
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setString('phone', _currentCheckingPhone!);
                        await prefs.setString('client_name', data['name'] ?? 'Клиент');
                        
                        await _capturePendingBonuses(_currentCheckingPhone!);

                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text('Вам начислено $userPoints приветственных баллов 🎁'),
                            backgroundColor: Colors.green[700],
                            behavior: SnackBarBehavior.floating,
                            duration: const Duration(seconds: 4),
                          ));
                          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomeScreen()));
                        }
                      },
                      child: const Text('ДАЛЕЕ', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                    ),
                  ] 
                  else if (rejectionReason != null && rejectionReason.isNotEmpty) ...[
                    const Icon(Icons.cancel, size: 80, color: Colors.red),
                    const SizedBox(height: 24),
                    const Text('Регистрация отклонена', textAlign: TextAlign.center, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.red)),
                    const SizedBox(height: 16),
                    Text('Введены неверные данные.\nПричина: $rejectionReason', textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, color: Colors.black87)),
                    const SizedBox(height: 32),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey[900], padding: const EdgeInsets.symmetric(vertical: 16)),
                      onPressed: () => setState(() => _currentCheckingPhone = null),
                      child: const Text('ИЗМЕНИТЬ НОМЕР ТЕЛЕФОНА', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ] 
                  else ...[
                    const Icon(Icons.mark_email_unread, size: 80, color: Colors.orange),
                    const SizedBox(height: 24),
                    const Text('Подтверждение номера', textAlign: TextAlign.center, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    RichText(
                      textAlign: TextAlign.center,
                      text: TextSpan(
                        style: const TextStyle(fontSize: 16, color: Colors.black87, height: 1.5),
                        children: [
                          const TextSpan(text: 'Для завершения регистрации отправьте SMS с кодом '),
                          TextSpan(text: smsCode, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Colors.blueGrey)),
                          const TextSpan(text: ' на номер администратора.'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey[900], padding: const EdgeInsets.symmetric(vertical: 16)),
                      onPressed: () => _sendSms(smsCode),
                      icon: const Icon(Icons.sms, color: Colors.white),
                      label: const Text('ОТПРАВИТЬ SMS', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(height: 32),
                    const CircularProgressIndicator(color: Colors.orange),
                    const SizedBox(height: 16),
                    const Text('Ожидание подтверждения администратором...', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
                    const SizedBox(height: 32),
                    TextButton(
                      onPressed: () => setState(() => _currentCheckingPhone = null),
                      child: const Text('Вернуться назад', style: TextStyle(color: Colors.grey)),
                    )
                  ]
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_currentCheckingPhone != null) {
      return Scaffold(
        backgroundColor: Colors.white, 
        body: _buildVerificationScreen(),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _openGuestChat,
          backgroundColor: Colors.orange,
          icon: const Icon(Icons.support_agent, color: Colors.white),
          label: const Text('Помощь', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openGuestChat,
        backgroundColor: Colors.orange,
        icon: const Icon(Icons.support_agent, color: Colors.white),
        label: const Text('Помощь', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.business_center, size: 48, color: Colors.blueGrey[900]),
                const SizedBox(height: 16),
                Text(
                  'M-SERVICE',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Colors.blueGrey[900], letterSpacing: 1.5),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  _isLogin ? 'ВХОД В СИСТЕМУ' : 'РЕГИСТРАЦИЯ',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey[500], letterSpacing: 1.0),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 48),

                if (!_isLogin) ...[
                  _buildTextField(_nameController, 'Ваше имя', Icons.person, keyboardType: TextInputType.name),
                  const SizedBox(height: 16),
                ],

                _buildTextField(_phoneController, 'Номер телефона', Icons.phone, keyboardType: TextInputType.phone, prefixText: '+993 ', maxLength: 8),
                const SizedBox(height: 16),

                _buildTextField(_passwordController, 'Пароль', Icons.lock, obscureText: true, hintText: 'Минимум 6 символов'),
                const SizedBox(height: 16),

                if (!_isLogin) ...[
                  _buildTextField(_confirmPasswordController, 'Повторите пароль', Icons.lock_outline, obscureText: true),
                ],

                if (_isLogin)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _showForgotPasswordDialog,
                      child: Text('Забыли пароль?', style: TextStyle(color: Colors.blueGrey[700])),
                    ),
                  ),

                SizedBox(height: _isLogin ? 16 : 32),

                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueGrey[900],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    elevation: 0,
                  ),
                  onPressed: _isLoading ? null : _submit,
                  child: _isLoading 
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) 
                      : Text(_isLogin ? 'ВОЙТИ' : 'ОТПРАВИТЬ', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
                ),
                const SizedBox(height: 24),

                TextButton(
                  onPressed: () {
                    setState(() {
                      _isLogin = !_isLogin;
                      _phoneController.clear();
                      _passwordController.clear();
                      _nameController.clear();
                      _confirmPasswordController.clear();
                    });
                  },
                  child: Text(
                    _isLogin ? 'Нет аккаунта? Создать' : 'Уже есть аккаунт? Войти',
                    style: TextStyle(color: Colors.blueGrey[600], fontSize: 15),
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- ИСПРАВЛЕНО: ПРИНУДИТЕЛЬНАЯ ТЕКСТОВАЯ КЛАВИАТУРА ДЛЯ ИМЕНИ ---
  Widget _buildTextField(TextEditingController controller, String label, IconData icon, {bool obscureText = false, TextInputType? keyboardType, String? prefixText, String? hintText, int? maxLength}) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      maxLength: maxLength,
      textCapitalization: keyboardType == TextInputType.name ? TextCapitalization.words : TextCapitalization.none, // Заставляет открывать буквенную клавиатуру
      inputFormatters: keyboardType == TextInputType.phone ? [FilteringTextInputFormatter.digitsOnly] : null,
      style: const TextStyle(fontSize: 16),
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
        prefixText: prefixText,
        counterText: '',
        prefixStyle: const TextStyle(fontSize: 16, color: Colors.black87),
        prefixIcon: Icon(icon, color: Colors.blueGrey[400]),
        filled: true,
        fillColor: Colors.grey[100],
        contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.blueGrey)),
      ),
    );
  }
}

// --- ВИДЖЕТ ВРЕМЕННОГО ЧАТА ---
class GuestChatWidget extends StatefulWidget {
  final String phone;
  const GuestChatWidget({super.key, required this.phone});

  @override
  _GuestChatWidgetState createState() => _GuestChatWidgetState();
}

class _GuestChatWidgetState extends State<GuestChatWidget> {
  final _msgController = TextEditingController();

  void _sendMessage() async {
    if (_msgController.text.trim().isEmpty) return;
    
    final text = _msgController.text.trim();
    _msgController.clear();
    FocusScope.of(context).unfocus();

    final db = FirebaseFirestore.instance;
    final chatId = 'guest_${widget.phone}';
    final chatRef = db.collection('support_chats').doc(chatId);

    await chatRef.set({
      'phone': widget.phone,
      'is_guest': true,
      'last_message': text,
      'updated_at': FieldValue.serverTimestamp(),
      'has_unread_admin': true,
    }, SetOptions(merge: true));

    await chatRef.collection('messages').add({
      'text': text,
      'sender_id': widget.phone,
      'is_admin': false,
      'created_at': FieldValue.serverTimestamp(),
    });
  }

  @override
  Widget build(BuildContext context) {
    final chatId = 'guest_${widget.phone}';

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.blueGrey[900],
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20))
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.support_agent, color: Colors.white),
                  SizedBox(width: 8),
                  Text('Чат с поддержкой', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white70),
                onPressed: () => Navigator.pop(context),
              )
            ],
          ),
        ),
        
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('support_chats')
                .doc(chatId)
                .collection('messages')
                .orderBy('created_at', descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              final docs = snapshot.data!.docs;
              
              if (docs.isEmpty) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32.0),
                    child: Text('Опишите вашу проблему, и администратор ответит вам в ближайшее время.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
                  ),
                );
              }

              return ListView.builder(
                reverse: true,
                padding: const EdgeInsets.all(16),
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final msg = docs[index].data() as Map<String, dynamic>;
                  final isAdmin = msg['is_admin'] ?? false;
                  
                  return Align(
                    alignment: isAdmin ? Alignment.centerLeft : Alignment.centerRight,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isAdmin ? Colors.grey[200] : Colors.blueGrey[800],
                        borderRadius: BorderRadius.circular(12).copyWith(
                          bottomRight: isAdmin ? const Radius.circular(12) : Radius.zero,
                          bottomLeft: isAdmin ? Radius.zero : const Radius.circular(12),
                        ),
                      ),
                      child: Text(
                        msg['text'] ?? '',
                        style: TextStyle(color: isAdmin ? Colors.black87 : Colors.white),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),

        // --- ИСПРАВЛЕНО: ЗАЩИТА ПОЛЯ ВВОДА ОТ СИСТЕМНЫХ КНОПОК ---
        SafeArea(
          bottom: true,
          child: Container(
            padding: const EdgeInsets.all(8.0),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -5))],
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _msgController,
                    decoration: InputDecoration(
                      hintText: 'Введите сообщение...',
                      filled: true,
                      fillColor: Colors.grey[100],
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                CircleAvatar(
                  backgroundColor: Colors.orange,
                  child: IconButton(
                    icon: const Icon(Icons.send, color: Colors.white, size: 20),
                    onPressed: _sendMessage,
                  ),
                )
              ],
            ),
          ),
        )
      ],
    );
  }
}

