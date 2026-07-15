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
    FocusScope.of(context).unfocus();

    try {
      final phone = _phoneController.text.trim();
      final password = _passwordController.text.trim();

      if (phone.isEmpty || password.isEmpty) {
        _showError('Заполните все обязательные поля');
        setState(() => _isLoading = false);
        return;
      }

      final fullPhone = '+993$phone';

      if (_isLogin) {
        final doc = await FirebaseFirestore.instance.collection('clients').doc(fullPhone).get();
        if (doc.exists) {
          final data = doc.data() as Map<String, dynamic>;
          if (data['password'].toString() == password) {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('phone', fullPhone);
            await prefs.setString('client_name', data['name'] ?? 'Клиент');
            
            if (mounted) {
              Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => HomeScreen()));
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
          _showError('Пользователь уже зарегистрирован');
        } else {
          await FirebaseFirestore.instance.collection('clients').doc(fullPhone).set({
            'name': name,
            'phone': fullPhone,
            'password': password,
            'created_at': FieldValue.serverTimestamp(),
          });

          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('phone', fullPhone);
          await prefs.setString('client_name', name);

          if (mounted) {
            Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => HomeScreen()));
          }
        }
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

  @override
  Widget build(BuildContext context) {
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
                SizedBox(height: 16),
                Text(
                  'M-SERVICE',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Colors.blueGrey[900], letterSpacing: 1.5),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 8),
                Text(
                  _isLogin ? 'ВХОД В СИСТЕМУ' : 'РЕГИСТРАЦИЯ',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey[500], letterSpacing: 1.0),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 48),

                if (!_isLogin) ...[
                  _buildTextField(_nameController, 'Ваше имя', Icons.person),
                  SizedBox(height: 16),
                ],

                _buildTextField(_phoneController, 'Номер телефона', Icons.phone, keyboardType: TextInputType.phone, prefixText: '+993 '),
                SizedBox(height: 16),

                _buildTextField(_passwordController, 'Пароль', Icons.lock, obscureText: true, hintText: 'Минимум 6 символов'),
                SizedBox(height: 16),

                if (!_isLogin) ...[
                  _buildTextField(_confirmPasswordController, 'Повторите пароль', Icons.lock_outline, obscureText: true),
                ],

                if (_isLogin)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () async {
                        final url = Uri.parse('tel:+99360000000');
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
                    padding: EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    elevation: 0,
                  ),
                  onPressed: _isLoading ? null : _submit,
                  child: _isLoading 
                      ? SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) 
                      : Text(_isLogin ? 'ВОЙТИ' : 'ОТПРАВИТЬ', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
                ),
                SizedBox(height: 24),

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

  Widget _buildTextField(TextEditingController controller, String label, IconData icon, {bool obscureText = false, TextInputType? keyboardType, String? prefixText, String? hintText}) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      style: TextStyle(fontSize: 16),
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
        prefixText: prefixText,
        prefixStyle: TextStyle(fontSize: 16, color: Colors.black87),
        prefixIcon: Icon(icon, color: Colors.blueGrey[400]),
        filled: true,
        fillColor: Colors.grey[100],
        contentPadding: EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.blueGrey)),
      ),
    );
  }
}
