import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';
import 'support_chat_screen.dart';

class CreateOrderScreen extends StatefulWidget {
  const CreateOrderScreen({super.key});

  @override
  _CreateOrderScreenState createState() => _CreateOrderScreenState();
}

class _CreateOrderScreenState extends State<CreateOrderScreen> {
  final _problemController = TextEditingController();
  
  // --- ТИПЫ ТЕХНИКИ И НАПРАВЛЕНИЯ БИЗНЕСА (БЕЗ ТЕЛЕФОНОВ) ---
  final List<Map<String, dynamic>> _deviceTypes = [
    {'name': 'Компьютеры / ИТ', 'icon': Icons.computer},
    {'name': 'Автосервис', 'icon': Icons.directions_car},
    {'name': 'Мебель / Сварка', 'icon': Icons.handyman},
    {'name': 'Другое', 'icon': Icons.category},
  ];
  String _selectedDeviceType = 'Компьютеры / ИТ'; 
  
  // --- СПОСОБ ОПЛАТЫ ---
  String _selectedPaymentMethod = 'Наличные';
  final List<String> _paymentMethods = [
    'Наличные',
    'Банковская карта',
    'Перечисление',
    'Оплата бонусами'
  ];
  
  bool _isLoading = false; 

  // --- МЕДИА ФАЙЛЫ ---
  File? _attachedImage;
  String? _attachedAudioPath;
  bool _isRecording = false;
  
  final _audioRecorder = AudioRecorder(); // Для версии 5.1.2+
  final ImagePicker _imagePicker = ImagePicker();

  @override
  void dispose() {
    _problemController.dispose();
    _audioRecorder.dispose();
    super.dispose();
  }

