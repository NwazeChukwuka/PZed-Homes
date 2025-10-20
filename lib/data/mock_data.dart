// Comprehensive Mock Data for P-Zed Luxury Hotels & Suites
import 'package:pzed_homes/data/models/menu_item.dart';
import 'package:pzed_homes/data/models/room.dart';
import 'package:pzed_homes/data/models/stock_item.dart';
import 'package:pzed_homes/data/models/user.dart';

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
List<Map<String, dynamic>> generateAllRooms() {
  final List<Map<String, dynamic>> allRooms = [];
  
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

      allRooms.add({
        'id': 'room_${roomIdCounter++}', // Generate unique ID
        'roomNumber': roomNumber,
        'type': category['type'] as String,
        'status': status,
      });
    }
  }
  return allRooms;
}

// Master room list
final List<Map<String, dynamic>> mockAllRooms = generateAllRooms();

// Stock items
final List<Map<String, dynamic>> mockStockItems = [
  {'id': 'stk01', 'name': 'Heineken', 'unit': 'bottles', 'currentQuantity': 48, 'reorderLevel': 12},
  {'id': 'stk02', 'name': 'Coca-Cola', 'unit': 'bottles', 'currentQuantity': 72, 'reorderLevel': 24},
  {'id': 'stk03', 'name': 'Bottled Water', 'unit': 'bottles', 'currentQuantity': 100, 'reorderLevel': 24},
  {'id': 'stk04', 'name': 'Red Wine', 'unit': 'bottles', 'currentQuantity': 24, 'reorderLevel': 6},
  {'id': 'stk05', 'name': 'Raw Chicken', 'unit': 'pieces', 'currentQuantity': 50, 'reorderLevel': 10},
  {'id': 'stk06', 'name': 'Tilapia Fish', 'unit': 'pieces', 'currentQuantity': 30, 'reorderLevel': 5},
];

// Updated menu items linked to stock and barcodes
final List<Map<String, dynamic>> mockMenuItems = [
  // Restaurant Items
  {
    'id': 'r01',
    'name': 'Jollof Rice & Chicken',
    'department': 'Restaurant',
    'price': 3500, // Price in kobo (3500 kobo = ₦35.00)
    'category': 'Food',
    'stockItemId': 'stk05',
  },
  {
    'id': 'r02',
    'name': 'Goat Meat Peppersoup',
    'department': 'Restaurant',
    'price': 2500, // Price in kobo
    'category': 'Food',
  },
  {
    'id': 'r03',
    'name': 'Grilled Tilapia',
    'department': 'Restaurant',
    'price': 4000, // Price in kobo
    'category': 'Food',
    'stockItemId': 'stk06',
  },
  {
    'id': 'r04',
    'name': 'Side Salad',
    'department': 'Restaurant',
    'price': 1500, // Price in kobo
    'category': 'Food',
  },

  // Bar Items with barcode support
  {
    'id': 'b01',
    'name': 'Heineken',
    'department': 'Bar',
    'price': 1000, // Price in kobo
    'category': 'Drink',
    'stockItemId': 'stk01',
    'barcode': '6151234567890',
  },
  {
    'id': 'b02',
    'name': 'Coca-Cola',
    'department': 'Bar',
    'price': 500, // Price in kobo
    'category': 'Drink',
    'stockItemId': 'stk02',
    'barcode': '5449000000996',
  },
  {
    'id': 'b03',
    'name': 'Bottled Water',
    'department': 'Bar',
    'price': 300, // Price in kobo
    'category': 'Drink',
    'stockItemId': 'stk03',
    'barcode': '6211234567891',
  },
  {
    'id': 'b04',
    'name': 'Red Wine (Glass)',
    'department': 'Bar',
    'price': 2000, // Price in kobo
    'category': 'Drink',
    'stockItemId': 'stk04',
  },
];

