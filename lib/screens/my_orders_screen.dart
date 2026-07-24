import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'client_order_details_screen.dart'; 

class MyOrdersScreen extends StatefulWidget {
  const MyOrdersScreen({super.key});

  @override
  State<MyOrdersScreen> createState() => _MyOrdersScreenState();
}

class _MyOrdersScreenState extends State<MyOrdersScreen> {
  String? _phone;

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

  Map<String, dynamic> _getStatusStyle(String status, bool isDark) {
    switch (status) {
      case 'new': return {'color': isDark ? Colors.blueGrey[300] : Colors.blueGrey, 'icon': Icons.inbox, 'text': 'Ожидает'};
      case 'awaiting_approval': return {'color': Colors.orange, 'icon': Icons.error_outline, 'text': 'Ждет ответа'};
      case 'in_progress': return {'color': isDark ? Colors.blue[300] : Colors.blue, 'icon': Icons.build, 'text': 'В работе'};
      case 'completed': return {'color': isDark ? Colors.green[400] : Colors.green, 'icon': Icons.check_circle, 'text': 'Готово'};
      case 'canceled': return {'color': isDark ? Colors.red[300] : Colors.red, 'icon': Icons.cancel, 'text': 'Отменен'};
      default: return {'color': Colors.grey, 'icon': Icons.help, 'text': 'Неизвестно'};
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Мои заказы', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        backgroundColor: Theme.of(context).cardColor,
        foregroundColor: isDark ? Colors.white : Colors.black87,
        elevation: 1,
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
                        Icon(Icons.inbox_outlined, size: 64, color: isDark ? Colors.grey[700] : Colors.blueGrey[200]),
                        const SizedBox(height: 16),
                        Text('У вас пока нет заказов', style: TextStyle(fontSize: 16, color: isDark ? Colors.grey[500] : Colors.blueGrey[500])),
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
                    final style = _getStatusStyle(status, isDark);

                    return Card(
                      elevation: 1,
                      margin: const EdgeInsets.only(bottom: 12.0),
                      color: Theme.of(context).cardColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: isDark ? Colors.grey[800]! : Colors.transparent)
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ClientOrderDetailsScreen(order: order, data: data),
                            ),
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: (style['color'] as Color).withOpacity(0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(style['icon'], color: style['color'], size: 24),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(data['device_type'] ?? 'Устройство', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isDark ? Colors.white : Colors.black87)),
                                    const SizedBox(height: 4),
                                    Text(
                                      data['problem'] ?? '', 
                                      maxLines: 1, 
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600], fontSize: 13),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(style['text'], style: TextStyle(color: style['color'], fontWeight: FontWeight.bold, fontSize: 12)),
                                  const SizedBox(height: 4),
                                  if (data.containsKey('price'))
                                    Text('${data['price']} TMT', style: TextStyle(fontWeight: FontWeight.w900, color: isDark ? Colors.white : Colors.black87)),
                                ],
                              ),
                            ],
                          ),
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
