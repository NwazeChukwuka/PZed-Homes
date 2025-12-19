import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:pzed_homes/presentation/screens/guest/guest_booking_screen.dart';
import 'package:pzed_homes/core/theme/responsive_helpers.dart';

class AvailableRoomsScreen extends StatefulWidget {
  const AvailableRoomsScreen({super.key});

  @override
  State<AvailableRoomsScreen> createState() => _AvailableRoomsScreenState();
}

class _AvailableRoomsScreenState extends State<AvailableRoomsScreen> {
  late DateTime checkInDate;
  late DateTime checkOutDate;
  Future<List<Map<String, dynamic>>>? _availableRoomsFuture;
  bool _isRefreshing = false;

  // Get Supabase client safely (returns null if not initialized)
  SupabaseClient? get _supabase {
    try {
      return Supabase.instance.client;
    } catch (e) {
      return null;
    }
  }

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
    if (!mounted) return;
    
    try {
      final state = GoRouterState.of(context);
      final extra = state.extra as Map<String, dynamic>?;
      if (extra != null) {
        // Check if dates are provided
        if (extra['checkInDate'] != null) {
          final date = extra['checkInDate'];
          if (date is DateTime) {
            checkInDate = date;
          } else if (date is String) {
            checkInDate = DateTime.parse(date);
          }
        }
        if (extra['checkOutDate'] != null) {
          final date = extra['checkOutDate'];
          if (date is DateTime) {
            checkOutDate = date;
          } else if (date is String) {
            checkOutDate = DateTime.parse(date);
          }
        }
      }
    } catch (e) {
      debugPrint('Error getting dates from router: $e');
      // Use fallback values from initState
    }
    
