import 'package:flutter/material.dart';
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

  Future<void> _submit() async {
    setState(() => _isLoading = true);
    FocusScope.of(context).unfocus(); // Скрываем клавиатуру

    try {
      final phone = _phoneController.text.trim();
      final password = _passwordController.text.trim();

      if (phone.isEmpty || password.isEmpty) {
        _showError('Заполните все обязательные поля');
        setState(() => _isLoading = false);
        return;
      }

      // Возвращаем наш железный префикс
      final fullPhone = '+993$phone';

      if (_isLogin) {
        // --- ЛОГИКА ВХОДА ---
        final doc = await FirebaseFirestore.instance.collection('clients').doc(fullPhone).get();
        if (doc.exists) {
          final data = doc.data() as Map<String, dynamic>;
          if (data['password'].toString() == password) {
            
            // Сохраняем данные в память телефона
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('phone', fullPhone);
            await prefs.setString('client_name', data['name'] ?? 'Клиент');
            
            if (mounted) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => HomeScreen()),
              );
            }
          } else {
            _showError('Неверный пароль');
          }
        } else {
          _showError('Пользователь с таким номером не найден');
        }
      } else {
        // --- ЛОГИКА РЕГИСТРАЦИИ ---
        final name = _nameController.text.trim();
        final confirm = _confirmPasswordController.text.trim();

        if (name.isEmpty || confirm.isEmpty) {
          _showError('Заполните все поля для регистрации');
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
          _showError('Пользователь с таким номером уже зарегистрирован');
        } else {
          // Создаем нового пользователя
          await FirebaseFirestore.instance.collection('clients').doc(fullPhone).set({
            'name': name,
            'phone': fullPhone,
            'password': password,
            'created_at': FieldValue.serverTimestamp(),
          });

          // Сохраняем в память
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('phone', fullPhone);
          await prefs.setString('client_name', name);

          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => HomeScreen()),
            );
          }
        }
      }
    } catch (e) {
      _showError('Системная ошибка: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: TextStyle(color: Colors.white, fontSize: 16)),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50], // Приятный фон
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(Icons.computer, size: 64, color: Colors.blueAccent),
                    SizedBox(height: 24),
                    Text(
                      _isLogin ? 'Вход в систему' : 'Регистрация',
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: 32),
                    
                    // ПОЛЕ: ИМЯ (Только при регистрации)
                    if (!_isLogin) ...[
                      TextField(
                        controller: _nameController,
                        decoration: InputDecoration(
                          labelText: 'Ваше имя',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          prefixIcon: Icon(Icons.person),
                        ),
                      ),
                      SizedBox(height: 16),
                    ],

                    // ПОЛЕ: ТЕЛЕФОН
                    TextField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        labelText: 'Номер телефона',
                        prefixText: '+993 ', // ВЕРНУЛИ ПРЕФИКС!
                        prefixStyle: TextStyle(fontSize: 16, color: Colors.black87),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        prefixIcon: Icon(Icons.phone),
                      ),
                    ),
                    SizedBox(height: 16),

                    // ПОЛЕ: ПАРОЛЬ
                    TextField(
                      controller: _passwordController,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: 'Пароль',
                        hintText: 'Минимум 6 символов',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        prefixIcon: Icon(Icons.lock),
                      ),
                    ),
                    SizedBox(height: 16),

                    // ПОЛЕ: ПОВТОР ПАРОЛЯ (Только при регистрации)
                    if (!_isLogin) ...[
                      TextField(
                        controller: _confirmPasswordController,
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: 'Повторите пароль',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          prefixIcon: Icon(Icons.lock_outline),
                        ),
                      ),
                    ],

                    // КНОПКА ЗАБЫЛИ ПАРОЛЬ
                    if (_isLogin)
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () async {
                            final url = Uri.parse('tel:+99360000000'); // Позже впишем твой номер
                            if (await canLaunchUrl(url)) {
                              await launchUrl(url);
                            }
                          },
                          child: Text('Забыли пароль?'),
                        ),
                      ),
                    
                    SizedBox(height: _isLogin ? 8 : 24),

                    // ГЛАВНАЯ КНОПКА
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        textStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      onPressed: _isLoading ? null : _submit,
                      child: _isLoading 
                          ? SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) 
                          : Text(_isLogin ? 'Войти' : 'Зарегистрироваться'),
                    ),
                    SizedBox(height: 16),

                    // ПЕРЕКЛЮЧАТЕЛЬ ВХОД/РЕГИСТРАЦИЯ
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
                        _isLogin 
                          ? 'Нет аккаунта? Зарегистрироваться' 
                          : 'Уже есть аккаунт? Войти',
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
