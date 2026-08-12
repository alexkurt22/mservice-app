import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';

class ContactsScreen extends StatelessWidget {
  const ContactsScreen({super.key});

  Future<void> _launchURL(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _openMap(String address) async {
    final url = 'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(address)}';
    await _launchURL(url);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).cardColor,
        foregroundColor: isDark ? Colors.white : Colors.black87,
        elevation: 1,
        title: const Text('Контакты и Карта', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('settings').doc('company_info').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          
          Map<String, dynamic> data = {};
          if (snapshot.hasData && snapshot.data!.exists) data = snapshot.data!.data() as Map<String, dynamic>;

          final phone = data['phone'] ?? '+993 60 000000';
          final address = data['address'] ?? 'г. Ашхабад';
          final schedule = data['schedule'] ?? 'Пн-Сб: 09:00 - 18:00';

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildCard(context, Icons.phone, 'Телефон', phone, isDark, onTap: () => _launchURL('tel:$phone')),
              const SizedBox(height: 12),
              _buildCard(context, Icons.access_time, 'Режим работы', schedule, isDark),
              const SizedBox(height: 12),
              _buildCard(context, Icons.location_on, 'Адрес', address, isDark),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: Colors.green[600],
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))
                ),
                onPressed: () => _openMap(address),
                icon: const Icon(Icons.map),
                label: const Text('ОТКРЫТЬ НА КАРТЕ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              )
            ],
          );
        },
      ),
    );
  }

  Widget _buildCard(BuildContext context, IconData icon, String title, String value, bool isDark, {VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(16), border: Border.all(color: isDark ? Colors.grey[800]! : Colors.grey.shade200)),
        child: Row(
          children: [
            CircleAvatar(backgroundColor: isDark ? Colors.blueGrey[800] : Colors.blue[50], child: Icon(icon, color: isDark ? Colors.blue[300] : Colors.blue[700])),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 12, color: isDark ? Colors.white54 : Colors.grey[600])),
                  const SizedBox(height: 4),
                  Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87)),
                ],
              ),
            ),
            if (onTap != null) Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey[400])
          ],
        ),
      ),
    );
  }
}

