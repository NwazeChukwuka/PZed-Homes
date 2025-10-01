import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pzed_homes/core/services/reporting_service.dart';

class ReportingScreen extends StatefulWidget {
  const ReportingScreen({super.key});

  @override
  State<ReportingScreen> createState() => _ReportingScreenState();
}

class _ReportingScreenState extends State<ReportingScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _reportingService = ReportingService();
  final NumberFormat currencyFormatter = NumberFormat.currency(locale: 'en_NG', symbol: '₦');

  PLData? _plData;
  TimePeriod _selectedPeriod = TimePeriod.thisMonth;
  DateTimeRange? _customDateRange;
  bool _isLoading = true;

  // Form controllers
  final _startDateController = TextEditingController();
  final _endDateController = TextEditingController();
  final _reportTypeController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _generateReport();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _startDateController.dispose();
    _endDateController.dispose();
    _reportTypeController.dispose();
    super.dispose();
  }

  Future<void> _generateReport() async {
    setState(() => _isLoading = true);
    final plData = await _reportingService.getProfitAndLoss(
      period: _selectedPeriod,
      customStart: _customDateRange?.start,
      customEnd: _customDateRange?.end,
    );
    if (mounted) {
      setState(() {
        _plData = plData;
        _isLoading = false;
      });
    }
  }

  Future<void> _selectCustomDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now,
      initialDateRange: _customDateRange ??
          DateTimeRange(
            start: DateTime(now.year, now.month, 1),
            end: now,
          ),
    );
    if (picked != null) {
      setState(() {
        _selectedPeriod = TimePeriod.custom;
        _customDateRange = picked;
        _startDateController.text = DateFormat('MMM dd, yyyy').format(picked.start);
        _endDateController.text = DateFormat('MMM dd, yyyy').format(picked.end);
      });
      _generateReport();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: Column(
        children: [
          _buildHeader(context),
          Container(
            color: Colors.white,
            child: TabBar(
              controller: _tabController,
              labelColor: Colors.green[800],
              unselectedLabelColor: Colors.grey[600],
              indicatorColor: Colors.green[800],
              tabs: const [
                Tab(text: 'Financial', icon: Icon(Icons.account_balance)),
                Tab(text: 'Guest', icon: Icon(Icons.people)),
                Tab(text: 'Operations', icon: Icon(Icons.engineering)),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildFinancialReportsTab(),
                _buildGuestReportsTab(),
                _buildOperationsReportsTab(),
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
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Reports & Analytics',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.green[800],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Generate comprehensive reports and analytics',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.green[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.green[200]!),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.analytics, color: Colors.green[700], size: 16),
                const SizedBox(width: 8),
                Text(
                  'Business Intelligence',
                  style: TextStyle(
                    color: Colors.green[700],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFinancialReportsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildReportGenerationForm(),
          const SizedBox(height: 24),
          if (_isLoading)
            const Center(child: CircularProgressIndicator())
          else if (_plData == null)
            const Center(child: Text('No data available'))
          else
            _buildFinancialReportResults(),
        ],
      ),
    );
  }

  Widget _buildGuestReportsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildGuestReportForm(),
          const SizedBox(height: 24),
          _buildGuestReportResults(),
        ],
      ),
    );
  }

  Widget _buildOperationsReportsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildOperationsReportForm(),
          const SizedBox(height: 24),
          _buildOperationsReportResults(),
        ],
      ),
    );
  }

  Widget _buildReportGenerationForm() {
    return Container(
      padding: const EdgeInsets.all(24),
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
            'Financial Report Generator',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: Colors.grey[800],
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _buildPeriodSelector(),
              ),
              const SizedBox(width: 16),
              ElevatedButton.icon(
                onPressed: _generateReport,
                icon: const Icon(Icons.refresh),
                label: const Text('Generate Report'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green[800],
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPeriodSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Select Period:', style: TextStyle(fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              label: const Text('This Month'),
              selected: _selectedPeriod == TimePeriod.thisMonth,
              onSelected: (_) {
                setState(() => _selectedPeriod = TimePeriod.thisMonth);
                _generateReport();
              },
            ),
            ChoiceChip(
              label: const Text('Last Month'),
              selected: _selectedPeriod == TimePeriod.lastMonth,
              onSelected: (_) {
                setState(() => _selectedPeriod = TimePeriod.lastMonth);
                _generateReport();
              },
            ),
            ChoiceChip(
              label: const Text('Custom'),
              selected: _selectedPeriod == TimePeriod.custom,
              onSelected: (_) => _selectCustomDateRange(),
            ),
          ],
        ),
        if (_selectedPeriod == TimePeriod.custom && _customDateRange != null) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _startDateController,
                  decoration: const InputDecoration(
                    labelText: 'Start Date',
                    border: OutlineInputBorder(),
                    suffixIcon: Icon(Icons.calendar_today),
                  ),
                  readOnly: true,
                  onTap: _selectCustomDateRange,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: TextField(
                  controller: _endDateController,
                  decoration: const InputDecoration(
                    labelText: 'End Date',
                    border: OutlineInputBorder(),
                    suffixIcon: Icon(Icons.calendar_today),
                  ),
                  readOnly: true,
                  onTap: _selectCustomDateRange,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildFinancialReportResults() {
    final revenue = _plData!.totalRevenue;
    final expenses = _plData!.totalExpenses;
    final netProfit = revenue - expenses;

    return Column(
      children: [
        _buildSummaryCard(revenue, expenses, netProfit),
        const SizedBox(height: 16),
        if (_plData!.revenueBreakdown.isNotEmpty)
          _buildBreakdownSection(
            'Revenue Breakdown',
            _plData!.revenueBreakdown,
            Colors.green,
          ),
        if (_plData!.expenseBreakdown.isNotEmpty) ...[
          const SizedBox(height: 16),
          _buildBreakdownSection(
            'Expense Breakdown',
            _plData!.expenseBreakdown,
            Colors.red,
          ),
        ],
      ],
    );
  }

  Widget _buildSummaryCard(int revenue, int expenses, int netProfit) {
    return Container(
      padding: const EdgeInsets.all(24),
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
        children: [
          Text(
            'Financial Summary',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: Colors.grey[800],
            ),
          ),
          const SizedBox(height: 20),
          _buildSummaryRow('Total Revenue', revenue, Colors.green),
          _buildSummaryRow('Total Expenses', expenses, Colors.red),
          const Divider(),
          _buildSummaryRow(
            'Net Profit/Loss',
            netProfit,
            netProfit >= 0 ? Colors.green : Colors.red,
            isTotal: true,
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String title, int amount, Color color, {bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: isTotal ? 18 : 16,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Text(
            currencyFormatter.format(amount / 100),
            style: TextStyle(
              fontSize: isTotal ? 18 : 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBreakdownSection(String title, List<CategoryAmount> items, Color color) {
    return Container(
      padding: const EdgeInsets.all(24),
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
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: Colors.grey[800],
            ),
          ),
          const SizedBox(height: 16),
          ...items.map(
            (item) => ListTile(
              title: Text(item.category),
              trailing: Text(
                currencyFormatter.format(item.amount / 100),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGuestReportForm() {
    return Container(
      padding: const EdgeInsets.all(24),
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
            'Guest Report Generator',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: Colors.grey[800],
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                    labelText: 'Report Type',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'guest_analytics', child: Text('Guest Analytics')),
                    DropdownMenuItem(value: 'booking_trends', child: Text('Booking Trends')),
                    DropdownMenuItem(value: 'guest_satisfaction', child: Text('Guest Satisfaction')),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _reportTypeController.text = value ?? '';
                    });
                  },
                ),
              ),
              const SizedBox(width: 16),
              ElevatedButton.icon(
                onPressed: () {
                  // Generate guest report
                },
                icon: const Icon(Icons.analytics),
                label: const Text('Generate Report'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green[800],
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGuestReportResults() {
    return Container(
      padding: const EdgeInsets.all(24),
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
            'Guest Analytics',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: Colors.grey[800],
            ),
          ),
          const SizedBox(height: 16),
          const Text('Guest report data will be displayed here...'),
        ],
      ),
    );
  }

  Widget _buildOperationsReportForm() {
    return Container(
      padding: const EdgeInsets.all(24),
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
            'Operations Report Generator',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: Colors.grey[800],
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                    labelText: 'Report Type',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'occupancy', child: Text('Occupancy Report')),
                    DropdownMenuItem(value: 'housekeeping', child: Text('Housekeeping Report')),
                    DropdownMenuItem(value: 'maintenance', child: Text('Maintenance Report')),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _reportTypeController.text = value ?? '';
                    });
                  },
                ),
              ),
              const SizedBox(width: 16),
              ElevatedButton.icon(
                onPressed: () {
                  // Generate operations report
                },
                icon: const Icon(Icons.engineering),
                label: const Text('Generate Report'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green[800],
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOperationsReportResults() {
    return Container(
      padding: const EdgeInsets.all(24),
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
            'Operations Analytics',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: Colors.grey[800],
            ),
          ),
          const SizedBox(height: 16),
          const Text('Operations report data will be displayed here...'),
        ],
      ),
    );
  }
}