import 'package:flutter/material.dart';
import 'create_order_screen.dart';

class ServicesCatalogScreen extends StatelessWidget {
  const ServicesCatalogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Список услуг на основе реальной матрицы сервисного центра
    final List<Map<String, dynamic>> categories = [
      {
        'title': 'Ноутбуки и Макбуки',
        'subtitle': 'Чистка от пыли, замена термопасты, замена матриц, клавиатур, ремонт питания.',
        'icon': Icons.laptop_mac,
        'color': Colors.blue,
      },
      {
        'title': 'Смартфоны и Планшеты',
        'subtitle': 'Замена дисплеев, аккумуляторов, разъемов зарядки, восстановление после воды.',
        'icon': Icons.smartphone,
        'color': Colors.orange,
      },
      {
        'title': 'Компьютеры (ПК)',
        'subtitle': 'Диагностика неисправностей, сборка на заказ, апгрейд комплектующих, установка ПО.',
        'icon': Icons.desktop_windows,
        'color': Colors.teal,
      },
      {
        'title': 'Оргтехника и Принтеры',
        'subtitle': 'Заправка картриджей, ремонт МФУ, устранение замятия бумаги.',
        'icon': Icons.print,
        'color': Colors.purple,
      },
      {
        'title': 'Игровые приставки',
        'subtitle': 'Чистка систем охлаждения (PlayStation, Xbox), замена термоинтерфейса.',
        'icon': Icons.gamepad,
        'color': Colors.red,
      },
      {
        'title': 'Другая техника',
        'subtitle': 'Любые электронные устройства и гаджеты. Проконсультируем по телефону.',
        'icon': Icons.devices_other,
        'color': Colors.blueGrey,
      },
    ];

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        title: const Text('Наши услуги', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 5))],
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: Colors.blue[50], shape: BoxShape.circle),
                  child: Icon(Icons.verified_user, size: 40, color: Colors.blue[700]),
                ),
                const SizedBox(height: 12),
                const Text('Профессиональный ремонт', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
                const SizedBox(height: 6),
                const Text(
                  'Точная стоимость определяется мастером после бесплатной диагностики.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.blueGrey, fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 0.9,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: categories.length,
              itemBuilder: (context, index) {
                final cat = categories[index];
                return InkWell(
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => CreateOrderScreen()));
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade200),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 5, offset: const Offset(0, 2))],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          backgroundColor: (cat['color'] as Color).withOpacity(0.1),
                          radius: 22,
                          child: Icon(cat['icon'], color: cat['color'], size: 24),
                        ),
                        const SizedBox(height: 10),
                        Text(cat['title'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14), maxLines: 1),
                        const SizedBox(height: 4),
                        Expanded(
                          child: Text(
                            cat['subtitle'],
                            style: TextStyle(color: Colors.grey[600], fontSize: 11),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 4,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

