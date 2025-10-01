// Location: lib/presentation/widgets/room_card.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pzed_homes/presentation/screens/room_details_screen.dart';
import '../../data/models/room_category.dart';

class RoomCard extends StatefulWidget {
  final RoomCategory roomCategory;

  const RoomCard({
    super.key,
    required this.roomCategory,
  });

  @override
  State<RoomCard> createState() => _RoomCardState();
}

class _RoomCardState extends State<RoomCard> {
  bool _isNavigating = false;

  @override
  Widget build(BuildContext context) {
    final currencyFormatter = NumberFormat.currency(locale: 'en_NG', symbol: '₦');

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias, // Ensures the InkWell ripple effect is contained
      child: InkWell(
        // This makes the card tappable
        onTap: () async {
          if (_isNavigating) return;
          
          setState(() => _isNavigating = true);
          
          try {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => RoomDetailsScreen(
                  roomType: {
                    'name': widget.roomCategory.type,
                    'price': widget.roomCategory.priceNgn,
                    'description': '${widget.roomCategory.roomCount} rooms available',
                    'id': widget.roomCategory.type.hashCode.toString(),
                  },
                ),
              ),
            );
          } catch (e) {
            print('DEBUG: Room card navigation error: $e');
          } finally {
            if (mounted) {
              setState(() => _isNavigating = false);
            }
          }
        },
        child: ListTile(
          contentPadding: const EdgeInsets.all(16),
          title: Text(
            widget.roomCategory.type,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          subtitle: Text(
            '${widget.roomCategory.roomCount} rooms available',
            style: TextStyle(color: Colors.grey[600]),
          ),
          trailing: Text(
            currencyFormatter.format(widget.roomCategory.priceNgn),
            style: const TextStyle(
              color: Colors.green,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ),
      ),
    );
  }
}