// Comprehensive MockData class with all features
class MockData {
  static List<Map<String, dynamic>> _bookings = [];
  static List<Map<String, dynamic>> _rooms = [];
  static List<Map<String, dynamic>> _staffProfiles = [];
  static List<Map<String, dynamic>> _inventoryItems = [];
  static List<Map<String, dynamic>> _stockTransactions = [];
  static List<Map<String, dynamic>> _expenses = [];
  static List<Map<String, dynamic>> _incomeRecords = [];
  static List<Map<String, dynamic>> _payrollRecords = [];
  static List<Map<String, dynamic>> _cashDeposits = [];
  static List<Map<String, dynamic>> _staffRoleAssignments = [];
  static List<Map<String, dynamic>> _debts = [];
  static List<Map<String, dynamic>> _purchases = [];

  // Initialize with comprehensive mock data
  static void _initializeData() {
    if (_bookings.isNotEmpty) return; // Already initialized

    // Staff Profiles with comprehensive Igbo names
    _staffProfiles = [
      {
        'id': 'staff001',
        'name': 'Chukwudi Okonkwo',
        'email': 'chukwudi.okonkwo@pzed.com',
        'role': 'owner',
        'department': 'management',
        'phone': '+2348012345678',
        'is_active': true,
        'hire_date': '2020-01-15',
        'salary': 500000,
      },
      {
        'id': 'staff002',
        'name': 'Adaeze Nwankwo',
        'email': 'adaeze.nwankwo@pzed.com',
        'role': 'manager',
        'department': 'management',
        'phone': '+2348012345679',
        'is_active': true,
        'hire_date': '2021-03-20',
        'salary': 350000,
      },
      {
        'id': 'staff003',
        'name': 'Emeka Onyeka',
        'email': 'emeka.onyeka@pzed.com',
        'role': 'receptionist',
        'department': 'front_desk',
        'phone': '+2348012345680',
        'is_active': true,
        'hire_date': '2022-01-10',
        'salary': 180000,
      },
      {
        'id': 'staff004',
        'name': 'Chioma Eze',
        'email': 'chioma.eze@pzed.com',
        'role': 'storekeeper',
        'department': 'store',
        'phone': '+2348012345681',
        'is_active': true,
        'hire_date': '2021-06-15',
        'salary': 150000,
      },
      {
        'id': 'staff005',
        'name': 'Ikenna Okafor',
        'email': 'ikenna.okafor@pzed.com',
        'role': 'purchaser',
        'department': 'procurement',
        'phone': '+2348012345682',
        'is_active': true,
        'hire_date': '2021-08-01',
        'salary': 200000,
      },
      {
        'id': 'staff006',
        'name': 'Ngozi Igwe',
        'email': 'ngozi.igwe@pzed.com',
        'role': 'accountant',
        'department': 'finance',
        'phone': '+2348012345683',
        'is_active': true,
        'hire_date': '2021-02-14',
        'salary': 220000,
      },
      {
        'id': 'staff007',
        'name': 'Obinna Nwosu',
        'email': 'obinna.nwosu@pzed.com',
        'role': 'kitchen_staff',
        'department': 'kitchen',
        'phone': '+2348012345684',
        'is_active': true,
        'hire_date': '2022-03-01',
        'salary': 120000,
      },
      {
        'id': 'staff008',
        'name': 'Amara Chukwu',
        'email': 'amara.chukwu@pzed.com',
        'role': 'bartender',
        'department': 'vip_bar',
        'phone': '+2348012345685',
        'is_active': true,
        'hire_date': '2021-09-15',
        'salary': 130000,
      },
      {
        'id': 'staff009',
        'name': 'Kelechi Ogbonna',
        'email': 'kelechi.ogbonna@pzed.com',
        'role': 'bartender',
        'department': 'outside_bar',
        'phone': '+2348012345686',
        'is_active': true,
        'hire_date': '2021-11-20',
        'salary': 130000,
      },
      {
        'id': 'staff010',
        'name': 'Ifeoma Nwosu',
        'email': 'ifeoma.nwosu@pzed.com',
        'role': 'hr',
        'department': 'human_resources',
        'phone': '+2348012345687',
        'is_active': true,
        'hire_date': '2021-04-10',
        'salary': 250000,
      },
      {
        'id': 'staff011',
        'name': 'Chidi Nwankwo',
        'email': 'chidi.nwankwo@pzed.com',
        'role': 'supervisor',
        'department': 'operations',
        'phone': '+2348012345688',
        'is_active': true,
        'hire_date': '2021-07-05',
        'salary': 200000,
      },
      {
        'id': 'staff012',
        'name': 'Uchechi Okoro',
        'email': 'uchechi.okoro@pzed.com',
        'role': 'housekeeper',
        'department': 'housekeeping',
        'phone': '+2348012345689',
        'is_active': true,
        'hire_date': '2022-02-15',
        'salary': 100000,
      },
      {
        'id': 'staff013',
        'name': 'Chinedu Eze',
        'email': 'chinedu.eze@pzed.com',
        'role': 'security',
        'department': 'security',
        'phone': '+2348012345690',
        'is_active': true,
        'hire_date': '2021-12-01',
        'salary': 110000,
      },
      {
        'id': 'staff014',
        'name': 'Nkemka Ogbonna',
        'email': 'nkemka.ogbonna@pzed.com',
        'role': 'laundry_attendant',
        'department': 'housekeeping',
        'phone': '+2348012345691',
        'is_active': true,
        'hire_date': '2022-04-20',
        'salary': 95000,
      },
      {
        'id': 'staff015',
        'name': 'Onyinye Nwosu',
        'email': 'onyinye.nwosu@pzed.com',
        'role': 'cleaner',
        'department': 'housekeeping',
        'phone': '+2348012345692',
        'is_active': true,
        'hire_date': '2022-05-10',
        'salary': 90000,
      },
    ];

    // Rooms
    _rooms = [
      {'id': '101', 'type': 'Standard', 'status': 'available', 'price': 15000},
      {'id': '102', 'type': 'Standard', 'status': 'occupied', 'price': 15000},
      {'id': '103', 'type': 'Standard', 'status': 'maintenance', 'price': 15000},
      {'id': '109', 'type': 'Classic', 'status': 'available', 'price': 20000},
      {'id': '201', 'type': 'Classic', 'status': 'occupied', 'price': 20000},
      {'id': '209', 'type': 'Diplomatic', 'status': 'available', 'price': 25000},
      {'id': '210', 'type': 'Deluxe', 'status': 'occupied', 'price': 30000},
      {'id': '211', 'type': 'Deluxe', 'status': 'available', 'price': 30000},
      {'id': '301', 'type': 'Executive', 'status': 'available', 'price': 50000},
      {'id': '302', 'type': 'Executive', 'status': 'occupied', 'price': 50000},
    ];

    // Bookings with Igbo guest names
    _bookings = [
      {
        'id': 'booking001',
        'guest_name': 'Chinonso Okonkwo',
        'room_id': '102',
        'check_in': '2024-01-15',
        'check_out': '2024-01-18',
        'status': 'checked_in',
        'total_amount': 45000,
        'payment_status': 'paid',
        'processed_by': 'staff003', // receptionist
      },
      {
        'id': 'booking002',
        'guest_name': 'Adanna Nwosu',
        'room_id': '201',
        'check_in': '2024-01-16',
        'check_out': '2024-01-20',
        'status': 'confirmed',
        'total_amount': 80000,
        'payment_status': 'pending',
        'processed_by': 'staff003',
      },
      {
        'id': 'booking003',
        'guest_name': 'Emmanuel Eze',
        'room_id': '210',
        'check_in': '2024-01-17',
        'check_out': '2024-01-19',
        'status': 'checked_out',
        'total_amount': 60000,
        'payment_status': 'paid',
        'processed_by': 'staff003',
      },
      {
        'id': 'booking004',
        'guest_name': 'Ngozi Okafor',
        'room_id': '301',
        'check_in': '2024-01-18',
        'check_out': '2024-01-21',
        'status': 'checked_in',
        'total_amount': 150000,
        'payment_status': 'paid',
        'processed_by': 'staff003',
      },
      {
        'id': 'booking005',
        'guest_name': 'Chidi Nwankwo',
        'room_id': '211',
        'check_in': '2024-01-19',
        'check_out': '2024-01-22',
        'status': 'confirmed',
        'total_amount': 90000,
        'payment_status': 'pending',
        'processed_by': 'staff003',
      },
    ];

    // Inventory Items with two-bar pricing
    _inventoryItems = [
      {
        'id': 'item001',
        'name': 'Premium Whiskey',
        'category': 'Alcoholic Drinks',
        'current_stock': 25,
        'vip_bar_price': 2500,
        'outside_bar_price': 2000,
        'department': 'vip_bar',
        'description': 'Premium imported whiskey',
        'unit': 'bottle',
      },
      {
        'id': 'item002',
        'name': 'Local Beer',
        'category': 'Alcoholic Drinks',
        'current_stock': 50,
        'vip_bar_price': 800,
        'outside_bar_price': 600,
        'department': 'outside_bar',
        'description': 'Local beer brand',
        'unit': 'bottle',
      },
      {
        'id': 'item003',
        'name': 'Coca Cola',
        'category': 'Soft Drinks',
        'current_stock': 100,
        'vip_bar_price': 300,
        'outside_bar_price': 250,
        'department': 'both',
        'description': 'Carbonated soft drink',
        'unit': 'bottle',
      },
      {
        'id': 'item004',
        'name': 'Mineral Water',
        'category': 'Soft Drinks',
        'current_stock': 75,
        'vip_bar_price': 200,
        'outside_bar_price': 150,
        'department': 'both',
        'description': 'Bottled mineral water',
        'unit': 'bottle',
      },
      {
        'id': 'item005',
        'name': 'Chocolate Bar',
        'category': 'Snacks',
        'current_stock': 30,
        'vip_bar_price': 500,
        'outside_bar_price': 400,
        'department': 'both',
        'description': 'Premium chocolate bar',
        'unit': 'piece',
      },
    ];

    // Stock Transactions
    _stockTransactions = [
      {
        'id': 'tx001',
        'item_id': 'item001',
        'type': 'sale',
        'quantity': -2,
        'unit_price': 2500,
        'total_amount': 5000,
        'staff_id': 'staff008',
        'customer_name': 'Guest Room 102',
        'timestamp': '2024-01-15 14:30:00',
        'notes': 'VIP Bar sale',
        'department': 'vip_bar',
      },
      {
        'id': 'tx002',
        'item_id': 'item002',
        'type': 'sale',
        'quantity': -5,
        'unit_price': 600,
        'total_amount': 3000,
        'staff_id': 'staff009',
        'customer_name': 'Guest Room 201',
        'timestamp': '2024-01-15 16:45:00',
        'notes': 'Outside Bar sale',
        'department': 'outside_bar',
      },
      // Mini mart sale
      {
        'id': 'tx003',
        'item_id': 'item005',
        'type': 'sale',
        'quantity': -3,
        'unit_price': 500,
        'total_amount': 1500,
        'staff_id': 'staff004',
        'customer_name': 'Walk-in',
        'timestamp': '2024-01-15 12:10:00',
        'notes': 'Mini Mart sale',
        'department': 'mini_mart',
      },
    ];

    // Purchases (recently purchased items)
    _purchases = [
      {
        'id': 'po001',
        'item_id': 'item001',
        'item_name': 'Premium Whiskey',
        'quantity': 12,
        'unit_cost': 2000,
        'total_cost': 24000,
        'department': 'vip_bar',
        'supplier': 'ABC Distributors',
        'purchased_by': 'staff005',
        'date': '2024-01-14',
      },
      {
        'id': 'po002',
        'item_id': 'item003',
        'item_name': 'Coca Cola',
        'quantity': 50,
        'unit_cost': 180,
        'total_cost': 9000,
        'department': 'outside_bar',
        'supplier': 'BeverageHub Ltd',
        'purchased_by': 'staff005',
        'date': '2024-01-13',
      },
      {
        'id': 'po003',
        'item_id': 'item004',
        'item_name': 'Mineral Water',
        'quantity': 40,
        'unit_cost': 120,
        'total_cost': 4800,
        'department': 'mini_mart',
        'supplier': 'WaterCo',
        'purchased_by': 'staff005',
        'date': '2024-01-12',
      },
    ];

    // Debts (who owes what and to whom)
    _debts = [
      {
        'id': 'debt001',
        'debtor_type': 'guest', // guest|department|staff
        'debtor_name': 'Fatima Ibrahim',
        'amount': 20000,
        'reason': 'Room service charges',
        'owed_to_type': 'department', // finance/store/etc.
        'owed_to': 'front_desk',
        'date': '2024-01-16',
        'status': 'unsettled',
        'related_booking_id': 'booking002',
      },
      {
        'id': 'debt002',
        'debtor_type': 'department',
        'debtor_name': 'kitchen',
        'amount': 75000,
        'reason': 'Supplies purchased',
        'owed_to_type': 'supplier',
        'owed_to': 'Kitchen Supplies Co',
        'date': '2024-01-10',
        'status': 'unsettled',
      },
      {
        'id': 'debt003',
        'debtor_type': 'staff',
        'debtor_name': 'Amara Chukwu',
        'amount': 5000,
        'reason': 'Cash shortage (reimbursable)',
        'owed_to_type': 'department',
        'owed_to': 'vip_bar',
        'date': '2024-01-15',
        'status': 'pending_review',
      },
    ];

    // Expenses with payment methods
    _expenses = [
      {
        'id': 'exp001',
        'description': 'Staff Salary Payment',
        'amount': 1500000,
        'category': 'payroll',
        'department': 'all',
        'date': '2024-01-01',
        'payment_method': 'bank_transfer',
        'staff_id': 'staff006',
      },
      {
        'id': 'exp002',
        'description': 'Utility Bills',
        'amount': 250000,
        'category': 'utilities',
        'department': 'all',
        'date': '2024-01-05',
        'payment_method': 'cash',
        'staff_id': 'staff006',
      },
      {
        'id': 'exp003',
        'description': 'Kitchen Supplies',
        'amount': 75000,
        'category': 'supplies',
        'department': 'kitchen',
        'date': '2024-01-10',
        'payment_method': 'bank_transfer',
        'staff_id': 'staff005',
      },
    ];

    // Income Records
    _incomeRecords = [
      {
        'id': 'inc001',
        'description': 'Room Revenue',
        'amount': 450000,
        'source': 'accommodation',
        'department': 'front_desk',
        'date': '2024-01-15',
        'payment_method': 'cash',
      },
      {
        'id': 'inc002',
        'description': 'VIP Bar Sales',
        'amount': 125000,
        'source': 'food_beverage',
        'department': 'vip_bar',
        'date': '2024-01-15',
        'payment_method': 'cash',
      },
      {
        'id': 'inc003',
        'description': 'Outside Bar Sales',
        'amount': 85000,
        'source': 'food_beverage',
        'department': 'outside_bar',
        'date': '2024-01-15',
        'payment_method': 'cash',
      },
      {
        'id': 'inc004',
        'description': 'Mini Mart Sales',
        'amount': 45000,
        'source': 'retail',
        'department': 'store',
        'date': '2024-01-15',
        'payment_method': 'cash',
      },
    ];

    // Payroll Records
    _payrollRecords = [
      {
        'id': 'pay001',
        'staff_id': 'staff001',
        'staff_name': 'Chukwudi Okonkwo',
        'amount': 500000,
        'month': '2024-01',
        'status': 'paid',
        'payment_method': 'bank_transfer',
      },
      {
        'id': 'pay002',
        'staff_id': 'staff002',
        'staff_name': 'Adaeze Nwankwo',
        'amount': 350000,
        'month': '2024-01',
        'status': 'paid',
        'payment_method': 'bank_transfer',
      },
      {
        'id': 'pay003',
        'staff_id': 'staff008',
        'staff_name': 'Amara Chukwu',
        'amount': 130000,
        'month': '2024-01',
        'status': 'pending',
        'payment_method': 'cash',
      },
    ];

    // Cash Deposits
    _cashDeposits = [
      {
        'id': 'dep001',
        'amount': 500000,
        'bank_name': 'First Bank',
        'account_type': 'current',
        'bank_charges': 2500,
        'net_amount': 497500,
        'date': '2024-01-15',
        'description': 'Daily cash deposit',
        'staff_id': 'staff006',
      },
      {
        'id': 'dep002',
        'amount': 300000,
        'bank_name': 'GTBank',
        'account_type': 'savings',
        'bank_charges': 1500,
        'net_amount': 298500,
        'date': '2024-01-14',
        'description': 'Weekly cash deposit',
        'staff_id': 'staff006',
      },
    ];

    // Staff Role Assignments
    _staffRoleAssignments = [
      {
        'id': 'assign001',
        'staff_id': 'staff001',
        'assigned_role': 'receptionist',
        'is_temporary': true,
        'assigned_by': 'staff002',
        'assigned_date': '2024-01-15',
        'expiry_date': '2024-01-20',
        'reason': 'Covering for sick leave',
      },
    ];
  }

