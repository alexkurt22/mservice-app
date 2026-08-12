import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class StoreScreen extends StatefulWidget {
  const StoreScreen({super.key});

  @override
  State<StoreScreen> createState() => _StoreScreenState();
}

class _StoreScreenState extends State<StoreScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Widget _buildProductGrid(String condition) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('products')
          .where('is_active', isEqualTo: true)
          .where('condition', isEqualTo: condition)
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
                Icon(Icons.production_quantity_limits, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text('Товаров пока нет', style: TextStyle(color: Colors.grey[500], fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
          );
        }

        final docs = snapshot.data!.docs;

        return GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 0.7,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            final name = data['name'] ?? 'Товар';
            final price = data['price'] ?? 0;
            final imageBase64 = data['image_base64'];
            final desc = data['description'] ?? '';

            return Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              clipBehavior: Clip.antiAlias,
              color: Theme.of(context).cardColor,
              child: InkWell(
                onTap: () {
                  // ПРИ КЛИКЕ ОТКРЫВАЕМ ДЕТАЛИ
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (ctx) => Container(
                      height: MediaQuery.of(context).size.height * 0.85,
                      decoration: BoxDecoration(
                        color: Theme.of(context).scaffoldBackgroundColor,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (imageBase64 != null && imageBase64.toString().isNotEmpty)
                            ClipRRect(
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                              child: Image.memory(base64Decode(imageBase64), height: 300, fit: BoxFit.cover),
                            )
                          else
                            Container(height: 200, color: Colors.grey[300], child: const Icon(Icons.image, size: 64, color: Colors.grey)),
                          
                          Expanded(
                            child: ListView(
                              padding: const EdgeInsets.all(24),
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(child: Text(name, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87))),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(color: condition == 'Новый' ? Colors.blue[100] : Colors.orange[100], borderRadius: BorderRadius.circular(8)),
                                      child: Text(condition, style: TextStyle(color: condition == 'Новый' ? Colors.blue[900] : Colors.orange[900], fontWeight: FontWeight.bold)),
                                    )
                                  ],
                                ),
                                const SizedBox(height: 16),
                                Text('$price TMT', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Colors.green)),
                                const SizedBox(height: 24),
                                Text('Описание', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: isDark ? Colors.white54 : Colors.grey[600])),
                                const SizedBox(height: 8),
                                Text(desc, style: TextStyle(fontSize: 15, height: 1.5, color: isDark ? Colors.white : Colors.black87)),
                              ],
                            ),
                          ),

                          SafeArea(
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  backgroundColor: Colors.blue[700],
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))
                                ),
                                onPressed: () {
                                  Navigator.pop(ctx);
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Добавлено в корзину (функционал в разработке)')));
                                }, 
                                icon: const Icon(Icons.add_shopping_cart), 
                                label: const Text('В КОРЗИНУ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))
                              ),
                            ),
                          )
                        ],
                      ),
                    )
                  );
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: isDark ? Colors.grey[800] : Colors.grey[200],
                          image: imageBase64 != null && imageBase64.toString().isNotEmpty
                              ? DecorationImage(image: MemoryImage(base64Decode(imageBase64)), fit: BoxFit.cover)
                              : null,
                        ),
                        child: imageBase64 == null || imageBase64.toString().isEmpty
                            ? Icon(Icons.image_not_supported, color: Colors.grey[400])
                            : null,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: isDark ? Colors.white : Colors.black87),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '$price TMT',
                            style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.green, fontSize: 16),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).cardColor,
        foregroundColor: isDark ? Colors.white : Colors.black87,
        elevation: 0,
        title: const Text('Магазин техники', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Badge(child: Icon(Icons.shopping_cart)),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Корзина пока пуста')));
            },
          ),
          const SizedBox(width: 8),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.blue[700],
          unselectedLabelColor: Colors.grey,
          indicatorColor: Colors.blue[700],
          tabs: const [
            Tab(text: 'НОВЫЕ'),
            Tab(text: 'Б/У ТЕХНИКА'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildProductGrid('Новый'),
          _buildProductGrid('Б/У'),
        ],
      ),
    );
  }
}

