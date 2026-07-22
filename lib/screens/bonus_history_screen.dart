import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class BonusHistoryScreen extends StatelessWidget {
  final String phone;

  const BonusHistoryScreen({super.key, required this.phone});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('История баллов', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 1,
      ),
      body: StreamBuilder<QuerySnapshot>(
        // Читаем подколлекцию bonus_history у конкретного клиента
        stream: FirebaseFirestore.instance
            .collection('clients')
            .doc(phone)
            .collection('bonus_history')
            .orderBy('created_at', descending: true)
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
                  Icon(Icons.history, size: 64, color: Colors.blueGrey[200]),
                  const SizedBox(height: 16),
                  Text('История операций пуста', style: TextStyle(fontSize: 16, color: Colors.blueGrey[500])),
                ],
              ),
            );
          }

          final docs = snapshot.data!.docs;

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final data = docs[index].data() as Map<String, dynamic>;
              final int amount = data['amount'] ?? 0;
              final String description = data['description'] ?? 'Операция';
              final Timestamp? time = data['created_at'] as Timestamp?;
              
              String timeStr = '';
              if (time != null) {
                final date = time.toDate();
                timeStr = '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
              }

              final isPositive = amount > 0;

              return Container(
                color: Colors.white,
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  leading: CircleAvatar(
                    backgroundColor: isPositive ? Colors.green[50] : Colors.orange[50],
                    child: Icon(
                      isPositive ? Icons.add_circle : Icons.remove_circle,
                      color: isPositive ? Colors.green : Colors.orange,
                    ),
                  ),
                  title: Text(description, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  subtitle: Text(timeStr, style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                  trailing: Text(
                    isPositive ? '+$amount' : amount.toString(),
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                      color: isPositive ? Colors.green[700] : Colors.orange[700],
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
