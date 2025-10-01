// ADD THESE IMPORT STATEMENTS AT THE TOP
import 'package:pzed_homes/data/models/menu_item.dart';
import 'package:pzed_homes/data/models/room.dart';
import 'package:pzed_homes/data/models/stock_item.dart';

// Room categories
const List<Map<String, dynamic>> mockRoomCategories = [
  {
    "type": "Standard",
    "price_ngn": 15000, 
    "rooms": ["101", "102", "103", "104", "105", "106", "107", "108"]
  },
  {
    "type": "Classic",
    "price_ngn": 20000,
    "rooms": ["109", "201", "202", "203", "204", "205", "206", "207", "208"]
  },
  {
    "type": "Diplomatic",
    "price_ngn": 25000,
    "rooms": ["209"]
  },
  {
    "type": "Deluxe",
    "price_ngn": 30000,
    "rooms": ["210", "211", "212"]
  },
  {
    "type": "Executive",
    "price_ngn": 50000,
    "rooms": ["213"]
  }
];

// Mock bookings
final List<Map<String, dynamic>> mockBookings = [
  {
    "guestName": "Adewale Johnson",
    "roomType": "Standard",
    "roomNumber": "102",
    "checkInDate": "2025-09-03T14:00:00Z",
    "checkOutDate": "2025-09-05T11:00:00Z",
    "status": "Checked-in",
    "extraCharges": []
  },
  {
    "guestName": "Chidinma Okoro",
    "roomType": "Executive",
    "roomNumber": "213",
    "checkInDate": "2025-09-03T16:00:00Z",
    "checkOutDate": "2025-09-04T11:00:00Z",
    "status": "Pending Check-in",
    "extraCharges": []
  },
  {
    "guestName": "Musa Bello",
    "roomType": "Classic",
    "roomNumber": "201",
    "checkInDate": "2025-09-01T12:00:00Z",
    "checkOutDate": "2025-09-03T10:00:00Z",
    "status": "Checked-out",
    "extraCharges": [
      {"item": "Laundry Service", "price": 3500}
    ]
  },
];

// Generate all rooms from categories
List<Room> generateAllRooms() {
  final List<Room> allRooms = [];
  
  int roomIdCounter = 1; // Counter for generating unique IDs
  
  for (var category in mockRoomCategories) {
    for (var roomNumber in category['rooms'] as List<String>) {
      final booking = mockBookings.firstWhere(
        (b) => b['roomNumber'] == roomNumber &&
               (b['status'] == 'Checked-in' || b['status'] == 'Pending Check-in'),
        orElse: () => {},
      );

      String status;
      if (booking.isNotEmpty) {
        status = 'Occupied';
      } else {
        status = (int.parse(roomNumber) % 5 == 0) ? 'Dirty' : 'Vacant';
      }

      allRooms.add(Room(
        id: 'room_${roomIdCounter++}', // Generate unique ID
        roomNumber: roomNumber,
        type: category['type'] as String,
        status: status,
      ));
    }
  }
  return allRooms;
}

// Master room list
final List<Room> mockAllRooms = generateAllRooms();

// Stock items
final List<StockItem> mockStockItems = [
  StockItem(id: 'stk01', name: 'Heineken', unit: 'bottles', currentQuantity: 48, reorderLevel: 12),
  StockItem(id: 'stk02', name: 'Coca-Cola', unit: 'bottles', currentQuantity: 72, reorderLevel: 24),
  StockItem(id: 'stk03', name: 'Bottled Water', unit: 'bottles', currentQuantity: 100, reorderLevel: 24),
  StockItem(id: 'stk04', name: 'Red Wine', unit: 'bottles', currentQuantity: 24, reorderLevel: 6),
  StockItem(id: 'stk05', name: 'Raw Chicken', unit: 'pieces', currentQuantity: 50, reorderLevel: 10),
  StockItem(id: 'stk06', name: 'Tilapia Fish', unit: 'pieces', currentQuantity: 30, reorderLevel: 5),
];

// Updated menu items linked to stock and barcodes
final List<MenuItem> mockMenuItems = [
  // Restaurant Items
  MenuItem(
    id: 'r01',
    name: 'Jollof Rice & Chicken',
    department: 'Restaurant',
    price: 3500, // Price in kobo (3500 kobo = ₦35.00)
    category: 'Food',
    stockItemId: 'stk05',
  ),
  MenuItem(
    id: 'r02',
    name: 'Goat Meat Peppersoup',
    department: 'Restaurant',
    price: 2500, // Price in kobo
    category: 'Food',
  ),
  MenuItem(
    id: 'r03',
    name: 'Grilled Tilapia',
    department: 'Restaurant',
    price: 4000, // Price in kobo
    category: 'Food',
    stockItemId: 'stk06',
  ),
  MenuItem(
    id: 'r04',
    name: 'Side Salad',
    department: 'Restaurant',
    price: 1500, // Price in kobo
    category: 'Food',
  ),

  // Bar Items with barcode support
  MenuItem(
    id: 'b01',
    name: 'Heineken',
    department: 'Bar',
    price: 1000, // Price in kobo
    category: 'Drink',
    stockItemId: 'stk01',
    barcode: '6151234567890',
  ),
  MenuItem(
    id: 'b02',
    name: 'Coca-Cola',
    department: 'Bar',
    price: 500, // Price in kobo
    category: 'Drink',
    stockItemId: 'stk02',
    barcode: '5449000000996',
  ),
  MenuItem(
    id: 'b03',
    name: 'Bottled Water',
    department: 'Bar',
    price: 300, // Price in kobo
    category: 'Drink',
    stockItemId: 'stk03',
    barcode: '6211234567891',
  ),
  MenuItem(
    id: 'b04',
    name: 'Red Wine (Glass)',
    department: 'Bar',
    price: 2000, // Price in kobo
    category: 'Drink',
    stockItemId: 'stk04',
  ),
];