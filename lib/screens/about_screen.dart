import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).cardColor,
        foregroundColor: isDark ? Colors.white : Colors.black87,
        elevation: 1,
        title: const Text('О нас', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('settings').doc('company_info').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          
          Map<String, dynamic> data = {};
          if (snapshot.hasData && snapshot.data!.exists) data = snapshot.data!.data() as Map<String, dynamic>;

          final aboutText = data['about_text'] ?? 'Информация о компании скоро появится здесь...';

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(color: isDark ? Colors.blueGrey[900] : Colors.blue[50], shape: BoxShape.circle),
                  child: Icon(Icons.computer, size: 72, color: isDark ? Colors.blue[300] : Colors.blue[700]),
                ),
                const SizedBox(height: 24),
                Text('M-Service', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: isDark ? Colors.white : Colors.black87)),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(16), border: Border.all(color: isDark ? Colors.grey[800]! : Colors.grey.shade200)),
                  child: Text(aboutText, style: TextStyle(fontSize: 16, height: 1.6, color: isDark ? Colors.white70 : Colors.black87)),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

