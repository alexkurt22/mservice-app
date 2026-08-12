import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ReviewsScreen extends StatelessWidget {
  const ReviewsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).cardColor,
        foregroundColor: isDark ? Colors.white : Colors.black87,
        elevation: 1,
        title: const Text('Отзывы клиентов', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('reviews').where('is_approved', isEqualTo: true).orderBy('created_at', descending: true).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.forum_outlined, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text('Пока нет отзывов.', style: TextStyle(fontSize: 18, color: Colors.grey[500], fontWeight: FontWeight.bold)),
                ],
              ),
            );
          }

          final docs = snapshot.data!.docs;
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index].data() as Map<String, dynamic>;
              return Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor, 
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
                  border: Border.all(color: isDark ? Colors.grey[800]! : Colors.grey.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(data['author_name'] ?? 'Клиент', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isDark ? Colors.white : Colors.black87)),
                        Row(children: List.generate(5, (starIdx) => Icon(starIdx < (data['rating'] ?? 5) ? Icons.star_rounded : Icons.star_border_rounded, color: Colors.orangeAccent, size: 18)))
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(data['device_type'] ?? '', style: TextStyle(color: isDark ? Colors.white54 : Colors.grey[500], fontSize: 12)),
                    const SizedBox(height: 12),
                    Text(data['text'] ?? '', style: TextStyle(fontSize: 14, height: 1.4, color: isDark ? Colors.white : Colors.black87)),
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

