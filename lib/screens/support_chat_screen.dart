import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import '../services/push_service.dart';

class SupportChatScreen extends StatefulWidget {
  const SupportChatScreen({super.key});

  @override
  State<SupportChatScreen> createState() => _SupportChatScreenState();
}

class _SupportChatScreenState extends State<SupportChatScreen> {
  final TextEditingController _controller = TextEditingController();
  String? _myPhone;
  String? _roomId;

  // --- МЕДИА И ЗАПИСЬ ---
  final ImagePicker _imagePicker = ImagePicker();
  FlutterSoundRecorder? _audioRecorder;
  bool _isRecording = false;
  String? _currentAudioPath;
  
  // --- ВОСПРОИЗВЕДЕНИЕ ---
  final AudioPlayer _audioPlayer = AudioPlayer();
  String? _currentlyPlayingId;

  @override
  void initState() {
    super.initState();
    _initChat();
    _initRecorder();
    
    _audioPlayer.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        if (mounted) setState(() => _currentlyPlayingId = null);
        _audioPlayer.stop();
      }
    });
  }

  Future<void> _initChat() async {
    final prefs = await SharedPreferences.getInstance();
    final phone = prefs.getString('phone'); 
    if (phone == null) return;

    if (mounted) setState(() => _myPhone = phone);

    final query = await FirebaseFirestore.instance.collection('chat_rooms')
        .where('type', isEqualTo: 'private')
        .where('participants', arrayContains: phone)
        .limit(1).get();

    if (query.docs.isNotEmpty) {
      if (mounted) setState(() => _roomId = query.docs.first.id);
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
        'unread_count': 0, 
        'last_sender': phone, 
      });
      if (mounted) setState(() => _roomId = newRoomId);
    }
  }

  Future<void> _initRecorder() async {
    _audioRecorder = FlutterSoundRecorder();
    await _audioRecorder!.openRecorder();
  }

  @override
  void dispose() {
    _controller.dispose();
    _audioRecorder?.closeRecorder();
    _audioPlayer.dispose();
    super.dispose();
  }

  // --- ОТПРАВКА ТЕКСТА ---
  Future<void> _sendTextMessage() async {
    if (_controller.text.trim().isEmpty || _roomId == null) return;
    final text = _controller.text.trim();
    _controller.clear();
    await _sendMessageToDb(text: text);
  }

  // --- ОТПРАВКА ФОТО ---
  Future<void> _pickAndSendImage() async {
    try {
      final pickedFile = await _imagePicker.pickImage(source: ImageSource.gallery, imageQuality: 50);
      if (pickedFile != null) {
        final bytes = await File(pickedFile.path).readAsBytes();
        final base64Image = base64Encode(bytes);
        await _sendMessageToDb(text: '📷 Фотография', imageBase64: base64Image);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка отправки фото: $e')));
    }
  }

  // --- ЗАПИСЬ АУДИО ---
  Future<void> _startRecording() async {
    var statusMicrophone = await Permission.microphone.request();
    if (statusMicrophone != PermissionStatus.granted) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Нет разрешения на микрофон!')));
      return;
    }

    try {
      final tempDir = await getTemporaryDirectory();
      _currentAudioPath = '${tempDir.path}/chat_audio_${DateTime.now().millisecondsSinceEpoch}.aac';
      
      await _audioRecorder!.startRecorder(toFile: _currentAudioPath, codec: Codec.aacADTS);
      if (mounted) setState(() => _isRecording = true);
    } catch (e) {
      debugPrint('Ошибка старта записи: $e');
    }
  }

  Future<void> _stopRecordingAndSend() async {
    if (!_isRecording) return;
    try {
      await _audioRecorder!.stopRecorder();
      if (mounted) setState(() => _isRecording = false);

      if (_currentAudioPath != null) {
        final bytes = await File(_currentAudioPath!).readAsBytes();
        final base64Audio = base64Encode(bytes);
        
        await _sendMessageToDb(text: '🎤 Голосовое сообщение', audioBase64: base64Audio);
      }
    } catch (e) {
      debugPrint('Ошибка остановки записи: $e');
    }
  }

  // --- ОБЩИЙ МЕТОД СОХРАНЕНИЯ В БАЗУ ---
  Future<void> _sendMessageToDb({required String text, String? imageBase64, String? audioBase64}) async {
    if (_roomId == null) return;

    await FirebaseFirestore.instance.collection('chat_rooms').doc(_roomId).collection('messages').add({
      'text': text,
      'sender_phone': _myPhone,
      'created_at': FieldValue.serverTimestamp(),
      'is_read': false,
      if (imageBase64 != null) 'image_base64': imageBase64,
      if (audioBase64 != null) 'audio_base64': audioBase64,
    });
    
    await FirebaseFirestore.instance.collection('chat_rooms').doc(_roomId).update({
      'last_message': text,
      'last_message_time': FieldValue.serverTimestamp(),
      'unread_count': FieldValue.increment(1), 
      'last_sender': _myPhone,
    });

    try {
      await PushService.sendPushToAdmins('Новое сообщение от клиента', text);
    } catch (e) {
      debugPrint('Push send failed: $e');
    }
  }

  // --- ВОСПРОИЗВЕДЕНИЕ АУДИО ---
  Future<void> _playAudio(String messageId, String base64Audio) async {
    if (_currentlyPlayingId == messageId) {
      await _audioPlayer.pause();
      if (mounted) setState(() => _currentlyPlayingId = null);
      return;
    }

    try {
      final bytes = base64Decode(base64Audio);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/play_$messageId.aac');
      await file.writeAsBytes(bytes);
      
      await _audioPlayer.setFilePath(file.path);
      if (mounted) setState(() => _currentlyPlayingId = messageId);
      await _audioPlayer.play();
    } catch (e) {
      debugPrint("Ошибка проигрывания: $e");
    }
  }

  String _getDateSeparatorText(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final msgDate = DateTime(date.year, date.month, date.day);

    if (msgDate == today) return 'Сегодня';
    if (msgDate == yesterday) return 'Вчера';
    return DateFormat('dd.MM.yyyy').format(date);
  }

  // --- ОТРИСОВКА ПУЗЫРЯ СООБЩЕНИЯ ---
  Widget _buildMessageBubble(Map<String, dynamic> data, String messageId, bool isMe, DateTime dt, bool isSending, bool isDark) {
    final bubbleColor = isMe 
        ? (isDark ? Colors.blueGrey[700] : Colors.blue[100]) 
        : (isDark ? Colors.grey[800] : Colors.white);
    final textColor = isDark ? Colors.white : Colors.black87;
    final timeColor = isDark ? Colors.white54 : Colors.grey[600];

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        padding: const EdgeInsets.all(12),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.circular(16).copyWith(
            bottomRight: isMe ? const Radius.circular(4) : const Radius.circular(16),
            bottomLeft: !isMe ? const Radius.circular(4) : const Radius.circular(16),
          ),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2))],
        ),
        child: Column(
          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            
            // Если есть картинка
            if (data['image_base64'] != null)
              GestureDetector(
                onTap: () {
                  showDialog(
                    context: context,
                    builder: (_) => Dialog(
                      backgroundColor: Colors.transparent,
                      insetPadding: const EdgeInsets.all(10),
                      child: InteractiveViewer(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.memory(base64Decode(data['image_base64']), fit: BoxFit.contain),
                        ),
                      ),
                    ),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(base64Decode(data['image_base64']), height: 150, width: double.infinity, fit: BoxFit.cover),
                  ),
                ),
              ),

            // Если есть аудио
            if (data['audio_base64'] != null)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isDark ? Colors.black26 : Colors.white54,
                  borderRadius: BorderRadius.circular(12)
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      onTap: () => _playAudio(messageId, data['audio_base64']),
                      child: CircleAvatar(
                        backgroundColor: isMe ? Colors.blue[600] : Colors.orange,
                        radius: 20,
                        child: Icon(_currentlyPlayingId == messageId ? Icons.pause : Icons.play_arrow, color: Colors.white),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        data['text'] ?? '🎤 Голосовое сообщение', 
                        style: TextStyle(fontSize: 13, color: textColor, fontStyle: FontStyle.italic),
                      ),
                    ),
                  ],
                ),
              )
            // Иначе просто текст
            else if (data['image_base64'] == null)
              Text(data['text'] ?? '', style: TextStyle(fontSize: 15, color: textColor)),
            
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(isSending ? 'Отправка...' : DateFormat('HH:mm').format(dt), style: TextStyle(fontSize: 11, color: timeColor)),
                if (isMe) ...[
                  const SizedBox(width: 4),
                  Icon(
                    isSending ? Icons.access_time : (data['is_read'] == true ? Icons.done_all : Icons.check), 
                    size: 14, 
                    color: isSending ? Colors.grey : (data['is_read'] == true ? (isDark ? Colors.blue[300] : Colors.blue[600]) : timeColor),
                  ),
                ]
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Чат с поддержкой', style: TextStyle(fontWeight: FontWeight.bold)), 
        backgroundColor: isDark ? Colors.grey[900] : Colors.blueGrey[900], 
        foregroundColor: Colors.white,
        elevation: 1,
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
                        final messageId = messages[i].id;
                        final bool isMe = data['sender_phone'] == _myPhone;
                        final Timestamp? ts = data['created_at'] as Timestamp?;
                        final DateTime dt = ts?.toDate() ?? DateTime.now();
                        final bool isSending = ts == null;
                        
                        if (!isMe && data['is_read'] == false && !isSending) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            messages[i].reference.update({'is_read': true});
                            FirebaseFirestore.instance.collection('chat_rooms').doc(_roomId).update({'unread_count': 0});
                          });
                        }
                        
                        bool showDate = false;
                        if (i == messages.length - 1) {
                          showDate = true; 
                        } else if (!isSending) {
                          final prevData = messages[i+1].data() as Map<String, dynamic>;
                          final prevTs = prevData['created_at'] as Timestamp?;
                          if (prevTs != null && ts != null) {
                            if (prevTs.toDate().day != dt.day) showDate = true;
                          }
                        }

                        return Column(
                          children: [
                            if (showDate) 
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 16.0),
                                child: Row(
                                  children: [
                                    Expanded(child: Divider(color: isDark ? Colors.grey[700] : Colors.grey[300], thickness: 1)),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 12.0),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                        decoration: BoxDecoration(color: isDark ? Colors.grey[800] : Colors.grey[200], borderRadius: BorderRadius.circular(12)),
                                        child: Text(_getDateSeparatorText(dt), style: TextStyle(color: isDark ? Colors.white70 : Colors.blueGrey, fontSize: 12, fontWeight: FontWeight.bold)),
                                      ),
                                    ),
                                    Expanded(child: Divider(color: isDark ? Colors.grey[700] : Colors.grey[300], thickness: 1)),
                                  ],
                                ),
                              ),
                            
                            _buildMessageBubble(data, messageId, isMe, dt, isSending, isDark),
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
              
              // --- ИНДИКАТОР ЗАПИСИ ---
              if (_isRecording)
                Container(
                  color: isDark ? Colors.red[900]?.withOpacity(0.5) : Colors.red[50],
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.mic, color: Colors.red),
                      const SizedBox(width: 8),
                      Text('Идет запись... Отпустите для отправки', style: TextStyle(color: isDark ? Colors.red[200] : Colors.red[800], fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),

              // --- ПОЛЕ ВВОДА ---
              SafeArea(
                top: false,
                child: Container(
                  padding: const EdgeInsets.all(8.0),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -5))],
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: Icon(Icons.attach_file, color: isDark ? Colors.grey[400] : Colors.grey[600]),
                        onPressed: _pickAndSendImage,
                      ),
                      Expanded(
                        child: TextField(
                          controller: _controller, 
                          style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                          decoration: InputDecoration(
                            hintText: 'Сообщение...', 
                            hintStyle: TextStyle(color: isDark ? Colors.white54 : Colors.grey),
                            filled: true,
                            fillColor: isDark ? Colors.grey[800] : Colors.grey[100],
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none)
                          ),
                          onChanged: (text) => setState(() {}),
                        )
                      ),
                      const SizedBox(width: 8),
                      
                      if (_controller.text.trim().isNotEmpty)
                        CircleAvatar(
                          radius: 22,
                          backgroundColor: isDark ? Colors.blue[700] : Colors.blue[600], 
                          child: IconButton(icon: const Icon(Icons.send, color: Colors.white, size: 20), onPressed: _sendTextMessage),
                        )
                      else
                        GestureDetector(
                          onLongPress: _startRecording,
                          onLongPressUp: _stopRecordingAndSend,
                          child: CircleAvatar(
                            radius: 22,
                            backgroundColor: _isRecording ? Colors.red : (isDark ? Colors.blueGrey[700] : Colors.blueGrey[900]), 
                            child: Icon(_isRecording ? Icons.stop : Icons.mic, color: Colors.white, size: 22),
                          ),
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

