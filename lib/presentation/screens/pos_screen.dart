import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:pzed_homes/core/services/mock_auth_service.dart';
import 'package:pzed_homes/presentation/screens/scanner_screen.dart';

class PosScreen extends StatefulWidget {
  const PosScreen({super.key});

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _currentOrder = [];
  Map<String, dynamic>? _linkedBooking;
  bool _isLoading = false;
  bool _isLoadingMenu = true;
  List<Map<String, dynamic>> _menuItems = [];
  List<Map<String, dynamic>> _checkedInGuests = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadInitialData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    try {
      final [menuItems, guests] = await Future.wait([
        _supabase.from('menu_items').select('id, name, price, department, barcode').order('name'),
        _supabase
            .from('bookings')
            .select('id, profiles!inner(full_name), rooms!inner(room_number)')
            .eq('status', 'Checked-in'),
      ]);

      setState(() {
        _menuItems = List<Map<String, dynamic>>.from(menuItems);
        _checkedInGuests = List<Map<String, dynamic>>.from(guests);
        _isLoadingMenu = false;
      });
    } catch (e) {
      setState(() => _isLoadingMenu = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading data: $e'), backgroundColor: Colors.red),
      );
    }
  }

  void _addItemToOrder(Map<String, dynamic> item) {
    final index = _currentOrder.indexWhere((o) => o['id'] == item['id']);
    setState(() {
      if (index != -1) {
        _currentOrder[index]['quantity'] = (_currentOrder[index]['quantity'] ?? 0) + 1;
      } else {
        _currentOrder.add({...item, 'quantity': 1});
      }
    });
  }

  void _clearOrder() {
    setState(() {
      _currentOrder = [];
      _linkedBooking = null;
    });
  }

  int get _orderTotal {
    return _currentOrder.fold(0, (sum, item) {
      final price = (item['price'] as int? ?? 0);
      final quantity = (item['quantity'] as int? ?? 0);
      return sum + (price * quantity);
    });
  }

  Future<void> _showLinkGuestDialog() async {
    if (_checkedInGuests.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No checked-in guests found')),
      );
      return;
    }

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Link to Checked-in Guest'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _checkedInGuests.length,
            itemBuilder: (context, index) {
              final guest = _checkedInGuests[index];
              final guestName = guest['profiles']?['full_name'] ?? 'Unknown';
              final roomNumber = guest['rooms']?['room_number'] ?? 'Unknown';
              
              return ListTile(
                title: Text(guestName),
                subtitle: Text('Room $roomNumber'),
                onTap: () {
                  setState(() => _linkedBooking = guest);
                  context.pop();
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _placeOrder() async {
    if (_linkedBooking == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please link a guest first')),
      );
      return;
    }
    
    if (_currentOrder.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add items to order')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final authService = Provider.of<MockAuthService>(context, listen: false);
      
      // Create order charges
      for (var orderItem in _currentOrder) {
        await _supabase.from('booking_charges').insert({
          'booking_id': _linkedBooking!['id'],
          'item_name': orderItem['name'],
          'price': orderItem['price'],
          'quantity': orderItem['quantity'],
          'department': orderItem['department'],
          'added_by': authService.currentUser!.id,
        });
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Order added to ${_linkedBooking!['profiles']?['full_name']?.toString() ?? 'guest'}\'s bill'),
          backgroundColor: Colors.green,
        ),
      );

      _clearOrder();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error placing order: $e'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _handleScannedBarcode(String barcode) {
    try {
      final foundItem = _menuItems.firstWhere(
        (item) => item['barcode'] == barcode,
        orElse: () => {},
      );
      
      if (foundItem.isNotEmpty) {
        _addItemToOrder(foundItem);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Item not found in menu')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error scanning barcode: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Point of Sale'),
        backgroundColor: Colors.deepPurple,
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: () async {
              final scannedValue = await context.push<String>('/scanner');
              if (scannedValue != null) {
                _handleScannedBarcode(scannedValue);
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadInitialData,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Restaurant'),
            Tab(text: 'Bar'),
          ],
        ),
      ),
      body: _isLoadingMenu
          ? const Center(child: CircularProgressIndicator())
          : Row(
              children: [
                // Menu Grid Section
                Expanded(
                  flex: 2,
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildMenuGrid('Restaurant'),
                      _buildMenuGrid('Bar'),
                    ],
                  ),
                ),

                // Order Cart Section
                Expanded(
                  flex: 1,
                  child: _buildOrderCart(),
                ),
              ],
            ),
    );
  }

  Widget _buildMenuGrid(String department) {
    final items = _menuItems.where((m) => m['department'] == department).toList();
    final currencyFormatter = NumberFormat.currency(locale: 'en_NG', symbol: '₦');

    return GridView.builder(
      padding: const EdgeInsets.all(8.0),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 0.8,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final price = item['price'] as int? ?? 0;
        
        return Card(
          child: InkWell(
            onTap: () => _addItemToOrder(item),
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    item['name'] as String? ?? 'Unknown',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    currencyFormatter.format(price),
                    style: TextStyle(
                      color: Colors.deepPurple,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildOrderCart() {
    final currencyFormatter = NumberFormat.currency(locale: 'en_NG', symbol: '₦');
    
    return Container(
      color: Colors.grey[100],
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Linked Guest Info
          Card(
            child: ListTile(
              leading: Icon(Icons.person, color: _linkedBooking != null ? Colors.green : Colors.grey),
              title: Text(_linkedBooking != null 
                  ? (_linkedBooking!['profiles']?['full_name'] ?? 'Unknown')
                  : 'No Guest Linked'),
              subtitle: Text(_linkedBooking != null 
                  ? 'Room ${_linkedBooking!['rooms']?['room_number'] ?? 'Unknown'}'
                  : 'Tap to link guest'),
              onTap: _showLinkGuestDialog,
            ),
          ),
          const SizedBox(height: 16),

          // Order Items List
          Expanded(
            child: _currentOrder.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.shopping_cart, size: 48, color: Colors.grey),
                        SizedBox(height: 16),
                        Text('Add items to order'),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: _currentOrder.length,
                    itemBuilder: (context, index) {
                      final item = _currentOrder[index];
                      final quantity = item['quantity'] as int? ?? 0;
                      final price = item['price'] as int? ?? 0;
                      final total = quantity * price;
                      
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        child: ListTile(
                          title: Text(item['name'] as String? ?? 'Unknown'),
                          subtitle: Text('$quantity x ${currencyFormatter.format(price)}'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                currencyFormatter.format(total),
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              IconButton(
                                icon: const Icon(Icons.remove),
                                onPressed: () {
                                  setState(() {
                                    if (quantity > 1) {
                                      item['quantity'] = quantity - 1;
                                    } else {
                                      _currentOrder.removeAt(index);
                                    }
                                  });
                                },
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),

          // Order Total and Actions
          const Divider(),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Total:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                Text(
                  currencyFormatter.format(_orderTotal),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.deepPurple),
                ),
              ],
            ),
          ),
          
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _clearOrder,
                  child: const Text('Clear'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: (_currentOrder.isEmpty || _linkedBooking == null || _isLoading) 
                      ? null 
                      : _placeOrder,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _isLoading 
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('Place Order'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}