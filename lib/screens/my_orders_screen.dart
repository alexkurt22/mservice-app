import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MyOrdersScreen extends StatefulWidget {
  const MyOrdersScreen({super.key});

  @override
  State<MyOrdersScreen> createState() => _MyOrdersScreenState();
}

class _MyOrdersScreenState extends State<MyOrdersScreen> {
  String? _phone;
  final Map<String, int> _selectedOptions = {};

  @override
  void initState() {
    super.initState();
    _loadUserPhone();
  }

  Future<void> _loadUserPhone() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _phone = prefs.getString('phone');
    });
    if (_phone != null) {
      _clearBadges();
    }
  }

  Future<void> _clearBadges() async {
    try {
      final querySnapshot = await FirebaseFirestore.instance
          .collection('orders')
          .where('phone', isEqualTo: _phone)
          .where('has_unread_update', isEqualTo: true)
          .get();

      for (var doc in querySnapshot.docs) {
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

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(
                    child: Text(
                      'У вас пока нет заявок на ремонт',
                      style: TextStyle(fontSize: 16),
                    ),
                  );
                }

                final docs = snapshot.data!.docs.toList();
                
                // Сортировка: awaiting_approval наверх, затем по created_at (по убыванию)
                docs.sort((a, b) {
                  final dataA = a.data() as Map<String, dynamic>;
                  final dataB = b.data() as Map<String, dynamic>;
                  final statusA = dataA['status'] ?? '';
                  final statusB = dataB['status'] ?? '';

                  if (statusA == 'awaiting_approval' && statusB != 'awaiting_approval') return -1;
                  if (statusA != 'awaiting_approval' && statusB == 'awaiting_approval') return 1;

                  final Timestamp? timeA = dataA['created_at'] as Timestamp?;
                  final Timestamp? timeB = dataB['created_at'] as Timestamp?;

                  if (timeA == null && timeB == null) return 0;
                  if (timeA == null) return 1;
                  if (timeB == null) return -1;

                  return timeB.compareTo(timeA);
                });

                return ListView.builder(
                  padding: const EdgeInsets.all(16.0),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final order = docs[index];
                    final data = order.data() as Map<String, dynamic>;
                    final status = data['status'] ?? '';
                    final options = data.containsKey('options') ? data['options'] as List<dynamic> : null;

                    return _buildOrderCard(order, data, status, options);
                  },
                );
              },
            ),
    );
  }

  Widget _buildOrderCard(QueryDocumentSnapshot order, Map<String, dynamic> data, String status, List<dynamic>? options) {
    switch (status) {
      case 'new':
        return Card(
          elevation: 2,
          margin: const EdgeInsets.only(bottom: 16.0),
          color: Colors.grey.shade100,
          child: ListTile(
            title: Text(data['device_type'] ?? 'Устройство', style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                Text('Проблема: ${data['problem']}'),
                const SizedBox(height: 8),
                const Text('Статус: Ожидает диагностики', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        );
      case 'awaiting_approval':
        return Card(
          elevation: 4,
          margin: const EdgeInsets.only(bottom: 16.0),
          color: Colors.orange.shade50,
          shape: RoundedRectangleBorder(
            side: const BorderSide(color: Colors.orange, width: 2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(data['device_type'] ?? 'Устройство', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                const SizedBox(height: 8),
                Text('Проблема: ${data['problem']}'),
                const Divider(),
                const Text('⚠️ Требуется согласование!', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange, fontSize: 16)),
                const SizedBox(height: 8),
                
                if (options != null) ...[
                  const Text('Мастер предложил варианты ремонта. Выберите подходящий:', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  ...options.asMap().entries.map((entry) {
                    final int idx = entry.key;
                    final opt = entry.value as Map<String, dynamic>;
                    return RadioListTile<int>(
                      title: Text(opt['description'] ?? ''),
                      subtitle: Text('${opt['price']} руб.', style: const TextStyle(fontWeight: FontWeight.bold)),
                      value: idx,
                      groupValue: _selectedOptions[order.id],
                      activeColor: Colors.orange,
                      onChanged: (int? value) {
                        setState(() {
                          if (value != null) {
                            _selectedOptions[order.id] = value;
                          }
                        });
                      },
                      contentPadding: EdgeInsets.zero,
                    );
                  }),
                ] else ...[
                  Text('Диагноз мастера: ${data['admin_comment']}'),
                  const SizedBox(height: 8),
                  Text('Стоимость ремонта: ${data['price']} руб.', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ],
                
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                        onPressed: () async {
                          if (options != null) {
                            final selectedIdx = _selectedOptions[order.id];
                            if (selectedIdx == null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Пожалуйста, выберите вариант ремонта!')),
                              );
                              return;
                            }
                            final selectedOption = options[selectedIdx];
                            await order.reference.update({
                              'status': 'in_progress',
                              'price': selectedOption['price'],
                              'admin_comment': selectedOption['description'],
                              'selected_option_index': selectedIdx,
                              'has_unread_update': true,
                            });
                          } else {
                            // Для старых заказов без массива options
                            await order.reference.update({
                              'status': 'in_progress',
                              'has_unread_update': true,
                            });
                          }
                          
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Вы успешно согласовали ремонт!')),
                            );
                          }
                        },
                        child: const Text('Согласиться'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.grey.shade300, foregroundColor: Colors.black87),
                        onPressed: () async {
                          await order.reference.update({
                            'status': 'canceled',
                            'has_unread_update': true,
                          });
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Ремонт отменен')),
                            );
                          }
                        },
                        child: const Text('Отказаться'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      case 'in_progress':
      case 'completed':
        final isCompleted = status == 'completed';
        final color = isCompleted ? Colors.green.shade50 : Colors.blue.shade50;
        final borderColor = isCompleted ? Colors.green : Colors.blue;
        final statusText = isCompleted ? 'Статус: Готово к выдаче! 🎉' : 'Статус: В работе (Ремонтируется)';
        
        return Card(
          elevation: 2,
          margin: const EdgeInsets.only(bottom: 16.0),
          color: color,
          shape: RoundedRectangleBorder(
            side: BorderSide(color: borderColor.withOpacity(0.5), width: 1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(data['device_type'] ?? 'Устройство', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                const SizedBox(height: 8),
                Text('Проблема: ${data['problem']}'),
                const Divider(),
                Text(statusText, style: TextStyle(fontWeight: FontWeight.bold, color: borderColor, fontSize: 16)),
                const SizedBox(height: 8),
                
                if (options != null && data.containsKey('selected_option_index')) ...[
                  const SizedBox(height: 8),
                  const Text('Аудиторский след предложений:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
                  const SizedBox(height: 8),
                  ...options.asMap().entries.map((entry) {
                    final int idx = entry.key;
                    final opt = entry.value as Map<String, dynamic>;
                    final bool isSelected = idx == data['selected_option_index'];
                    
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            isSelected ? Icons.check_circle : Icons.cancel_outlined,
                            color: isSelected ? Colors.green : Colors.grey,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  opt['description'] ?? '',
                                  style: TextStyle(
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                    color: isSelected ? Colors.black87 : Colors.grey,
                                    decoration: isSelected ? TextDecoration.none : TextDecoration.lineThrough,
                                  ),
                                ),
                                Text(
                                  '${opt['price']} руб.',
                                  style: TextStyle(
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                    color: isSelected ? Colors.black87 : Colors.grey,
                                  ),
                                ),
                                if (isSelected)
                                  const Text('Выбранный вариант', style: TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                  if (isCompleted) ...[
                     const Divider(),
                     Text('Итоговая цена: ${data['price']} руб.', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ]
                ] else ...[
                  Text('Диагноз мастера: ${data['admin_comment']}'),
                  const SizedBox(height: 8),
                  Text('Утвержденная цена: ${data['price']} руб.', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ],
              ],
            ),
          ),
        );
      case 'canceled':
        return Card(
          elevation: 2,
          margin: const EdgeInsets.only(bottom: 16.0),
          color: Colors.red.shade50,
          child: ListTile(
            title: Text(data['device_type'] ?? 'Устройство', style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                Text('Проблема: ${data['problem']}'),
                const SizedBox(height: 8),
                const Text('Статус: Отменен', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        );
      default:
        return const SizedBox.shrink();
    }
  }
}
