import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class FaqScreen extends StatelessWidget {
  const FaqScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).cardColor,
        foregroundColor: isDark ? Colors.white : Colors.black87,
        elevation: 1,
        title: const Text('Частые вопросы', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('settings').doc('faq').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          
          if (!snapshot.hasData || !snapshot.data!.exists) {
            return Center(child: Text('База знаний формируется...', style: TextStyle(color: Colors.grey[500])));
          }

          final data = snapshot.data!.data() as Map<String, dynamic>;
          final List<dynamic> items = data['items'] ?? [];

          if (items.isEmpty) return Center(child: Text('Вопросов пока нет', style: TextStyle(color: Colors.grey[500])));

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                color: Theme.of(context).cardColor,
                // ИСПРАВЛЕНА СТРОКА НИЖЕ (side: BorderSide вместо border: Border.all)
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12), 
                  side: BorderSide(color: isDark ? Colors.grey[800]! : Colors.grey.shade200)
                ),
                child: ExpansionTile(
                  iconColor: Colors.blue,
                  title: Text(item['question'] ?? 'Вопрос', style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87)),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 16.0, right: 16.0, bottom: 16.0),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(item['answer'] ?? '', style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, height: 1.4)),
                      ),
                    )
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
