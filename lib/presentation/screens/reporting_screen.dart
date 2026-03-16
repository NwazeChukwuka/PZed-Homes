import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:pzed_homes/core/services/reporting_service.dart';
import 'package:pzed_homes/core/services/payment_service.dart';

class ReportingScreen extends StatefulWidget {
  const ReportingScreen({super.key});

  @override
  State<ReportingScreen> createState() => _ReportingScreenState();
}

class _ReportingScreenState extends State<ReportingScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _reportingService = ReportingService();
  final NumberFormat _currency = NumberFormat.currency(locale: 'en_NG', symbol: '₦');

  PLData? _plData;
  Map<String, dynamic>? _guestStats;
  Map<String, dynamic>? _opsStats;
  TimePeriod _selectedPeriod = TimePeriod.thisMonth;
  DateTimeRange? _customDateRange;
  bool _isLoading = true;
  String? _loadError;

  final _startDateController = TextEditingController();
  final _endDateController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadAll();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _startDateController.dispose();
    _endDateController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final results = await Future.wait([
        _reportingService.getProfitAndLoss(
          period: _selectedPeriod,
          customStart: _customDateRange?.start,
          customEnd: _customDateRange?.end,
        ),
        _reportingService.getGuestStats(
          period: _selectedPeriod,
          customStart: _customDateRange?.start,
          customEnd: _customDateRange?.end,
        ),
        _reportingService.getOperationsStats(
          period: _selectedPeriod,
          customStart: _customDateRange?.start,
          customEnd: _customDateRange?.end,
        ),
      ]);
      if (mounted) {
        setState(() {
          _plData = results[0] as PLData;
          _guestStats = results[1] as Map<String, dynamic>;
          _opsStats = results[2] as Map<String, dynamic>;
          _isLoading = false;
          _loadError = null;
        });
      }
    } catch (e, stackTrace) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadError = e is Exception ? e.toString() : 'Failed to load reports.';
        });
        // No dialog: in-tab Retry and header Refresh are the recovery paths.
      }
    }
  }

  Future<void> _selectCustomDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now,
      initialDateRange: _customDateRange ??
          DateTimeRange(start: DateTime(now.year, now.month, 1), end: now),
    );
    if (picked != null) {
      setState(() {
        _selectedPeriod = TimePeriod.custom;
        _customDateRange = picked;
        _startDateController.text = DateFormat('MMM dd, yyyy').format(picked.start);
        _endDateController.text = DateFormat('MMM dd, yyyy').format(picked.end);
      });
      _loadAll();
    }
  }

  String _periodLabel() {
    switch (_selectedPeriod) {
      case TimePeriod.thisMonth:
        return DateFormat('MMMM yyyy').format(DateTime.now());
      case TimePeriod.lastMonth:
        final lm = DateTime(DateTime.now().year, DateTime.now().month - 1, 1);
        return DateFormat('MMMM yyyy').format(lm);
      case TimePeriod.last30Days:
        return 'Last 30 days';
      case TimePeriod.custom:
        if (_customDateRange != null) {
          return '${DateFormat('MMM dd').format(_customDateRange!.start)} – ${DateFormat('MMM dd, yyyy').format(_customDateRange!.end)}';
        }
        return 'Last 30 days (default)';
      default:
        return _selectedPeriod.name;
    }
  }

  String _fmtNaira(int kobo) => _currency.format(PaymentService.koboToNaira(kobo));

  // ────────────────────────── BUILD ──────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: Column(
        children: [
          _buildHeader(context),
          _buildTabBar(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildFinancialTab(),
                _buildGuestTab(),
                _buildOperationsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Reports & Analytics',
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold, color: Colors.green[800])),
                    const SizedBox(height: 4),
                    Text(_periodLabel(), style: TextStyle(color: Colors.grey[600], fontSize: 14)),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _isLoading ? null : () {
                  setState(() => _loadError = null);
                  _loadAll();
                },
                tooltip: 'Refresh',
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(color: Colors.green[50], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.green[200]!)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.analytics, color: Colors.green[700], size: 16),
                    const SizedBox(width: 8),
                    Text('Business Intelligence', style: TextStyle(color: Colors.green[700], fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildPeriodSelector(),
        ],
      ),
    );
  }

  Widget _buildErrorRetry() {
    return _card(
      child: Column(
        children: [
          Icon(Icons.error_outline, size: 48, color: Colors.red[400]),
          const SizedBox(height: 12),
          Text(_loadError ?? 'Something went wrong.', style: TextStyle(color: Colors.grey[800]), textAlign: TextAlign.center),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _isLoading ? null : () { setState(() => _loadError = null); _loadAll(); },
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green[700], foregroundColor: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 2, offset: const Offset(0, 1))],
      ),
      child: TabBar(
        controller: _tabController,
        labelColor: Colors.green[700],
        unselectedLabelColor: Colors.grey[700],
        indicatorColor: Colors.green[700],
        tabs: const [
          Tab(text: 'Financial', icon: Icon(Icons.account_balance)),
          Tab(text: 'Guest', icon: Icon(Icons.people)),
          Tab(text: 'Operations', icon: Icon(Icons.engineering)),
        ],
      ),
    );
  }

  // ────────────────────── SHARED WIDGETS ──────────────────────

  Widget _buildPeriodSelector() {
    const chipSpacing = 8.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 500;
        final chips = [
          ChoiceChip(label: const Text('This Month'), selected: _selectedPeriod == TimePeriod.thisMonth,
            onSelected: (_) { setState(() => _selectedPeriod = TimePeriod.thisMonth); _loadAll(); }),
          ChoiceChip(label: const Text('Last Month'), selected: _selectedPeriod == TimePeriod.lastMonth,
            onSelected: (_) { setState(() => _selectedPeriod = TimePeriod.lastMonth); _loadAll(); }),
          ChoiceChip(label: const Text('Last 30 Days'), selected: _selectedPeriod == TimePeriod.last30Days,
            onSelected: (_) { setState(() => _selectedPeriod = TimePeriod.last30Days); _loadAll(); }),
          ChoiceChip(label: const Text('Custom'), selected: _selectedPeriod == TimePeriod.custom,
            onSelected: (_) => _selectCustomDateRange()),
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Select Period:', style: TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            isNarrow
                ? SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var i = 0; i < chips.length; i++) ...[
                          if (i > 0) const SizedBox(width: chipSpacing),
                          chips[i],
                        ],
                      ],
                    ),
                  )
                : Wrap(
                    spacing: chipSpacing,
                    runSpacing: chipSpacing,
                    children: chips,
                  ),
            if (_selectedPeriod == TimePeriod.custom && _customDateRange != null) ...[
              const SizedBox(height: 12),
              isNarrow
                  ? Column(
                      children: [
                        TextField(
                          controller: _startDateController,
                          readOnly: true,
                          onTap: _selectCustomDateRange,
                          decoration: const InputDecoration(
                            labelText: 'Start Date',
                            border: OutlineInputBorder(),
                            suffixIcon: Icon(Icons.calendar_today),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _endDateController,
                          readOnly: true,
                          onTap: _selectCustomDateRange,
                          decoration: const InputDecoration(
                            labelText: 'End Date',
                            border: OutlineInputBorder(),
                            suffixIcon: Icon(Icons.calendar_today),
                          ),
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _startDateController,
                            readOnly: true,
                            onTap: _selectCustomDateRange,
                            decoration: const InputDecoration(
                              labelText: 'Start Date',
                              border: OutlineInputBorder(),
                              suffixIcon: Icon(Icons.calendar_today),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextField(
                            controller: _endDateController,
                            readOnly: true,
                            onTap: _selectCustomDateRange,
                            decoration: const InputDecoration(
                              labelText: 'End Date',
                              border: OutlineInputBorder(),
                              suffixIcon: Icon(Icons.calendar_today),
                            ),
                          ),
                        ),
                      ],
                    ),
            ],
          ],
        );
      },
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 2))],
      ),
      child: child,
    );
  }

  Widget _kpiCard(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: _card(
        child: Column(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600]), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey[800])),
    );
  }

  // ────────────────────── FINANCIAL TAB ──────────────────────

  Widget _buildFinancialTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'P&L includes payroll, purchases and maintenance. Room revenue is from check-outs in the selected period.',
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
          ),
          const SizedBox(height: 24),
          if (_loadError != null)
            _buildErrorRetry()
          else if (_isLoading)
            const Center(child: Padding(padding: EdgeInsets.all(48), child: CircularProgressIndicator()))
          else if (_plData == null)
            const Center(child: Text('No financial transactions recorded for this period.'))
          else ...[
            _buildFinancialKPIs(),
            const SizedBox(height: 16),
            _buildTopDepartmentCard(),
            const SizedBox(height: 16),
            _buildSummaryCard(),
            const SizedBox(height: 16),
            _buildBreakdownSection('Revenue Breakdown (checked out in period)', _plData!.revenueBreakdown, Colors.green),
            const SizedBox(height: 16),
            _buildBreakdownSection('Expense Breakdown', _plData!.expenseBreakdown, Colors.red),
            const SizedBox(height: 24),
            _buildFinancialDetailTables(),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _generatePDF,
                icon: const Icon(Icons.picture_as_pdf),
                label: const Text('Save / Print Report as PDF'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green[800], foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFinancialKPIs() {
    final revenue = _plData!.totalRevenue;
    final expenses = _plData!.totalExpenses;
    final netProfit = revenue - expenses;
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 500;
        final cards = [
          _kpiCard('Total Revenue', _fmtNaira(revenue), Icons.trending_up, Colors.green[700]!),
          _kpiCard('Total Expenses', _fmtNaira(expenses), Icons.trending_down, Colors.red[600]!),
          _kpiCard('Net Profit', _fmtNaira(netProfit), Icons.account_balance_wallet, netProfit >= 0 ? Colors.green[800]! : Colors.red[800]!),
        ];
        if (isNarrow) {
          return Column(children: cards.map((c) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Row(children: [c]))).toList());
        }
        return Row(children: cards.map((c) => Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: c)).toList());
      },
    );
  }

  Widget _buildTopDepartmentCard() {
    final breakdown = _plData!.revenueBreakdown;
    if (breakdown.isEmpty) return const SizedBox.shrink();
    final top = breakdown.reduce((a, b) => a.amount >= b.amount ? a : b);
    if (top.amount <= 0) return const SizedBox.shrink();
    return _card(
      child: Row(
        children: [
          Icon(Icons.emoji_events, color: Colors.amber[700], size: 36),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Top Performing', style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                Text(top.category, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
          ),
          Text(_fmtNaira(top.amount), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.green[700])),
        ],
      ),
    );
  }

  Widget _buildSummaryCard() {
    final revenue = _plData!.totalRevenue;
    final expenses = _plData!.totalExpenses;
    final net = revenue - expenses;
    return _card(child: Column(
      children: [
        _sectionTitle('Financial Summary'),
        _summaryRow('Total Revenue', revenue, Colors.green),
        _summaryRow('Total Expenses', expenses, Colors.red),
        const Divider(),
        _summaryRow('Net Profit/Loss', net, net >= 0 ? Colors.green : Colors.red, bold: true),
      ],
    ));
  }

  Widget _summaryRow(String title, int amount, Color color, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: TextStyle(fontSize: bold ? 17 : 15, fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
          Text(_fmtNaira(amount), style: TextStyle(fontSize: bold ? 17 : 15, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  Widget _buildBreakdownSection(String title, List<CategoryAmount> items, Color color) {
    return _card(child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(title),
        ...items.map((item) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(child: Text(item.category, overflow: TextOverflow.ellipsis)),
              Text(_fmtNaira(item.amount), style: TextStyle(fontWeight: FontWeight.w600, color: color)),
            ],
          ),
        )),
      ],
    ));
  }

  Widget _buildFinancialDetailTables() {
    final revenueItems = _plData!.revenueItems;
    final expenseItems = _plData!.expenseItems;

    if (revenueItems.isEmpty && expenseItems.isEmpty) {
      return Center(
        child: Text(
          'No financial transactions recorded for this period.',
          style: TextStyle(color: Colors.grey[600]),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Revenue Transactions'),
        if (revenueItems.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text('No revenue transactions for this period.', style: TextStyle(color: Colors.grey[600])),
          )
        else
          _card(
            child: SizedBox(
              height: 260,
              child: Scrollbar(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('Check-out Date')),
                      DataColumn(label: Text('Room Type')),
                      DataColumn(label: Text('Status')),
                      DataColumn(label: Text('Amount (₦)')),
                      DataColumn(label: Text('Booking ID')),
                    ],
                    rows: revenueItems.map((b) {
                      final id = b['id']?.toString() ?? '';
                      final status = b['status']?.toString() ?? '';
                      final rooms = b['rooms'];
                      String roomType = '';
                      if (rooms is Map && rooms['type'] != null) {
                        roomType = rooms['type']?.toString() ?? '';
                      } else if (rooms is List && rooms.isNotEmpty && rooms.first is Map) {
                        roomType = (rooms.first as Map)['type']?.toString() ?? '';
                      } else {
                        roomType = b['requested_room_type']?.toString() ?? '';
                      }
                      final rawDate = b['check_out_date']?.toString();
                      String dateStr = rawDate ?? '';
                      try {
                        if (rawDate != null) {
                          final dt = DateTime.parse(rawDate);
                          dateStr = DateFormat('MMM dd, yyyy').format(dt);
                        }
                      } catch (_) {}
                      final totalAmount = (b['total_amount'] as num?)?.toInt();
                      final paidAmount = (b['paid_amount'] as num?)?.toInt() ?? 0;
                      final amount = totalAmount ?? paidAmount;
                      return DataRow(
                        cells: [
                          DataCell(Text(dateStr)),
                          DataCell(Text(roomType.isEmpty ? 'Room' : roomType)),
                          DataCell(Text(status)),
                          DataCell(Text(_fmtNaira(amount))),
                          DataCell(Text(id)),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(height: 24),
        _sectionTitle('Expense & Payroll Transactions'),
        if (expenseItems.isEmpty)
          Text('No expense or payroll transactions for this period.', style: TextStyle(color: Colors.grey[600]))
        else
          _card(
            child: SizedBox(
              height: 260,
              child: Scrollbar(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('Date')),
                      DataColumn(label: Text('Category')),
                      DataColumn(label: Text('Department')),
                      DataColumn(label: Text('Description')),
                      DataColumn(label: Text('Amount (₦)')),
                    ],
                    rows: expenseItems.map((e) {
                      final rawDate = e['transaction_date']?.toString();
                      String dateStr = rawDate ?? '';
                      try {
                        if (rawDate != null) {
                          final dt = DateTime.parse(rawDate);
                          dateStr = DateFormat('MMM dd, yyyy').format(dt);
                        }
                      } catch (_) {}
                      final category = e['category']?.toString() ?? '';
                      final dept = e['department']?.toString() ?? '';
                      final desc = e['description']?.toString() ?? '';
                      final amount = (e['amount'] as num?)?.toInt() ?? 0;
                      return DataRow(
                        cells: [
                          DataCell(Text(dateStr)),
                          DataCell(Text(category)),
                          DataCell(Text(dept.isEmpty ? 'General' : dept)),
                          DataCell(SizedBox(width: 260, child: Text(desc, overflow: TextOverflow.ellipsis))),
                          DataCell(Text(_fmtNaira(amount))),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ────────────────────── GUEST TAB ──────────────────────

  Widget _buildGuestTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'Guest metrics for the selected period.',
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
          ),
          const SizedBox(height: 24),
          if (_loadError != null)
            _buildErrorRetry()
          else if (_isLoading)
            const Center(child: Padding(padding: EdgeInsets.all(48), child: CircularProgressIndicator()))
          else if (_guestStats == null)
            const Center(child: Text('No guest bookings recorded for this period.'))
          else ...[
            _buildGuestKPIs(),
            const SizedBox(height: 16),
            _buildGuestBreakdown(),
            const SizedBox(height: 24),
            _buildGuestDetailsTable(),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _generateGuestPDF,
                icon: const Icon(Icons.picture_as_pdf),
                label: const Text('Save / Print Report as PDF'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green[800], foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildGuestKPIs() {
    final g = _guestStats!;
    return LayoutBuilder(builder: (context, constraints) {
      final isNarrow = constraints.maxWidth < 500;
      final cards = [
        _kpiCard('Total Bookings', '${g['total']}', Icons.book_online, Colors.blue[700]!),
        _kpiCard('Room Revenue (bookings created in period)', _fmtNaira(g['revenue'] ?? 0), Icons.hotel, Colors.green[700]!),
        _kpiCard('Avg Stay', '${g['avg_nights']} nights', Icons.nights_stay, Colors.purple[600]!),
      ];
      if (isNarrow) {
        return Column(children: cards.map((c) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Row(children: [c]))).toList());
      }
      return Row(children: cards.map((c) => Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: c)).toList());
    });
  }

  Widget _buildGuestBreakdown() {
    final g = _guestStats!;
    final statuses = [
      ('Checked In', g['checked_in'] ?? 0, Colors.green),
      ('Checked Out', g['checked_out'] ?? 0, Colors.blue),
      ('Confirmed', g['confirmed'] ?? 0, Colors.teal),
      ('Pending', g['pending'] ?? 0, Colors.orange),
      ('Cancelled', g['cancelled'] ?? 0, Colors.red),
    ];
    return _card(child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Booking Status Breakdown'),
        ...statuses.map((s) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Container(width: 12, height: 12, decoration: BoxDecoration(color: s.$3, shape: BoxShape.circle)),
              const SizedBox(width: 12),
              Expanded(child: Text(s.$1, style: const TextStyle(fontSize: 15))),
              Text('${s.$2}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ],
          ),
        )),
        const Divider(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Avg Revenue / Booking', style: TextStyle(fontSize: 14)),
            Text(_fmtNaira(g['avg_revenue'] ?? 0), style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green[700])),
          ],
        ),
      ],
    ));
  }

  Widget _buildGuestDetailsTable() {
    final rows = (_guestStats?['rows'] as List?) ?? const [];
    if (rows.isEmpty) {
      return Center(
        child: Text(
          'No guest bookings recorded for this period.',
          style: TextStyle(color: Colors.grey[600]),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Booking Details'),
        _card(
          child: SizedBox(
            height: 260,
            child: Scrollbar(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('Booking ID')),
                    DataColumn(label: Text('Check-in')),
                    DataColumn(label: Text('Check-out')),
                    DataColumn(label: Text('Status')),
                    DataColumn(label: Text('Total (₦)')),
                  ],
                  rows: rows.map<DataRow>((b) {
                    final id = b['id']?.toString() ?? '';
                    final status = b['status']?.toString() ?? '';
                    String ciStr = '';
                    String coStr = '';
                    try {
                      final ci = b['check_in_date']?.toString();
                      if (ci != null) {
                        ciStr = DateFormat('MMM dd, yyyy').format(DateTime.parse(ci));
                      }
                    } catch (_) {}
                    try {
                      final co = b['check_out_date']?.toString();
                      if (co != null) {
                        coStr = DateFormat('MMM dd, yyyy').format(DateTime.parse(co));
                      }
                    } catch (_) {}
                    final totalAmount = (b['total_amount'] as num?)?.toInt();
                    final paidAmount = (b['paid_amount'] as num?)?.toInt() ?? 0;
                    final amount = totalAmount ?? paidAmount;
                    return DataRow(
                      cells: [
                        DataCell(Text(id)),
                        DataCell(Text(ciStr)),
                        DataCell(Text(coStr)),
                        DataCell(Text(status)),
                        DataCell(Text(_fmtNaira(amount))),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ────────────────────── OPERATIONS TAB ──────────────────────

  Widget _buildOperationsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'Operations metrics for the selected period.',
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
          ),
          const SizedBox(height: 24),
          if (_loadError != null)
            _buildErrorRetry()
          else if (_isLoading)
            const Center(child: Padding(padding: EdgeInsets.all(48), child: CircularProgressIndicator()))
          else if (_opsStats == null)
            const Center(child: Text('No operations activity recorded for this period.'))
          else ...[
            _buildOpsKPIs(),
            const SizedBox(height: 16),
            _buildOpsDetails(),
            const SizedBox(height: 24),
            _buildOpsActivityTable(),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _generateOperationsPDF,
                icon: const Icon(Icons.picture_as_pdf),
                label: const Text('Save / Print Report as PDF'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green[800], foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildOpsKPIs() {
    final o = _opsStats!;
    return LayoutBuilder(builder: (context, constraints) {
      final isNarrow = constraints.maxWidth < 500;
      final cards = [
        _kpiCard('Staff Activities', '${o['activity_count']}', Icons.assignment, Colors.blue[700]!),
        _kpiCard('Active Staff', '${o['unique_staff']}', Icons.people, Colors.teal[600]!),
        _kpiCard('Stock Warnings', '${o['negative_adjustments']}', Icons.warning_amber, (o['negative_adjustments'] ?? 0) > 0 ? Colors.red[600]! : Colors.green[600]!),
      ];
      if (isNarrow) {
        return Column(children: cards.map((c) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Row(children: [c]))).toList());
      }
      return Row(children: cards.map((c) => Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: c)).toList());
    });
  }

  Widget _buildOpsDetails() {
    final o = _opsStats!;
    final negAdj = o['negative_adjustments'] ?? 0;
    return _card(child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Operational Summary'),
        _opsRow(Icons.assignment_turned_in, 'Total Logged Activities', '${o['activity_count']}'),
        _opsRow(Icons.badge, 'Unique Active Staff', '${o['unique_staff']}'),
        _opsRow(Icons.star, 'Most Active Department', o['top_department'] ?? 'N/A'),
        const Divider(height: 24),
        _opsRow(
          negAdj > 0 ? Icons.warning : Icons.check_circle,
          'Stock Wastage / Losses',
          '$negAdj',
          valueColor: negAdj > 0 ? Colors.red : Colors.green,
        ),
        if (negAdj > 0)
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 36),
            child: Text(
              'Includes wastage entries and negative-quantity transactions. Review with the storekeeper.',
              style: TextStyle(fontSize: 12, color: Colors.red[400]),
            ),
          ),
      ],
    ));
  }

  Widget _buildOpsActivityTable() {
    final activities = (_opsStats?['activities'] as List?) ?? const [];
    if (activities.isEmpty) {
      return Center(
        child: Text(
          'No staff activities recorded for this period.',
          style: TextStyle(color: Colors.grey[600]),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Staff Activity Details'),
        _card(
          child: SizedBox(
            height: 260,
            child: Scrollbar(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('Timestamp')),
                    DataColumn(label: Text('Department')),
                    DataColumn(label: Text('Action')),
                    DataColumn(label: Text('Details')),
                  ],
                  rows: activities.map<DataRow>((a) {
                    final raw = a['created_at']?.toString();
                    String ts = raw ?? '';
                    try {
                      if (raw != null) {
                        ts = DateFormat('MMM dd, yyyy – HH:mm').format(DateTime.parse(raw));
                      }
                    } catch (_) {}
                    final dept = a['department']?.toString() ?? '';
                    final action = a['action']?.toString() ?? '';
                    final details = a['details']?.toString() ?? '';
                    return DataRow(
                      cells: [
                        DataCell(Text(ts)),
                        DataCell(Text(dept.isEmpty ? 'N/A' : dept)),
                        DataCell(Text(action)),
                        DataCell(SizedBox(width: 280, child: Text(details, overflow: TextOverflow.ellipsis))),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _opsRow(IconData icon, String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.grey[600]),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 14))),
          Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: valueColor)),
        ],
      ),
    );
  }

  // ────────────────────── PDF GENERATION ──────────────────────

  Future<void> _generatePDF() async {
    if (_plData == null) return;
    final pdf = pw.Document();
    final revenue = _plData!.totalRevenue;
    final expenses = _plData!.totalExpenses;
    final net = revenue - expenses;
    final period = _periodLabel();

    pdf.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(40),
      build: (pw.Context ctx) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('PZed Homes', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold, color: PdfColors.green800)),
            pw.SizedBox(height: 4),
            pw.Text('Monthly Financial Report – $period', style: const pw.TextStyle(fontSize: 14, color: PdfColors.grey700)),
            pw.Divider(thickness: 2, color: PdfColors.green800),
            pw.SizedBox(height: 16),

            pw.Text('Financial Summary', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 8),
            _pdfRow('Total Revenue', _fmtNaira(revenue)),
            _pdfRow('Total Expenses', _fmtNaira(expenses)),
            pw.Divider(),
            _pdfRow('Net Profit/Loss', _fmtNaira(net), bold: true),
            pw.SizedBox(height: 20),

            pw.Text('Revenue Breakdown', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 8),
            ..._plData!.revenueBreakdown.map((item) => _pdfRow(item.category, _fmtNaira(item.amount))),
            pw.SizedBox(height: 20),

            pw.Text('Expense Breakdown', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 8),
            ..._plData!.expenseBreakdown.map((item) => _pdfRow(item.category, _fmtNaira(item.amount))),
            pw.SizedBox(height: 30),

            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text(
                'Generated on ${DateFormat('MMMM dd, yyyy – hh:mm a').format(DateTime.now())}',
                style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
              ),
            ),
          ],
        );
      },
    ));

    await Printing.layoutPdf(onLayout: (format) => pdf.save());
  }

  Future<void> _generateGuestPDF() async {
    if (_guestStats == null) return;
    final g = _guestStats!;
    final pdf = pw.Document();
    final period = _periodLabel();

    pdf.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(40),
      build: (pw.Context ctx) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('PZed Homes', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold, color: PdfColors.green800)),
            pw.SizedBox(height: 4),
            pw.Text('Guest Report – $period', style: const pw.TextStyle(fontSize: 14, color: PdfColors.grey700)),
            pw.Divider(thickness: 2, color: PdfColors.green800),
            pw.SizedBox(height: 16),

            pw.Text('Guest KPIs', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 8),
            _pdfRow('Total Bookings', '${g['total']}'),
            _pdfRow('Room Revenue (bookings created in period)', _fmtNaira(g['revenue'] ?? 0)),
            _pdfRow('Avg Stay', '${g['avg_nights']} nights'),
            pw.SizedBox(height: 20),

            pw.Text('Booking Status Breakdown', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 8),
            _pdfRow('Checked In', '${g['checked_in'] ?? 0}'),
            _pdfRow('Checked Out', '${g['checked_out'] ?? 0}'),
            _pdfRow('Confirmed', '${g['confirmed'] ?? 0}'),
            _pdfRow('Pending', '${g['pending'] ?? 0}'),
            _pdfRow('Cancelled', '${g['cancelled'] ?? 0}'),
            pw.Divider(),
            _pdfRow('Avg Revenue / Booking', _fmtNaira(g['avg_revenue'] ?? 0), bold: true),
            pw.SizedBox(height: 30),

            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text(
                'Generated on ${DateFormat('MMMM dd, yyyy – hh:mm a').format(DateTime.now())}',
                style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
              ),
            ),
          ],
        );
      },
    ));

    await Printing.layoutPdf(onLayout: (format) => pdf.save());
  }

  Future<void> _generateOperationsPDF() async {
    if (_opsStats == null) return;
    final o = _opsStats!;
    final negAdj = o['negative_adjustments'] ?? 0;
    final pdf = pw.Document();
    final period = _periodLabel();

    pdf.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(40),
      build: (pw.Context ctx) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('PZed Homes', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold, color: PdfColors.green800)),
            pw.SizedBox(height: 4),
            pw.Text('Operations Report – $period', style: const pw.TextStyle(fontSize: 14, color: PdfColors.grey700)),
            pw.Divider(thickness: 2, color: PdfColors.green800),
            pw.SizedBox(height: 16),

            pw.Text('Operations KPIs', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 8),
            _pdfRow('Staff Activities', '${o['activity_count']}'),
            _pdfRow('Active Staff', '${o['unique_staff']}'),
            _pdfRow('Stock Warnings', '${o['negative_adjustments']}'),
            pw.SizedBox(height: 20),

            pw.Text('Operational Summary', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 8),
            _pdfRow('Total Logged Activities', '${o['activity_count']}'),
            _pdfRow('Unique Active Staff', '${o['unique_staff']}'),
            _pdfRow('Most Active Department', o['top_department'] ?? 'N/A'),
            _pdfRow('Stock Wastage / Losses', '$negAdj'),
            pw.SizedBox(height: 30),

            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text(
                'Generated on ${DateFormat('MMMM dd, yyyy – hh:mm a').format(DateTime.now())}',
                style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
              ),
            ),
          ],
        );
      },
    ));

    await Printing.layoutPdf(onLayout: (format) => pdf.save());
  }

  static pw.Widget _pdfRow(String label, String value, {bool bold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: pw.TextStyle(fontSize: 12, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
          pw.Text(value, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
        ],
      ),
    );
  }
}
