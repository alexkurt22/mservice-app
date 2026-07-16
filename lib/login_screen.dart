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

        final String generatedCode = (Random().nextInt(9000) + 1000).toString();

        await FirebaseFirestore.instance.collection('clients').doc(fullPhone).set({
          'name': name,
          'phone': fullPhone,
          'password': password,
          'created_at': FieldValue.serverTimestamp(),
          'is_approved': false,
          'sms_code': generatedCode,
          'rejection_reason': null,
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
                        if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => HomeScreen()));
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
      return Scaffold(backgroundColor: Colors.white, body: _buildVerificationScreen());
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
                      onPressed: () async {
                        final url = Uri.parse('tel:+99363644925');
                        if (await canLaunchUrl(url)) await launchUrl(url);
                      },
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
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String label, IconData icon, {bool obscureText = false, TextInputType? keyboardType, String? prefixText, String? hintText, int? maxLength}) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      maxLength: maxLength,
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