    // Always fetch rooms (will use default dates if not provided)
    if (mounted) {
      _availableRoomsFuture = _fetchAvailableRooms();
    }
  }

  Future<List<Map<String, dynamic>>> _fetchAvailableRooms() async {
    // Check if Supabase is initialized
    if (_supabase == null) {
      // Return empty list - will show "Supabase not configured" message
      return [];
    }

    try {
      // Get conflicting bookings for the date range
      // Include bookings with room_id assigned AND bookings by requested_room_type
      final conflictingBookings = await _supabase!
          .from('bookings')
          .select('room_id, requested_room_type')
          .or('status.eq.Pending Check-in,status.eq.Checked-in')
          .lte('check_in_date', checkOutDate.toIso8601String())
          .gte('check_out_date', checkInDate.toIso8601String());

      // Get room types for booked rooms
      final bookedRoomIds = <String>{};
      for (var booking in conflictingBookings as List) {
        if (booking['room_id'] != null) {
          bookedRoomIds.add(booking['room_id'] as String);
        }
      }

      // Get room types for directly assigned rooms
      final bookedByType = <String, int>{};
      if (bookedRoomIds.isNotEmpty) {
        // Query all rooms and filter in code (more reliable than .in_())
        final allBookedRooms = await _supabase!
            .from('rooms')
            .select('id, type');
        
        for (var room in allBookedRooms as List) {
          final roomId = room['id'] as String? ?? '';
          if (bookedRoomIds.contains(roomId)) {
            final type = room['type'] as String? ?? '';
            if (type.isNotEmpty) {
              bookedByType[type] = (bookedByType[type] ?? 0) + 1;
            }
          }
        }
      }

      // Count bookings by requested room type (without room_id)
      for (var booking in conflictingBookings as List) {
        if (booking['room_id'] == null && booking['requested_room_type'] != null) {
          final type = booking['requested_room_type'] as String? ?? '';
          if (type.isNotEmpty) {
            bookedByType[type] = (bookedByType[type] ?? 0) + 1;
          }
        }
      }

      // Get all room types
      final roomTypes = await _supabase!
          .from('room_types')
          .select()
          .order('price');

      // Get all vacant rooms and group by type
      final allRooms = await _supabase!
          .from('rooms')
          .select('type_id, type, status')
          .eq('status', 'Vacant');

      // Count rooms by type_id
      final roomsByTypeId = <String, int>{};
      final typeNameByTypeId = <String, String>{};
      for (var room in allRooms as List) {
        final typeId = room['type_id'] as String? ?? '';
        final typeName = room['type'] as String? ?? '';
        if (typeId.isNotEmpty) {
          roomsByTypeId[typeId] = (roomsByTypeId[typeId] ?? 0) + 1;
          typeNameByTypeId[typeId] = typeName;
        }
      }

      // Calculate available count for each type
      final result = <Map<String, dynamic>>[];
      for (var type in roomTypes as List) {
        final typeId = type['id'] as String? ?? '';
        final typeName = type['type'] as String? ?? '';
        final totalRooms = roomsByTypeId[typeId] ?? 0;
        final booked = bookedByType[typeName] ?? 0;
        final available = totalRooms - booked;

        if (available > 0) {
          result.add({
            'id': typeId,
            'type': typeName,
            'price': type['price'] ?? 0,
            'description': type['description'] ?? '',
            'image_url': type['image_url'],
            'available_count': available,
            'amenities': type['amenities'] ?? [],
          });
        }
      }

      return result;
    } catch (e, st) {
      debugPrint('Error fetching available rooms: $e');
      debugPrint('Stack trace: $st');
      // Return more detailed error for debugging
      if (e is Exception) {
        debugPrint('Exception details: ${e.toString()}');
      }
      // Re-throw with more context
      throw Exception('Failed to load available rooms: ${e.toString()}');
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

  Future<void> _selectDate(bool isCheckIn) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isCheckIn ? checkInDate : checkOutDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() {
        if (isCheckIn) {
          checkInDate = picked;
          // Ensure check-out is after check-in
          if (checkOutDate.isBefore(checkInDate) || checkOutDate.isAtSameMomentAs(checkInDate)) {
            checkOutDate = checkInDate.add(const Duration(days: 1));
          }
        } else {
          checkOutDate = picked;
          // Ensure check-out is after check-in
          if (checkOutDate.isBefore(checkInDate) || checkOutDate.isAtSameMomentAs(checkInDate)) {
            checkInDate = checkOutDate.subtract(const Duration(days: 1));
          }
        }
        _availableRoomsFuture = _fetchAvailableRooms();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormatter = NumberFormat.currency(locale: 'en_NG', symbol: '₦');
    final isMobile = ResponsiveHelper.isMobile(context);

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
        child: Column(
          children: [
            // Date selection card
            Container(
              margin: ResponsiveHelper.getResponsivePadding(
                context,
                mobile: const EdgeInsets.all(12),
                tablet: const EdgeInsets.all(16),
                desktop: const EdgeInsets.all(16),
              ),
              padding: ResponsiveHelper.getResponsivePadding(
                context,
                mobile: const EdgeInsets.all(12),
                tablet: const EdgeInsets.all(16),
                desktop: const EdgeInsets.all(16),
              ),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: isMobile
                  ? Column(
                      children: [
                        InkWell(
                          onTap: () => _selectDate(true),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Check-in',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      DateFormat('MMM d, yyyy').format(checkInDate),
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                                const Icon(Icons.calendar_today, size: 20, color: Colors.grey),
                              ],
                            ),
                          ),
                        ),
                        Divider(height: 1, thickness: 1, color: Colors.grey[300]),
                        InkWell(
                          onTap: () => _selectDate(false),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Check-out',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      DateFormat('MMM d, yyyy').format(checkOutDate),
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                                const Icon(Icons.calendar_today, size: 20, color: Colors.grey),
                              ],
                            ),
                          ),
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () => _selectDate(true),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Check-in',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  DateFormat('MMM d, yyyy').format(checkInDate),
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Container(
                          width: 1,
                          height: 40,
                          color: Colors.grey[300],
                        ),
                        Expanded(
                          child: InkWell(
                            onTap: () => _selectDate(false),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Check-out',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  DateFormat('MMM d, yyyy').format(checkOutDate),
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
            // Rooms list
            Expanded(
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
            
            // Check if Supabase is not configured
            if (_supabase == null) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.cloud_off,
                        size: 64,
                        color: Colors.orange,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Supabase Not Configured',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'This feature requires Supabase to be configured.\n'
                        'Please set your Supabase credentials to view available rooms.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.arrow_back),
                        label: const Text('Go Back'),
                      ),
                    ],
                  ),
                ),
              );
            }
            
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

                final imageHeight = ResponsiveHelper.getResponsiveValue(
                  context,
                  mobile: 180.0,
                  tablet: 200.0,
                  desktop: 220.0,
                );

                return Card(
                  margin: ResponsiveHelper.getResponsivePadding(
                    context,
                    mobile: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    tablet: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    desktop: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  ),
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
                              height: imageHeight,
                              width: double.infinity,
                              fit: BoxFit.cover,
                              loadingBuilder: (context, child, loadingProgress) {
                                if (loadingProgress == null) return child;
                                return Container(
                                  height: imageHeight,
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
                                  height: imageHeight,
                                  color: Colors.grey[300],
                                  alignment: Alignment.center,
                                  child: const Icon(Icons.image_not_supported, size: 48, color: Colors.grey),
                                );
                              },
                            )
                          else
                            Container(
                              height: imageHeight,
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
                            padding: ResponsiveHelper.getResponsivePadding(
                              context,
                              mobile: const EdgeInsets.all(12),
                              tablet: const EdgeInsets.all(16),
                              desktop: const EdgeInsets.all(16),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Room Type Name - with overflow handling
                                Text(
                                  '${roomType['type']}',
                                  style: TextStyle(
                                    fontSize: ResponsiveHelper.getResponsiveFontSize(
                                      context,
                                      mobile: 16,
                                      tablet: 18,
                                      desktop: 20,
                                    ),
                                    fontWeight: FontWeight.bold,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                
                                // Description if available
                                if (roomType['description'] != null && 
                                    (roomType['description'] as String).isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    roomType['description'] as String,
                                    style: TextStyle(
                                      fontSize: ResponsiveHelper.getResponsiveFontSize(
                                        context,
                                        mobile: 12,
                                        tablet: 13,
                                        desktop: 14,
                                      ),
                                      color: Colors.grey[600],
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                                
                                // Amenities if available
                                if (roomType['amenities'] != null && 
                                    (roomType['amenities'] as List).isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Wrap(
                                    spacing: 4,
                                    runSpacing: 4,
                                    children: (roomType['amenities'] as List)
                                        .take(3) // Limit to 3 amenities on mobile
                                        .map<Widget>((amenity) {
                                      final amenityStr = amenity.toString();
                                      return Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.grey[200],
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          amenityStr,
                                          style: TextStyle(
                                            fontSize: ResponsiveHelper.getResponsiveFontSize(
                                              context,
                                              mobile: 10,
                                              tablet: 11,
                                              desktop: 12,
                                            ),
                                            color: Colors.grey[700],
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ],
                                
                                const SizedBox(height: 8),
                                
                                // Availability and Price
                                isMobile
                                    ? Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            availableCount > 0 
                                                ? '$availableCount room${availableCount > 1 ? 's' : ''} available'
                                                : 'Sold out',
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: availableCount > 0 ? Colors.green : Colors.red,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 4),
                                          Row(
                                            children: [
                                              Flexible(
                                                child: Text(
                                                  currencyFormatter.format(price),
                                                  style: const TextStyle(
                                                    fontSize: 18,
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.green,
                                                  ),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                              const SizedBox(width: 4),
                                              const Text(
                                                '/ night',
                                                style: TextStyle(fontSize: 12),
                                              ),
                                            ],
                                          ),
                                        ],
                                      )
                                    : Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Flexible(
                                            child: Text(
                                              availableCount > 0 
                                                  ? '$availableCount room${availableCount > 1 ? 's' : ''} available'
                                                  : 'Sold out',
                                              style: TextStyle(
                                                fontSize: ResponsiveHelper.getResponsiveFontSize(
                                                  context,
                                                  mobile: 14,
                                                  tablet: 15,
                                                  desktop: 16,
                                                ),
                                                color: availableCount > 0 ? Colors.green : Colors.red,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          Column(
                                            crossAxisAlignment: CrossAxisAlignment.end,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                currencyFormatter.format(price),
                                                style: TextStyle(
                                                  fontSize: ResponsiveHelper.getResponsiveFontSize(
                                                    context,
                                                    mobile: 16,
                                                    tablet: 18,
                                                    desktop: 20,
                                                  ),
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.green,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
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
          ],
        ),
      ),
    );
  }
}