// lib/screens/create_order_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CreateOrderScreen extends StatefulWidget {
  const CreateOrderScreen({super.key});

  @override
  State<CreateOrderScreen> createState() => _CreateOrderScreenState();
}

class _CreateOrderScreenState extends State<CreateOrderScreen> {
  final _formKey = GlobalKey<FormState>();
  String? _deviceType;
  final TextEditingController _problemController = TextEditingController();
  String _deliveryMethod = 'Привезу в сервис сам';
  bool _isLoading = false;

  final List<String> _deviceTypes = ['Ноутбук', 'ПК', 'Моноблок', 'Другое'];

  @override
  void dispose() {
    _problemController.dispose();
    super.dispose();
  }

  Future<void> _submitOrder() async {
    if (!_formKey.currentState!.validate()) return;
    
    if (_deviceType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Пожалуйста, выберите тип техники')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final clientName = prefs.getString('client_name') ?? 'Неизвестный клиент';
      final phone = prefs.getString('phone') ?? 'Номер не указан';

      await FirebaseFirestore.instance.collection('orders').add({
        'client_name': clientName,
        'phone': phone,
        'device_type': _deviceType,
        'problem': _problemController.text.trim(),
        'delivery_method': _deliveryMethod,
        'status': 'new',
        'created_at': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Заявка успешно отправлена!')),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка отправки: $e')),
      );
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Новая заявка'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<String>(
                      decoration: const InputDecoration(
                        labelText: 'Тип техники',
                        border: OutlineInputBorder(),
                      ),
                      value: _deviceType,
                      items: _deviceTypes.map((type) {
                        return DropdownMenuItem(
                          value: type,
                          child: Text(type),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() {
                          _deviceType = value;
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _problemController,
                      decoration: const InputDecoration(
                        labelText: 'Описание проблемы',
                        border: OutlineInputBorder(),
                        alignLabelWithHint: true,
                      ),
                      maxLines: 3,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Пожалуйста, опишите проблему';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Способ доставки',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    RadioListTile<String>(
                      title: const Text('Привезу в сервис сам'),
                      value: 'Привезу в сервис сам',
                      groupValue: _deliveryMethod,
                      onChanged: (value) {
                        setState(() {
                          _deliveryMethod = value!;
                        });
                      },
                    ),
                    RadioListTile<String>(
                      title: const Text('Нужен выезд мастера'),
                      value: 'Нужен выезд мастера',
                      groupValue: _deliveryMethod,
                      onChanged: (value) {
                        setState(() {
                          _deliveryMethod = value!;
                        });
                      },
                    ),
                    const SizedBox(height: 32),
                    ElevatedButton(
                      onPressed: _submitOrder,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        textStyle: const TextStyle(fontSize: 18),
                      ),
                      child: const Text('Отправить заявку'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
