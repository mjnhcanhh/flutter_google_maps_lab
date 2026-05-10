// ─────────────────────────────────────────────────────────────────────────────
// BÀI 4 (Bài tập về nhà): 
//   - Tìm kiếm địa chỉ bằng Geocoding API (nhập địa chỉ → tọa độ)
//   - Chọn loại phương tiện (driving / walking / bicycling / transit)
//   - Lưu tuyến đường yêu thích vào SQLite và hiển thị lại
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'maps_screen.dart'; // kGoogleApiKey

// ─── Model tuyến đường yêu thích ────────────────────────────────────────────
class FavoriteRoute {
  final int? id;
  final String startAddress;
  final String endAddress;
  final double startLat;
  final double startLng;
  final double endLat;
  final double endLng;
  final String travelMode;

  const FavoriteRoute({
    this.id,
    required this.startAddress,
    required this.endAddress,
    required this.startLat,
    required this.startLng,
    required this.endLat,
    required this.endLng,
    required this.travelMode,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'startAddress': startAddress,
        'endAddress': endAddress,
        'startLat': startLat,
        'startLng': startLng,
        'endLat': endLat,
        'endLng': endLng,
        'travelMode': travelMode,
      };

  factory FavoriteRoute.fromMap(Map<String, dynamic> m) => FavoriteRoute(
        id: m['id'] as int?,
        startAddress: m['startAddress'] as String,
        endAddress: m['endAddress'] as String,
        startLat: m['startLat'] as double,
        startLng: m['startLng'] as double,
        endLat: m['endLat'] as double,
        endLng: m['endLng'] as double,
        travelMode: m['travelMode'] as String,
      );
}

// ─── Database Helper ─────────────────────────────────────────────────────────
class RouteDatabase {
  static Database? _db;

  static Future<Database> get database async {
    _db ??= await _initDb();
    return _db!;
  }

