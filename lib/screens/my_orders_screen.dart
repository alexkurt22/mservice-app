import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MyOrdersScreen extends StatefulWidget {
  const MyOrdersScreen({super.key});

  @override
  State<MyOrdersScreen> createState() => _MyOrdersScreenState();
}

class _MyOrdersScreenState extends State<MyOrdersScreen> {
  String _phone = '';

  @override
  void initState() {
    super.initState();
    _loadPhoneAndClearBadges();
  }

  Future<void> _loadPhoneAndClearBadges() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _phone = prefs.getString('phone') ?? '';
    });
    if (_phone.isNotEmpty) {
      await _clearBadges();
    }
  }

  Future<void> _clearBadges() async {
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
      debugPrint('Ошибка при очистке бейджей: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Мои ремонты'),
      ),
      body: _phone.isEmpty
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

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(
                    child: Text(
                      'У вас пока нет заявок на ремонт',
                      style: TextStyle(fontSize: 16),
                    ),
                  );
                }

                // Извлекаем и сортируем документы
                final docs = snapshot.data!.docs.toList();
                
                docs.sort((a, b) {
                  final dataA = a.data() as Map<String, dynamic>;
                  final dataB = b.data() as Map<String, dynamic>;
                  
                  final statusA = dataA['status'] ?? '';
                  final statusB = dataB['status'] ?? '';
                  
                  // Высший приоритет у awaiting_approval
                  if (statusA == 'awaiting_approval' && statusB != 'awaiting_approval') {
                    return -1; // a выше b
                  } else if (statusA != 'awaiting_approval' && statusB == 'awaiting_approval') {
                    return 1; // b выше a
                  }
                  
                  // Сортировка по дате создания (по убыванию, от новых к старым)
                  final tsA = dataA['created_at'] as Timestamp?;
                  final tsB = dataB['created_at'] as Timestamp?;
                  
                  if (tsA == null && tsB == null) return 0;
                  if (tsA == null) return 1; // null (еще не записано на сервере) уходит вниз или вверх на ваше усмотрение
                  if (tsB == null) return -1;
                  
                  return tsB.compareTo(tsA);
                });

                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final data = doc.data() as Map<String, dynamic>;
                    final status = data['status'];
                    final adminComment = data['admin_comment'] ?? 'Нет данных';
                    final price = data['price'] ?? '0';
                    final problem = data['problem'] ?? 'Без описания';
                    final deviceType = data['device_type'] ?? 'Устройство';

                    if (status == 'awaiting_approval') {
                      return Card(
                        color: Colors.orange.shade100,
                        margin: const EdgeInsets.only(bottom: 12),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '$deviceType: $problem', 
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                '⚠️ Требуется согласование!', 
                                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red, fontSize: 16),
                              ),
                              const SizedBox(height: 8),
                              Text('Диагноз мастера: $adminComment'),
                              const SizedBox(height: 4),
                              Text(
                                'Стоимость ремонта: $price руб.', 
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Expanded(
                                    child: ElevatedButton(
                                      style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                                      onPressed: () async {
                                        await doc.reference.update({'status': 'in_progress'});
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(content: Text('Вы успешно согласовали ремонт!')),
                                          );
                                        }
                                      },
                                      child: const Text('Согласиться', style: TextStyle(color: Colors.white)),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: ElevatedButton(
                                      style: ElevatedButton.styleFrom(backgroundColor: Colors.grey.shade400),
                                      onPressed: () async {
                                        await doc.reference.update({'status': 'canceled'});
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(content: Text('Ремонт отменен')),
                                          );
                                        }
                                      },
                                      child: const Text('Отказаться', style: TextStyle(color: Colors.black87)),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    }

                    Color badgeColor = Colors.grey;
                    String statusText = 'Неизвестно';

                    if (status == 'new') {
                      badgeColor = Colors.grey.shade300;
                      statusText = 'Ожидает диагностики';
                    } else if (status == 'in_progress') {
                      badgeColor = Colors.blue.shade200;
                      statusText = 'В работе (Ремонтируется)';
                    } else if (status == 'completed') {
                      badgeColor = Colors.green.shade300;
                      statusText = 'Готово к выдаче! 🎉';
                    } else if (status == 'canceled') {
                      badgeColor = Colors.red.shade200;
                      statusText = 'Отменен';
                    }

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$deviceType: $problem', 
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: badgeColor,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'Статус: $statusText', 
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                            if (status == 'in_progress' || status == 'completed') ...[
                              const SizedBox(height: 12),
                              Text('Диагноз мастера: $adminComment'),
                              const SizedBox(height: 4),
                              Text(
                                'Стоимость ремонта: $price руб.', 
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                              ),
                            ],
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
}
