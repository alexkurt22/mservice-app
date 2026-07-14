// lib/screens/my_orders_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MyOrdersScreen extends StatefulWidget {
  const MyOrdersScreen({Key? key}) : super(key: key);

  @override
  _MyOrdersScreenState createState() => _MyOrdersScreenState();
}

class _MyOrdersScreenState extends State<MyOrdersScreen> {
  String? _phone;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _phone = prefs.getString('phone');
    });
    _clearBadges();
  }

  Future<void> _clearBadges() async {
    if (_phone == null) return;
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('orders')
          .where('phone', isEqualTo: _phone)
          .where('has_unread_update', isEqualTo: true)
          .get();

      for (var doc in snapshot.docs) {
        await doc.reference.update({'has_unread_update': false});
      }
    } catch (e) {
      debugPrint('Error clearing badges: $e');
    }
  }

  Future<void> _updateOrderStatus(String docId, String newStatus, String successMessage) async {
    try {
      await FirebaseFirestore.instance
          .collection('orders')
          .doc(docId)
          .update({'status': newStatus});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(successMessage)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка обновления: $e')),
        );
      }
    }
  }

  Widget _buildOrderCard(Map<String, dynamic> data, String status, String docId) {
    Color cardColor = Colors.white;
    Widget statusContent = const SizedBox();

    final String adminComment = data['admin_comment'] ?? 'Нет комментария';
    final String price = data['price']?.toString() ?? '0';
    final String deviceType = data['device_type'] ?? 'Устройство';
    final String problem = data['problem'] ?? 'Не указана';

    if (status == 'new') {
      cardColor = Colors.grey.shade200;
      statusContent = Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey.shade300,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Text(
          'Статус: Ожидает диагностики',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
        ),
      );
    } else if (status == 'awaiting_approval') {
      cardColor = Colors.orange.shade50;
      statusContent = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.shade200,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              '⚠️ Требуется согласование!',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.deepOrange),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Диагноз мастера: $adminComment',
            style: const TextStyle(fontSize: 15),
          ),
          const SizedBox(height: 8),
          Text(
            'Стоимость ремонта: $price руб.',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: () => _updateOrderStatus(
                    docId,
                    'in_progress',
                    'Вы успешно согласовали ремонт!',
                  ),
                  child: const Text('Согласиться', style: TextStyle(fontSize: 16)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey.shade600,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: () => _updateOrderStatus(
                    docId,
                    'canceled',
                    'Ремонт отменен',
                  ),
                  child: const Text('Отказаться', style: TextStyle(fontSize: 16)),
                ),
              ),
            ],
          ),
        ],
      );
    } else if (status == 'in_progress') {
      cardColor = Colors.blue.shade50;
      statusContent = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.shade200,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'Статус: В работе (Ремонтируется)',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blueAccent),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Диагноз мастера: $adminComment',
            style: const TextStyle(fontSize: 15),
          ),
          const SizedBox(height: 8),
          Text(
            'Стоимость ремонта: $price руб.',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ],
      );
    } else if (status == 'completed') {
      cardColor = Colors.green.shade50;
      statusContent = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.green.shade200,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'Статус: Готово к выдаче! 🎉',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.green),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Итоговая цена: $price руб.',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ],
      );
    } else if (status == 'canceled') {
      cardColor = Colors.red.shade50;
      statusContent = Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.red.shade200,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Text(
          'Статус: Отменен',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.red),
        ),
      );
    }

    return Card(
      color: cardColor,
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              deviceType,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Проблема: $problem',
              style: const TextStyle(fontSize: 15, color: Colors.black87),
            ),
            const Divider(height: 24, thickness: 1),
            statusContent,
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Мои ремонты'),
      ),
      body: _phone == null
          ? const Center(child: CircularProgressIndicator())
          : StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('orders')
                  .where('phone', isEqualTo: _phone)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Text('Произошла ошибка: ${snapshot.error}'),
                  );
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(
                    child: Text(
                      'У вас пока нет заявок на ремонт',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
                    ),
                  );
                }

                final docs = snapshot.data!.docs;

                return ListView.builder(
                  padding: const EdgeInsets.all(16.0),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final data = doc.data() as Map<String, dynamic>;
                    final String status = data['status'] ?? 'new';

                    return _buildOrderCard(data, status, doc.id);
                  },
                );
              },
            ),
    );
  }
}
