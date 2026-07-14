// lib/screens/my_orders_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MyOrdersScreen extends StatefulWidget {
  const MyOrdersScreen({super.key});

  @override
  State<MyOrdersScreen> createState() => _MyOrdersScreenState();
}

class _MyOrdersScreenState extends State<MyOrdersScreen> {
  String _userPhone = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUserPhone();
  }

  Future<void> _loadUserPhone() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _userPhone = prefs.getString('phone') ?? '';
      _isLoading = false;
    });
  }

  Future<void> _updateOrderStatus(String orderId, String status, String message) async {
    try {
      await FirebaseFirestore.instance.collection('orders').doc(orderId).update({
        'status': status,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_userPhone.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Мои ремонты')),
        body: const Center(child: Text('Ошибка: телефон не найден')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Мои ремонты')),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('orders')
            .where('phone', isEqualTo: _userPhone)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Ошибка: ${snapshot.error}'));
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(
              child: Text(
                'У вас пока нет заявок на ремонт',
                style: TextStyle(fontSize: 18, color: Colors.grey),
              ),
            );
          }

          final orders = snapshot.data!.docs;

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: orders.length,
            itemBuilder: (context, index) {
              final doc = orders[index];
              final data = doc.data() as Map<String, dynamic>;
              final orderId = doc.id;
              final status = data['status'] ?? 'new';
              final adminComment = data['admin_comment'] ?? 'Нет комментария';
              final price = data['price'] ?? '0';
              final deviceType = data['device_type'] ?? 'Устройство';
              final problem = data['problem'] ?? 'Описание отсутствует';

              Color cardColor = Theme.of(context).cardColor;
              if (status == 'awaiting_approval') cardColor = Colors.orange.shade50;

              return Card(
                color: cardColor,
                elevation: 3,
                margin: const EdgeInsets.symmetric(vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$deviceType',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text('Проблема: $problem', style: const TextStyle(fontSize: 14)),
                      const Divider(height: 24),
                      _buildStatusBanner(status, adminComment, price),
                      if (status == 'awaiting_approval') ...[
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                                onPressed: () => _updateOrderStatus(orderId, 'in_progress', 'Вы успешно согласовали ремонт!'),
                                child: const Text('Согласиться', style: TextStyle(color: Colors.white)),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.grey.shade400),
                                onPressed: () => _updateOrderStatus(orderId, 'canceled', 'Ремонт отменен'),
                                child: const Text('Отказаться', style: TextStyle(color: Colors.white)),
                              ),
                            ),
                          ],
                        )
                      ]
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildStatusBanner(String status, String adminComment, String price) {
    if (status == 'new') {
      return Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(8)),
        child: const Row(
          children: [
            Icon(Icons.access_time, color: Colors.grey),
            SizedBox(width: 8),
            Expanded(child: Text('Статус: Ожидает диагностики', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w600))),
          ],
        ),
      );
    } else if (status == 'awaiting_approval') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('⚠️ Требуется согласование!', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.deepOrange)),
          const SizedBox(height: 8),
          Text('Диагноз мастера: $adminComment', style: const TextStyle(fontSize: 14)),
          const SizedBox(height: 8),
          Text('Стоимость ремонта: $price руб.', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      );
    } else if (status == 'in_progress') {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.build, color: Colors.blue),
                SizedBox(width: 8),
                Expanded(child: Text('Статус: В работе (Ремонтируется)', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold))),
              ],
            ),
            const SizedBox(height: 8),
            Text('Диагноз: $adminComment', style: const TextStyle(fontSize: 14)),
            const SizedBox(height: 4),
            Text('Согласованная цена: $price руб.', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          ],
        ),
      );
    } else if (status == 'completed') {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(8)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green),
                SizedBox(width: 8),
                Expanded(child: Text('Статус: Готово к выдаче! 🎉', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold))),
              ],
            ),
            const SizedBox(height: 8),
            Text('Итоговая цена: $price руб.', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          ],
        ),
      );
    } else if (status == 'canceled') {
      return Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8)),
        child: const Row(
          children: [
            Icon(Icons.cancel, color: Colors.red),
            SizedBox(width: 8),
            Expanded(child: Text('Статус: Отменен', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600))),
          ],
        ),
      );
    }
    return const SizedBox.shrink();
  }
}
