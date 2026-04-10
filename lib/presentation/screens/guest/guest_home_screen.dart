import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:pzed_homes/core/error/error_handler.dart';
import 'package:pzed_homes/core/services/auth_service.dart';
import 'package:pzed_homes/data/models/user.dart';
import 'package:pzed_homes/core/services/payment_service.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class GuestHomeScreen extends StatefulWidget {
  const GuestHomeScreen({super.key});

  @override
  State<GuestHomeScreen> createState() => _GuestHomeScreenState();
}

class _GuestHomeScreenState extends State<GuestHomeScreen> with SingleTickerProviderStateMixin {
  /// Matches tab indicator; reads as luxury gold on dark green.
  static const Color _guestGold = Color(0xFFFFD54F);

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
    _tabController = TabController(length: 4, vsync: this);
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

  /// Catalog grid: null price → Contact Reception; zero kobo → TBD; else formatted money.
  String _catalogPriceLabel(dynamic rawPrice) {
    if (rawPrice == null) return 'Contact Reception';
    final kobo = rawPrice is num ? rawPrice.toInt() : int.tryParse(rawPrice.toString()) ?? 0;
    if (kobo == 0) return 'TBD';
    return _money(kobo);
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

    var stays = <Map<String, dynamic>>[];
    var restaurant = <Map<String, dynamic>>[];
    var barSource = <Map<String, dynamic>>[];
    var miniMart = <Map<String, dynamic>>[];
    var fetchFailureCount = 0;

    try {
      final bookingsRes = await supabase
          .from('bookings')
          .select(
            'id,status,requested_room_type,room_id,room_number,check_in_date,check_out_date,paid_amount,total_amount,payment_reference,extra_charges,created_at',
          )
          .eq('guest_profile_id', currentUser.id)
          .order('created_at', ascending: false)
          .limit(50);
      stays = List<Map<String, dynamic>>.from(bookingsRes as List);
      if (kDebugMode) {
        debugPrint('[GuestPortal] bookings rows: ${stays.length}');
      }
    } catch (e, st) {
      fetchFailureCount++;
      if (kDebugMode) {
        debugPrint('[GuestPortal] bookings fetch failed: $e\n$st');
      }
    }

    try {
      final res = await supabase
          .from('menu_items')
          .select('name,price')
          .eq('department', 'restaurant')
          .order('name', ascending: true);
      restaurant = List<Map<String, dynamic>>.from(res as List);
      if (kDebugMode) {
        debugPrint('[GuestPortal] restaurant catalog rows: ${restaurant.length}');
      }
    } catch (e, st) {
      fetchFailureCount++;
      if (kDebugMode) {
        debugPrint('[GuestPortal] restaurant catalog fetch failed: $e\n$st');
      }
    }

    try {
      final res = _barView == 'vip_bar'
          ? await supabase
              .from('inventory_items')
              .select('name,vip_bar_price')
              .inFilter('department', ['vip_bar', 'both'])
              .order('name', ascending: true)
          : await supabase
              .from('inventory_items')
              .select('name,outside_bar_price')
              .inFilter('department', ['outside_bar', 'both'])
              .order('name', ascending: true);
      barSource = List<Map<String, dynamic>>.from(res as List);
      if (kDebugMode) {
        debugPrint('[GuestPortal] bar (${_barView == 'vip_bar' ? 'vip' : 'outside'}) catalog rows: ${barSource.length}');
      }
    } catch (e, st) {
      fetchFailureCount++;
      if (kDebugMode) {
        debugPrint('[GuestPortal] bar catalog fetch failed: $e\n$st');
      }
    }

    try {
      final res = await supabase.from('mini_mart_items').select('name,price').order('name', ascending: true);
      miniMart = List<Map<String, dynamic>>.from(res as List);
      if (kDebugMode) {
        debugPrint('[GuestPortal] mini_mart catalog rows: ${miniMart.length}');
      }
    } catch (e, st) {
      fetchFailureCount++;
      if (kDebugMode) {
        debugPrint('[GuestPortal] mini_mart catalog fetch failed: $e\n$st');
      }
    }

    final mappedBarItems = barSource
        .map((row) {
          final priceKey = _barView == 'vip_bar' ? 'vip_bar_price' : 'outside_bar_price';
          return <String, dynamic>{'name': row['name'], 'price': row[priceKey]};
        })
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

    if (fetchFailureCount >= 4 && mounted) {
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
    final AppUser? user = Provider.of<AuthService>(context).currentUser;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.green[800],
        foregroundColor: Colors.white,
        title: Text(
          'P-ZED Guest Portal',
          style: TextStyle(
            color: _guestGold,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
            shadows: const [
              Shadow(color: Color(0x66000000), blurRadius: 6, offset: Offset(0, 1)),
            ],
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white.withValues(alpha: 0.72),
          indicatorColor: const Color(0xFFFFD54F),
          indicatorWeight: 3,
          dividerColor: Colors.white24,
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) {
              return Colors.white.withValues(alpha: 0.12);
            }
            if (states.contains(WidgetState.hovered)) {
              return Colors.white.withValues(alpha: 0.08);
            }
            return null;
          }),
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(icon: Icon(Icons.home_rounded), text: 'Overview'),
            Tab(icon: Icon(Icons.restaurant_menu_rounded), text: 'Restaurant'),
            Tab(icon: Icon(Icons.wine_bar_rounded), text: 'Bar'),
            Tab(icon: Icon(Icons.storefront_rounded), text: 'Mini-Mart'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildOverviewTab(context, user),
          _buildRestaurantCatalogTab(),
          _buildBarCatalogTab(),
          _buildMiniMartCatalogTab(),
        ],
      ),
    );
  }

  Widget _buildOverviewTab(BuildContext context, AppUser? user) {
    return RefreshIndicator(
      onRefresh: _loadPortalData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        physics: const AlwaysScrollableScrollPhysics(),
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
                  'Welcome${user != null && user.name.trim().isNotEmpty ? ', ${user.name}' : ''}',
                  style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (user == null)
            _buildEmptyState('Login required', 'Login to view your stay dashboard and statement of account.')
          else ...[
            _buildActiveStayCard(),
            const SizedBox(height: 12),
            _buildPlanNextVisitCard(context),
            const SizedBox(height: 12),
            _buildPastStaysSection(),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildRestaurantCatalogTab() {
    return _buildCompactCatalogTab(
      emptyTitle: 'No menu available',
      emptySubtitle: 'Restaurant items will appear here when published.',
      items: _restaurantItems,
    );
  }

  Widget _buildMiniMartCatalogTab() {
    return _buildCompactCatalogTab(
      emptyTitle: 'No items available',
      emptySubtitle: 'Mini-mart items will appear here when published.',
      items: _miniMartItems,
    );
  }

  /// Dense name + price rows; full tab height, pull-to-refresh.
  Widget _buildCompactCatalogTab({
    required String emptyTitle,
    required String emptySubtitle,
    required List<Map<String, dynamic>> items,
  }) {
    return RefreshIndicator(
      onRefresh: _loadPortalData,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (_isLoading)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
            )
          else if (items.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: _buildEmptyState(emptyTitle, emptySubtitle),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.only(bottom: 16),
              sliver: SliverList.separated(
                itemCount: items.length,
                separatorBuilder: (_, __) => Divider(height: 1, indent: 16, endIndent: 16, color: Colors.green.shade100),
                itemBuilder: (context, index) {
                  final item = items[index];
                  final name = item['name']?.toString() ?? 'Item';
                  final priceLabel = _catalogPriceLabel(item['price']);
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                    minVerticalPadding: 10,
                    title: Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                    ),
                    trailing: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 120),
                      child: Text(
                        priceLabel,
                        textAlign: TextAlign.end,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Colors.green[800],
                          fontSize: 14,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBarCatalogTab() {
    final barTitle = _barView == 'vip_bar' ? 'VIP Bar' : 'Outside Bar';
    final barHint = _barView == 'vip_bar' ? 'Premium selections' : 'Outdoor selections';

    return RefreshIndicator(
      onRefresh: _loadPortalData,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          barTitle,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          barHint,
                          style: TextStyle(color: Colors.grey[700], fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _openBarTypePicker,
                    icon: const Icon(Icons.swap_horiz, size: 20),
                    label: const Text('Switch'),
                  ),
                ],
              ),
            ),
          ),
          if (_isLoading)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
            )
          else if (_barItems.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: _buildEmptyState('No menu available', 'Bar items will appear here when published.'),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.only(bottom: 16),
              sliver: SliverList.separated(
                itemCount: _barItems.length,
                separatorBuilder: (_, __) => Divider(height: 1, indent: 16, endIndent: 16, color: Colors.green.shade100),
                itemBuilder: (context, index) {
                  final item = _barItems[index];
                  final name = item['name']?.toString() ?? 'Item';
                  final priceLabel = _catalogPriceLabel(item['price']);
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                    minVerticalPadding: 10,
                    title: Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                    ),
                    trailing: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 120),
                      child: Text(
                        priceLabel,
                        textAlign: TextAlign.end,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Colors.green[800],
                          fontSize: 14,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  /// Future stay booking — distinct from the active stay statement above.
  Widget _buildPlanNextVisitCard(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          final now = DateTime.now();
          final checkOut = now.add(const Duration(days: 1));
          context.push('/guest/rooms', extra: <String, dynamic>{
            'checkInDate': now,
            'checkOutDate': checkOut,
          });
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _guestGold.withValues(alpha: 0.85), width: 1.5),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.green.shade900,
                Colors.green.shade800,
                Colors.green.shade700,
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: _guestGold.withValues(alpha: 0.12),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.event_available_rounded, color: _guestGold, size: 28),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Plan your next visit',
                      style: TextStyle(
                        color: _guestGold,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                  Icon(Icons.arrow_forward_ios_rounded, color: _guestGold.withValues(alpha: 0.9), size: 16),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Book a new stay for a future trip—choose dates and room type. This is separate from your current stay and bill above.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.92),
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: _guestGold,
                    foregroundColor: Colors.green.shade900,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    final now = DateTime.now();
                    final checkOut = now.add(const Duration(days: 1));
                    context.push('/guest/rooms', extra: <String, dynamic>{
                      'checkInDate': now,
                      'checkOutDate': checkOut,
                    });
                  },
                  icon: const Icon(Icons.bed_rounded, size: 22),
                  label: const Text(
                    'Book a new stay',
                    style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.2),
                  ),
                ),
              ),
            ],
          ),
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