  // Getter methods
  static List<Map<String, dynamic>> getBookings() {
    _initializeData();
    return _bookings;
  }

  static List<Map<String, dynamic>> getRooms() {
    _initializeData();
    return _rooms;
  }

  static List<Map<String, dynamic>> getStaffProfiles() {
    _initializeData();
    return _staffProfiles;
  }

  static List<Map<String, dynamic>> getInventoryItems() {
    _initializeData();
    return _inventoryItems;
  }

  static List<Map<String, dynamic>> getStockTransactions() {
    _initializeData();
    return _stockTransactions;
  }

  static List<Map<String, dynamic>> getExpenses() {
    _initializeData();
    return _expenses;
  }

  static List<Map<String, dynamic>> getIncomeRecords() {
    _initializeData();
    return _incomeRecords;
  }

  static List<Map<String, dynamic>> getPayrollRecords() {
    _initializeData();
    return _payrollRecords;
  }

  static List<Map<String, dynamic>> getCashDeposits() {
    _initializeData();
    return _cashDeposits;
  }

  static List<Map<String, dynamic>> getStaffRoleAssignments() {
    _initializeData();
    return _staffRoleAssignments;
  }

  // New getters
  static List<Map<String, dynamic>> getDebts() {
    _initializeData();
    return _debts;
  }