  static Future<Database> _initDb() async {
    final path = p.join(await getDatabasesPath(), 'favorite_routes.db');
    return openDatabase(
      path,
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE routes(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            startAddress TEXT,
            endAddress TEXT,
            startLat REAL,
            startLng REAL,
            endLat REAL,
            endLng REAL,
            travelMode TEXT
          )
        ''');
      },
    );
  }

  static Future<int> insert(FavoriteRoute route) async {
    final db = await database;
    return db.insert('routes', route.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<List<FavoriteRoute>> getAll() async {
    final db = await database;
    final maps = await db.query('routes', orderBy: 'id DESC');
    return maps.map(FavoriteRoute.fromMap).toList();
  }

  static Future<void> delete(int id) async {
    final db = await database;
    await db.delete('routes', where: 'id = ?', whereArgs: [id]);
  }
}

// ─── Screen ──────────────────────────────────────────────────────────────────
class RouteFinderFullScreen extends StatefulWidget {
  const RouteFinderFullScreen({super.key});

  @override
  State<RouteFinderFullScreen> createState() => _RouteFinderFullScreenState();
}

class _RouteFinderFullScreenState extends State<RouteFinderFullScreen> {
  final Completer<GoogleMapController> _controller = Completer();
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};

  final TextEditingController _startController = TextEditingController();
  final TextEditingController _endController = TextEditingController();

  LatLng? _startLatLng;
  LatLng? _endLatLng;

  String? _distance;
  String? _duration;
  String _travelMode = 'driving'; // driving | walking | bicycling | transit

  List<FavoriteRoute> _favoriteRoutes = [];
  bool _showFavorites = false;
  bool _isLoading = false;

  static const CameraPosition _initialPosition = CameraPosition(
    target: LatLng(10.7769, 106.7009),
    zoom: 12,
  );

  final Map<String, IconData> _modeIcons = {
    'driving': Icons.directions_car,
    'walking': Icons.directions_walk,
    'bicycling': Icons.directions_bike,
    'transit': Icons.directions_bus,
  };

  @override
  void initState() {
    super.initState();
    _loadFavorites();
    _initCurrentLocation();
  }

  @override
  void dispose() {
    _startController.dispose();
    _endController.dispose();
    super.dispose();
  }

  Future<void> _initCurrentLocation() async {
    LocationPermission perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) return;
    final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high);
    _startLatLng = LatLng(pos.latitude, pos.longitude);
    _startController.text =
        '${pos.latitude.toStringAsFixed(6)}, ${pos.longitude.toStringAsFixed(6)}';
    _setMarker(_startLatLng!, 'Xuất phát', isStart: true);
    _moveCamera(_startLatLng!);
  }

  Future<void> _loadFavorites() async {
    final routes = await RouteDatabase.getAll();
    setState(() => _favoriteRoutes = routes);
  }

  // ── Geocoding API: địa chỉ → tọa độ ──────────────────────────────────────
  Future<LatLng?> _geocodeAddress(String address) async {
    final encoded = Uri.encodeComponent(address);
    final url =
        'https://maps.googleapis.com/maps/api/geocode/json?address=$encoded&key=$kGoogleApiKey';
    final response = await http.get(Uri.parse(url));
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data['results'] != null && (data['results'] as List).isNotEmpty) {
        final loc = data['results'][0]['geometry']['location'];
        return LatLng(loc['lat'] as double, loc['lng'] as double);
      }
    }
    return null;
  }

  void _setMarker(LatLng pos, String label, {required bool isStart}) {
    setState(() {
      _markers.removeWhere((m) => m.markerId.value == label);
      _markers.add(
        Marker(
          markerId: MarkerId(label),
          position: pos,
          infoWindow: InfoWindow(title: label),
          icon: isStart
              ? BitmapDescriptor.defaultMarkerWithHue(
                  BitmapDescriptor.hueGreen)
              : BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        ),
      );
    });
  }

  Future<void> _moveCamera(LatLng pos) async {
    if (!_controller.isCompleted) return;
    final c = await _controller.future;
    c.animateCamera(CameraUpdate.newLatLng(pos));
  }

  // ── Tìm đường đi ─────────────────────────────────────────────────────────
  Future<void> _findRoute() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _isLoading = true;
      _distance = null;
      _duration = null;
    });

    // Geocoding nếu nhập địa chỉ (không phải lat,lng)
    final startText = _startController.text.trim();
    final endText = _endController.text.trim();

    if (startText.isEmpty || endText.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Vui lòng nhập địa chỉ hoặc tọa độ!')),
        );
      }
      setState(() => _isLoading = false);
      return;
    }

    // Kiểm tra xem là lat,lng hay địa chỉ
    _startLatLng = _tryParseLatLng(startText) ?? await _geocodeAddress(startText);
    _endLatLng = _tryParseLatLng(endText) ?? await _geocodeAddress(endText);

    if (_startLatLng == null || _endLatLng == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Không tìm thấy địa chỉ!')),
        );
      }
      setState(() => _isLoading = false);
      return;
    }

    final url =
        'https://maps.googleapis.com/maps/api/directions/json'
        '?origin=${_startLatLng!.latitude},${_startLatLng!.longitude}'
        '&destination=${_endLatLng!.latitude},${_endLatLng!.longitude}'
        '&mode=$_travelMode'
        '&key=$kGoogleApiKey';

    final response = await http.get(Uri.parse(url));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data['routes'] != null && (data['routes'] as List).isNotEmpty) {
        final route = data['routes'][0];
        final leg = route['legs'][0];
        final points = _decodePolyline(route['overview_polyline']['points']);

        setState(() {
          _distance = leg['distance']['text'];
          _duration = leg['duration']['text'];
          _markers.clear();
          _setMarker(_startLatLng!, 'Xuất phát', isStart: true);
          _setMarker(_endLatLng!, 'Đích đến', isStart: false);
          _polylines.clear();
          _polylines.add(Polyline(
            polylineId: const PolylineId('route'),
            points: points,
            color: const Color(0xFFEA4335),
            width: 5,
          ));
          _isLoading = false;
        });
        _moveCamera(_startLatLng!);
      } else {
        setState(() => _isLoading = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Không tìm thấy tuyến đường!')),
          );
        }
      }
    } else {
      setState(() => _isLoading = false);
    }
  }

  // ── Lưu tuyến đường yêu thích ─────────────────────────────────────────────
  Future<void> _saveFavorite() async {
    if (_startLatLng == null || _endLatLng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Hãy tìm đường đi trước!')),
      );
      return;
    }

    final route = FavoriteRoute(
      startAddress: _startController.text.trim(),
      endAddress: _endController.text.trim(),
      startLat: _startLatLng!.latitude,
      startLng: _startLatLng!.longitude,
      endLat: _endLatLng!.latitude,
      endLng: _endLatLng!.longitude,
      travelMode: _travelMode,
    );

    await RouteDatabase.insert(route);
    await _loadFavorites();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đã lưu tuyến đường yêu thích!'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  // ── Tải lại tuyến đường yêu thích đã lưu ──────────────────────────────────
  void _loadFavoriteRoute(FavoriteRoute r) {
    setState(() {
      _startLatLng = LatLng(r.startLat, r.startLng);
      _endLatLng = LatLng(r.endLat, r.endLng);
      _startController.text = r.startAddress;
      _endController.text = r.endAddress;
      _travelMode = r.travelMode;
      _showFavorites = false;
    });
    _findRoute();
  }

  LatLng? _tryParseLatLng(String text) {
    final parts = text.split(',');
    if (parts.length != 2) return null;
    try {
      return LatLng(double.parse(parts[0].trim()), double.parse(parts[1].trim()));
    } catch (_) {
      return null;
    }
  }

  List<LatLng> _decodePolyline(String encoded) {
    List<LatLng> points = [];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;
    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;
      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;
      points.add(LatLng(lat / 1E5, lng / 1E5));
    }
    return points;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bài 4 – Full Route Finder'),
        backgroundColor: const Color(0xFFEA4335),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Badge(
              isLabelVisible: _favoriteRoutes.isNotEmpty,
              label: Text('${_favoriteRoutes.length}'),
              child: const Icon(Icons.favorite),
            ),
            tooltip: 'Tuyến đường yêu thích',
            onPressed: () => setState(() => _showFavorites = !_showFavorites),
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              // ── Form ────────────────────────────────────────────────────
              Container(
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                child: Column(
                  children: [
                    // Điểm xuất phát
                    TextField(
                      controller: _startController,
                      decoration: InputDecoration(
                        labelText: 'Điểm xuất phát (địa chỉ hoặc lat,lng)',
                        prefixIcon: const Icon(Icons.trip_origin,
                            color: Color(0xFF34A853)),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Điểm đích
                    TextField(
                      controller: _endController,
                      decoration: InputDecoration(
                        labelText: 'Điểm đích (địa chỉ hoặc lat,lng)',
                        prefixIcon: const Icon(Icons.location_on,
                            color: Colors.red),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Chọn loại phương tiện
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: _modeIcons.entries.map((entry) {
                          final selected = _travelMode == entry.key;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(entry.value, size: 16,
                                      color: selected ? Colors.white : Colors.grey[700]),
                                  const SizedBox(width: 4),
                                  Text(
                                    _modeName(entry.key),
                                    style: TextStyle(
                                      color: selected ? Colors.white : Colors.grey[700],
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                              selected: selected,
                              selectedColor: const Color(0xFFEA4335),
                              onSelected: (_) =>
                                  setState(() => _travelMode = entry.key),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _isLoading ? null : _findRoute,
                            icon: _isLoading
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.search, size: 18),
                            label:
                                Text(_isLoading ? 'Đang tìm...' : 'Tìm đường'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFEA4335),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: _saveFavorite,
                          icon: const Icon(Icons.favorite_border, size: 18),
                          label: const Text('Lưu'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.pink[100],
                            foregroundColor: Colors.pink,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ],
                    ),
                    // Khoảng cách / thời gian
                    if (_distance != null && _duration != null)
                      Container(
                        margin: const EdgeInsets.only(top: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.red[50],
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            Row(children: [
                              const Icon(Icons.straighten,
                                  size: 16, color: Colors.red),
                              const SizedBox(width: 4),
                              Text('$_distance',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600)),
                            ]),
                            Row(children: [
                              const Icon(Icons.timer,
                                  size: 16, color: Colors.red),
                              const SizedBox(width: 4),
                              Text('$_duration',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600)),
                            ]),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              // ── Bản đồ ──────────────────────────────────────────────────
              Expanded(
                child: GoogleMap(
                  initialCameraPosition: _initialPosition,
                  markers: _markers,
                  polylines: _polylines,
                  myLocationEnabled: true,
                  onMapCreated: (GoogleMapController c) {
                    _controller.complete(c);
                  },
                ),
              ),
            ],
          ),
          // ── Panel yêu thích ─────────────────────────────────────────────
          if (_showFavorites)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              bottom: 0,
              child: GestureDetector(
                onTap: () => setState(() => _showFavorites = false),
                child: Container(color: Colors.black45),
              ),
            ),
          if (_showFavorites)
            Positioned(
              top: 0,
              right: 0,
              bottom: 0,
              width: 300,
              child: Material(
                elevation: 8,
                child: Column(
                  children: [
                    Container(
                      color: const Color(0xFFEA4335),
                      padding: const EdgeInsets.fromLTRB(16, 40, 8, 12),
                      child: Row(
                        children: [
                          const Icon(Icons.favorite, color: Colors.white),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Tuyến đường yêu thích',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.white),
                            onPressed: () =>
                                setState(() => _showFavorites = false),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: _favoriteRoutes.isEmpty
                          ? const Center(
                              child: Text('Chưa có tuyến đường yêu thích'),
                            )
                          : ListView.separated(
                              itemCount: _favoriteRoutes.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, i) {
                                final r = _favoriteRoutes[i];
                                return ListTile(
                                  leading: Icon(
                                    _modeIcons[r.travelMode] ??
                                        Icons.directions_car,
                                    color: const Color(0xFFEA4335),
                                  ),
                                  title: Text(
                                    r.startAddress,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                  subtitle: Text(
                                    '→ ${r.endAddress}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  trailing: IconButton(
                                    icon: const Icon(Icons.delete_outline,
                                        color: Colors.grey),
                                    onPressed: () async {
                                      await RouteDatabase.delete(r.id!);
                                      await _loadFavorites();
                                    },
                                  ),
                                  onTap: () => _loadFavoriteRoute(r),
                                );
                              },
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

  String _modeName(String mode) {
    switch (mode) {
      case 'driving':
        return 'Xe hơi';
      case 'walking':
        return 'Đi bộ';
      case 'bicycling':
        return 'Xe đạp';
      case 'transit':
        return 'Công cộng';
      default:
        return mode;
    }
  }
}
