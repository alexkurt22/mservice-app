import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

class SupportChatScreen extends StatefulWidget {
  const SupportChatScreen({super.key});

  @override
  State<SupportChatScreen> createState() => _SupportChatScreenState();
}

class _SupportChatScreenState extends State<SupportChatScreen> {
  final TextEditingController _controller = TextEditingController();
  String? _myPhone;
  String? _roomId;

  @override
  void initState() {
    super.initState();
    _initChat();
  }

  Future<void> _initChat() async {
    final prefs = await SharedPreferences.getInstance();
    final phone = prefs.getString('phone'); 
    if (phone == null) return;

    setState(() => _myPhone = phone);

    final query = await FirebaseFirestore.instance.collection('chat_rooms')
        .where('type', isEqualTo: 'private')
        .where('participants', arrayContains: phone)
        .limit(1).get();

    if (query.docs.isNotEmpty) {
      setState(() => _roomId = query.docs.first.id);
    } else {
      List<String> parts = ['admin', phone];
      parts.sort(); 
      final newRoomId = 'private_${parts[0]}_${parts[1]}';
      
      await FirebaseFirestore.instance.collection('chat_rooms').doc(newRoomId).set({
        'type': 'private',
        'participants': parts,
        'created_at': FieldValue.serverTimestamp(),
        'last_message': 'Чат начат',
        'last_message_time': FieldValue.serverTimestamp(),
      });
      setState(() => _roomId = newRoomId);
    }
  }

  Future<void> _sendMessage() async {
    if (_controller.text.trim().isEmpty || _roomId == null) return;
    final text = _controller.text.trim();
    _controller.clear();

    await FirebaseFirestore.instance.collection('chat_rooms').doc(_roomId).collection('messages').add({
      'text': text,
      'sender_phone': _myPhone,
      'created_at': FieldValue.serverTimestamp(),
      'is_read': false,
    });
    
    await FirebaseFirestore.instance.collection('chat_rooms').doc(_roomId).update({
      'last_message': text,
      'last_message_time': FieldValue.serverTimestamp(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Чат с мастером'), // Более солидное название
        backgroundColor: Colors.blueGrey[900], // Цвет как на главном экране
        foregroundColor: Colors.white,
      ),
      body: _roomId == null 
        ? const Center(child: CircularProgressIndicator())
        : Column(
            children: [
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('chat_rooms')
                      .doc(_roomId)
                      .collection('messages')
                      .orderBy('created_at', descending: true)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                    
                    final messages = snapshot.data!.docs;
                    
                    return ListView.builder(
                      reverse: true,
                      padding: EdgeInsets.only(top: 10, bottom: MediaQuery.of(context).padding.bottom + 80.0),
                      itemCount: messages.length,
                      itemBuilder: (ctx, i) {
                        final data = messages[i].data() as Map<String, dynamic>;
                        final bool isMe = data['sender_phone'] == _myPhone;
                        final Timestamp? ts = data['created_at'] as Timestamp?;
                        final DateTime dt = ts?.toDate() ?? DateTime.now();
                        
                        if (!isMe && data['is_read'] == false) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            messages[i].reference.update({'is_read': true});
                          });
                        }
                        
                        bool showDate = false;
                        if (i == messages.length - 1) {
                          showDate = true;
                        } else {
                          final prevData = messages[i+1].data() as Map<String, dynamic>;
                          final prevTs = prevData['created_at'] as Timestamp?;
                          if (prevTs != null && ts != null) {
                            if (prevTs.toDate().day != ts.toDate().day) showDate = true;
                          }
                        }

                        return Column(
                          children: [
                            if (showDate) Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Text(DateFormat('dd MMM yyyy').format(dt), style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
                            ),
                            Align(
                              alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                              child: Container(
                                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  // ❗ СВЕТЛО-ГОЛУБОЙ ДЛЯ СВОИХ, БЕЛЫЙ ДЛЯ ЧУЖИХ
                                  color: isMe ? Colors.blue[50] : Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2))],
                                ),
                                child: Column(
                                  crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                                  children: [
                                    // ❗ ТЕКСТ ВСЕГДА ТЕМНЫЙ ДЛЯ ЧИТАЕМОСТИ
                                    Text(data['text'], style: const TextStyle(fontSize: 16, color: Colors.black87)),
                                    const SizedBox(height: 4),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(DateFormat('HH:mm').format(dt), style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                        if (isMe) ...[
                                          const SizedBox(width: 4),
                                          // ❗ ИДЕАЛЬНЫЕ ГАЛОЧКИ КАК В ТЕЛЕГРАМ
                                          Icon(
                                            data['is_read'] == true ? Icons.done_all : Icons.check, 
                                            size: 14, 
                                            color: data['is_read'] == true ? Colors.blue[600] : Colors.grey
                                          ),
                                        ]
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _controller, 
                          decoration: InputDecoration(
                            hintText: 'Напишите мастеру...', 
                            filled: true,
                            fillColor: Colors.white,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none)
                          )
                        )
                      ),
                      const SizedBox(width: 8),
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: Colors.blueGrey[900], // Кнопка отправки тоже строгая
                        child: IconButton(icon: const Icon(Icons.send, color: Colors.white), onPressed: _sendMessage),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
    );
  }
}