  static List<Map<String, dynamic>> getRecentPurchases() {
    _initializeData();
    return _purchases;
  }

  static List<Map<String, dynamic>> getCheckedInGuests() {
    _initializeData();
    return _bookings
        .where((b) => b['status'] == 'checked_in')
        .map((b) => {
              'guest_name': b['guest_name'],
              'room_id': b['room_id'],
              'check_in': b['check_in'],
              'processed_by': b['processed_by'],
            })
        .toList();
  }

  static List<Map<String, dynamic>> getDepartmentSales(String department) {
    _initializeData();
    final tx = _stockTransactions.where((t) => t['type'] == 'sale' && (t['department'] == department)).toList();
    return tx.map((t) {
      final item = _inventoryItems.firstWhere((i) => i['id'] == t['item_id'], orElse: () => {});
      return {
        'item_id': t['item_id'],
        'item_name': item['name'] ?? t['item_id'],
        'quantity': (t['quantity'] as int).abs(),
        'unit_price': t['unit_price'],
        'total_amount': t['total_amount'],
        'timestamp': t['timestamp'],
        'staff_id': t['staff_id'],
      };
    }).toList();
  }

  // Financial Summary
  static Map<String, dynamic> getFinancialSummary() {
    _initializeData();
    double totalIncome = _incomeRecords.fold(0.0, (sum, record) => sum + (record['amount'] as num).toDouble());
    double totalExpenses = _expenses.fold(0.0, (sum, record) => sum + (record['amount'] as num).toDouble());
    double totalPayroll = _payrollRecords.where((p) => p['status'] == 'paid').fold(0.0, (sum, record) => sum + (record['amount'] as num).toDouble());
    double totalDeposits = _cashDeposits.fold(0.0, (sum, record) => sum + (record['net_amount'] as num).toDouble());
    
    return {
      'total_income': totalIncome,
      'total_expenses': totalExpenses,
      'total_payroll': totalPayroll,
      'total_deposits': totalDeposits,
      'available_cash': totalIncome - totalExpenses - totalDeposits,
      'net_profit': totalIncome - totalExpenses,
    };
  }

