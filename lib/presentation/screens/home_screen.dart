import 'package:flutter/material.dart';
import 'package:pzed_homes/presentation/widgets/room_card.dart';
import 'package:pzed_homes/data/models/room_category.dart';
import 'package:pzed_homes/core/error/error_handler.dart';
import 'package:pzed_homes/core/services/data_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Map<String, dynamic>> _roomTypes = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRoomTypes();
  }

  Future<void> _loadRoomTypes() async {
    try {
      final dataService = DataService();
      final roomTypes = await dataService.getRoomTypes();

      if (mounted) {
        setState(() {
          // Transform room_types data to match RoomCategory format
          _roomTypes = roomTypes.map((type) {
            return {
              'type': type['type'] ?? 'Unknown',
              'price_ngn': (type['price'] as int? ?? 0) ~/ 100, // Convert from kobo to naira
              'rooms': [], // Rooms are loaded separately
              'images': type['image_url'] != null ? [type['image_url']] : [],
            };
          }).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ErrorHandler.handleError(
          context,
          e,
          customMessage: 'Failed to load room types. Please try again.',
          onRetry: _loadRoomTypes,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('P-ZED Luxury Hotels & Suites'),
        backgroundColor: Colors.green,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadRoomTypes,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadRoomTypes,
              child: _roomTypes.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Image.asset(
                            'assets/images/PZED logo.png',
                            height: 64,
                            width: 64,
                            fit: BoxFit.contain,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'No room types available',
                            style: TextStyle(fontSize: 18, color: Colors.grey),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _roomTypes.length,
                      itemBuilder: (BuildContext context, int index) {
                        final roomType = _roomTypes[index];
                        return RoomCard(roomCategory: RoomCategory.fromMap(roomType));
                      },
                    ),
            ),
    );
  }
}