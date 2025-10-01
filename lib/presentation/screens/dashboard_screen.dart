import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:pzed_homes/core/services/mock_auth_service.dart';
import 'package:pzed_homes/core/state/app_state.dart';
import 'package:pzed_homes/core/animations/app_animations.dart';
import 'package:pzed_homes/core/layout/responsive_layout.dart';
import 'package:pzed_homes/core/error/error_handler.dart';
import 'package:pzed_homes/presentation/widgets/summary_card.dart';
import 'package:pzed_homes/presentation/screens/create_booking_screen.dart';
import 'package:pzed_homes/presentation/screens/user_profile_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _searchController = TextEditingController();
  final _supabase = Supabase.instance.client;

  List<Map<String, dynamic>> _bookings = [];
  List<Map<String, dynamic>> _filteredBookings = [];
  Map<String, dynamic> _stats = {};
  Map<String, dynamic>? _lastAttendanceRecord;
  bool _isClockedIn = false;
  bool _isLoading = true;
  bool _isLoadingAttendance = true;

  @override
  void initState() {
    super.initState();
    _loadData();
    _searchController.addListener(_filterBookings);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      // Load data sequentially to avoid type issues
      final bookings = await _supabase
          .from('bookings')
          .select('*, profiles(full_name), rooms(room_number)')
          .order('created_at', ascending: false)
          .limit(50);
      
      final stats = await _calculateDashboardStats();
      final attendance = await _fetchLastAttendance();

      if (mounted) {
        setState(() {
          _bookings = List<Map<String, dynamic>>.from(bookings);
          _filteredBookings = _bookings;
          _stats = stats;
          _lastAttendanceRecord = attendance;
          _isClockedIn = attendance != null && attendance['clock_out_time'] == null;
          _isLoading = false;
          _isLoadingAttendance = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isLoadingAttendance = false;
        });
      }
      ErrorHandler.handleError(context, e);
    }
  }

  Future<Map<String, dynamic>> _calculateDashboardStats() async {
    try {
      final checkedIn = await _supabase
          .from('bookings')
          .select('id')
          .eq('status', 'Checked-in');
      
      final pending = await _supabase
          .from('bookings')
          .select('id')
          .eq('status', 'Pending Check-in');
      
      final totalRooms = await _supabase
          .from('rooms')
          .select('id');

      final checkedInCount = checkedIn.length;
      final pendingCount = pending.length;
      final totalRoomsCount = totalRooms.length;
      final occupancyRate = totalRoomsCount > 0 ? ((checkedInCount / totalRoomsCount) * 100).round() : 0;

      return {
        'checked_in_count': checkedInCount,
        'pending_count': pendingCount,
        'occupancy_rate': occupancyRate,
        'total_revenue': 0, // You can calculate this from bookings if needed
      };
    } catch (e) {
      return {
        'checked_in_count': 0,
        'pending_count': 0,
        'occupancy_rate': 0,
        'total_revenue': 0,
      };
    }
  }

  Future<Map<String, dynamic>?> _fetchLastAttendance() async {
    try {
      final userId = _supabase.auth.currentUser!.id;
      final response = await _supabase
          .from('attendance_records')
          .select()
          .eq('profile_id', userId)
          .order('clock_in_time', ascending: false)
          .limit(1);

      return response.isNotEmpty ? response.first : null;
    } catch (e) {
      return null;
    }
  }

  void _filterBookings() {
    final query = _searchController.text.toLowerCase();
    if (mounted) {
      setState(() {
        _filteredBookings = _bookings.where((booking) {
          final guestName = (booking['profiles'] as Map<String, dynamic>?)?
              ['full_name']?.toString().toLowerCase() ?? '';
          final roomNumber = (booking['rooms'] as Map<String, dynamic>?)?
              ['room_number']?.toString().toLowerCase() ?? '';
          return guestName.contains(query) || roomNumber.contains(query);
        }).toList();
      });
    }
  }

  Future<void> _handleClockIn() async {
    try {
      final userId = _supabase.auth.currentUser!.id;
      await _supabase.from('attendance_records').insert({
        'profile_id': userId,
        'clock_in_time': DateTime.now().toIso8601String(),
      });
      await _loadData();
    } catch (e) {
      ErrorHandler.handleError(context, e);
    }
  }

  Future<void> _handleClockOut() async {
    try {
      await _supabase
          .from('attendance_records')
          .update({'clock_out_time': DateTime.now().toIso8601String()})
          .eq('id', _lastAttendanceRecord!['id']);
      await _loadData();
    } catch (e) {
      ErrorHandler.handleError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth > 1200) {
                  return _buildDesktopLayout(context);
                } else if (constraints.maxWidth > 800) {
                  return _buildTabletLayout(context);
                } else {
                  return _buildMobileLayout(context);
                }
              },
            ),
    );
  }

  Widget _buildDesktopLayout(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: AppAnimations.staggeredList(
        children: [
          AppAnimations.slideInFromBottom(
            child: _buildHeader(context),
          ),
          const SizedBox(height: 24),
          AppAnimations.staggeredGrid(
            children: _buildMetricCardsList(context),
            crossAxisCount: 4,
          ),
          const SizedBox(height: 24),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 2,
                child: AppAnimations.scaleTransition(
                  child: _buildOccupancyChart(context),
                  animation: AlwaysStoppedAnimation(1.0),
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                flex: 1,
                child: AppAnimations.slideTransition(
                  child: _buildRecentActivities(context),
                  animation: AlwaysStoppedAnimation(1.0),
                  direction: SlideDirection.right,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          AppAnimations.fadeTransition(
            child: _buildBookingsTable(context),
            animation: AlwaysStoppedAnimation(1.0),
          ),
        ],
      ),
    );
  }

  Widget _buildTabletLayout(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(context),
          const SizedBox(height: 16),
          _buildMetricCards(context),
          const SizedBox(height: 16),
          _buildOccupancyChart(context),
          const SizedBox(height: 16),
          _buildRecentActivities(context),
          const SizedBox(height: 16),
          _buildBookingsTable(context),
        ],
      ),
    );
  }

  Widget _buildMobileLayout(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(context),
          const SizedBox(height: 16),
          _buildMetricCards(context),
          const SizedBox(height: 16),
          _buildOccupancyChart(context),
          const SizedBox(height: 16),
          _buildRecentActivities(context),
          const SizedBox(height: 16),
          _buildBookingsTable(context),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Dashboard',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.green[800],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Welcome back! Here\'s what\'s happening at P-ZED Homes.',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
        _buildAttendanceCard(),
      ],
    );
  }

  List<Widget> _buildMetricCardsList(BuildContext context) {
    return [
      _buildMetricCard(
          context,
          'New Bookings',
          '${_stats['pending_count'] ?? 0}',
          Icons.book_online,
          Colors.blue,
        ),
        _buildMetricCard(
          context,
          'Checked In',
          '${_stats['checked_in_count'] ?? 0}',
          Icons.login,
          Colors.green,
        ),
        _buildMetricCard(
          context,
          'Occupancy Rate',
          '${_stats['occupancy_rate'] ?? 0}%',
          Icons.hotel,
          Colors.orange,
        ),
        _buildMetricCard(
          context,
          'Total Revenue',
          '₦${_stats['total_revenue'] ?? 0}',
          Icons.attach_money,
          Colors.purple,
        ),
    ];
  }

  Widget _buildMetricCards(BuildContext context) {
    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: _buildMetricCardsList(context),
    );
  }

  Widget _buildMetricCard(BuildContext context, String title, String value, IconData icon, Color color) {
    return AppAnimations.animatedCard(
      child: Container(
        width: 200,
        padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const Spacer(),
              Icon(Icons.trending_up, color: Colors.green[400], size: 16),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            value,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: Colors.grey[800],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    ),
    );
  }

  Widget _buildOccupancyChart(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Occupancy by Rooms',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: Colors.grey[800],
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 300,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: 100,
                barTouchData: BarTouchData(enabled: false),
                titlesData: FlTitlesData(
                  show: true,
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        return Text(
                          'Room ${value.toInt()}',
                          style: const TextStyle(fontSize: 10),
                        );
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        return Text(
                          '${value.toInt()}%',
                          style: const TextStyle(fontSize: 10),
                        );
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                barGroups: _generateBarGroups(),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: 20,
                  getDrawingHorizontalLine: (value) {
                    return FlLine(
                      color: Colors.grey[200]!,
                      strokeWidth: 1,
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<BarChartGroupData> _generateBarGroups() {
    // Generate sample data for the chart
    return List.generate(5, (index) {
      return BarChartGroupData(
        x: index + 1,
        barRods: [
          BarChartRodData(
            toY: (index + 1) * 15.0 + 20.0,
            color: Colors.green[400],
            width: 20,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(4),
              topRight: Radius.circular(4),
            ),
          ),
        ],
      );
    });
  }

  Widget _buildRecentActivities(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Recent Activities',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: Colors.grey[800],
            ),
          ),
          const SizedBox(height: 16),
          ...List.generate(5, (index) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: Colors.green[400],
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Guest checked in Room ${101 + index}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w500,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          '${index + 1} hour${index > 0 ? 's' : ''} ago',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildBookingsTable(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Text(
                  'Recent Bookings',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[800],
                  ),
                ),
                const Spacer(),
                SizedBox(
                  width: 300,
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search by guest name or room...',
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_filteredBookings.isEmpty)
            Container(
              padding: const EdgeInsets.all(40),
              child: Center(
                child: Column(
                  children: [
                    Image.asset(
                      'assets/images/PZED logo.png',
                      height: 64,
                      width: 64,
                      fit: BoxFit.contain,
                      color: Colors.grey[400],
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'No bookings found',
                      style: TextStyle(fontSize: 18, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            )
          else
            DataTable(
              columns: const [
                DataColumn(label: Text('Guest Name')),
                DataColumn(label: Text('Room')),
                DataColumn(label: Text('Status')),
                DataColumn(label: Text('Check-in')),
                DataColumn(label: Text('Check-out')),
                DataColumn(label: Text('Actions')),
              ],
              rows: _filteredBookings.take(10).map((booking) {
                final guestName = (booking['profiles'] as Map<String, dynamic>?)?['full_name'] ?? 'Unknown';
                final roomNumber = (booking['rooms'] as Map<String, dynamic>?)?['room_number'] ?? 'Unknown';
                final status = booking['status'] as String? ?? 'Unknown';
                final checkIn = booking['check_in_date'] != null 
                    ? DateFormat('MMM dd, yyyy').format(DateTime.parse(booking['check_in_date']))
                    : 'N/A';
                final checkOut = booking['check_out_date'] != null 
                    ? DateFormat('MMM dd, yyyy').format(DateTime.parse(booking['check_out_date']))
                    : 'N/A';

                return DataRow(
                  cells: [
                    DataCell(Text(guestName)),
                    DataCell(Text(roomNumber)),
                    DataCell(
                      Chip(
                        label: Text(status),
                        backgroundColor: _getStatusColor(status).withOpacity(0.1),
                        labelStyle: TextStyle(color: _getStatusColor(status)),
                      ),
                    ),
                    DataCell(Text(checkIn)),
                    DataCell(Text(checkOut)),
                    DataCell(
                      IconButton(
                        icon: const Icon(Icons.visibility),
                        onPressed: () {
                          // Navigate to booking details
                        },
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildAttendanceCard() {
    if (_isLoadingAttendance) return const LinearProgressIndicator();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _isClockedIn ? Colors.green[50] : Colors.blue[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _isClockedIn ? Colors.green[200]! : Colors.blue[200]!,
        ),
      ),
      child: Column(
        children: [
          Text(
            'Attendance',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 8),
          Text(
            _isClockedIn ? 'You are clocked IN' : 'You are clocked OUT',
            style: TextStyle(
              color: _isClockedIn ? Colors.green[700] : Colors.blue[700],
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _isClockedIn ? _handleClockOut : _handleClockIn,
            style: ElevatedButton.styleFrom(
              backgroundColor: _isClockedIn ? Colors.red : Colors.green,
              foregroundColor: Colors.white,
            ),
            child: Text(_isClockedIn ? 'Clock Out' : 'Clock In'),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'checked-in':
        return Colors.green;
      case 'pending check-in':
        return Colors.orange;
      case 'checked-out':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }
}