  // Department Performance
  static List<Map<String, dynamic>> getDepartmentPerformance() {
    _initializeData();
    return [
      {
        'department': 'VIP Bar',
        'revenue': 125000,
        'expenses': 35000,
        'profit': 90000,
        'performance': 'excellent',
      },
      {
        'department': 'Outside Bar',
        'revenue': 85000,
        'expenses': 25000,
        'profit': 60000,
        'performance': 'good',
      },
      {
        'department': 'Store',
        'revenue': 45000,
        'expenses': 15000,
        'profit': 30000,
        'performance': 'good',
      },
      {
        'department': 'Front Desk',
        'revenue': 450000,
        'expenses': 0,
        'profit': 450000,
        'performance': 'excellent',
      },
    ];
  }

  // Dashboard Statistics
  static Map<String, dynamic> getDashboardStats() {
    _initializeData();
    return {
      'pending_count': _bookings.where((b) => b['status'] == 'confirmed').length,
      'checked_in_count': _bookings.where((b) => b['status'] == 'checked_in').length,
      'occupancy_rate': ((_bookings.where((b) => b['status'] == 'checked_in').length / _rooms.length) * 100).round(),
      'total_revenue': _incomeRecords.fold(0.0, (sum, record) => sum + (record['amount'] as num).toDouble()),
      'available_rooms': _rooms.where((r) => r['status'] == 'available').length,
      'total_rooms': _rooms.length,
    };
  }

