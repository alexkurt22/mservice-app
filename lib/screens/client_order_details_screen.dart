import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ClientOrderDetailsScreen extends StatefulWidget {
  final QueryDocumentSnapshot order;
  final Map<String, dynamic> data;

  const ClientOrderDetailsScreen({super.key, required this.order, required this.data});

  @override
  State<ClientOrderDetailsScreen> createState() => _ClientOrderDetailsScreenState();
}

class _ClientOrderDetailsScreenState extends State<ClientOrderDetailsScreen> {
  int? _selectedOption;
  bool _isLoading = false;

  // Функция для красивого форматирования даты и времени
  String _formatDate(DateTime date) {
    final d = date.day.toString().padLeft(2, '0');
    final m = date.month.toString().padLeft(2, '0');
    final y = date.year.toString();
    final h = date.hour.toString().padLeft(2, '0');
    final min = date.minute.toString().padLeft(2, '0');
    return '$d.$m.$y в $h:$min';
  }

  Widget _buildHistoryBlock(Map<String, dynamic> data) {
    final history = data['history'] as List<dynamic>?;
    if (history == null || history.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('История предложений:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.blueGrey)),
        const SizedBox(height: 8),
        ...history.asMap().entries.map((entry) {
          int round = entry.key + 1;
          List<dynamic> oldOptions = entry.value['options'] ?? [];
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Раунд $round (Отклонено)', style: TextStyle(color: Colors.red[400], fontWeight: FontWeight.bold, fontSize: 12)),
                const SizedBox(height: 6),
                ...oldOptions.map((opt) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('${opt['description']} — ${opt['price']} TMT', style: const TextStyle(color: Colors.grey, decoration: TextDecoration.lineThrough, fontSize: 13)),
                )).toList(),
              ],
            ),
          );
        }).toList(),
        const SizedBox(height: 16),
      ],
    );
  }

  // --- УМНЫЙ ЭЛЕКТРОННЫЙ ЧЕК И ГАРАНТИЯ ---
  Widget _buildReceiptCard() {
    Timestamp? completedAtTs = widget.data['completed_at'] as Timestamp?;
    
    String dateStr = 'Дата не указана';
    String warrantyText = 'Ожидание выдачи...';
    Color warrantyColor = Colors.orange;
    IconData warrantyIcon = Icons.hourglass_bottom;

    // Логика расчета гарантии
    if (completedAtTs != null) {
      DateTime completedDate = completedAtTs.toDate();
      dateStr = _formatDate(completedDate);
      
      DateTime expiryDate = completedDate.add(const Duration(days: 30)); // 30 дней базовой гарантии
      DateTime now = DateTime.now();
      
      if (now.isAfter(expiryDate)) {
        // Гарантия истекла
        warrantyText = 'Гарантийный период завершён';
        warrantyColor = Colors.grey;
        warrantyIcon = Icons.gpp_bad;
      } else {
        // Гарантия еще действует
        int daysLeft = expiryDate.difference(now).inDays;
        String daysStr = daysLeft > 0 ? 'Осталось дней: $daysLeft' : 'Истекает сегодня!';
        warrantyText = 'Гарантия активна\n$daysStr';
        warrantyColor = Colors.green;
        warrantyIcon = Icons.verified_user;
      }
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade300),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 5))],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('ЭЛЕКТРОННЫЙ ЧЕК', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey, letterSpacing: 1.2)),
              Icon(Icons.receipt_long, color: Colors.blueGrey[300]),
            ],
          ),
          const Divider(height: 24, thickness: 1),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Дата выдачи:', style: TextStyle(color: Colors.grey)),
              Text(dateStr, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Устройство:', style: TextStyle(color: Colors.grey)),
              Text('${widget.data['device_type']}', style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Выполненные работы:', style: TextStyle(color: Colors.grey)),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  '${widget.data['admin_comment'] ?? 'Ремонт'}', 
                  style: const TextStyle(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
          const Divider(height: 24, thickness: 1),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('ИТОГО К ОПЛАТЕ:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              Text('${widget.data['price']} TMT', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: Colors.green)),
            ],
          ),
          const SizedBox(height: 24),
          
          // ДИНАМИЧЕСКИЙ ГАРАНТИЙНЫЙ ТАЛОН
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: warrantyColor.withOpacity(0.1), 
              borderRadius: BorderRadius.circular(8), 
              border: Border.all(color: warrantyColor.withOpacity(0.5))
            ),
            child: Row(
              children: [
                Icon(warrantyIcon, color: warrantyColor, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    warrantyText, 
                    style: TextStyle(color: warrantyColor, fontSize: 14, fontWeight: FontWeight.bold)
                  )
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.data['status'] ?? 'unknown';
    final options = widget.data.containsKey('options') ? widget.data['options'] as List<dynamic> : null;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        title: const Text('Детали заказа', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
          padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: MediaQuery.of(context).padding.bottom + 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              
              // 1. БАЗОВАЯ ИНФОРМАЦИЯ О ПОЛОМКЕ
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.grey.shade200)),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.devices, color: Colors.blueGrey[400]),
                          const SizedBox(width: 12),
                          Text('${widget.data['device_type']}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Text('Заявленная проблема:', style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text('${widget.data['problem']}', style: const TextStyle(fontSize: 16, color: Colors.black87)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // 2. ИСТОРИЯ И ТОРГИ
              _buildHistoryBlock(widget.data),

              // 3. БЛОК ОЖИДАНИЯ ОТВЕТА (ТОРГОВ)
              if (status == 'awaiting_approval' && options != null) ...[
                const Text('Варианты ремонта от мастера:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.black87)),
                const SizedBox(height: 12),
                ...options.asMap().entries.map((entry) {
                  final int idx = entry.key;
                  final opt = entry.value as Map<String, dynamic>;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: _selectedOption == idx ? Colors.orange : Colors.grey.shade300, width: _selectedOption == idx ? 2 : 1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: RadioListTile<int>(
                      title: Text(opt['description'] ?? '', style: const TextStyle(fontSize: 15)),
                      subtitle: Text('${opt['price']} TMT', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.deepOrange, fontSize: 16)),
                      value: idx,
                      groupValue: _selectedOption,
                      activeColor: Colors.orange,
                      onChanged: (int? value) => setState(() => _selectedOption = value),
                    ),
                  );
                }),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.green[600], padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                        onPressed: () async {
                          if (_selectedOption == null) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Выберите вариант!')));
                            return;
                          }
                          setState(() => _isLoading = true);
                          final selectedOpt = options[_selectedOption!];
                          await widget.order.reference.update({
                            'status': 'in_progress',
                            'price': selectedOpt['price'],
                            'admin_comment': selectedOpt['description'],
                            'selected_option_index': _selectedOption,
                            'has_unread_update': true,
                          });
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ремонт согласован!'), backgroundColor: Colors.green));
                            Navigator.pop(context);
                          }
                        },
                        child: const Text('СОГЛАСИТЬСЯ', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(foregroundColor: Colors.red, padding: const EdgeInsets.symmetric(vertical: 16), side: const BorderSide(color: Colors.red), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                        onPressed: () async {
                          setState(() => _isLoading = true);
                          await widget.order.reference.update({'status': 'canceled', 'has_unread_update': true});
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Заказ отменен')));
                            Navigator.pop(context);
                          }
                        },
                        child: const Text('ОТКАЗАТЬСЯ', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ],

              // 4. БЛОК В РАБОТЕ И ЗАВЕРШЕНО
              if (status == 'in_progress' || status == 'completed') ...[
                if (status == 'in_progress')
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.blue[200]!)),
                    child: const Row(
                      children: [
                        Icon(Icons.handyman, color: Colors.blue),
                        SizedBox(width: 12),
                        Expanded(child: Text('Мастер уже приступил к ремонту вашего устройства.', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold))),
                      ],
                    ),
                  ),

                if (status == 'completed') 
                  _buildReceiptCard(), 
              ],

              // 5. БЛОК ОТМЕНЕНО
              if (status == 'canceled')
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: Colors.red[50], borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.red[200]!)),
                  child: const Row(
                    children: [
                      Icon(Icons.cancel, color: Colors.red),
                      SizedBox(width: 12),
                      Expanded(child: Text('Заказ отменен. Вы можете создать новую заявку.', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold))),
                    ],
                  ),
                ),
            ],
          ),
        ),
    );
  }
}
