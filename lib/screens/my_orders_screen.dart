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

  // --- НОВЫЙ БЛОК: ОТРИСОВКА ИСТОРИИ ТОРГОВ ---
  Widget _buildHistoryBlock(Map<String, dynamic> data) {
    final history = data['history'] as List<dynamic>?;
    if (history == null || history.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('История предложений:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.blueGrey)),
        const SizedBox(height: 8),
        ...history.asMap().entries.map((entry) {
          int round = entry.key + 1;
          List<dynamic> oldOptions = entry.value['options'] ?? [];
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Раунд $round (Отклонено)', style: TextStyle(color: Colors.red[400], fontWeight: FontWeight.bold, fontSize: 12)),
                const SizedBox(height: 6),
                ...oldOptions.map((opt) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '${opt['description']} — ${opt['price']} TMT',
                    style: const TextStyle(color: Colors.grey, decoration: TextDecoration.lineThrough, fontSize: 13),
                  ),
                )).toList(),
              ],
            ),
          );
        }).toList(),
        const SizedBox(height: 16),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Мои заказы', style: TextStyle(fontSize: 18)),
        backgroundColor: Colors.blueGrey[900],
        foregroundColor: Colors.white,
        elevation: 0,
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
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.inbox_outlined, size: 64, color: Colors.blueGrey[200]),
                        const SizedBox(height: 16),
                        Text(
                          'У вас пока нет активных заказов',
                          style: TextStyle(fontSize: 16, color: Colors.blueGrey[500]),
                        ),
                      ],
                    ),
                  );
                }

                final docs = snapshot.data!.docs.toList();
                
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
          color: Colors.white,
          shape: RoundedRectangleBorder(
            side: BorderSide(color: Colors.grey.shade300, width: 1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(data['device_type'] ?? 'Устройство', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.black87)),
                const SizedBox(height: 8),
                Text('Проблема: ${data['problem']}', style: TextStyle(color: Colors.blueGrey[800])),
                const Divider(height: 24),
                Row(
                  children: [
                    Icon(Icons.hourglass_empty, size: 20, color: Colors.blueGrey[400]),
                    const SizedBox(width: 8),
                    Text('Статус: Ожидает диагностики', style: TextStyle(color: Colors.blueGrey[600], fontWeight: FontWeight.bold)),
                  ],
                ),
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
            side: const BorderSide(color: Colors.orange, width: 1.5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(data['device_type'] ?? 'Устройство', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                const SizedBox(height: 8),
                Text('Проблема: ${data['problem']}'),
                const Divider(height: 24),
                
                _buildHistoryBlock(data), // <-- ДОБАВЛЕН ВЫВОД ИСТОРИИ

                if (options != null) ...[
                  const Text('Мастер предложил варианты ремонта. Выберите подходящий:', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.black87)),
                  const SizedBox(height: 8),
                  ...options.asMap().entries.map((entry) {
                    final int idx = entry.key;
                    final opt = entry.value as Map<String, dynamic>;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: _selectedOptions[order.id] == idx ? Colors.orange : Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: RadioListTile<int>(
                        title: Text(opt['description'] ?? '', style: const TextStyle(fontSize: 15)),
                        subtitle: Text('${opt['price']} TMT', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.deepOrange)),
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
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                    );
                  }),
                ] else ...[
                  Text('Диагноз мастера: ${data['admin_comment']}'),
                  const SizedBox(height: 8),
                  Text('Стоимость ремонта: ${data['price']} TMT', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.deepOrange)),
                ],
                
                const SizedBox(height: 16),
                const Text('Ваше решение:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87)),
                const SizedBox(height: 12),

                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green[600],
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          elevation: 1,
                        ),
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
                            await order.reference.update({
                              'status': 'in_progress',
                              'has_unread_update': true,
                            });
                          }
                          
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Вы успешно согласовали ремонт!'), backgroundColor: Colors.green),
                            );
                          }
                        },
                        icon: const Icon(Icons.check_circle_outline, size: 20),
                        label: const Text('Согласиться', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red[50], // Активный красный фон
                          foregroundColor: Colors.red[700], // Красный текст
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: BorderSide(color: Colors.red.shade200), // Красная окантовка
                          ),
                          elevation: 0,
                        ),
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
                        icon: const Icon(Icons.close_rounded, size: 20),
                        label: const Text('Отказаться', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
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
        final statusText = isCompleted ? 'Статус: Выполнено' : 'Статус: Выполняется';
        final iconStatus = isCompleted ? Icons.check_circle : Icons.handyman;
        
        return Card(
          elevation: 2,
          margin: const EdgeInsets.only(bottom: 16.0),
          color: color,
          shape: RoundedRectangleBorder(
            side: BorderSide(color: borderColor.withOpacity(0.5), width: 1.5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(data['device_type'] ?? 'Устройство', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.black87)),
                const SizedBox(height: 8),
                Text('Проблема: ${data['problem']}', style: TextStyle(color: Colors.blueGrey[800])),
                const Divider(height: 24),
                
                _buildHistoryBlock(data), // <-- ДОБАВЛЕН ВЫВОД ИСТОРИИ

                Row(
                  children: [
                    Icon(iconStatus, color: borderColor, size: 22),
                    const SizedBox(width: 8),
                    Text(statusText, style: TextStyle(fontWeight: FontWeight.bold, color: borderColor, fontSize: 16)),
                  ],
                ),
                const SizedBox(height: 12),
                
                if (options != null && data.containsKey('selected_option_index')) ...[
                  const Text('Согласованный вариант:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
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
                            color: isSelected ? Colors.green[600] : Colors.grey[400],
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
                                    color: isSelected ? Colors.black87 : Colors.grey[500],
                                    decoration: isSelected ? TextDecoration.none : TextDecoration.lineThrough,
                                  ),
                                ),
                                Text(
                                  '${opt['price']} TMT',
                                  style: TextStyle(
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                    color: isSelected ? (isCompleted ? Colors.green[700] : Colors.blue[700]) : Colors.grey[500],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                  if (isCompleted) ...[
                     const Divider(height: 24),
                     Text('Итого к оплате: ${data['price']} TMT', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                  ]
                ] else ...[
                  Text('Диагноз мастера: ${data['admin_comment']}'),
                  const SizedBox(height: 8),
                  Text('Утвержденная цена: ${data['price']} TMT', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: borderColor)),
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
          shape: RoundedRectangleBorder(
            side: BorderSide(color: Colors.red.shade200, width: 1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(data['device_type'] ?? 'Устройство', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.black87)),
                const SizedBox(height: 8),
                Text('Проблема: ${data['problem']}', style: TextStyle(color: Colors.blueGrey[800])),
                const Divider(height: 24),
                
                _buildHistoryBlock(data), // <-- ДОБАВЛЕН ВЫВОД ИСТОРИИ

                Row(
                  children: [
                    Icon(Icons.cancel, size: 20, color: Colors.red[700]),
                    const SizedBox(width: 8),
                    Text('Статус: Ремонт отменен', style: TextStyle(color: Colors.red[700], fontWeight: FontWeight.bold, fontSize: 16)),
                  ],
                ),
              ],
            ),
          ),
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