  // --- ЛОГИКА ФОТО (СЖАТИЕ) ---
  Future<void> _pickImage(ImageSource source) async {
    try {
      final pickedFile = await _imagePicker.pickImage(
        source: source, 
        imageQuality: 40, 
        maxWidth: 800
      );
      if (pickedFile != null) {
        setState(() => _attachedImage = File(pickedFile.path));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка фото: $e')));
    }
  }

  void _showImageSourceDialog() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Colors.blue),
              title: const Text('Сделать фото'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: Colors.orange),
              title: const Text('Выбрать из галереи'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  // --- ЛОГИКА АУДИО ---
  Future<void> _toggleRecording() async {
    try {
      if (_isRecording) {
        final path = await _audioRecorder.stop();
        setState(() {
          _isRecording = false;
          _attachedAudioPath = path;
        });
      } else {
        if (await _audioRecorder.hasPermission()) {
          if (_attachedAudioPath != null) {
            final oldFile = File(_attachedAudioPath!);
            if (oldFile.existsSync()) oldFile.deleteSync();
          }

          final tempDir = Directory.systemTemp.path;
          final audioPath = '$tempDir/audio_${DateTime.now().millisecondsSinceEpoch}.m4a';
          
          await _audioRecorder.start(
            const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 64000), 
            path: audioPath
          );
          
          setState(() {
            _isRecording = true;
            _attachedAudioPath = null;
          });
        } else {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Нет разрешения на микрофон!')));
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка аудио: $e')));
    }
  }

  // --- ОТПРАВКА БЕЗ КАРТЫ (КОНВЕРТАЦИЯ В BASE64) ---
  Future<void> _submitOrder() async {
    if (_problemController.text.trim().isEmpty && _attachedImage == null && _attachedAudioPath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Пожалуйста, опишите проблему (текстом, фото или голосовым)'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final phone = prefs.getString('phone') ?? 'Неизвестный номер';
      final clientName = prefs.getString('client_name') ?? 'Неизвестный пользователь';

      String? imageBase64;
      String? audioBase64;

      if (_attachedImage != null) {
        final bytes = await _attachedImage!.readAsBytes();
        imageBase64 = base64Encode(bytes);
      }

      if (_attachedAudioPath != null) {
        final audioFile = File(_attachedAudioPath!);
        final bytes = await audioFile.readAsBytes();
        audioBase64 = base64Encode(bytes);
      }

      await FirebaseFirestore.instance.collection('orders').add({
        'client_name': clientName,
        'phone': phone,
        'category': 'Вызов мастера', 
        'device_type': _selectedDeviceType, 
        'problem': _problemController.text.trim(),
        'payment_method': _selectedPaymentMethod,
        'image_base64': imageBase64,
        'audio_base64': audioBase64,
        'status': 'new',
        'created_at': FieldValue.serverTimestamp(),
        'has_unread_update': false,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Заявка отправлена! Мастер скоро свяжется с вами.'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 4),
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка отправки: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  IconData _getPaymentIcon(String method) {
    if (method.contains('карта')) return Icons.credit_card;
    if (method.contains('Перечисление')) return Icons.account_balance;
    if (method.contains('бонус')) return Icons.stars_rounded;
    return Icons.payments; 
  }

  void _onPaymentMethodSelected(String method) {
    if (method == 'Перечисление') {
      final isDark = Theme.of(context).brightness == Brightness.dark;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: Theme.of(context).cardColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              const Icon(Icons.info_outline, color: Colors.orange, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Text('Оплата перечислением', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87))
              ),
            ],
          ),
          content: Text(
            'Для оплаты перечислением вам требуется предварительно связаться с администрацией.\n\nОбратите внимание: цены могут отличаться, и мы работаем по предоплате.',
            style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, height: 1.5, fontSize: 15),
          ),
          actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                setState(() => _selectedPaymentMethod = 'Наличные'); 
              },
              child: const Text('Отмена', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue[600],
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12)
              ),
              onPressed: () {
                Navigator.pop(ctx);
                setState(() => _selectedPaymentMethod = 'Перечисление');
                Navigator.push(context, MaterialPageRoute(builder: (context) => const SupportChatScreen()));
              },
              icon: const Icon(Icons.chat, color: Colors.white, size: 20),
              label: const Text('Связаться в чате', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            )
          ],
        )
      );
    } else {
      setState(() => _selectedPaymentMethod = method);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor, 
      appBar: AppBar(
        title: const Text('Вызов мастера', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Theme.of(context).cardColor,
        foregroundColor: isDark ? Colors.white : Colors.black87,
        elevation: 1,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            
            // --- БЛОК 1: НАПРАВЛЕНИЯ БИЗНЕСА ---
            Text('КАТЕГОРИЯ', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: isDark ? Colors.white70 : Colors.blueGrey, letterSpacing: 1.2)),
            const SizedBox(height: 12),
            SizedBox(
              height: 105,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _deviceTypes.length,
                itemBuilder: (context, index) {
                  final device = _deviceTypes[index];
                  final isSelected = _selectedDeviceType == device['name'];
                  
                  return GestureDetector(
                    onTap: () => setState(() => _selectedDeviceType = device['name']),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 100,
                      margin: const EdgeInsets.only(right: 12),
                      decoration: BoxDecoration(
                        color: isSelected ? (isDark ? Colors.blue[900] : Colors.blue[50]) : Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isSelected ? Colors.blue : (isDark ? Colors.grey[800]! : Colors.grey.shade300),
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(device['icon'], size: 32, color: isSelected ? Colors.blue : (isDark ? Colors.white54 : Colors.blueGrey)),
                          const SizedBox(height: 8),
                          Text(
                            device['name'],
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              color: isSelected ? (isDark ? Colors.white : Colors.blue[900]) : (isDark ? Colors.white70 : Colors.black87),
                            ),
                          )
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

            // --- БЛОК 2: ОПИСАНИЕ ПРОБЛЕМЫ ---
            const SizedBox(height: 32),
            Text('ОПИШИТЕ ПРОБЛЕМУ', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: isDark ? Colors.white70 : Colors.blueGrey, letterSpacing: 1.2)),
            const SizedBox(height: 12),
            Card(
              elevation: 0,
              color: Theme.of(context).cardColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: isDark ? Colors.grey[800]! : Colors.grey.shade300)),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(4.0),
                    child: TextField(
                      controller: _problemController,
                      maxLines: 4, 
                      style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                      decoration: InputDecoration(
                        hintText: 'Что случилось?\nНапример: Не включается ноутбук, нужна сборка шкафа или ремонт генератора.', 
                        hintStyle: TextStyle(color: isDark ? Colors.white24 : Colors.grey[400]),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        filled: true, fillColor: Theme.of(context).cardColor,
                        contentPadding: const EdgeInsets.all(16),
                      ),
                    ),
                  ),

                  if (_attachedImage != null || _attachedAudioPath != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Column(
                        children: [
                          if (_attachedImage != null)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.file(_attachedImage!, width: 40, height: 40, fit: BoxFit.cover),
                              ),
                              title: const Text('Фото прикреплено', style: TextStyle(fontSize: 14)),
                              trailing: IconButton(
                                icon: const Icon(Icons.close, color: Colors.red),
                                onPressed: () => setState(() => _attachedImage = null),
                              ),
                            ),
                          if (_attachedAudioPath != null)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const CircleAvatar(backgroundColor: Colors.orange, child: Icon(Icons.audiotrack, color: Colors.white, size: 20)),
                              title: const Text('Голосовое сообщение', style: TextStyle(fontSize: 14)),
                              trailing: IconButton(
                                icon: const Icon(Icons.close, color: Colors.red),
                                onPressed: () {
                                  final f = File(_attachedAudioPath!);
                                  if (f.existsSync()) f.deleteSync();
                                  setState(() => _attachedAudioPath = null);
                                },
                              ),
                            ),
                        ],
                      ),
                    ),

                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(border: Border(top: BorderSide(color: isDark ? Colors.grey[800]! : Colors.grey.shade200))),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(_isRecording ? 'Идёт запись...' : 'Лень писать?', 
                          style: TextStyle(color: _isRecording ? Colors.red : (isDark ? Colors.white54 : Colors.grey[600]), fontSize: 13, fontWeight: _isRecording ? FontWeight.bold : FontWeight.normal)),
                        Row(
                          children: [
                            IconButton(
                              icon: Icon(Icons.attach_file, color: isDark ? Colors.blueGrey[400] : Colors.blueGrey),
                              onPressed: _isRecording ? null : _showImageSourceDialog,
                            ),
                            GestureDetector(
                              onTap: _toggleRecording,
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 300),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: _isRecording ? Colors.red : (isDark ? Colors.orange[900]?.withOpacity(0.3) : Colors.orange[50]),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  _isRecording ? Icons.stop : Icons.mic, 
                                  color: _isRecording ? Colors.white : Colors.orange[700]
                                ),
                              ),
                            ),
                          ],
                        )
                      ],
                    ),
                  )
                ],
              ),
            ),

            // --- БЛОК 3: СПОСОБ ОПЛАТЫ ---
            const SizedBox(height: 32),
            Text('СПОСОБ ОПЛАТЫ', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: isDark ? Colors.white70 : Colors.blueGrey, letterSpacing: 1.2)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8.0,
              runSpacing: 8.0,
              children: _paymentMethods.map((method) {
                final isSelected = _selectedPaymentMethod == method;
                return ChoiceChip(
                  label: Text(method),
                  selected: isSelected,
                  onSelected: (selected) {
                    if (selected) _onPaymentMethodSelected(method);
                  },
                  avatar: Icon(_getPaymentIcon(method), color: isSelected ? Colors.white : (isDark ? Colors.white54 : Colors.blueGrey), size: 18),
                  selectedColor: isDark ? Colors.blueGrey[700] : Colors.blueGrey[900],
                  backgroundColor: Theme.of(context).cardColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12), 
                    side: BorderSide(color: isSelected ? (isDark ? Colors.blueGrey[700]! : Colors.blueGrey[900]!) : (isDark ? Colors.grey[800]! : Colors.grey.shade300))
                  ),
                  labelStyle: TextStyle(color: isSelected ? Colors.white : (isDark ? Colors.white70 : Colors.black87), fontWeight: isSelected ? FontWeight.bold : FontWeight.normal),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                );
              }).toList(),
            ),
            
            const SizedBox(height: 40),
            
            // --- КНОПКА ОТПРАВКИ ---
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange[600],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 4,
              ),
              onPressed: _isLoading ? null : _submitOrder,
              child: _isLoading
                  ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
                  : const Text('ОТПРАВИТЬ ЗАЯВКУ', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

