import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CreateOrderScreen extends StatefulWidget {
  const CreateOrderScreen({super.key});

  @override
  _CreateOrderScreenState createState() => _CreateOrderScreenState();
}

class _CreateOrderScreenState extends State<CreateOrderScreen> {
  final _problemController = TextEditingController();
  
  // --- ДИНАМИЧЕСКИЕ КАТЕГОРИИ ---
  Map<String, List<String>> _categoriesMap = {}; 
  String? _selectedDirection; 
  String? _selectedSubCategory; 
  
  // --- СПОСОБ ОПЛАТЫ ---
  String _selectedPaymentMethod = 'Наличные';
  final List<String> _paymentMethods = [
    'Наличные',
    'Банковская карта',
    'Перечисление',
    'Оплата бонусами'
  ];
  
  bool _isLoadingCategories = true; 
  bool _isLoading = false; 

  @override
  void initState() {
    super.initState();
    _loadCategories(); 
  }

  // Скачиваем структуру из базы
  Future<void> _loadCategories() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('settings').doc('categories_v2').get();
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        Map<String, List<String>> tempMap = {};
        
        data.forEach((key, value) {
          tempMap[key] = List<String>.from(value as List);
        });

        if (tempMap.isNotEmpty && mounted) {
          setState(() {
            _categoriesMap = tempMap;
            _isLoadingCategories = false;
          });
          return;
        }
      }
    } catch (e) {
      debugPrint('Ошибка загрузки категорий: $e');
    }
    
    // Подстраховка на случай отсутствия интернета или пустой базы
    if (mounted) {
      setState(() {
        _categoriesMap = {
          'Компьютерный сервис': ['Смартфон', 'Ноутбук', 'Компьютер (ПК)', 'Другое'],
        };
        _isLoadingCategories = false;
      });
    }
  }

  Future<void> _submitOrder() async {
    if (_selectedDirection == null || _selectedSubCategory == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Пожалуйста, выберите направление и услугу'), backgroundColor: Colors.red),
      );
      return;
    }

    if (_problemController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Пожалуйста, добавьте описание проблемы'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final phone = prefs.getString('phone') ?? 'Неизвестный номер';
      final clientName = prefs.getString('client_name') ?? 'Неизвестный пользователь';

      await FirebaseFirestore.instance.collection('orders').add({
        'client_name': clientName,
        'phone': phone,
        'category': _selectedDirection, 
        'device_type': _selectedSubCategory, 
        'problem': _problemController.text.trim(),
        'payment_method': _selectedPaymentMethod, // Сохраняем способ оплаты
        'status': 'new',
        'created_at': FieldValue.serverTimestamp(),
        'has_unread_update': false,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Заказ отправлен! Ожидайте ответа администратора.'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 4),
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка отправки: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _problemController.dispose();
    super.dispose();
  }

  // --- ВСПОМОГАТЕЛЬНЫЙ ВИДЖЕТ ДЛЯ ИКОНОК ОПЛАТЫ ---
  IconData _getPaymentIcon(String method) {
    if (method.contains('карта')) return Icons.credit_card;
    if (method.contains('Перечисление')) return Icons.account_balance;
    if (method.contains('бонус')) return Icons.stars_rounded;
    return Icons.payments; // Наличные по умолчанию
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100], 
      appBar: AppBar(
        title: const Text('Новый заказ', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.blueGrey[900],
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isLoadingCategories
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  
                  // --- БЛОК 1: ЧТО НУЖНО ПОЧИНИТЬ ---
                  const Text('ЧТО НУЖНО СДЕЛАТЬ?', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.blueGrey, letterSpacing: 1.2)),
                  const SizedBox(height: 12),
                  Card(
                    elevation: 0,
                    // ИСПРАВЛЕНИЕ 1: side: BorderSide вместо border: Border.all
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.grey.shade300)),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          DropdownButtonFormField<String>(
                            value: _selectedDirection,
                            icon: const Icon(Icons.expand_more, color: Colors.blueGrey),
                            decoration: InputDecoration(
                              labelText: 'Направление',
                              prefixIcon: const Icon(Icons.category, color: Colors.blueGrey),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                              filled: true,
                              fillColor: Colors.grey[50],
                            ),
                            hint: const Text('Выберите сферу услуг'),
                            items: _categoriesMap.keys
                                .map<DropdownMenuItem<String>>((String d) => DropdownMenuItem<String>(value: d, child: Text(d)))
                                .toList(),
                            onChanged: (val) {
                              setState(() {
                                _selectedDirection = val;
                                _selectedSubCategory = null; 
                              });
                            },
                          ),
                          const SizedBox(height: 16),
                          DropdownButtonFormField<String>(
                            value: _selectedSubCategory,
                            icon: const Icon(Icons.expand_more, color: Colors.blueGrey),
                            decoration: InputDecoration(
                              labelText: 'Услуга / Устройство',
                              prefixIcon: const Icon(Icons.devices, color: Colors.blueGrey),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                              filled: true,
                              fillColor: _selectedDirection == null ? Colors.grey[200] : Colors.grey[50],
                            ),
                            hint: const Text('Сначала выберите направление'),
                            items: (_selectedDirection != null ? _categoriesMap[_selectedDirection]! : <String>[])
                                .map<DropdownMenuItem<String>>((String d) => DropdownMenuItem<String>(value: d, child: Text(d)))
                                .toList(),
                            onChanged: _selectedDirection == null ? null : (val) => setState(() => _selectedSubCategory = val),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // --- БЛОК 2: ОПИСАНИЕ ПРОБЛЕМЫ ---
                  const SizedBox(height: 24),
                  const Text('ОПИСАНИЕ ПРОБЛЕМЫ', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.blueGrey, letterSpacing: 1.2)),
                  const SizedBox(height: 12),
                  Card(
                    elevation: 0,
                    // ИСПРАВЛЕНИЕ 2: side: BorderSide вместо border: Border.all
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.grey.shade300)),
                    child: Padding(
                      padding: const EdgeInsets.all(4.0),
                      child: TextField(
                        controller: _problemController,
                        maxLines: 4, 
                        decoration: InputDecoration(
                          hintText: 'Опишите проблему или что нужно сделать...\nНапример: Не включается экран, нужно заменить стекло.', 
                          hintStyle: TextStyle(color: Colors.grey[400]),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.all(16),
                        ),
                      ),
                    ),
                  ),

                  // --- БЛОК 3: СПОСОБ ОПЛАТЫ ---
                  const SizedBox(height: 24),
                  const Text('СПОСОБ ОПЛАТЫ', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.blueGrey, letterSpacing: 1.2)),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8.0,
                    runSpacing: 8.0,
                    children: _paymentMethods.map((method) {
                      final isSelected = _selectedPaymentMethod == method;
                      return ChoiceChip(
                        label: Text(method),
                        selected: isSelected,
                        onSelected: (selected) {
                          if (selected) setState(() => _selectedPaymentMethod = method);
                        },
                        avatar: Icon(_getPaymentIcon(method), color: isSelected ? Colors.white : Colors.blueGrey, size: 18),
                        selectedColor: Colors.blueGrey[900],
                        backgroundColor: Colors.white,
                        // ИСПРАВЛЕНИЕ 3: side: BorderSide вместо border: Border.all
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: isSelected ? Colors.blueGrey[900]! : Colors.grey.shade300)),
                        labelStyle: TextStyle(color: isSelected ? Colors.white : Colors.black87, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      );
                    }).toList(),
                  ),
                  
                  const SizedBox(height: 40),
                  
                  // --- КНОПКА ОТПРАВКИ ---
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange[600],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 4,
                    ),
                    onPressed: _isLoading ? null : _submitOrder,
                    child: _isLoading
                        ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
                        : const Text('ОТПРАВИТЬ ЗАЯВКУ', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }
}
