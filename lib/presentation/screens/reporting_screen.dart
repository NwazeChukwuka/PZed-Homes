import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:pzed_homes/core/error/error_handler.dart';
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

  bool _financialLoading = false;
  bool _guestLoading = false;
  bool _opsLoading = false;
  String? _financialLoadError;
  String? _guestLoadError;
  String? _opsLoadError;

  // Paginated detail lists (10 per page); reset when tab/period changes
  List<Map<String, dynamic>> _revenueItemsDisplayed = [];
  List<Map<String, dynamic>> _expenseItemsDisplayed = [];
  List<Map<String, dynamic>> _guestRowsDisplayed = [];
  List<Map<String, dynamic>> _opsActivitiesDisplayed = [];
  bool _revenueLoadingMore = false;
  bool _expenseLoadingMore = false;
  bool _guestLoadingMore = false;
  bool _opsLoadingMore = false;

  static const double _kDetailTableHeight = 280.0;
  static const int _detailPageSize = 10;

  final _startDateController = TextEditingController();
  final _endDateController = TextEditingController();

  final ScrollController _revenueTableScroll = ScrollController();
  final ScrollController _expenseTableScroll = ScrollController();
  final ScrollController _guestTableScroll = ScrollController();
  final ScrollController _opsTableScroll = ScrollController();

  bool _isLoadingForTab(int index) {
    switch (index) {
      case 0:
        return _financialLoading;
      case 1:
        return _guestLoading;
      case 2:
        return _opsLoading;
      default:
        return false;
    }
  }

  String? _loadErrorForTab(int index) {
    switch (index) {
      case 0:
        return _financialLoadError;
      case 1:
        return _guestLoadError;
      case 2:
        return _opsLoadError;
      default:
        return null;
    }
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_onTabChanged);
    _revenueTableScroll.addListener(_onRevenueTableScroll);
    _expenseTableScroll.addListener(_onExpenseTableScroll);
    _guestTableScroll.addListener(_onGuestTableScroll);
    _opsTableScroll.addListener(_onOpsTableScroll);
    _loadForTab(0);
  }

  void _onRevenueTableScroll() {
    if (_plData == null || _revenueLoadingMore) return;
    if (_revenueItemsDisplayed.length >= _plData!.totalRevenueCount) return;
    final pos = _revenueTableScroll.position;
    if (pos.pixels >= pos.maxScrollExtent - 40) _loadMoreRevenue();
  }

  void _onExpenseTableScroll() {
    if (_plData == null || _expenseLoadingMore) return;
    if (_expenseItemsDisplayed.length >= _plData!.totalExpenseCount) return;
    final pos = _expenseTableScroll.position;
    if (pos.pixels >= pos.maxScrollExtent - 40) _loadMoreExpense();
  }

  void _onGuestTableScroll() {
    if (_guestStats == null || _guestLoadingMore) return;
    final total = _guestStats!['total_rows_count'] as int? ?? 0;
    if (_guestRowsDisplayed.length >= total) return;
    final pos = _guestTableScroll.position;
    if (pos.pixels >= pos.maxScrollExtent - 40) _loadMoreGuestRows();
  }

  void _onOpsTableScroll() {
    if (_opsStats == null || _opsLoadingMore) return;
    final total = _opsStats!['total_activities_count'] as int? ?? 0;
    if (_opsActivitiesDisplayed.length >= total) return;
    final pos = _opsTableScroll.position;
    if (pos.pixels >= pos.maxScrollExtent - 40) _loadMoreOpsActivities();
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    setState(() {}); // Switch visible tab content
    _loadForTab(_tabController.index, force: false);
  }

  /// Loads data for the given tab. If [force] is false, only loads when that tab's
  /// data is not yet loaded (cached). Force reload on explicit Refresh or after period change.
  void _loadForTab(int index, {bool force = false}) {
    final alreadyLoaded = switch (index) {
      0 => _plData != null,
      1 => _guestStats != null,
      2 => _opsStats != null,
      _ => true,
    };
    if (!force && alreadyLoaded) return;

    switch (index) {
      case 0:
        _loadFinancial();
        break;
      case 1:
        _loadGuest();
        break;
      case 2:
        _loadOperations();
        break;
    }
  }

  void _invalidateAllTabCaches() {
    setState(() {
      _plData = null;
      _guestStats = null;
      _opsStats = null;
      _financialLoadError = null;
      _guestLoadError = null;
      _opsLoadError = null;
      _revenueItemsDisplayed = [];
      _expenseItemsDisplayed = [];
      _guestRowsDisplayed = [];
      _opsActivitiesDisplayed = [];
    });
  }

  Future<void> _loadFinancial() async {
    setState(() {
      _financialLoading = true;
      _financialLoadError = null;
    });
    try {
    final plData = await _reportingService.getProfitAndLoss(
      period: _selectedPeriod,
      customStart: _customDateRange?.start,
      customEnd: _customDateRange?.end,
    );
    if (mounted) {
      setState(() {
        _plData = plData;
          _revenueItemsDisplayed = List.from(plData.revenueItems);
          _expenseItemsDisplayed = List.from(plData.expenseItems);
          _financialLoading = false;
          _financialLoadError = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _financialLoading = false;
          _financialLoadError = ErrorHandler.getFriendlyErrorMessage(e);
        });
      }
    }
  }

  Future<void> _loadGuest() async {
    setState(() {
      _guestLoading = true;
      _guestLoadError = null;
    });
    try {
      final guestStats = await _reportingService.getGuestStats(
        period: _selectedPeriod,
        customStart: _customDateRange?.start,
        customEnd: _customDateRange?.end,
      );
      if (mounted) {
        setState(() {
          _guestStats = guestStats;
          _guestRowsDisplayed = List<Map<String, dynamic>>.from((guestStats['rows'] as List?) ?? []);
          _guestLoading = false;
          _guestLoadError = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _guestLoading = false;
          _guestLoadError = ErrorHandler.getFriendlyErrorMessage(e);
        });
      }
    }
  }

  Future<void> _loadOperations() async {
    setState(() {
      _opsLoading = true;
      _opsLoadError = null;
    });
    try {
      final opsStats = await _reportingService.getOperationsStats(
        period: _selectedPeriod,
        customStart: _customDateRange?.start,
        customEnd: _customDateRange?.end,
      );
      if (mounted) {
        setState(() {
          _opsStats = opsStats;
          _opsActivitiesDisplayed = List<Map<String, dynamic>>.from((opsStats['activities'] as List?) ?? []);
          _opsLoading = false;
          _opsLoadError = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _opsLoading = false;
          _opsLoadError = ErrorHandler.getFriendlyErrorMessage(e);
        });
      }
    }
  }

  Future<void> _loadMoreRevenue() async {
    if (_plData == null || _revenueLoadingMore) return;
    if (_revenueItemsDisplayed.length >= _plData!.totalRevenueCount) return;
    setState(() => _revenueLoadingMore = true);
    try {
      final next = await _reportingService.getRevenueItemsPage(
        period: _selectedPeriod,
        customStart: _customDateRange?.start,
        customEnd: _customDateRange?.end,
        offset: _revenueItemsDisplayed.length,
        limit: _detailPageSize,
      );
      if (mounted) setState(() {
        _revenueItemsDisplayed = [..._revenueItemsDisplayed, ...next];
        _revenueLoadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _revenueLoadingMore = false);
    }
  }

  Future<void> _loadMoreExpense() async {
    if (_plData == null || _expenseLoadingMore) return;
    if (_expenseItemsDisplayed.length >= _plData!.totalExpenseCount) return;
    setState(() => _expenseLoadingMore = true);
    try {
      final next = await _reportingService.getExpenseItemsPage(
        period: _selectedPeriod,
        customStart: _customDateRange?.start,
        customEnd: _customDateRange?.end,
        offset: _expenseItemsDisplayed.length,
        limit: _detailPageSize,
      );
      if (mounted) setState(() {
        _expenseItemsDisplayed = [..._expenseItemsDisplayed, ...next];
        _expenseLoadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _expenseLoadingMore = false);
    }
  }

  Future<void> _loadMoreGuestRows() async {
    if (_guestStats == null || _guestLoadingMore) return;
    final total = _guestStats!['total_rows_count'] as int? ?? 0;
    if (_guestRowsDisplayed.length >= total) return;
    setState(() => _guestLoadingMore = true);
    try {
      final next = await _reportingService.getGuestBookingRowsPage(
        period: _selectedPeriod,
        customStart: _customDateRange?.start,
        customEnd: _customDateRange?.end,
        offset: _guestRowsDisplayed.length,
        limit: _detailPageSize,
      );
      if (mounted) setState(() {
        _guestRowsDisplayed = [..._guestRowsDisplayed, ...next];
        _guestLoadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _guestLoadingMore = false);
    }
  }

  Future<void> _loadMoreOpsActivities() async {
    if (_opsStats == null || _opsLoadingMore) return;
    final total = _opsStats!['total_activities_count'] as int? ?? 0;
    if (_opsActivitiesDisplayed.length >= total) return;
    setState(() => _opsLoadingMore = true);
    try {
      final next = await _reportingService.getOperationsActivitiesPage(
        period: _selectedPeriod,
        customStart: _customDateRange?.start,
        customEnd: _customDateRange?.end,
        offset: _opsActivitiesDisplayed.length,
        limit: _detailPageSize,
      );
      if (mounted) setState(() {
        _opsActivitiesDisplayed = [..._opsActivitiesDisplayed, ...next];
        _opsLoadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _opsLoadingMore = false);
    }
  }

  @override
  void dispose() {
    _revenueTableScroll.removeListener(_onRevenueTableScroll);
    _expenseTableScroll.removeListener(_onExpenseTableScroll);
    _guestTableScroll.removeListener(_onGuestTableScroll);
    _opsTableScroll.removeListener(_onOpsTableScroll);
    _revenueTableScroll.dispose();
    _expenseTableScroll.dispose();
    _guestTableScroll.dispose();
    _opsTableScroll.dispose();
    _tabController.dispose();
    _startDateController.dispose();
    _endDateController.dispose();
    super.dispose();
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
      _invalidateAllTabCaches();
      _loadForTab(_tabController.index);
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
      backgroundColor: Colors.white,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(context),
          _buildTabBar(),
          Expanded(
            child: SingleChildScrollView(
              child: _buildCurrentTabContent(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentTabContent() {
    switch (_tabController.index) {
      case 0:
        return _buildFinancialTab();
      case 1:
        return _buildGuestTab();
      case 2:
        return _buildOperationsTab();
      default:
        return _buildFinancialTab();
    }
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
                onPressed: _isLoadingForTab(_tabController.index) ? null : () {
                  setState(() {
                    switch (_tabController.index) {
                      case 0:
                        _financialLoadError = null;
                        break;
                      case 1:
                        _guestLoadError = null;
                        break;
                      case 2:
                        _opsLoadError = null;
                        break;
                    }
                  });
                  _loadForTab(_tabController.index, force: true);
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

  Widget _buildErrorRetry({
    required String? message,
    required VoidCallback onRetry,
    required bool isLoading,
  }) {
    return _card(
      child: Column(
        children: [
          Icon(Icons.error_outline, size: 48, color: Colors.red[400]),
          const SizedBox(height: 12),
          Text(message ?? 'Something went wrong.', style: TextStyle(color: Colors.grey[800]), textAlign: TextAlign.center),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: isLoading ? null : onRetry,
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
            onSelected: (_) { setState(() => _selectedPeriod = TimePeriod.thisMonth); _invalidateAllTabCaches(); _loadForTab(_tabController.index); }),
          ChoiceChip(label: const Text('Last Month'), selected: _selectedPeriod == TimePeriod.lastMonth,
            onSelected: (_) { setState(() => _selectedPeriod = TimePeriod.lastMonth); _invalidateAllTabCaches(); _loadForTab(_tabController.index); }),
          ChoiceChip(label: const Text('Last 30 Days'), selected: _selectedPeriod == TimePeriod.last30Days,
            onSelected: (_) { setState(() => _selectedPeriod = TimePeriod.last30Days); _invalidateAllTabCaches(); _loadForTab(_tabController.index); }),
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
    return _card(
      child: Column(
      children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600]), textAlign: TextAlign.center),
          ],
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
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'P&L includes approved payroll only, plus purchases and maintenance. Use Finance → Payroll to see pending or rejected rows. Room revenue is from check-outs in the selected period.',
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
          ),
          const SizedBox(height: 24),
          if (_financialLoadError != null)
            _buildErrorRetry(
              message: _financialLoadError,
              onRetry: _loadFinancial,
              isLoading: _financialLoading,
            )
          else if (_financialLoading)
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
          return Column(
            children: cards
                .map((c) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: c,
                    ))
                .toList(),
          );
        }
        return Row(
          children: cards
              .map((c) => Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: c,
                    ),
                  ))
              .toList(),
        );
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
          Flexible(child: Text(title, style: TextStyle(fontSize: bold ? 17 : 15, fontWeight: bold ? FontWeight.bold : FontWeight.normal), overflow: TextOverflow.ellipsis)),
          Flexible(child: Text(_fmtNaira(amount), style: TextStyle(fontSize: bold ? 17 : 15, fontWeight: FontWeight.bold, color: color), overflow: TextOverflow.ellipsis, textAlign: TextAlign.end)),
        ],
      ),
    );
  }

  Widget _buildBreakdownSection(String title, List<CategoryAmount> items, Color color) {
    return _card(child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _sectionTitle(title),
        ...items.map((item) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(child: Text(item.category, overflow: TextOverflow.ellipsis)),
              Flexible(child: Text(_fmtNaira(item.amount), style: TextStyle(fontWeight: FontWeight.w600, color: color), overflow: TextOverflow.ellipsis, textAlign: TextAlign.end)),
            ],
          ),
        )),
      ],
    ));
  }

  Widget _buildFinancialDetailTables() {
    final revenueItems = _revenueItemsDisplayed;
    final expenseItems = _expenseItemsDisplayed;
    final totalRevenue = _plData!.totalRevenueCount;
    final totalExpense = _plData!.totalExpenseCount;

    if (revenueItems.isEmpty && expenseItems.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Revenue Transactions'),
          _card(
            child: SizedBox(
              height: _kDetailTableHeight,
              child: Center(
                child: Text(
                  'No revenue transactions for this period.',
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          _sectionTitle('Expense transactions'),
          _card(
            child: SizedBox(
              height: _kDetailTableHeight,
              child: Center(
                child: Text(
                  'No expense transactions for this period. Staff Payroll is in the breakdown; payroll rows are in the PDF export.',
                  style: TextStyle(color: Colors.grey[600]),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ],
      );
    }

    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
        _sectionTitle('Revenue Transactions'),
        if (revenueItems.isEmpty)
          _card(
            child: SizedBox(
              height: _kDetailTableHeight,
              child: Center(
                child: Text(
                  'No revenue transactions for this period.',
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ),
            ),
          )
        else
          _card(
            child: Column(
                mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                SizedBox(
                  height: _kDetailTableHeight,
                  width: double.infinity,
                  child: Scrollbar(
                    controller: _revenueTableScroll,
                    child: SingleChildScrollView(
                      controller: _revenueTableScroll,
                      child: Scrollbar(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(minWidth: 700),
                            child: DataTable(
                              columns: const [
                                DataColumn(label: Text('Date')),
                                DataColumn(label: Text('Source')),
                                DataColumn(label: Text('Description')),
                                DataColumn(label: Text('Status')),
                                DataColumn(label: Text('Amount (₦)')),
                              ],
                              rows: revenueItems.map((r) {
                                final source = r['source']?.toString() ?? '';
                                final description = r['description']?.toString() ?? '';
                                final status = r['status']?.toString() ?? '';
                                final rawDate = r['event_date']?.toString();
                                String dateStr = rawDate ?? '';
                                try {
                                  if (rawDate != null) {
                                    final dt = DateTime.parse(rawDate);
                                    dateStr = DateFormat('MMM dd, yyyy').format(dt);
                                  }
                                } catch (_) {}
                                final amount = (r['amount'] as num?)?.toInt() ?? 0;
                                return DataRow(
                                  cells: [
                                    DataCell(Text(dateStr)),
                                    DataCell(Text(source.isEmpty ? 'Revenue' : source)),
                                    DataCell(ConstrainedBox(constraints: const BoxConstraints(maxWidth: 280), child: Text(description.isEmpty ? '—' : description, overflow: TextOverflow.ellipsis))),
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
                  ),
                ),
                if (totalRevenue > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Showing ${revenueItems.length} of $totalRevenue', style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                        TextButton.icon(
                          onPressed: (_revenueLoadingMore || revenueItems.length >= totalRevenue) ? null : _loadMoreRevenue,
                          icon: _revenueLoadingMore ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : Icon(Icons.add_circle_outline, size: 18),
                          label: Text(_revenueLoadingMore ? 'Loading...' : 'Load more'),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 24),
        _sectionTitle('Expense transactions'),
        if (expenseItems.isEmpty)
          _card(
            child: SizedBox(
              height: _kDetailTableHeight,
              child: Center(
                child: Text(
                  'No expense transactions for this period. Staff Payroll is in the breakdown; payroll rows are in the PDF export.',
                  style: TextStyle(color: Colors.grey[600]),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          )
        else
          _card(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: _kDetailTableHeight,
                  width: double.infinity,
                  child: Scrollbar(
                    controller: _expenseTableScroll,
                    child: SingleChildScrollView(
                      controller: _expenseTableScroll,
                      child: Scrollbar(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(minWidth: 700),
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
                                    DataCell(ConstrainedBox(constraints: const BoxConstraints(maxWidth: 260), child: Text(desc, overflow: TextOverflow.ellipsis))),
                                    DataCell(Text(_fmtNaira(amount))),
                                  ],
                                );
                              }).toList(),
              ),
            ),
          ),
                      ),
                    ),
                  ),
                ),
                if (totalExpense > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Showing ${expenseItems.length} of $totalExpense', style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                        TextButton.icon(
                          onPressed: (_expenseLoadingMore || expenseItems.length >= totalExpense) ? null : _loadMoreExpense,
                          icon: _expenseLoadingMore ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : Icon(Icons.add_circle_outline, size: 18),
                          label: Text(_expenseLoadingMore ? 'Loading...' : 'Load more'),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  // ────────────────────── GUEST TAB ──────────────────────

  Widget _buildGuestTab() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'Guest metrics for the selected period.',
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
          ),
          const SizedBox(height: 24),
          if (_guestLoadError != null)
            _buildErrorRetry(
              message: _guestLoadError,
              onRetry: _loadGuest,
              isLoading: _guestLoading,
            )
          else if (_guestLoading)
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
        return Column(
          children: cards
              .map((c) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: c,
                  ))
              .toList(),
        );
      }
      return Row(
        children: cards
            .map((c) => Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: c,
                  ),
                ))
            .toList(),
      );
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
    final rows = _guestRowsDisplayed;
    final total = _guestStats?['total_rows_count'] as int? ?? 0;
    if (rows.isEmpty && total == 0) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Booking Details'),
          _card(
            child: SizedBox(
              height: _kDetailTableHeight,
              child: Center(
                child: Text(
                  'No guest bookings recorded for this period.',
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ),
                ),
              ),
            ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Booking Details'),
        _card(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: _kDetailTableHeight,
                width: double.infinity,
                child: Scrollbar(
                  controller: _guestTableScroll,
                  child: SingleChildScrollView(
                    controller: _guestTableScroll,
                    child: Scrollbar(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minWidth: 600),
                          child: DataTable(
                            columns: const [
                              DataColumn(label: Text('Guest')),
                              DataColumn(label: Text('Check-in')),
                              DataColumn(label: Text('Check-out')),
                              DataColumn(label: Text('Status')),
                              DataColumn(label: Text('Total (₦)')),
                            ],
                            rows: rows.map<DataRow>((b) {
                              final guestName = b['guest_name']?.toString()?.trim() ?? '—';
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
                              final paidAmount = (b['paid_amount'] as num?)?.toInt();
                              final amount = paidAmount ?? (totalAmount ?? 0);
                              return DataRow(
                                cells: [
                                  DataCell(Text(guestName)),
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
                ),
              ),
              if (total > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Showing ${rows.length} of $total', style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                      TextButton.icon(
                        onPressed: (_guestLoadingMore || rows.length >= total) ? null : _loadMoreGuestRows,
                        icon: _guestLoadingMore ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : Icon(Icons.add_circle_outline, size: 18),
                        label: Text(_guestLoadingMore ? 'Loading...' : 'Load more'),
          ),
        ],
      ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  // ────────────────────── OPERATIONS TAB ──────────────────────

  Widget _buildOperationsTab() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'Operations metrics for the selected period.',
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
          ),
          const SizedBox(height: 24),
          if (_opsLoadError != null)
            _buildErrorRetry(
              message: _opsLoadError,
              onRetry: _loadOperations,
              isLoading: _opsLoading,
            )
          else if (_opsLoading)
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
        return Column(
          children: cards
              .map((c) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: c,
                  ))
              .toList(),
        );
      }
      return Row(
        children: cards
            .map((c) => Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: c,
                  ),
                ))
            .toList(),
      );
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
    final activities = _opsActivitiesDisplayed;
    final total = _opsStats?['total_activities_count'] as int? ?? 0;
    if (activities.isEmpty && total == 0) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Staff Activity Details'),
          _card(
            child: SizedBox(
              height: _kDetailTableHeight,
              child: Center(
                child: Text(
                  'No staff activities recorded for this period.',
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ),
            ),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
            children: [
        _sectionTitle('Staff Activity Details'),
        _card(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: _kDetailTableHeight,
                width: double.infinity,
                child: Scrollbar(
                  controller: _opsTableScroll,
                  child: SingleChildScrollView(
                    controller: _opsTableScroll,
                    child: Scrollbar(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minWidth: 750),
                          child: DataTable(
                            dataRowMinHeight: 88,
                            dataRowMaxHeight: 88,
                            columns: const [
                              DataColumn(label: Text('Timestamp')),
                              DataColumn(label: Text('Department')),
                              DataColumn(label: Text('Action')),
                              DataColumn(label: Text('Staff')),
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
                              final staffProfile = a['staff_profile'];
                              String staffName = '—';
                              if (staffProfile is Map) {
                                staffName = staffProfile['full_name']?.toString()?.trim() ?? '—';
                              } else if (staffProfile is List && staffProfile.isNotEmpty && staffProfile.first is Map) {
                                staffName = (staffProfile.first as Map)['full_name']?.toString()?.trim() ?? '—';
                              }
                              return DataRow(
                                cells: [
                                  DataCell(Text(ts)),
                                  DataCell(Text(dept.isEmpty ? 'N/A' : dept)),
                                  DataCell(Text(action)),
                                  DataCell(Text(staffName)),
                                  DataCell(
                                    SizedBox(
                                      width: 320,
                                      height: 72,
                                      child: Scrollbar(
                                        child: SingleChildScrollView(
                                          child: Text(details, softWrap: true),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (total > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Showing ${activities.length} of $total', style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                      TextButton.icon(
                        onPressed: (_opsLoadingMore || activities.length >= total) ? null : _loadMoreOpsActivities,
                        icon: _opsLoadingMore ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : Icon(Icons.add_circle_outline, size: 18),
                        label: Text(_opsLoadingMore ? 'Loading...' : 'Load more'),
                      ),
                    ],
                  ),
          ),
        ],
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
    final revenueItems = _revenueItemsDisplayed;
    final expenseItems = _expenseItemsDisplayed;

    final revenueRows = revenueItems.map((r) {
      String dateStr = '';
      try {
        final raw = r['event_date']?.toString();
        if (raw != null) dateStr = DateFormat('MMM dd, yyyy').format(DateTime.parse(raw));
      } catch (_) {}
      final source = r['source']?.toString() ?? '';
      final description = r['description']?.toString() ?? '';
      final status = r['status']?.toString() ?? '';
      final amount = (r['amount'] as num?)?.toInt() ?? 0;
      return [dateStr, source, description, status, _fmtNaira(amount)];
    }).toList();

    final expenseRows = expenseItems.map((e) {
      String dateStr = '';
      try {
        final raw = e['transaction_date']?.toString();
        if (raw != null) dateStr = DateFormat('MMM dd, yyyy').format(DateTime.parse(raw));
      } catch (_) {}
      final desc = (e['description']?.toString() ?? '').replaceAll('\n', ' ').trim();
      final descShort = desc.length > 80 ? '${desc.substring(0, 80)}…' : desc;
      return [
        dateStr,
        e['category']?.toString() ?? '',
        e['department']?.toString() ?? 'General',
        descShort,
        _fmtNaira((e['amount'] as num?)?.toInt() ?? 0),
      ];
    }).toList();

    String shortPdfCell(String? s, {int max = 48}) {
      final t = (s ?? '').replaceAll('\n', ' ').trim();
      if (t.length <= max) return t;
      return '${t.substring(0, max)}…';
    }

    final payrollPdfRows = _plData!.payrollPdfRows.map((r) {
      final amt = (r['amount'] as num?)?.toInt() ?? 0;
      return [
        r['month']?.toString() ?? '',
        shortPdfCell(r['staff_name']?.toString(), max: 28),
        _fmtNaira(amt),
        r['approval_status']?.toString() ?? '',
        shortPdfCell(r['rejection_reason']?.toString(), max: 36),
      ];
    }).toList();

    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(40),
      build: (pw.Context ctx) => [
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
        _pdfTableSection(
          title: 'Revenue Transactions',
          headers: const ['Date', 'Source', 'Description', 'Status', 'Amount (₦)'],
          rows: revenueRows,
        ),
        _pdfTableSection(
          title: 'Expense transactions',
          headers: const ['Date', 'Category', 'Department', 'Description', 'Amount (₦)'],
          rows: expenseRows,
        ),
        if (payrollPdfRows.isEmpty)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 12),
            child: pw.Text(
              'Payroll: no rows in this period.',
              style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700),
            ),
          )
        else ...[
          _pdfTableSection(
            title: 'Payroll records (period, up to 60 rows)',
            headers: const ['Month', 'Staff', 'Amount (₦)', 'Approval', 'Rejection note'],
            rows: payrollPdfRows,
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 4, bottom: 4),
            child: pw.Text(
              'Totals above: P&L includes approved payroll only in Staff Payroll. This table lists every payroll row in the period (all statuses).',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
            ),
          ),
        ],
        pw.SizedBox(height: 20),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Generated on ${DateFormat('MMMM dd, yyyy – hh:mm a').format(DateTime.now())}',
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
          ),
        ),
      ],
    ));

    await Printing.layoutPdf(onLayout: (format) => pdf.save());
  }

  Future<void> _generateGuestPDF() async {
    if (_guestStats == null) return;
    final g = _guestStats!;
    final pdf = pw.Document();
    final period = _periodLabel();
    final rows = _guestRowsDisplayed;

    final bookingRows = rows.map<List<String>>((b) {
      final guestName = b['guest_name']?.toString()?.trim() ?? '—';
      String ciStr = '', coStr = '';
      try {
        final ci = b['check_in_date']?.toString();
        if (ci != null) ciStr = DateFormat('MMM dd, yyyy').format(DateTime.parse(ci));
      } catch (_) {}
      try {
        final co = b['check_out_date']?.toString();
        if (co != null) coStr = DateFormat('MMM dd, yyyy').format(DateTime.parse(co));
      } catch (_) {}
      final totalAmount = (b['total_amount'] as num?)?.toInt();
      final paidAmount = (b['paid_amount'] as num?)?.toInt();
      final amount = paidAmount ?? (totalAmount ?? 0);
      return [guestName, ciStr, coStr, b['status']?.toString() ?? '', _fmtNaira(amount)];
    }).toList();

    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(40),
      build: (pw.Context ctx) => [
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
        _pdfTableSection(
          title: 'Booking Details',
          headers: const ['Guest', 'Check-in', 'Check-out', 'Status', 'Total (₦)'],
          rows: bookingRows,
        ),
        pw.SizedBox(height: 20),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Generated on ${DateFormat('MMMM dd, yyyy – hh:mm a').format(DateTime.now())}',
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
          ),
        ),
      ],
    ));

    await Printing.layoutPdf(onLayout: (format) => pdf.save());
  }

  Future<void> _generateOperationsPDF() async {
    if (_opsStats == null) return;
    final o = _opsStats!;
    final negAdj = o['negative_adjustments'] ?? 0;
    final pdf = pw.Document();
    final period = _periodLabel();
    final activities = _opsActivitiesDisplayed;

    final activityRows = activities.map<List<String>>((a) {
      String ts = '';
      try {
        final raw = a['created_at']?.toString();
        if (raw != null) ts = DateFormat('MMM dd, yyyy – HH:mm').format(DateTime.parse(raw));
      } catch (_) {}
      final dept = a['department']?.toString() ?? '';
      final action = a['action']?.toString() ?? '';
      final details = (a['details']?.toString() ?? '').replaceAll('\n', ' ').trim();
      final detailsShort = details.length > 100 ? '${details.substring(0, 100)}…' : details;
      final staffProfile = a['staff_profile'];
      String staffName = '—';
      if (staffProfile is Map) {
        staffName = staffProfile['full_name']?.toString()?.trim() ?? '—';
      } else if (staffProfile is List && staffProfile.isNotEmpty && staffProfile.first is Map) {
        staffName = (staffProfile.first as Map)['full_name']?.toString()?.trim() ?? '—';
      }
      return [ts, dept.isEmpty ? 'N/A' : dept, action, staffName, detailsShort];
    }).toList();

    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(40),
      build: (pw.Context ctx) => [
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
        _pdfTableSection(
          title: 'Staff Activity Details',
          headers: const ['Timestamp', 'Department', 'Action', 'Staff', 'Details'],
          rows: activityRows,
        ),
        pw.SizedBox(height: 20),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Generated on ${DateFormat('MMMM dd, yyyy – hh:mm a').format(DateTime.now())}',
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
          ),
        ),
      ],
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

  static pw.Widget _pdfTableSection({
    required String title,
    required List<String> headers,
    required List<List<String>> rows,
  }) {
    if (rows.isEmpty) return pw.SizedBox(height: 8);
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(height: 12),
        pw.Text(title, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 6),
        pw.Table.fromTextArray(headers: headers, data: rows),
      ],
    );
  }
}
