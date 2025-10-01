import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:pzed_homes/presentation/screens/guest/guest_booking_screen.dart';

class AvailableRoomsScreen extends StatefulWidget {
  const AvailableRoomsScreen({super.key});

  @override
  State<AvailableRoomsScreen> createState() => _AvailableRoomsScreenState();
}

class _AvailableRoomsScreenState extends State<AvailableRoomsScreen> {
  late DateTime checkInDate;
  late DateTime checkOutDate;
  Future<List<Map<String, dynamic>>>? _availableRoomsFuture;
  final _supabase = Supabase.instance.client;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    // Fallback values
    checkInDate = DateTime.now();
    checkOutDate = DateTime.now().add(const Duration(days: 1));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = GoRouterState.of(context);
    final extra = state.extra as Map<String, dynamic>?;
    if (extra != null) {
      checkInDate = extra['checkInDate'] as DateTime;
      checkOutDate = extra['checkOutDate'] as DateTime;
    }
    _availableRoomsFuture = _fetchAvailableRooms();
  }

  Future<List<Map<String, dynamic>>> _fetchAvailableRooms() async {
    try {
      // Mock room types data - in production, this would come from Supabase
      await Future.delayed(const Duration(seconds: 1)); // Simulate network delay
      
      final mockRoomTypes = [
        {
          'id': '1',
          'type': 'Standard Room',
          'price': 15000,
          'description': 'Comfortable, affordable, and equipped with all the essentials for a pleasant stay.',
          'image_url': 'https://i.postimg.cc/13GjSg2f/nigerian-hotel-room-1.jpg',
          'available_count': 5,
          'amenities': ['WiFi', 'Air Conditioning', 'TV', 'Mini Bar'],
        },
        {
          'id': '2',
          'type': 'Classic Room',
          'price': 20000,
          'description': 'A touch of elegance with enhanced amenities and more space to relax and unwind.',
          'image_url': 'https://i.postimg.cc/yNnKkM0S/nigerian-hotel-classic-1.jpg',
          'available_count': 3,
          'amenities': ['WiFi', 'Air Conditioning', 'TV', 'Mini Bar', 'Balcony'],
        },
        {
          'id': '3',
          'type': 'Diplomatic Room',
          'price': 25000,
          'description': 'Spacious and refined, designed for the discerning traveler requiring extra comfort.',
          'image_url': 'https://i.postimg.cc/WbFfKx58/nigerian-hotel-diplomatic-1.jpg',
          'available_count': 2,
          'amenities': ['WiFi', 'Air Conditioning', 'TV', 'Mini Bar', 'Balcony', 'Room Service'],
        },
        {
          'id': '4',
          'type': 'Deluxe Room',
          'price': 30000,
          'description': 'A premium experience with superior furnishings and breathtaking views.',
          'image_url': 'https://i.postimg.cc/tJnB8t3P/nigerian-hotel-deluxe-1.jpg',
          'available_count': 1,
          'amenities': ['WiFi', 'Air Conditioning', 'TV', 'Mini Bar', 'Balcony', 'Room Service', 'Jacuzzi'],
        },
        {
          'id': '5',
          'type': 'Executive Suite',
          'price': 50000,
          'description': 'The pinnacle of luxury, featuring a separate living area and exclusive amenities.',
          'image_url': 'https://i.postimg.cc/sxGYb7D8/nigerian-hotel-executive-1.jpg',
          'available_count': 1,
          'amenities': ['WiFi', 'Air Conditioning', 'TV', 'Mini Bar', 'Balcony', 'Room Service', 'Jacuzzi', 'Butler Service'],
        },
      ];
      
      return mockRoomTypes;
    } catch (e, st) {
      debugPrint('Error fetching available rooms: $e');
      debugPrintStack(stackTrace: st);
      throw Exception('Failed to load available rooms. Please try again.');
    }
  }

  Future<void> _refreshRooms() async {
    setState(() => _isRefreshing = true);
    try {
      await _fetchAvailableRooms();
    } finally {
      if (mounted) {
        setState(() => _isRefreshing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormatter = NumberFormat.currency(locale: 'en_NG', symbol: '₦');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Available Rooms'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isRefreshing ? null : _refreshRooms,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshRooms,
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _availableRoomsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, size: 48, color: Colors.red),
                      const SizedBox(height: 16),
                      Text(
                        'Error loading rooms',
                        style: Theme.of(context).textTheme.titleMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        snapshot.error?.toString() ?? 'Unknown error occurred',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.grey),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _refreshRooms,
                        child: const Text('Try Again'),
                      ),
                    ],
                  ),
                ),
              );
            }
            
            final availableRooms = snapshot.data;
            if (availableRooms == null || availableRooms.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Image.asset(
                        'assets/images/PZED logo.png',
                        height: 48,
                        width: 48,
                        fit: BoxFit.contain,
                        color: Colors.grey,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'No rooms available',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Sorry, no rooms are available for the selected dates:\n'
                        '${DateFormat('MMM d, yyyy').format(checkInDate)} - '
                        '${DateFormat('MMM d, yyyy').format(checkOutDate)}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              );
            }

            return ListView.builder(
              itemCount: availableRooms.length,
              itemBuilder: (context, index) {
                final roomType = availableRooms[index];
                final price = (roomType['price'] is int) 
                    ? roomType['price'] as int 
                    : int.tryParse('${roomType['price']}') ?? 0;
                final imageUrl = (roomType['image_url'] as String?) ?? '';
                final availableCount = roomType['available_count'] as int? ?? 0;

                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  clipBehavior: Clip.antiAlias,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: InkWell(
                    onTap: availableCount > 0 ? () {
                      context.push('/guest/booking', extra: {
                        'roomType': roomType,
                        'checkInDate': checkInDate,
                        'checkOutDate': checkOutDate,
                      });
                    } : null,
                    child: Opacity(
                      opacity: availableCount > 0 ? 1.0 : 0.6,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (imageUrl.isNotEmpty)
                            Image.network(
                              imageUrl,
                              height: 200,
                              width: double.infinity,
                              fit: BoxFit.cover,
                              loadingBuilder: (context, child, loadingProgress) {
                                if (loadingProgress == null) return child;
                                return Container(
                                  height: 200,
                                  color: Colors.grey[300],
                                  child: Center(
                                    child: CircularProgressIndicator(
                                      value: loadingProgress.expectedTotalBytes != null
                                          ? loadingProgress.cumulativeBytesLoaded / 
                                            loadingProgress.expectedTotalBytes!
                                          : null,
                                    ),
                                  ),
                                );
                              },
                              errorBuilder: (context, error, stackTrace) {
                                return Container(
                                  height: 200,
                                  color: Colors.grey[300],
                                  alignment: Alignment.center,
                                  child: const Icon(Icons.image_not_supported, size: 48, color: Colors.grey),
                                );
                              },
                            )
                          else
                            Container(
                              height: 200,
                              color: Colors.grey[300],
                              alignment: Alignment.center,
                              child: Image.asset(
                                'assets/images/PZED logo.png',
                                height: 48,
                                width: 48,
                                fit: BoxFit.contain,
                                color: Colors.grey,
                              ),
                            ),
                          
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${roomType['type']}',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      availableCount > 0 
                                          ? '$availableCount room${availableCount > 1 ? 's' : ''} available'
                                          : 'Sold out',
                                      style: TextStyle(
                                        color: availableCount > 0 ? Colors.green : Colors.red,
                                      ),
                                    ),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          currencyFormatter.format(price),
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.green,
                                          ),
                                        ),
                                        const Text(
                                          '/ night',
                                          style: TextStyle(fontSize: 12),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}