  // Recent Activities
  static List<Map<String, dynamic>> getRecentActivities() {
    _initializeData();
    return [
      {
        'id': 'act001',
        'type': 'booking',
        'description': 'New booking created for Room 210',
        'timestamp': '2024-01-15 10:30:00',
        'staff_name': 'Emeka Onyeka',
      },
      {
        'id': 'act002',
        'type': 'sale',
        'description': 'VIP Bar sale completed - ₦5,000',
        'timestamp': '2024-01-15 14:30:00',
        'staff_name': 'Amara Chukwu',
      },
      {
        'id': 'act003',
        'type': 'checkout',
        'description': 'Guest checked out from Room 103',
        'timestamp': '2024-01-15 12:00:00',
        'staff_name': 'Emeka Onyeka',
      },
      {
        'id': 'act004',
        'type': 'inventory',
        'description': 'Stock updated for Premium Whiskey',
        'timestamp': '2024-01-15 09:15:00',
        'staff_name': 'Chioma Eze',
      },
    ];
  }

  // Update methods
  static void updateBookingStatus(String bookingId, String newStatus) {
    _initializeData();
    final index = _bookings.indexWhere((b) => b['id'] == bookingId);
    if (index != -1) {
      _bookings[index]['status'] = newStatus;
    }
  }

