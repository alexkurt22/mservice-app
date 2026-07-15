// lib/create_order_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CreateOrderScreen extends StatefulWidget {
  const CreateOrderScreen({Key? key}) : super(key: key);

  @override
  State<CreateOrderScreen> createState() => _CreateOrderScreenState();
}

class _CreateOrderScreenState extends State<CreateOrderScreen> {
  final TextEditingController _deviceController = TextEditingController();
  final TextEditingController _problemController = TextEditingController();
  bool _isLoading = false;

  Future<void> _submitOrder() async {
    final device = _deviceController.text.trim();
    final problem = _problemController.text.trim();

    if (device.isEmpty || problem.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Пожалуйста, заполните все поля')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final phone = prefs.getString('phone');
      final clientName = prefs.getString('client_name'); // Достаем имя клиента

      if (phone == null) {
        throw Exception('Ошибка: номер телефона не найден');
      }

      await FirebaseFirestore.instance.collection('orders').add({
        'phone': phone,
        'client_name': clientName ?? 'Клиент', // Добавляем client_name в документ заказа
        'device': device,
        'problem': problem,
        'status': 'new',
        'created_at': FieldValue.serverTimestamp(),
        'has_unread_update': false,
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Заявка успешно создана!')),
      );
      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: ${e.toString()}')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Новая заявка на ремонт')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _deviceController,
              decoration: const InputDecoration(
                labelText: 'Устройство (например, iPhone 12)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _problemController,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Описание проблемы',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            _isLoading
                ? const CircularProgressIndicator()
                : SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _submitOrder,
                      child: const Text('Отправить заявку', style: TextStyle(fontSize: 16)),
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}
