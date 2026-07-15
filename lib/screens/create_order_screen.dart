import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CreateOrderScreen extends StatefulWidget {
  @override
  _CreateOrderScreenState createState() => _CreateOrderScreenState();
}

class _CreateOrderScreenState extends State<CreateOrderScreen> {
  final _problemController = TextEditingController();
  String _deviceType = 'Ноутбук';
  String _deliveryMethod = 'Привезу в сервис сам';
  bool _isLoading = false;

  final List<String> _deviceTypes = ['Ноутбук', 'ПК', 'Моноблок', 'Другое'];
  final List<String> _deliveryMethods = ['Привезу в сервис сам', 'Нужен выезд мастера'];

  Future<void> _submitOrder() async {
    final problem = _problemController.text.trim();
    if (problem.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Пожалуйста, опишите проблему')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final phone = prefs.getString('phone');
      final clientName = prefs.getString('client_name') ?? 'Клиент';

      if (phone == null) {
        throw Exception('Номер телефона не найден в памяти');
      }

      await FirebaseFirestore.instance.collection('orders').add({
        'client_name': clientName,
        'phone': phone,
        'device_type': _deviceType,
        'problem': problem,
        'delivery_method': _deliveryMethod,
        'status': 'new',
        'created_at': FieldValue.serverTimestamp(),
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Заявка успешно отправлена!')),
      );
      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка отправки: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Новая заявка')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<String>(
              value: _deviceType,
              decoration: const InputDecoration(
                labelText: 'Тип техники',
                border: OutlineInputBorder(),
              ),
              items: _deviceTypes.map((type) {
                return DropdownMenuItem(
                  value: type,
                  child: Text(type),
                );
              }).toList(),
              onChanged: (val) {
                if (val != null) {
                  setState(() => _deviceType = val);
                }
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _problemController,
              decoration: const InputDecoration(
                labelText: 'Описание проблемы',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            const Text(
              'Способ доставки:',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            ..._deliveryMethods.map((method) {
              return RadioListTile<String>(
                title: Text(method),
                value: method,
                groupValue: _deliveryMethod,
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _deliveryMethod = val);
                  }
                },
              );
            }).toList(),
            const SizedBox(height: 24),
            _isLoading
                ? const Center(child: CircularProgressIndicator())
                : ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      textStyle: const TextStyle(fontSize: 18),
                    ),
                    onPressed: _submitOrder,
                    child: const Text('Отправить заявку'),
                  ),
          ],
        ),
      ),
    );
  }
}
