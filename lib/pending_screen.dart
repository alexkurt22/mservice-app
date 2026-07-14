import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'home_screen.dart';
import 'register_screen.dart';

class PendingScreen extends StatefulWidget {
  const PendingScreen({super.key});

  @override
  State<PendingScreen> createState() => _PendingScreenState();
}

class _PendingScreenState extends State<PendingScreen> {
  String? _phone;
  bool _handled = false;

  @override
  void initState() {
    super.initState();
    _loadPhone();
  }

  Future<void> _loadPhone() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _phone = prefs.getString('phone');
    });
  }

  Future<void> _sendSms(String authCode) async {
    final Uri smsUri = Uri(
      scheme: 'sms',
      path: '+99360000000',
      queryParameters: <String, String>{
        'body': 'Подтверждение регистрации. Мой код: $authCode',
      },
    );
    if (await canLaunchUrl(smsUri)) {
      await launchUrl(smsUri);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось открыть приложение SMS')),
        );
      }
    }
  }

  void _showRejectedDialog(String reason, Map<String, dynamic> data) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Регистрация отклонена'),
        content: Text('Причина: $reason'),
        actions: [
          TextButton(
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.clear();
              if (context.mounted) {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(
                    builder: (_) => RegisterScreen(
                      initialName: data['client_name'],
                      initialPhone: data['phone'],
                    ),
                  ),
                  (route) => false,
                );
              }
            },
            child: const Text('ОК'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_phone == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Ожидание активации')),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .where('phone', isEqualTo: _phone)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('Ошибка загрузки данных'));
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          final doc = snapshot.data!.docs.first;
          final data = doc.data() as Map<String, dynamic>;
          final status = data['status'] ?? 'pending';
          final authCode = data['auth_code'] ?? '';

          WidgetsBinding.instance.addPostFrameCallback((_) async {
            if (_handled) return;
            if (status == 'approved') {
              _handled = true;
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('status', 'approved');
              if (mounted) {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const HomeScreen()),
                );
              }
            } else if (status == 'rejected') {
              _handled = true;
              _showRejectedDialog(data['rejection_reason'] ?? 'не указана', data);
            }
          });

          return Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Пожалуйста, отправьте SMS с проверочным кодом для активации.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Подтверждение занимает до 1 часа. Если не активировано, повторите отправку.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: () => _sendSms(authCode),
                  child: const Text('Отправить SMS'),
                ),
                const SizedBox(height: 32),
                const Center(child: CircularProgressIndicator()),
              ],
            ),
          );
        },
      ),
    );
  }
}