  static void createBooking(Map<String, dynamic> booking) {
    _initializeData();
    _bookings.add(booking);
  }

  static void addInventoryItem(Map<String, dynamic> item) {
    _initializeData();
    _inventoryItems.add(item);
  }

  static void recordStockTransaction(Map<String, dynamic> transaction) {
    _initializeData();
    _stockTransactions.add(transaction);
    
    // Update stock quantity
    final itemIndex = _inventoryItems.indexWhere((item) => item['id'] == transaction['item_id']);
    if (itemIndex != -1) {
      _inventoryItems[itemIndex]['current_stock'] += transaction['quantity'] as int;
    }
  }

  static void addExpense(Map<String, dynamic> expense) {
    _initializeData();
    _expenses.add(expense);
  }

  static void addIncomeRecord(Map<String, dynamic> income) {
    _initializeData();
    _incomeRecords.add(income);
  }

  static void addCashDeposit(Map<String, dynamic> deposit) {
    _initializeData();
    _cashDeposits.add(deposit);
  }

  static void addPayrollRecord(Map<String, dynamic> payroll) {
    _initializeData();
    _payrollRecords.add(payroll);
  }

  static void recordDebt(Map<String, dynamic> debt) {
    _initializeData();
    // Add ID if not present
    if (!debt.containsKey('id')) {
      debt['id'] = 'debt${_debts.length + 1}';
    }
    _debts.add(debt);
  }

