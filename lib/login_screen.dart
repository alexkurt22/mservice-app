import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
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

  // --- ГОСТЕВОЙ ЧАТ ДЛЯ НЕЗАРЕГИСТРИРОВАННЫХ ПОЛЬЗОВАТЕЛЕЙ ---
  Future<void> _openGuestChat() async {
    final prefs = await SharedPreferences.getInstance();
    String? guestId = prefs.getString('guest_id');
    if (guestId == null) {
      guestId = 'guest_${DateTime.now().millisecondsSinceEpoch}';
      await prefs.setString('guest_id', guestId);
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        final chatController = TextEditingController();
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.75,
            child: Column(
              children:, 
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(20))
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children:,
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      )
                    ],
                  ),
                ),
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                       .collection('guest_chats')
                       .doc(guestId)
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
                            child: Text('Опишите вашу проблему, и администратор ответит вам здесь.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
                          )
                        );
                      }
                      return ListView.builder(
                        reverse: true,
                        padding: const EdgeInsets.all(16),
                        itemCount: docs.length,
                        itemBuilder: (context, index) {
                          final data = docs[index].data() as Map<String, dynamic>;
                          final isMe = data['sender'] == 'guest';
                          return Align(
                            alignment: isMe? Alignment.centerRight : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: isMe? Colors.blueGrey : Colors.orange,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(data['text']?? '', style: const TextStyle(fontSize: 15)),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Row(
                    children:,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      CircleAvatar(
                        backgroundColor: Colors.blueGrey,
                        child: IconButton(
                          icon: const Icon(Icons.send, color: Colors.white, size: 20),
                          onPressed: () async {
                            if (chatController.text.trim().isEmpty) return;
                            final msg = chatController.text.trim();
                            chatController.clear();
                            
                            await FirebaseFirestore.instance.collection('guest_chats').doc(guestId).set({
                              'last_message': msg,
                              'updated_at': FieldValue.serverTimestamp(),
                              'is_resolved': false,
                            }, SetOptions(merge: true));
                            
                            await FirebaseFirestore.instance.collection('guest_chats').doc(guestId).collection('messages').add({
                              'text': msg,
                              'sender': 'guest',
                              'created_at': FieldValue.serverTimestamp(),
                            });
                          },
                        ),
                      )
                    ],
                  ),
                )
              ],
            ),
          ),
        );
      }
    );
  }

  // --- ДИАЛОГ ВОССТАНОВЛЕНИЯ ПАРОЛЯ ---
  void _showForgotPasswordDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Восстановление доступа', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text('Для сброса пароля или изменения данных свяжитесь с администратором сервиса.'),
        actions:),
            icon: const Icon(Icons.phone, color: Colors.white, size: 18),
            label: const Text('Позвонить', style: TextStyle(color: Colors.white)),
            onPressed: () async {
              final url = Uri.parse('tel:+99363644925');
              if (await canLaunchUrl(url)) await launchUrl(url);
            },
          ),
        ],
      ),
    );
  }

  // --- ЛОГИКА ЗАХВАТА ОЖИДАЮЩИХ БОНУСОВ ---
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
        final amount = data['amount'] as int??? 0;
        final senderPhone = data['sender_phone']?? 'Друг';
        
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
          content: Text('Вам зачислено $totalBonus подарочных бонусов от друзей! 🎉'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 5),
        ));
      }
    } catch (e) {
      debugPrint('Ошибка при начислении ожидающих бонусов: $e');
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
      if (rawPhone.length!= 8 ||!validPrefixes.any((p) => rawPhone.startsWith(p))) {
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
              await prefs.setString('client_name', data['name']?? 'Клиент');
              
              await _capturePendingBonuses(fullPhone);

              if (mounted) {
                Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => HomeScreen()));
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
        if (password!= confirm) {
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

        final String generatedCode = (Random().nextInt(9000) + 1000).toString();

        // 🔥 ИСПРАВЛЕНИЕ: НАЧИСЛЯЕМ ПРИВЕТСТВЕННЫЕ БОНУСЫ СРАЗУ ПРИ РЕГИСТРАЦИИ 🔥
        await FirebaseFirestore.instance.collection('clients').doc(fullPhone).set({
          'name': name,
          'phone': fullPhone,
          'password': password,
          'created_at': FieldValue.serverTimestamp(),
          'is_approved': false,
          'sms_code': generatedCode,
          'rejection_reason': null,
          'bonus_points': 10, // Начисляем 10 бонусов
        });

        await FirebaseFirestore.instance.collection('clients').doc(fullPhone).collection('bonus_history').add({
          'amount': 10,
          'description': 'Приветственный бонус за регистрацию',
          'created_at': FieldValue.serverTimestamp(),
        });

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
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
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

  Widget _buildVerificationScreen() {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('clients').doc(_currentCheckingPhone).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        
        final data = snapshot.data!.data() as Map<String, dynamic>?;
        if (data == null) return const Center(child: Text('Ошибка данных'));

        final bool isApproved = data['is_approved']?? false;
        final String? rejectionReason = data['rejection_reason'];
        final String smsCode = data['sms_code']?? '';

        return SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children:, padding: const EdgeInsets.symmetric(vertical: 16)),
                      onPressed: () async {
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setString('phone', _currentCheckingPhone!);
                        await prefs.setString('client_name', data['name']?? 'Клиент');
                        
                        await _capturePendingBonuses(_currentCheckingPhone!);

                        if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => HomeScreen()));
                      },
                      child: const Text('ДАЛЕЕ', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                    ),
                  ] 
                  else if (rejectionReason!= null && rejectionReason.isNotEmpty)..., padding: const EdgeInsets.symmetric(vertical: 16)),
                      onPressed: () => setState(() => _currentCheckingPhone = null),
                      child: const Text('ИЗМЕНИТЬ НОМЕР ТЕЛЕФОНА', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ] 
                  else...,
                      ),
                    ),
                    const SizedBox(height: 32),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey, padding: const EdgeInsets.symmetric(vertical: 16)),
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
    if (_currentCheckingPhone!= null) {
      return Scaffold(
        backgroundColor: Colors.white, 
        body: _buildVerificationScreen(),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _openGuestChat,
          backgroundColor: Colors.orange,
          icon: const Icon(Icons.help_outline, color: Colors.white),
          label: const Text('Помощь', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.business_center, size: 48, color: Colors.blueGrey),
                const SizedBox(height: 16),
                Text(
                  'M-SERVICE',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Colors.blueGrey, letterSpacing: 1.5),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  _isLogin? 'ВХОД В СИСТЕМУ' : 'РЕГИСТРАЦИЯ',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1.0),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 48),

                if (!_isLogin)...,

                _buildTextField(_phoneController, 'Номер телефона', Icons.phone, keyboardType: TextInputType.phone, prefixText: '+993 ', maxLength: 8),
                const SizedBox(height: 16),

                _buildTextField(_passwordController, 'Пароль', Icons.lock, obscureText: true, hintText: 'Минимум 6 символов'),
                const SizedBox(height: 16),

                if (!_isLogin)...,

                if (_isLogin)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _showForgotPasswordDialog,
                      child: Text('Забыли пароль?', style: TextStyle(color: Colors.blueGrey)),
                    ),
                  ),

                SizedBox(height: _isLogin? 16 : 32),

                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueGrey,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    elevation: 0,
                  ),
                  onPressed: _isLoading? null : _submit,
                  child: _isLoading 
                     ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) 
                      : Text(_isLogin? 'ВОЙТИ' : 'ОТПРАВИТЬ', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
                ),
                const SizedBox(height: 24),

                TextButton(
                  onPressed: () {
                    setState(() {
                      _isLogin =!_isLogin;
                      _phoneController.clear();
                      _passwordController.clear();
                      _nameController.clear();
                      _confirmPasswordController.clear();
                    });
                  },
                  child: Text(
                    _isLogin? 'Нет аккаунта? Создать' : 'Уже есть аккаунт? Войти',
                    style: TextStyle(color: Colors.blueGrey, fontSize: 15),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openGuestChat,
        backgroundColor: Colors.orange,
        icon: const Icon(Icons.help_outline, color: Colors.white),
        label: const Text('Помощь', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String label, IconData icon, {bool obscureText = false, TextInputType? keyboardType, String? prefixText, String? hintText, int? maxLength}) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      maxLength: maxLength,
      inputFormatters: keyboardType == TextInputType.phone? : null,
      style: const TextStyle(fontSize: 16),
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
        prefixText: prefixText,
        counterText: '',
        prefixStyle: const TextStyle(fontSize: 16, color: Colors.black87),
        prefixIcon: Icon(icon, color: Colors.blueGrey),
        filled: true,
        fillColor: Colors.grey,
        contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.blueGrey)),
      ),
    );
  }
}
