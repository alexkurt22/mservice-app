import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({Key? key}) : super(key: key);

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  String? _phone;

  @override
  void initState() {
    super.initState();
    _loadPhone();
  }

  Future<void> _loadPhone() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _phone = prefs.getString('phone');
    });
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).cardColor,
        elevation: 1,
        iconTheme: IconThemeData(color: isDark ? Colors.white : Colors.black87),
        title: Text(
          'Уведомления',
          style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.bold),
        ),
      ),
      body: _phone == null
          ? const Center(child: CircularProgressIndicator())
          : StreamBuilder<QuerySnapshot>(
              // Слушаем коллекцию уведомлений конкретного клиента
              stream: FirebaseFirestore.instance
                  .collection('clients')
                  .doc(_phone)
                  .collection('notifications')
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
                        Icon(Icons.notifications_off_outlined, size: 80, color: isDark ? Colors.grey[700] : Colors.grey[300]),
                        const SizedBox(height: 16),
                        Text(
                          'У вас пока нет уведомлений',
                          style: TextStyle(color: isDark ? Colors.white54 : Colors.grey[600], fontSize: 16),
                        ),
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
                    final title = data['title'] ?? 'Уведомление';
                    final body = data['body'] ?? '';
                    final isRead = data['is_read'] ?? false;
                    final timestamp = data['created_at'] as Timestamp?;
                    final dateStr = timestamp != null ? _formatDate(timestamp.toDate()) : '';

                    return Card(
                      color: isRead 
                          ? Theme.of(context).cardColor 
                          : (isDark ? Colors.blueGrey[800] : Colors.blue[50]), // Подсветка непрочитанных
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: isRead ? 0 : 2,
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(16),
                        leading: CircleAvatar(
                          backgroundColor: isDark ? Colors.blueGrey[700] : Colors.white,
                          child: Icon(
                            Icons.notifications, 
                            color: isRead ? Colors.grey : Colors.orange,
                          ),
                        ),
                        title: Text(
                          title,
                          style: TextStyle(
                            fontWeight: isRead ? FontWeight.normal : FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 8),
                            Text(body, style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, height: 1.3)),
                            if (dateStr.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(dateStr, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                            ]
                          ],
                        ),
                        onTap: () {
                          // Делаем уведомление "прочитанным" при нажатии
                          if (!isRead) {
                            docs[index].reference.update({'is_read': true});
                          }
                        },
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}