  static void assignRoleToStaff(String staffId, String role, {bool isTemporary = false, DateTime? expiryDate}) {
    _initializeData();
    _staffRoleAssignments.add({
      'id': 'assign${_staffRoleAssignments.length + 1}',
      'staff_id': staffId,
      'assigned_role': role,
      'is_temporary': isTemporary,
      'assigned_by': 'staff001', // Current user
      'assigned_date': DateTime.now().toIso8601String().split('T')[0],
      'expiry_date': expiryDate?.toIso8601String().split('T')[0],
      'reason': isTemporary ? 'Temporary role assignment' : 'Permanent role assignment',
    });
  }

  // Mini Mart methods
  static List<Map<String, dynamic>> getMiniMartItems() {
    _initializeData();
    return [
      {
        'id': 'mm001',
        'name': 'Coca-Cola',
        'price': 500,
        'stock': 50,
        'category': 'Beverages',
        'barcode': '5449000000996',
      },
      {
        'id': 'mm002',
        'name': 'Bottled Water',
        'price': 300,
        'stock': 100,
        'category': 'Beverages',
        'barcode': '6211234567891',
      },
      {
        'id': 'mm003',
        'name': 'Bread',
        'price': 400,
        'stock': 25,
        'category': 'Food',
        'barcode': '1234567890123',
      },
      {
        'id': 'mm004',
        'name': 'Cigarettes',
        'price': 1200,
        'stock': 30,
        'category': 'Tobacco',
        'barcode': '9876543210987',
      },
      {
        'id': 'mm005',
        'name': 'Snacks',
        'price': 200,
        'stock': 40,
        'category': 'Food',
        'barcode': '4567891234567',
      },
    ];
  }

  static List<Map<String, dynamic>> getMiniMartSales() {
    _initializeData();
    return [
      {
        'id': 'sale001',
        'customer_name': 'Chinonso Okonkwo',
        'customer_phone': '+2348012345678',
        'items': [
          {'name': 'Coca-Cola', 'quantity': 2, 'price': 500},
          {'name': 'Bread', 'quantity': 1, 'price': 400},
        ],
        'total': 1400,
        'payment_method': 'Cash',
        'timestamp': '2024-01-15 14:30:00',
        'processed_by': 'staff003',
      },
      {
        'id': 'sale002',
        'customer_name': 'Adanna Nwosu',
        'customer_phone': '+2348012345679',
        'items': [
          {'name': 'Bottled Water', 'quantity': 3, 'price': 300},
          {'name': 'Snacks', 'quantity': 2, 'price': 200},
        ],
        'total': 1300,
        'payment_method': 'Card',
        'timestamp': '2024-01-15 16:45:00',
        'processed_by': 'staff003',
      },
    ];
  }

  // Kitchen methods
  static List<Map<String, dynamic>> getKitchenOrders() {
    _initializeData();
    return [
      {
        'id': 'order001',
        'guest_name': 'Chinonso Okonkwo',
        'room_number': '102',
        'items': [
          {'name': 'Jollof Rice & Chicken', 'quantity': 2, 'price': 3500},
          {'name': 'Goat Meat Peppersoup', 'quantity': 1, 'price': 2500},
        ],
        'total': 9500,
        'status': 'preparing',
        'timestamp': '2024-01-15 19:30:00',
        'processed_by': 'staff007',
      },
      {
        'id': 'order002',
        'guest_name': 'Ngozi Okafor',
        'room_number': '301',
        'items': [
          {'name': 'Grilled Tilapia', 'quantity': 1, 'price': 4000},
          {'name': 'Side Salad', 'quantity': 1, 'price': 1500},
        ],
        'total': 5500,
        'status': 'ready',
        'timestamp': '2024-01-15 20:15:00',
        'processed_by': 'staff007',
      },
    ];
  }

  // POS/Menu methods
  static List<Map<String, dynamic>> getMenuItems() {
    _initializeData();
    return mockMenuItems;
  }
}