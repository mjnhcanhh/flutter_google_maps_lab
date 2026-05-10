import 'package:flutter/material.dart';
import 'maps_screen.dart';
import 'router_finder_screen.dart';
import 'route_finder_extended_screen.dart';
import 'route_finder_full_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Google Maps - Tuần 10',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1A73E8)),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

// ─────────────────────────────────────────────
// Màn hình chính: chọn bài để chạy
// ─────────────────────────────────────────────
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final List<_BaiItem> baiList = [
      _BaiItem(
        label: 'Bài 1',
        title: 'Hiển thị bản đồ & đánh dấu vị trí hiện tại',
        subtitle: 'GoogleMap + Geolocator + Marker',
        icon: Icons.location_on,
        color: const Color(0xFF1A73E8),
        destination: const MapScreen(),
      ),
      _BaiItem(
        label: 'Bài 2',
        title: 'Nhập 2 điểm, vẽ đường đi (Polyline)',
        subtitle: 'Directions API + Polyline + 2 Marker',
        icon: Icons.route,
        color: const Color(0xFF34A853),
        destination: const RouteFinderScreen(),
      ),
      _BaiItem(
        label: 'Bài 3',
        title: 'Tìm đường + khoảng cách + chọn điểm trên bản đồ',
        subtitle: 'Lấy vị trí hiện tại làm đích + distance/duration',
        icon: Icons.directions,
        color: const Color(0xFFFBBC05),
        destination: const RouteFinderExtendedScreen(),
      ),
      _BaiItem(
        label: 'Bài 4',
        title: 'Geocoding + loại phương tiện + lưu yêu thích',
        subtitle: 'Geocoding API + SQLite + phương tiện',
        icon: Icons.map,
        color: const Color(0xFFEA4335),
        destination: const RouteFinderFullScreen(),
      ),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A73E8),
        foregroundColor: Colors.white,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Lập trình di động – Tuần 10',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Text(
              'Google Maps – Chọn bài để chạy',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
            ),
          ],
        ),
        elevation: 2,
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: baiList.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final item = baiList[index];
          return _BaiCard(item: item);
        },
      ),
    );
  }
}

class _BaiItem {
  final String label;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final Widget destination;

  const _BaiItem({
    required this.label,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.destination,
  });
}

class _BaiCard extends StatelessWidget {
  final _BaiItem item;
  const _BaiCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => item.destination),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: item.color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(item.icon, color: item.color, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: item.color,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        item.label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      item.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.subtitle,
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios, color: Colors.grey[400], size: 16),
            ],
          ),
        ),
      ),
    );
  }
}
