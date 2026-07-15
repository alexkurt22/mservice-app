import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'register_screen.dart';
import 'pending_screen.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _rememberMe = true;
  bool _isLoading = false;

  Future<void> _login() async {
    setState(() => _isLoading = true);
    final phone = _phoneController.text.trim();
    final password = _passwordController.text;

    if (phone.length != 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Введите корректный номер (8 цифр)')),
      );
      setState(() => _isLoading = false);
      return;
    }

    try {
      final query = await FirebaseFirestore.instance
          .collection('users')
          .where('phone', isEqualTo: phone)
          .where('password', isEqualTo: password)
          .get();

      if (query.docs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Неверный телефон или пароль')),
        );
        setState(() => _isLoading = false);
        return;
      }

      final userData = query.docs.first.data();
      final status = userData['status'];
      final clientName = userData['client_name'];

      if (status == 'rejected') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Профиль отклонен: ${userData['rejection_reason'] ?? 'без причины'}')),
        );
        setState(() => _isLoading = false);
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      if (_rememberMe) {
        await prefs.setString('phone', phone);
        await prefs.setString('status', status);
      }
      
      // Обязательно сохраняем имя клиента в SharedPreferences
      if (clientName != null) {
        await prefs.setString('client_name', clientName);
      }

      if (status == 'pending') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => PendingScreen()),
        );
      } else if (status == 'approved') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => HomeScreen()),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e')),
      );
    }
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Вход')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Телефон',
                prefixText: '+993 ',
              ),
              maxLength: 8,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Пароль',
                hintText: 'минимум 6 символов',
              ),
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              title: const Text('Запомнить меня'),
              value: _rememberMe,
              onChanged: (val) => setState(() => _rememberMe = val ?? true),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Обратитесь к администратору: +99360000000')),
                  );
                },
                child: const Text('Забыли пароль?'),
              ),
            ),
            const SizedBox(height: 16),
            _isLoading
                ? const Center(child: CircularProgressIndicator())
                : ElevatedButton(
                    onPressed: _login,
                    style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(16)),
                    child: const Text('Войти', style: TextStyle(fontSize: 16)),
                  ),
            TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => RegisterScreen()),
              ),
              child: const Text('Зарегистрироваться'),
            ),
          ],
        ),
      ),
    );
  }
}
