// ─────────────────────────────────────────────────────────────────────────────
// BÀI 3: Bổ sung các chức năng:
//   - Nút lấy vị trí hiện tại làm điểm đích
//   - Hiển thị khoảng cách và thời gian di chuyển (từ Directions API)
//   - Chọn điểm trên bản đồ bằng cách nhấn (onTap)
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'maps_screen.dart'; // kGoogleApiKey

class RouteFinderExtendedScreen extends StatefulWidget {
  const RouteFinderExtendedScreen({super.key});

  @override
  State<RouteFinderExtendedScreen> createState() =>
      _RouteFinderExtendedScreenState();
}

class _RouteFinderExtendedScreenState
    extends State<RouteFinderExtendedScreen> {
  final Completer<GoogleMapController> _controller = Completer();
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};

  final TextEditingController _startController = TextEditingController();
  final TextEditingController _endController = TextEditingController();

  LatLng? _startLatLng;
  LatLng? _endLatLng;
  LatLng? _currentPosition;

  String? _distance;
  String? _duration;

  // Trạng thái: đang chọn điểm xuất phát hay đích đến khi nhấn bản đồ
  // 'start' | 'end' | null
  String? _selectingMode;

  static const CameraPosition _initialPosition = CameraPosition(
    target: LatLng(10.7769, 106.7009),
    zoom: 12,
  );

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
  }

  @override
  void dispose() {
    _startController.dispose();
    _endController.dispose();
    super.dispose();
  }

  Future<void> _getCurrentLocation() async {
    LocationPermission permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) return;

    final Position position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );

    setState(() {
      _currentPosition = LatLng(position.latitude, position.longitude);
      _startLatLng = _currentPosition;
      _startController.text =
          '${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}';
      _setMarker(_startLatLng!, 'Xuất phát', isStart: true);
      _moveCamera(_startLatLng!);
    });
  }

  // Lấy vị trí hiện tại và đặt làm ĐIỂM ĐÍCH
  Future<void> _setCurrentAsDestination() async {
    if (_currentPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chưa lấy được vị trí hiện tại!')),
      );
      return;
    }
    setState(() {
      _endLatLng = _currentPosition;
      _endController.text =
          '${_currentPosition!.latitude.toStringAsFixed(6)}, ${_currentPosition!.longitude.toStringAsFixed(6)}';
      _setMarker(_endLatLng!, 'Đích đến', isStart: false);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Đã đặt vị trí hiện tại làm điểm đích!')),
    );
  }

  void _setMarker(LatLng position, String label, {required bool isStart}) {
    final markerId = MarkerId(label);
    _markers.removeWhere((m) => m.markerId == markerId);
    _markers.add(
      Marker(
        markerId: markerId,
        position: position,
        infoWindow: InfoWindow(title: label),
        icon: isStart
            ? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen)
            : BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      ),
    );
  }

  Future<void> _moveCamera(LatLng position) async {
    final GoogleMapController controller = await _controller.future;
    controller.animateCamera(CameraUpdate.newLatLng(position));
  }

  // Xử lý khi người dùng nhấn vào bản đồ
  void _onMapTap(LatLng tapped) {
    if (_selectingMode == null) return;

    final String coords =
        '${tapped.latitude.toStringAsFixed(6)}, ${tapped.longitude.toStringAsFixed(6)}';

    setState(() {
      if (_selectingMode == 'start') {
        _startLatLng = tapped;
        _startController.text = coords;
        _setMarker(tapped, 'Xuất phát', isStart: true);
      } else {
        _endLatLng = tapped;
        _endController.text = coords;
        _setMarker(tapped, 'Đích đến', isStart: false);
      }
      _selectingMode = null; // Hủy chế độ chọn sau khi chọn xong
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${_selectingMode == null ? "Đã chọn" : ""} điểm: $coords',
        ),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  Future<void> _findRoute() async {
    if (_startLatLng == null || _endLatLng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vui lòng chọn đủ điểm xuất phát và đích đến!'),
        ),
      );
      return;
    }

    final String url =
        'https://maps.googleapis.com/maps/api/directions/json'
        '?origin=${_startLatLng!.latitude},${_startLatLng!.longitude}'
        '&destination=${_endLatLng!.latitude},${_endLatLng!.longitude}'
        '&key=$kGoogleApiKey';

    final response = await http.get(Uri.parse(url));

    if (response.statusCode == 200) {
      final Map<String, dynamic> data = jsonDecode(response.body);
      if (data['routes'] != null && (data['routes'] as List).isNotEmpty) {
        final route = data['routes'][0];
        final leg = route['legs'][0];

        final String polylinePoints = route['overview_polyline']['points'];
        final List<LatLng> points = _decodePolyline(polylinePoints);

        setState(() {
          _distance = leg['distance']['text'];
          _duration = leg['duration']['text'];
          _polylines.clear();
          _polylines.add(
            Polyline(
              polylineId: const PolylineId('route'),
              points: points,
              color: const Color(0xFFFBBC05),
              width: 5,
            ),
          );
        });
        _moveCamera(_startLatLng!);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Không tìm thấy tuyến đường!')),
          );
        }
      }
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
        title: const Text('Bài 3 – Route + Distance'),
        backgroundColor: const Color(0xFFFBBC05),
        foregroundColor: Colors.black,
      ),
      body: Column(
        children: [
          // ── Form nhập điểm ──────────────────────────────────
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Column(
              children: [
                // Điểm xuất phát
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _startController,
                        decoration: InputDecoration(
                          labelText: 'Điểm xuất phát (lat, lng)',
                          prefixIcon: const Icon(Icons.trip_origin,
                              color: Color(0xFF34A853)),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10)),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                        ),
                        keyboardType: TextInputType.number,
                        onChanged: (v) {
                          final parts = v.split(',');
                          if (parts.length == 2) {
                            try {
                              _startLatLng = LatLng(
                                double.parse(parts[0].trim()),
                                double.parse(parts[1].trim()),
                              );
                            } catch (_) {}
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 6),
                    // Nút chọn điểm xuất phát trên bản đồ
                    _SelectOnMapButton(
                      active: _selectingMode == 'start',
                      color: const Color(0xFF34A853),
                      onPressed: () {
                        setState(() {
                          _selectingMode =
                              _selectingMode == 'start' ? null : 'start';
                        });
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(_selectingMode == 'start'
                                ? 'Nhấn vào bản đồ để chọn điểm xuất phát'
                                : 'Đã hủy chọn điểm'),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Điểm đích
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _endController,
                        decoration: InputDecoration(
                          labelText: 'Điểm đích (lat, lng)',
                          prefixIcon: const Icon(Icons.location_on,
                              color: Colors.red),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10)),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                        ),
                        keyboardType: TextInputType.number,
                        onChanged: (v) {
                          final parts = v.split(',');
                          if (parts.length == 2) {
                            try {
                              _endLatLng = LatLng(
                                double.parse(parts[0].trim()),
                                double.parse(parts[1].trim()),
                              );
                            } catch (_) {}
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 6),
                    // Nút chọn điểm đích trên bản đồ
                    _SelectOnMapButton(
                      active: _selectingMode == 'end',
                      color: Colors.red,
                      onPressed: () {
                        setState(() {
                          _selectingMode =
                              _selectingMode == 'end' ? null : 'end';
                        });
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(_selectingMode == 'end'
                                ? 'Nhấn vào bản đồ để chọn điểm đích'
                                : 'Đã hủy chọn điểm'),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _setCurrentAsDestination,
                        icon: const Icon(Icons.my_location, size: 18),
                        label: const Text('Vị trí hiện tại → Đích'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _findRoute,
                        icon: const Icon(Icons.directions, size: 18),
                        label: const Text('Tìm đường'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFBBC05),
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                  ],
                ),
                // Thông tin khoảng cách / thời gian
                if (_distance != null && _duration != null)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF8E1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFFBBC05)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.straighten,
                                size: 18, color: Colors.orange),
                            const SizedBox(width: 4),
                            Text('Khoảng cách: $_distance',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                        Row(
                          children: [
                            const Icon(Icons.timer,
                                size: 18, color: Colors.orange),
                            const SizedBox(width: 4),
                            Text('Thời gian: $_duration',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ],
                    ),
                  ),
                // Hướng dẫn chọn điểm
                if (_selectingMode != null)
                  Container(
                    margin: const EdgeInsets.only(top: 6),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.touch_app,
                            size: 16, color: Colors.blue),
                        const SizedBox(width: 6),
                        Text(
                          'Nhấn lên bản đồ để chọn ${_selectingMode == "start" ? "điểm xuất phát" : "điểm đích"}',
                          style: const TextStyle(
                              color: Colors.blue, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          // ── Bản đồ ────────────────────────────────────────
          Expanded(
            child: GoogleMap(
              initialCameraPosition: _initialPosition,
              markers: _markers,
              polylines: _polylines,
              myLocationEnabled: true,
              onMapCreated: (GoogleMapController controller) {
                _controller.complete(controller);
              },
              onTap: _onMapTap,
            ),
          ),
        ],
      ),
    );
  }
}

/// Nút nhỏ để bật chế độ chọn điểm trên bản đồ
class _SelectOnMapButton extends StatelessWidget {
  final bool active;
  final Color color;
  final VoidCallback onPressed;

  const _SelectOnMapButton({
    required this.active,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: active ? color : color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color),
        ),
        child: Icon(
          Icons.touch_app,
          color: active ? Colors.white : color,
          size: 20,
        ),
      ),
    );
  }
}
