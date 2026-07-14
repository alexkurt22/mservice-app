import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'register_screen.dart';
import 'pending_screen.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _rememberMe = true;
  bool _isLoading = false;

  Future<void> _login() async {
    final phone = _phoneController.text.trim();
    final password = _passwordController.text.trim();

    if (phone.length != 8 || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Введите корректный номер (8 цифр) и пароль')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final query = await FirebaseFirestore.instance
          .collection('users')
          .where('phone', isEqualTo: '+993$phone')
          .where('password', isEqualTo: password)
          .get();

      if (query.docs.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Неверный телефон или пароль')),
          );
        }
        setState(() => _isLoading = false);
        return;
      }

      final userData = query.docs.first.data();
      final status = userData['status'] ?? 'pending';

      if (status == 'rejected') {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Профиль отклонен')),
          );
        }
        setState(() => _isLoading = false);
        return;
      }

      if (_rememberMe) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('phone', '+993$phone');
        await prefs.setString('status', status);
      }

      if (mounted) {
        if (status == 'pending') {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const PendingScreen()),
          );
        } else if (status == 'approved') {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const HomeScreen()),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Вход')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              maxLength: 8,
              decoration: const InputDecoration(
                labelText: 'Телефон',
                prefixText: '+993 ',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Пароль',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Checkbox(
                  value: _rememberMe,
                  onChanged: (val) => setState(() => _rememberMe = val ?? true),
                ),
                const Text('Запомнить меня'),
              ],
            ),
            const SizedBox(height: 16),
            _isLoading
                ? const CircularProgressIndicator()
                : ElevatedButton(
                    onPressed: _login,
                    child: const Text('Войти'),
                  ),
            TextButton(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Обратитесь к администратору: +99360000000'),
                  ),
                );
              },
              child: const Text('Забыли пароль?'),
            ),
            TextButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const RegisterScreen()),
                );
              },
              child: const Text('Зарегистрироваться'),
            ),
          ],
        ),
      ),
    );
  }
}
