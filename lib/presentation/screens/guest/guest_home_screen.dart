import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:pzed_homes/core/error/error_handler.dart';
import 'package:pzed_homes/core/services/auth_service.dart';
import 'package:pzed_homes/core/services/payment_service.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class GuestHomeScreen extends StatefulWidget {
  const GuestHomeScreen({super.key});

  @override
  State<GuestHomeScreen> createState() => _GuestHomeScreenState();
}

class _GuestHomeScreenState extends State<GuestHomeScreen> with SingleTickerProviderStateMixin {
  final DateFormat _dateFormatter = DateFormat('EEE, MMM d, yyyy');
  late TabController _tabController;
  bool _isLoading = true;
  String _barView = 'vip_bar';
  Map<String, dynamic>? _primaryBooking;
  List<Map<String, dynamic>> _stays = [];
  List<Map<String, dynamic>> _pastStays = [];
  List<Map<String, dynamic>> _restaurantItems = [];
  List<Map<String, dynamic>> _barItems = [];
  List<Map<String, dynamic>> _miniMartItems = [];

  SupabaseClient? get _supabase {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadPortalData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  DateTime? _safeDate(dynamic value) {
    if (value == null) return null;
    try {
      return DateTime.parse(value.toString());
    } catch (_) {
      return null;
    }
  }

  int _sumExtraCharges(dynamic raw) {
    if (raw is! List) return 0;
    int total = 0;
    for (final entry in raw) {
      if (entry is! Map<String, dynamic>) continue;
      final price = (entry['price'] as num?)?.toInt() ?? 0;
      final qty = (entry['quantity'] as num?)?.toInt() ?? (entry['qty'] as num?)?.toInt() ?? 1;
      total += price * (qty <= 0 ? 1 : qty);
    }
    return total;
  }

  int _outstanding(Map<String, dynamic> booking) {
    final total = (booking['total_amount'] as num?)?.toInt() ?? 0;
    final paid = (booking['paid_amount'] as num?)?.toInt() ?? 0;
    final diff = total - paid;
    return diff > 0 ? diff : 0;
  }

  String _money(num? amountKobo) {
    final kobo = amountKobo?.toInt() ?? 0;
    final naira = PaymentService.koboToNaira(kobo);
    return NumberFormat.currency(locale: 'en_NG', symbol: '₦').format(naira);
  }

  Future<void> _loadPortalData() async {
    setState(() => _isLoading = true);
    final authService = Provider.of<AuthService>(context, listen: false);
    final currentUser = authService.currentUser;
    final supabase = _supabase;

    if (currentUser == null || supabase == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final results = await Future.wait([
        supabase
            .from('bookings')
            .select(
              'id,status,requested_room_type,room_id,room_number,check_in_date,check_out_date,paid_amount,total_amount,payment_reference,extra_charges,created_at',
            )
            .eq('guest_profile_id', currentUser.id)
            .order('created_at', ascending: false)
            .limit(50),
        supabase
            .from('menu_items')
            .select('name,price')
            .eq('department', 'restaurant')
            .order('name', ascending: true),
        _barView == 'vip_bar'
            ? supabase
                .from('inventory_items')
                .select('name,vip_bar_price')
                .inFilter('department', ['vip_bar', 'both'])
                .order('name', ascending: true)
            : supabase
                .from('inventory_items')
                .select('name,outside_bar_price')
                .inFilter('department', ['outside_bar', 'both'])
                .order('name', ascending: true),
        supabase.from('mini_mart_items').select('name,price').order('name', ascending: true),
      ]);

      final stays = List<Map<String, dynamic>>.from(results[0] as List);
      final restaurant = List<Map<String, dynamic>>.from(results[1] as List);
      final barSource = List<Map<String, dynamic>>.from(results[2] as List);
      final miniMart = List<Map<String, dynamic>>.from(results[3] as List);

      final mappedBarItems = barSource
          .map((row) {
            final priceKey = _barView == 'vip_bar' ? 'vip_bar_price' : 'outside_bar_price';
            return {'name': row['name'], 'price': row[priceKey] ?? 0};
          })
          .where((row) => ((row['price'] as num?)?.toInt() ?? 0) > 0)
          .toList();

      Map<String, dynamic>? primaryBooking;
      final now = DateTime.now();
      final active = stays.where((b) {
        final status = (b['status']?.toString().toLowerCase() ?? '');
        final checkOut = _safeDate(b['check_out_date']);
        final isPast = checkOut != null && checkOut.isBefore(DateTime(now.year, now.month, now.day));
        return status != 'checked-out' &&
            status != 'cancelled' &&
            status != 'rejected' &&
            !isPast;
      }).toList();
      if (active.isNotEmpty) {
        primaryBooking = active.first;
      }

      final past = stays.where((b) {
        final out = _safeDate(b['check_out_date']);
        if (out == null) return false;
        return out.isBefore(DateTime(now.year, now.month, now.day));
      }).toList();

      if (!mounted) return;
      setState(() {
        _stays = stays;
        _primaryBooking = primaryBooking;
        _pastStays = past;
        _restaurantItems = restaurant;
        _barItems = List<Map<String, dynamic>>.from(mappedBarItems);
        _miniMartItems = miniMart;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ErrorHandler.showWarningMessage(context, 'Could not load your guest portal data. Pull to refresh.');
    }
  }

  Future<void> _openBarTypePicker() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('VIP Bar'),
              onTap: () => Navigator.of(ctx).pop('vip_bar'),
            ),
            ListTile(
              title: const Text('Outside Bar'),
              onTap: () => Navigator.of(ctx).pop('outside_bar'),
            ),
          ],
        ),
      ),
    );
    if (selected != null && selected != _barView) {
      setState(() => _barView = selected);
      await _loadPortalData();
    }
  }

  void _showStayStatement(Map<String, dynamic> booking) {
    final checkIn = _safeDate(booking['check_in_date']);
    final checkOut = _safeDate(booking['check_out_date']);
    final nights = (checkIn != null && checkOut != null) ? checkOut.difference(checkIn).inDays : 0;
    final extra = _sumExtraCharges(booking['extra_charges']);
    final total = (booking['total_amount'] as num?)?.toInt() ?? 0;
    final paid = (booking['paid_amount'] as num?)?.toInt() ?? 0;
    final roomCharges = (total - extra).clamp(0, total);
    final perNight = nights > 0 ? (roomCharges ~/ nights) : roomCharges;
    final balance = _outstanding(booking);

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Stay Statement'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Room: ${booking['requested_room_type'] ?? 'N/A'}'),
              Text('Assigned Room: ${booking['room_number']?.toString().isNotEmpty == true ? booking['room_number'] : 'Awaiting assignment'}'),
              const SizedBox(height: 10),
              Text('Room Charges: $nights nights @ ${_money(perNight)}'),
              Text('Extra Charges: ${_money(extra)}'),
              const SizedBox(height: 8),
              const Divider(height: 14),
              Text('Total Collected: ${_money(paid)}', style: const TextStyle(fontWeight: FontWeight.w600)),
              Text('Balance: ${_money(balance)}'),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: balance == 0 ? Colors.green.shade100 : Colors.orange.shade100,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  balance == 0 ? 'Zero Balance - Settled' : 'Outstanding Balance',
                  style: TextStyle(
                    color: balance == 0 ? Colors.green.shade800 : Colors.orange.shade900,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<AuthService>(context).currentUser;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.green[800],
        title: const Text('P-ZED Guest Portal'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.restaurant_menu_rounded), text: 'Restaurant'),
            Tab(icon: Icon(Icons.wine_bar_rounded), text: 'Bar'),
            Tab(icon: Icon(Icons.storefront_rounded), text: 'Mini-Mart'),
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _loadPortalData,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [Colors.green.shade800, Colors.green.shade600]),
                borderRadius: BorderRadius.circular(16),
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('My Stay', style: TextStyle(color: Colors.white70)),
                  const SizedBox(height: 4),
                  Text(
                    'Welcome${user?.name.isNotEmpty == true ? ', ${user!.name}' : ''}',
                    style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (_isLoading)
              const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
            else if (user == null)
              _buildEmptyState('Login required', 'Login to view your stay dashboard and statement of account.')
            else ...[
              _buildActiveStayCard(),
              const SizedBox(height: 12),
              _buildPastStaysSection(),
            ],
            const SizedBox(height: 16),
            SizedBox(
              height: 420,
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildCatalogPanel(
                    title: 'Restaurant Menu',
                    subtitle: 'Curated dining selections',
                    items: _restaurantItems,
                  ),
                  _buildBarPanel(),
                  _buildCatalogPanel(
                    title: 'Mini-Mart',
                    subtitle: 'Convenience essentials',
                    items: _miniMartItems,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(String title, String subtitle) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(subtitle),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveStayCard() {
    if (_primaryBooking == null) {
      return _buildEmptyState('No active stay found', 'Your current stay will appear here once a booking is active.');
    }

    final booking = _primaryBooking!;
    final outstanding = _outstanding(booking);
    final assignedRoom =
        (booking['room_number']?.toString().isNotEmpty ?? false) ? booking['room_number'].toString() : 'Awaiting assignment';

    return InkWell(
      onTap: () => _showStayStatement(booking),
      borderRadius: BorderRadius.circular(12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Active Booking', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 8),
              Text('Room Type: ${booking['requested_room_type'] ?? 'N/A'}'),
              Text('Assigned Room: $assignedRoom'),
              Text('Status: ${booking['status'] ?? 'N/A'}'),
              Text('Check-in: ${booking['check_in_date'] != null ? _dateFormatter.format(DateTime.parse(booking['check_in_date'].toString())) : 'N/A'}'),
              Text('Check-out: ${booking['check_out_date'] != null ? _dateFormatter.format(DateTime.parse(booking['check_out_date'].toString())) : 'N/A'}'),
              const Divider(height: 24),
              const Text('Statement of Account', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Paid'),
                  Text(_money(booking['paid_amount'] as num?)),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Outstanding'),
                  Text(
                    _money(outstanding),
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: outstanding > 0 ? Colors.orange[800] : Colors.green[700],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text('Tap to view full statement', style: TextStyle(color: Colors.grey[700], fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPastStaysSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Stay History', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            if (_pastStays.isEmpty)
              Text('No past history', style: TextStyle(color: Colors.grey[700]))
            else
              ..._pastStays.map((stay) {
                final inDate = _safeDate(stay['check_in_date']);
                final outDate = _safeDate(stay['check_out_date']);
                final room = stay['room_number']?.toString().isNotEmpty == true ? stay['room_number'].toString() : 'Not assigned';
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    '${inDate != null ? _dateFormatter.format(inDate) : 'N/A'} - ${outDate != null ? _dateFormatter.format(outDate) : 'N/A'}',
                  ),
                  subtitle: Text('Room: $room'),
                  trailing: Text(_money(stay['paid_amount'] as num?)),
                  onTap: () => _showStayStatement(stay),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildBarPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _barView == 'vip_bar' ? 'VIP Bar Menu' : 'Outside Bar Menu',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            TextButton.icon(
              onPressed: _openBarTypePicker,
              icon: const Icon(Icons.swap_horiz),
              label: const Text('Switch Bar'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Expanded(
          child: _buildCatalogPanel(
            title: '',
            subtitle: _barView == 'vip_bar' ? 'Premium bar selections' : 'Outdoor bar selections',
            items: _barItems,
          ),
        ),
      ],
    );
  }

  Widget _buildCatalogPanel({
    required String title,
    required String subtitle,
    required List<Map<String, dynamic>> items,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title.isNotEmpty) Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        if (subtitle.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(subtitle, style: TextStyle(color: Colors.grey[700])),
        ],
        const SizedBox(height: 12),
        if (items.isEmpty)
          _buildEmptyState('No menu available', 'Menu items will appear here as soon as they are published.')
        else
          Expanded(
            child: GridView.builder(
              itemCount: items.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 1.45,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              itemBuilder: (context, index) {
                final item = items[index];
                final name = item['name']?.toString() ?? 'Item';
                final price = (item['price'] as num?)?.toInt() ?? 0;
                return Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.green.shade100),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _money(price),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.green[800],
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final authService = Provider.of<AuthService>(context, listen: false);
    if (authService.currentUser == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ErrorHandler.showInfoMessage(context, 'Login to access your account-native stay dashboard.');
      });
    }
  }
}