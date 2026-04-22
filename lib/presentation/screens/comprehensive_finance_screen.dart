import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/services/data_service.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/payment_service.dart';
import '../../core/utils/input_sanitizer.dart';
import '../../core/error/error_handler.dart';
import '../../data/models/user.dart';
import '../../presentation/widgets/context_aware_role_button.dart';
import '../../presentation/widgets/finance_record_dialog.dart';
import '../../presentation/widgets/layered_scroll_body.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pzed_homes/core/utils/file_download_helper.dart';

/// Wraps a tab child to preserve state and isolate errors so one broken tab doesn't crash the whole screen.
class _KeepAliveTab extends StatefulWidget {
  final Widget child;

  const _KeepAliveTab({required this.child});

  @override
  State<_KeepAliveTab> createState() => _KeepAliveTabState();
}

class _KeepAliveTabState extends State<_KeepAliveTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

/// Builds tab content only when the tab is first selected (lazy loading).
class _LazyTab extends StatefulWidget {
  final int index;
  final TabController controller;
  final Widget Function() builder;

  const _LazyTab({
    super.key,
    required this.index,
    required this.controller,
    required this.builder,
  });

  @override
  State<_LazyTab> createState() => _LazyTabState();
}

class _LazyTabState extends State<_LazyTab> {
  bool _hasBuiltOnce = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_check);
  }

  @override
  void didUpdateWidget(covariant _LazyTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_check);
      widget.controller.addListener(_check);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_check);
    super.dispose();
  }

  void _check() {
    if (mounted && !_hasBuiltOnce && widget.controller.index == widget.index) {
      setState(() => _hasBuiltOnce = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasBuiltOnce && widget.controller.index != widget.index) {
      return const SizedBox.shrink();
    }
    // Important: do NOT cache the built widget instance.
    // The finance screen relies on parent state updates (e.g. date range changes),
    // so the tab content must be rebuilt to reflect the latest data.
    return _KeepAliveTab(child: widget.builder());
  }
}

class ComprehensiveFinanceScreen extends StatefulWidget {
  const ComprehensiveFinanceScreen({super.key});

  @override
  State<ComprehensiveFinanceScreen> createState() => _ComprehensiveFinanceScreenState();
}

class _ComprehensiveFinanceScreenState extends State<ComprehensiveFinanceScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  final DataService _dataService = DataService();

  // Data lists
  List<Map<String, dynamic>> _debts = [];
  List<Map<String, dynamic>> _incomeRecords = [];
  List<Map<String, dynamic>> _expenses = [];
  List<Map<String, dynamic>> _payrollRecords = [];
  List<Map<String, dynamic>> _cashDeposits = [];
  List<Map<String, dynamic>> _auditLogs = [];
  Map<String, dynamic> _financialSummary = {};
  List<Map<String, dynamic>> _departmentPerformance = [];
  bool _isLoadingData = false;
  /// True only after a successful load for the currently selected _summaryRange; keeps exports disabled until data matches range.
  bool _dataMatchesRange = false;
  /// Non-null when last _loadFinancialData failed; shows banner and disables exports.
  String? _loadError;
  /// Separate from _isLoadingData so export buttons show spinner while generating file.
  final ValueNotifier<bool> _isExporting = ValueNotifier<bool>(false);
  int _activeTabLoadToken = 0;
  DateTimeRange? _summaryRange;
  bool _showPendingExpenses = false;
  /// Payroll tab list filter: all | pending | approved | rejected (client-side on loaded rows).
  String _payrollListFilter = 'all';
  bool _dismissPayrollConfigWarning = false;
  bool _showOverdueDebtsOnly = false;
  String? _auditFilterTable;
  String? _auditFilterAction;

  // Controllers for debt recording
  final _debtAmountController = TextEditingController();
  final _debtorNameController = TextEditingController();
  final _debtorPhoneController = TextEditingController();
  final _debtDescriptionController = TextEditingController();
  final _debtDueDateController = TextEditingController();
  String _debtorType = 'customer'; // Default to 'customer'
  String _debtDepartment = 'all'; // Default department
  
  // Controllers for payment recording
  final _paymentAmountController = TextEditingController();
  final _paymentNotesController = TextEditingController();
  String _paymentMethod = 'cash';
  DateTime? _paymentDate;

  // Controllers for income recording
  final _incomeAmountController = TextEditingController();
  final _incomeDescriptionController = TextEditingController();
  final _incomeSourceController = TextEditingController();
  String _incomePaymentMethod = 'cash';

  // Controllers for expense recording
  final _expenseAmountController = TextEditingController();
  final _expenseDescriptionController = TextEditingController();
  final _expenseCategoryController = TextEditingController();

  // Controllers for payroll recording
  final _staffIdController = TextEditingController();
  final _payrollAmountController = TextEditingController();
  final _payrollMonthController = TextEditingController();
  final _salaryAmountController = TextEditingController();

  // Finance form state
  final List<Map<String, dynamic>> _staffProfiles = [];
  String? _selectedPayrollStaffId;
  String? _selectedSalaryStaffId;
  DateTime? _selectedPayrollMonth;
  String _payrollPaymentMethod = 'bank_transfer';
  String _expensePaymentMethod = 'cash';
  String _expenseDepartment = 'all';
  String _incomeDepartment = 'finance';
  DateTime? _selectedDebtDueDate;

  // Controllers for cash deposit recording
  final _depositAmountController = TextEditingController();
  final _bankChargesController = TextEditingController();
  final _bankNameController = TextEditingController();
  final _accountTypeController = TextEditingController();
  final _depositDescriptionController = TextEditingController();

  List<Map<String, dynamic>> _debtPaymentClaims = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 7, vsync: this);
    final now = DateTime.now();
    _summaryRange = DateTimeRange(
      start: DateTime(now.year, now.month, 1),
      end: DateTime(now.year, now.month + 1, 0),
    );
    _tabController.addListener(_onTabChanged);
    // Load only the visible tab (Overview) initially
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadDataForTab(0);
    });
  }

  void _onTabChanged() {
    if (!mounted || _tabController.indexIsChanging) return;
    _loadDataForTab(_tabController.index);
  }

  Future<void> _loadCurrentTabData() {
    return _loadDataForTab(_tabController.index);
  }

  String _formatKobo(num value) {
    return PaymentService.koboToNaira(value.toInt()).toStringAsFixed(2);
  }

  /// Non-blocking UI guard: warn if any payroll row already exists for this staff + month (any approval status).
  Future<void> _maybeShowDuplicatePayrollWarning() async {
    final staffId = _selectedPayrollStaffId;
    final month = _selectedPayrollMonth;
    if (staffId == null || staffId.isEmpty || month == null) return;
    try {
      final monthStart = DateTime(month.year, month.month, 1);
      final records = await _dataService.getPayrollRecords(
        startMonth: monthStart,
        endMonth: monthStart,
        limit: 50,
      );
      final hasExisting = records.any((r) => (r['staff_id']?.toString() ?? '') == staffId);
      if (hasExisting && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Note: A payroll row already exists for this staff and month (any status). '
              'Saving adds another row — use the Payroll tab to review or approve.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (_) {
      // Silently ignore; this is best-effort warning only.
    }
  }

  List<Map<String, dynamic>> _payrollListForFilter() {
    if (_payrollListFilter == 'all') return List<Map<String, dynamic>>.from(_payrollRecords);
    final want = _payrollListFilter.toLowerCase();
    return _payrollRecords
        .where((r) => (r['approval_status']?.toString().toLowerCase() ?? '') == want)
        .toList();
  }

  Color _payrollStatusChipColor(String? approvalStatus) {
    switch ((approvalStatus ?? '').toLowerCase()) {
      case 'approved':
        return Colors.green.shade100;
      case 'rejected':
        return Colors.red.shade100;
      default:
        return Colors.orange.shade100;
    }
  }

  Future<void> _showPayrollRecordDetail(Map<String, dynamic> payroll, {required bool canApprove}) async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final userId = authService.currentUser?.id;
    final approval = (payroll['approval_status']?.toString() ?? 'pending').toLowerCase();
    final isPending = approval == 'pending';

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(payroll['staff_name']?.toString() ?? 'Payroll'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Amount: ₦${_formatKobo(payroll['amount'] ?? 0)}'),
              const SizedBox(height: 8),
              Text('Month: ${payroll['month']?.toString() ?? '—'}'),
              const SizedBox(height: 8),
              Text('Approval: ${payroll['approval_status']?.toString() ?? '—'}'),
              if (approval == 'rejected' &&
                  (payroll['rejection_reason']?.toString().isNotEmpty ?? false)) ...[
                const SizedBox(height: 8),
                Text('Rejection reason: ${payroll['rejection_reason']}'),
              ],
              const SizedBox(height: 8),
              Text('Payment method: ${payroll['payment_method']?.toString() ?? '—'}'),
              if (payroll['notes'] != null && payroll['notes'].toString().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('Notes: ${payroll['notes']}'),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
          if (isPending && canApprove && userId != null) ...[
            TextButton(
              onPressed: () async {
                Navigator.pop(dialogContext);
                await _showRejectionReasonDialog(
                  onSubmit: (reason) async {
                    await _dataService.rejectPayroll(
                      payrollId: payroll['id']?.toString() ?? '',
                      rejectedBy: userId,
                      reason: reason,
                    );
                  },
                );
                _loadCurrentTabData();
              },
              child: const Text('Reject'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(dialogContext);
                await _dataService.approvePayroll(
                  payrollId: payroll['id']?.toString() ?? '',
                  approvedBy: userId,
                );
                _loadCurrentTabData();
              },
              child: const Text('Approve'),
            ),
          ],
        ],
      ),
    );
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _isExporting.dispose();
    _tabController.dispose();
    _debtAmountController.dispose();
    _debtorNameController.dispose();
    _debtorPhoneController.dispose();
    _debtDescriptionController.dispose();
    _debtDueDateController.dispose();
    _incomeAmountController.dispose();
    _incomeDescriptionController.dispose();
    _incomeSourceController.dispose();
    _expenseAmountController.dispose();
    _expenseDescriptionController.dispose();
    _expenseCategoryController.dispose();
    _staffIdController.dispose();
    _payrollAmountController.dispose();
    _payrollMonthController.dispose();
    _salaryAmountController.dispose();
    _depositAmountController.dispose();
    _bankChargesController.dispose();
    _bankNameController.dispose();
    _accountTypeController.dispose();
    _depositDescriptionController.dispose();
    _paymentAmountController.dispose();
    _paymentNotesController.dispose();
    super.dispose();
  }

  /// Loads only the data required for the given tab index (0=Overview, 1=Debt, 2=Income, 3=Expenses, 4=Payroll, 5=Cash Deposits, 6=Audit).
  Future<void> _loadDataForTab(int index) async {
    if (!mounted) return;
    final loadToken = ++_activeTabLoadToken;
    setState(() {
      _isLoadingData = true;
      _loadError = null;
      _dataMatchesRange = false;
    });
    try {
      switch (index) {
        case 0:
          await _loadOverviewData(loadToken);
          break;
        case 1:
          await _loadDebtData(loadToken);
          break;
        case 2:
          await _loadIncomeData(loadToken);
          break;
        case 3:
          await _loadExpensesData(loadToken);
          break;
        case 4:
          await _loadPayrollData(loadToken);
          break;
        case 5:
          await _loadCashDepositsData(loadToken);
          break;
        case 6:
          await _loadAuditData(loadToken);
          break;
        default:
          if (mounted && loadToken == _activeTabLoadToken) {
            setState(() => _isLoadingData = false);
          }
      }
    } catch (e, stackTrace) {
      if (kDebugMode) debugPrint('DEBUG _loadDataForTab($index): $e\n$stackTrace');
      if (mounted && loadToken == _activeTabLoadToken) {
        setState(() {
          _isLoadingData = false;
          _loadError = ErrorHandler.getFriendlyErrorMessage(e);
        });
        ErrorHandler.handleError(
          context,
          e,
          customMessage: 'Failed to load data. Please try again.',
          onRetry: () {
            setState(() => _loadError = null);
            _loadDataForTab(_tabController.index);
          },
          stackTrace: stackTrace,
        );
      }
    }
  }

  bool _isStaleLoad(int loadToken) => !mounted || loadToken != _activeTabLoadToken;

  Future<void> _loadOverviewData(int loadToken) async {
    final range = _effectiveSummaryRange;
    final results = await Future.wait([
      _dataService.getFinancialSummary(startDate: range.start, endDate: range.end),
      _dataService.getDepartmentPerformance(startDate: range.start, endDate: range.end),
      _dataService.getDepartmentSales(department: 'vip_bar', startDate: range.start, endDate: range.end),
      _dataService.getDepartmentSales(department: 'outside_bar', startDate: range.start, endDate: range.end),
      _dataService.getDepartmentSales(department: 'mini_mart', startDate: range.start, endDate: range.end),
      _dataService.getDepartmentSales(department: 'restaurant', startDate: range.start, endDate: range.end),
    ]);
    if (_isStaleLoad(loadToken)) return;
    setState(() {
      _financialSummary = results[0] as Map<String, dynamic>;
      _departmentPerformance = results[1] as List<Map<String, dynamic>>;
      _isLoadingData = false;
      _dataMatchesRange = true;
    });
  }

  Future<void> _loadDebtData(int loadToken) async {
    final range = _effectiveSummaryRange;
    final results = await Future.wait([
      _dataService.getDebts(startDate: range.start, endDate: range.end),
      _dataService.getDebtPaymentClaims(status: 'pending'),
    ]);
    if (_isStaleLoad(loadToken)) return;
    setState(() {
      _debts = results[0];
      _debtPaymentClaims = results[1];
      _isLoadingData = false;
      _dataMatchesRange = true;
    });
  }

  Future<void> _loadIncomeData(int loadToken) async {
    final range = _effectiveSummaryRange;
    final income = await _dataService.getIncomeRecords(startDate: range.start, endDate: range.end);
    if (_isStaleLoad(loadToken)) return;
    setState(() {
      _incomeRecords = income;
      _isLoadingData = false;
      _dataMatchesRange = true;
    });
  }

  Future<void> _loadExpensesData(int loadToken) async {
    final range = _effectiveSummaryRange;
    final expenses = await _dataService.getExpenses(
      startDate: range.start,
      endDate: range.end,
      status: _showPendingExpenses ? 'Pending' : null,
    );
    if (_isStaleLoad(loadToken)) return;
    setState(() {
      _expenses = expenses;
      _isLoadingData = false;
      _dataMatchesRange = true;
    });
  }

  Future<void> _loadPayrollData(int loadToken) async {
    final range = _effectiveSummaryRange;
    final results = await Future.wait([
      _dataService.getPayrollRecords(
        startMonth: range.start,
        endMonth: range.end,
        limit: 2000,
      ),
      _dataService.getStaffProfiles(),
    ]);
    if (_isStaleLoad(loadToken)) return;
    setState(() {
      _payrollRecords = results[0];
      _staffProfiles
        ..clear()
        ..addAll(results[1]);
      _isLoadingData = false;
      _dataMatchesRange = true;
    });
  }

  Future<void> _loadCashDepositsData(int loadToken) async {
    final range = _effectiveSummaryRange;
    final results = await Future.wait([
      _dataService.getCashDeposits(startDate: range.start, endDate: range.end),
      _dataService.getFinancialSummary(startDate: range.start, endDate: range.end),
    ]);
    if (_isStaleLoad(loadToken)) return;
    setState(() {
      _cashDeposits = results[0] as List<Map<String, dynamic>>;
      _financialSummary = results[1] as Map<String, dynamic>;
      _isLoadingData = false;
      _dataMatchesRange = true;
    });
  }

  Future<void> _loadAuditData(int loadToken) async {
    final range = _effectiveSummaryRange;
    final auditLogs = await _dataService.getAuditorTransactions(startDate: range.start, endDate: range.end);
    if (_isStaleLoad(loadToken)) return;
    setState(() {
      _auditLogs = auditLogs;
      _isLoadingData = false;
      _dataMatchesRange = true;
    });
  }

  /// Loads income, expenses, debts, payroll, deposits, audit for export (PDF/CSV). Does not set _isLoadingData.
  Future<void> _loadDataForExport() async {
    final range = _effectiveSummaryRange;
    final results = await Future.wait([
      _dataService.getIncomeRecords(startDate: range.start, endDate: range.end),
      _dataService.getExpenses(startDate: range.start, endDate: range.end),
      _dataService.getDebts(startDate: range.start, endDate: range.end),
      _dataService.getPayrollRecords(startMonth: range.start, endMonth: range.end, limit: 2000),
      _dataService.getCashDeposits(startDate: range.start, endDate: range.end),
      _dataService.getAuditorTransactions(startDate: range.start, endDate: range.end),
    ]);
    if (!mounted) return;
    setState(() {
      _incomeRecords = results[0];
      _expenses = results[1];
      _debts = results[2];
      _payrollRecords = results[3];
      _cashDeposits = results[4];
      _auditLogs = results[5];
      _dataMatchesRange = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context, listen: false);
    final user = authService.currentUser;
    final isAccountant = (user?.roles.any((role) => role.name == 'accountant') ?? false);
    final isAssumedAccountant = authService.hasAssumedRole(AppRole.accountant);
    final isOwnerOrManager = user?.roles.any((r) => r.name == 'owner' || r.name == 'manager') ?? false;
    final canApprove = isOwnerOrManager || isAccountant || isAssumedAccountant;

    // Owner, manager, and accountant can record (expenses, income, debts, etc.); no need to assume role
    final canRecord = isOwnerOrManager || isAccountant || isAssumedAccountant;
    // Set monthly gross (staff salary) restricted to Owner/Manager only (same as price edits).
    final canSetMonthlyGross = isOwnerOrManager;
    final roleKey = ValueKey('$canRecord-$canApprove-$canSetMonthlyGross');

    return LayeredScrollBody(
      topSection: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Green header (no AppBar - avoids duplicate hamburger from MainScreen drawer)
          Material(
            color: Colors.green[700],
            elevation: 4,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    if (Navigator.of(context).canPop())
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    const Expanded(
                      child: Text(
                        'Finance & Accounting',
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh, color: Colors.white),
                      onPressed: _isLoadingData ? null : _loadCurrentTabData,
                      tooltip: 'Refresh',
                    ),
                    if (MediaQuery.sizeOf(context).width >= 700)
                      const ContextAwareRoleButton(suggestedRole: AppRole.accountant),
                  ],
                ),
              ),
            ),
          ),
          // 2. TabBar in its own white container (matches Inventory/Mini Mart)
          Container(
            color: Colors.white,
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 2,
                  offset: const Offset(0, 1),
                ),
              ],
              border: Border(
                bottom: BorderSide(color: Colors.grey[300]!, width: 1),
              ),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 800;
                return TabBar(
                  controller: _tabController,
                  isScrollable: !isWide,
                  labelColor: Colors.green[800],
                  unselectedLabelColor: Colors.grey[700],
                  indicatorColor: Colors.green[800],
                  tabAlignment: isWide ? TabAlignment.fill : TabAlignment.start,
                  tabs: const [
                    Tab(text: 'Overview', icon: Icon(Icons.dashboard)),
                    Tab(text: 'Debt Management', icon: Icon(Icons.money_off)),
                    Tab(text: 'Income', icon: Icon(Icons.trending_up)),
                    Tab(text: 'Expenses', icon: Icon(Icons.trending_down)),
                    Tab(text: 'Payroll', icon: Icon(Icons.payment)),
                    Tab(text: 'Cash Deposits', icon: Icon(Icons.account_balance)),
                    Tab(text: 'Audit', icon: Icon(Icons.list_alt)),
                  ],
                );
              },
            ),
          ),
          // 3. Date range strip (visible on all tabs, below tab row)
          _buildSummaryRangeStrip(),
        ],
      ),
      content: TabBarView(
        controller: _tabController,
        children: [
          _LazyTab(index: 0, controller: _tabController, builder: _buildOverviewTab),
          _LazyTab(key: roleKey, index: 1, controller: _tabController, builder: () => _buildDebtManagementTab(canRecord, canApprove)),
          _LazyTab(key: roleKey, index: 2, controller: _tabController, builder: () => _buildIncomeTab(canRecord)),
          _LazyTab(key: roleKey, index: 3, controller: _tabController, builder: () => _buildExpensesTab(canRecord, canApprove)),
          _LazyTab(key: roleKey, index: 4, controller: _tabController, builder: () => _buildPayrollTab(canRecord, canApprove, canSetMonthlyGross)),
          _LazyTab(key: roleKey, index: 5, controller: _tabController, builder: () => _buildCashDepositsTab(canRecord)),
          _LazyTab(index: 6, controller: _tabController, builder: _buildAuditTab),
        ],
      ),
    );
  }

  Widget _buildOverviewTab() {
    return RefreshIndicator(
      onRefresh: () => _loadDataForTab(0),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_isLoadingData)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.green[700])),
                    const SizedBox(width: 12),
                    Text('Loading summary for selected range…', style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                  ],
                ),
              ),
            if (_isLoadingData) const SizedBox(height: 16),
            _buildFinancialSummaryCard(),
            const SizedBox(height: 16),
            if (_loadError != null) _buildDataLoadFailedBanner(),
            if (_loadError != null) const SizedBox(height: 12),
            _buildAuditorExportsCard(),
            const SizedBox(height: 20),
            _buildDepartmentPerformanceCard(),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryMetricRow(String label, String value, Color valueColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 13),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDataLoadFailedBanner() {
    return Material(
      color: Colors.red[50],
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red[700], size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Data load failed', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red[800])),
                  if (_loadError != null && _loadError!.isNotEmpty)
                    Text(_loadError!, style: TextStyle(fontSize: 12, color: Colors.red[700]), maxLines: 2, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            TextButton.icon(
              onPressed: () {
                setState(() => _loadError = null);
                _loadCurrentTabData();
              },
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAuditorExportsCard() {
    final canExport = _loadError == null && _dataMatchesRange;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.fact_check, color: Colors.green[700], size: 22),
                const SizedBox(width: 8),
                Text(
                  'Exports for Auditors',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              canExport
                  ? 'Generate CSV or PDF for the selected date range. Use for external audit or records.'
                  : (_loadError != null
                      ? 'Export is disabled until the data load succeeds. Use Retry above.'
                      : 'Select a date range and wait for data to load before exporting.'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 12),
            ValueListenableBuilder<bool>(
              valueListenable: _isExporting,
              builder: (_, isExporting, __) {
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: (!canExport || isExporting) ? null : _downloadFinanceCsv,
                      icon: isExporting
                          ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.green[700]))
                          : const Icon(Icons.download, size: 18),
                      label: Text(isExporting ? 'Exporting…' : 'Download CSV'),
                    ),
                    ElevatedButton.icon(
                      onPressed: (!canExport || isExporting) ? null : _exportAuditorPackPdf,
                      icon: isExporting
                          ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.description, size: 18),
                      label: Text(isExporting ? 'Exporting…' : 'Auditor Pack PDF'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: (!canExport || isExporting) ? Colors.grey : Colors.green[700],
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  DateTimeRange get _effectiveSummaryRange {
    final now = DateTime.now();
    if (_summaryRange != null) {
      final start = _summaryRange!.start;
      final end = _summaryRange!.end;
      return DateTimeRange(
        start: DateTime(start.year, start.month, start.day),
        end: DateTime(end.year, end.month, end.day, 23, 59, 59, 999),
      );
    }
    return DateTimeRange(
      start: DateTime(now.year, now.month, 1),
      end: DateTime(now.year, now.month + 1, 0, 23, 59, 59, 999),
    );
  }

  /// Compares only calendar date parts (ignores time-of-day).
  bool _isSameDate(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  /// Compact date range strip shown below the tab row on all tabs.
  /// One row on desktop (width >= 600), two rows on mobile.
  Widget _buildSummaryRangeStrip() {
    final now = DateTime.now();
    final defaultStart = DateTime(now.year, now.month, 1);
    final defaultEnd = DateTime(now.year, now.month + 1, 0);
    final lastMonth = now.month == 1 ? 12 : now.month - 1;
    final lastYear = now.month == 1 ? now.year - 1 : now.year;
    final lastMonthStart = DateTime(lastYear, lastMonth, 1);
    final lastMonthEnd = DateTime(lastYear, lastMonth + 1, 0);
    final last30Start = now.subtract(const Duration(days: 30));
    final range = _effectiveSummaryRange;
    final label =
        '${range.start.toIso8601String().split('T')[0]} → ${range.end.toIso8601String().split('T')[0]}';
    final isThisMonth = _isSameDate(range.start, defaultStart) && _isSameDate(range.end, defaultEnd);
    final isLastMonth = _isSameDate(range.start, lastMonthStart) && _isSameDate(range.end, lastMonthEnd);
    final last30End = now;
    final isLast30 = _isSameDate(range.start, last30Start) &&
        _isSameDate(range.end, last30End);
    final isCustom = !isThisMonth && !isLastMonth && !isLast30;

    final chips = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ChoiceChip(
          label: const Text('This Month'),
          selected: isThisMonth,
          onSelected: (_) {
            setState(() {
              _summaryRange = DateTimeRange(start: defaultStart, end: defaultEnd);
            });
            _loadCurrentTabData();
          },
        ),
        const SizedBox(width: 8),
        ChoiceChip(
          label: const Text('Last Month'),
          selected: isLastMonth,
          onSelected: (_) {
            setState(() {
              _summaryRange = DateTimeRange(start: lastMonthStart, end: lastMonthEnd);
            });
            _loadCurrentTabData();
          },
        ),
        const SizedBox(width: 8),
        ChoiceChip(
          label: const Text('Last 30 Days'),
          selected: isLast30,
          onSelected: (_) {
            setState(() {
              _summaryRange = DateTimeRange(start: last30Start, end: now);
            });
            _loadCurrentTabData();
          },
        ),
        const SizedBox(width: 8),
        ChoiceChip(
          label: const Text('Custom'),
          selected: isCustom,
          onSelected: (_) async {
            final picked = await showDateRangePicker(
              context: context,
              firstDate: DateTime(2020),
              lastDate: now,
              initialDateRange:
                  _summaryRange ?? DateTimeRange(start: defaultStart, end: defaultEnd),
            );
            if (picked != null) {
              setState(() {
                _summaryRange = picked;
              });
              _loadCurrentTabData();
            }
          },
        ),
      ],
    );

    final labelWidget = Text(
      label,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Colors.grey[700],
          ),
      overflow: TextOverflow.ellipsis,
      maxLines: 1,
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: Colors.grey[50],
      child: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isDesktop = constraints.maxWidth >= 600;
            if (isDesktop) {
              return Row(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: chips,
                    ),
                  ),
                  const SizedBox(width: 12),
                  labelWidget,
                ],
              );
            }
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: chips,
                ),
                const SizedBox(height: 6),
                labelWidget,
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildFinancialSummaryCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Financial Summary',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Summary from recorded income, expenses and cash.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildSummaryItem(
                    'Total Income',
                    '₦${_formatKobo(_financialSummary['total_income'] ?? 0)}',
                    Colors.green,
                    Icons.trending_up,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildSummaryItem(
                    'Total Expenses',
                    '₦${_formatKobo(_financialSummary['total_expenses'] ?? 0)}',
                    Colors.red,
                    Icons.trending_down,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildSummaryItem(
                    'Available Cash',
                    '₦${_formatKobo(_financialSummary['available_cash'] ?? 0)}',
                    Colors.blue,
                    Icons.account_balance_wallet,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildSummaryItem(
                    'Net Profit',
                    '₦${_formatKobo(_financialSummary['net_profit'] ?? 0)}',
                    Colors.orange,
                    Icons.attach_money,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryItem(String title, String value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(
            title,
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: color,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(String status) {
    final normalized = status.toLowerCase();
    Color color;
    switch (normalized) {
      case 'approved':
      case 'paid':
        color = Colors.green;
        break;
      case 'rejected':
      case 'cancelled':
        color = Colors.red;
        break;
      default:
        color = Colors.orange;
    }
    return Chip(
      label: Text(status),
      backgroundColor: color.withValues(alpha: 0.15),
      labelStyle: TextStyle(color: color),
      visualDensity: VisualDensity.compact,
    );
  }

  Future<void> _showExpenseApprovalDialog(Map<String, dynamic> expense) async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final userId = authService.currentUser?.id;
    if (userId == null) return;

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Expense Approval'),
        content: Text(
          'Approve expense of ₦${_formatKobo(expense['amount'] ?? 0)}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _showRejectionReasonDialog(
                onSubmit: (reason) async {
                  await _dataService.rejectExpense(
                    expenseId: expense['id'],
                    rejectedBy: userId,
                    reason: reason,
                  );
                },
              );
              _loadCurrentTabData();
            },
            child: const Text('Reject'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _dataService.approveExpense(
                expenseId: expense['id'],
                approvedBy: userId,
              );
              _loadCurrentTabData();
            },
            child: const Text('Approve'),
          ),
        ],
      ),
    );
  }

  Future<void> _showRejectionReasonDialog({
    required Future<void> Function(String? reason) onSubmit,
  }) async {
    final controller = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rejection Reason'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Reason (optional)',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await onSubmit(controller.text.trim().isEmpty ? null : controller.text.trim());
            },
            child: const Text('Submit'),
          ),
        ],
      ),
    );
    controller.dispose();
  }

  Widget _buildDepartmentPerformanceCard() {
    final range = _effectiveSummaryRange;
    final rangeLabel = '${range.start.toIso8601String().split('T')[0]} – ${range.end.toIso8601String().split('T')[0]}';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Department Performance',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              rangeLabel,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
            ),
            const SizedBox(height: 16),
            if (_isLoadingData)
              const Center(child: CircularProgressIndicator())
            else if (_departmentPerformance.isEmpty)
              const Center(child: Text('No department data available'))
            else
              Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: Text(
                            'Department',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.grey[700],
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            'Revenue',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.grey[700],
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            'Profit',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.grey[700],
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  ..._departmentPerformance.map((dept) => _buildDepartmentItem(dept)),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDepartmentItem(Map<String, dynamic> dept) {
    final performance = dept['performance']?.toString() ?? 'fair';
    Color performanceColor = performance == 'excellent' ? Colors.green : 
                           performance == 'good' ? Colors.blue : Colors.orange;
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              dept['department'],
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              '₦${_formatKobo(dept['revenue'] ?? 0)}',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            child: Text(
              '₦${_formatKobo(dept['profit'] ?? 0)}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: performanceColor,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDebtManagementTab(bool canRecord, bool canApprove) {
    final now = DateTime.now();
    final debts = _showOverdueDebtsOnly
        ? _debts.where((debt) {
            final dueRaw = debt['due_date'];
            if (dueRaw == null) return false;
            final dueDate = DateTime.tryParse(dueRaw.toString());
            if (dueDate == null) return false;
            final status = (debt['status'] ?? '').toString().toLowerCase();
            final isOpen = status == 'outstanding' || status == 'partially_paid';
            return isOpen && dueDate.isBefore(DateTime(now.year, now.month, now.day));
          }).toList()
        : _debts;
    final isMobile = MediaQuery.sizeOf(context).width < 600;

    return RefreshIndicator(
      onRefresh: _loadCurrentTabData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (canRecord)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: ElevatedButton.icon(
                onPressed: () => _showAddDebtDialog(),
                icon: const Icon(Icons.add),
                label: const Text('Record New Debt'),
              ),
            ),
          // Pending payment approvals section
          if (_debtPaymentClaims.isNotEmpty) ...[
            Text(
              'Pending Payment Approvals',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.orange[800],
              ),
            ),
            const SizedBox(height: 8),
            ..._debtPaymentClaims.map((claim) {
              final debt = claim['debts'] as Map<String, dynamic>? ?? {};
              final debtorName = debt['debtor_name'] ?? claim['debtor_name'] ?? 'Unknown';
              final recProfile = claim['recorded_by_profile'];
              final recordedBy = recProfile is Map ? (recProfile['full_name'] ?? 'Staff') : 'Staff';
              final amount = PaymentService.koboToNaira(int.tryParse(claim['amount']?.toString() ?? '') ?? 0);
              final method = (claim['payment_method'] ?? 'cash').toString();
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Text(debtorName),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('₦${NumberFormat('#,##0.00').format(amount)} • ${method.toUpperCase()}', style: TextStyle(color: Colors.green[700], fontWeight: FontWeight.w500)),
                      Text('Recorded by: $recordedBy', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                      if (debt['reason'] != null) Text('${debt['reason']}', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                    ],
                  ),
                  trailing: canApprove
                      ? isMobile
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.check_circle, color: Colors.green),
                                  tooltip: 'Approve',
                                  onPressed: () => _approveDebtClaim(claim['id']?.toString() ?? ''),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.cancel, color: Colors.red),
                                  tooltip: 'Reject',
                                  onPressed: () => _rejectDebtClaim(claim['id']?.toString() ?? ''),
                                ),
                              ],
                            )
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                TextButton.icon(
                                  icon: const Icon(Icons.check_circle, size: 18, color: Colors.green),
                                  label: const Text('Approve'),
                                  onPressed: () => _approveDebtClaim(claim['id']?.toString() ?? ''),
                                ),
                                const SizedBox(width: 8),
                                TextButton.icon(
                                  icon: const Icon(Icons.cancel, size: 18, color: Colors.red),
                                  label: const Text('Reject'),
                                  onPressed: () => _rejectDebtClaim(claim['id']?.toString() ?? ''),
                                ),
                              ],
                            )
                      : null,
                ),
              );
            }),
            const SizedBox(height: 24),
          ],
          // Debt list section
          Row(
            children: [
              Text(
                _showOverdueDebtsOnly ? 'Overdue Debts' : 'All Debts',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Text(
                _showOverdueDebtsOnly ? 'Overdue only' : 'All',
                style: TextStyle(color: Colors.grey[700], fontSize: 12),
              ),
              Switch(
                value: _showOverdueDebtsOnly,
                onChanged: (value) {
                  setState(() => _showOverdueDebtsOnly = value);
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...debts.map((debt) {
            final isPending = debt['status'] == 'outstanding' || debt['status'] == 'partially_paid';
            final dueRaw = debt['due_date'];
            final dueDate = dueRaw != null ? DateTime.tryParse(dueRaw.toString()) : null;
            final isOverdue = dueDate != null &&
                isPending &&
                dueDate.isBefore(DateTime(now.year, now.month, now.day));
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text(debt['debtor_name'] ?? 'Unknown'),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${debt['debtor_type'] ?? ''} owes ₦${PaymentService.koboToNaira((int.tryParse(debt['amount']?.toString() ?? '') ?? 0))}'),
                    if (debt['paid_amount'] != null && (int.tryParse(debt['paid_amount']?.toString() ?? '') ?? 0) > 0)
                      Text(
                        'Paid: ₦${PaymentService.koboToNaira(int.tryParse(debt['paid_amount']?.toString() ?? '') ?? 0)} | Remaining: ₦${PaymentService.koboToNaira((int.tryParse(debt['amount']?.toString() ?? '') ?? 0) - (int.tryParse(debt['paid_amount']?.toString() ?? '') ?? 0))}',
                        style: TextStyle(fontSize: 12, color: Colors.green[700], fontWeight: FontWeight.w500),
                      ),
                    Text('${debt['reason'] ?? ''}', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                    if (debt['debtor_phone'] != null)
                      Text('Phone: ${debt['debtor_phone']}', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                    if (debt['department'] != null)
                      Text('Department: ${debt['department']}', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                    if (dueDate != null)
                      Text(
                        'Due: ${dueDate.toIso8601String().split('T')[0]}${isOverdue ? ' (Overdue)' : ''}',
                        style: TextStyle(fontSize: 11, color: isOverdue ? Colors.red[700] : Colors.grey[500]),
                      ),
                    if (debt['sold_by'] != null && debt['sold_by_profile'] != null)
                      Text('Sold by: ${debt['sold_by_profile']?['full_name'] ?? 'Unknown'}', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                    if (debt['created_by'] != null && debt['created_by_profile'] != null)
                      Text('Created by: ${debt['created_by_profile']?['full_name'] ?? 'Unknown'}', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                    if (debt['approved_by'] != null)
                      Text('Approved by: ${debt['approved_by']}', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                  ],
                ),
                trailing: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Chip(
                      label: Text(debt['status'] ?? ''),
                      backgroundColor: isPending ? Colors.orange[100] : Colors.green[100],
                    ),
                    if (canRecord && debt['status'] != 'paid')
                      TextButton(
                        onPressed: () => _showRecordPaymentDialog(debt),
                        child: const Text('Record Payment', style: TextStyle(fontSize: 11)),
                      ),
                  ],
                ),
                onTap: null,
              ),
            );
          }),
          if (debts.isEmpty && _debtPaymentClaims.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: Text('No debts or pending approvals.')),
            ),
        ],
      ),
    );
  }

  Future<void> _approveDebtClaim(String claimId) async {
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final userId = authService.currentUser?.id;
      if (userId == null) return;
      await _dataService.approveDebtPaymentClaim(claimId, userId);
      if (mounted) {
        ErrorHandler.showSuccessMessage(context, 'Claim approved. Debt balance updated.');
        _loadCurrentTabData();
      }
    } catch (e, stackTrace) {
      if (kDebugMode) debugPrint('DEBUG _approveDebtClaim: $e\n$stackTrace');
      if (mounted) {
        ErrorHandler.handleError(context, e, customMessage: 'Failed to approve claim.', stackTrace: stackTrace);
      }
    }
  }

  Future<void> _rejectDebtClaim(String claimId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject Claim'),
        content: const Text('Are you sure you want to reject this debt payment claim?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Reject', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final userId = authService.currentUser?.id;
      if (userId == null) return;
      await _dataService.rejectDebtPaymentClaim(claimId, userId);
      if (mounted) {
        ErrorHandler.showInfoMessage(context, 'Claim rejected.');
        _loadCurrentTabData();
      }
    } catch (e, stackTrace) {
      if (kDebugMode) debugPrint('DEBUG _rejectDebtClaim: $e\n$stackTrace');
      if (mounted) {
        ErrorHandler.handleError(context, e, customMessage: 'Failed to reject claim.', stackTrace: stackTrace);
      }
    }
  }

  Widget _buildIncomeTab(bool canRecord) {
    return Column(
      children: [
        if (canRecord)
          Padding(
            padding: const EdgeInsets.all(16),
            child: ElevatedButton.icon(
              onPressed: () => _showAddIncomeDialog(),
              icon: const Icon(Icons.add),
              label: const Text('Record Income'),
            ),
          ),
        Expanded(
          child: ListView.builder(
            itemCount: _incomeRecords.length,
            itemBuilder: (context, index) {
              final income = _incomeRecords[index];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: ListTile(
                  title: Text(income['description'] ?? 'Unknown'),
                  subtitle: Text('₦${_formatKobo(income['amount'] ?? 0)} - ${income['department'] ?? ''}'),
                  trailing: Text(income['date'] ?? ''),
                  leading: const Icon(Icons.trending_up, color: Colors.green),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildExpensesTab(bool canRecord, bool canApprove) {
    return Column(
      children: [
        if (canRecord)
          Padding(
            padding: const EdgeInsets.all(16),
            child: ElevatedButton.icon(
              onPressed: () => _showAddExpenseDialog(),
              icon: const Icon(Icons.add),
              label: const Text('Record Expense'),
            ),
          ),
        if (canApprove)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _showPendingExpenses ? 'Showing pending only' : 'Showing all',
                    style: TextStyle(color: Colors.grey[700]),
                  ),
                ),
                Switch(
                  value: _showPendingExpenses,
                  onChanged: (value) {
                    setState(() => _showPendingExpenses = value);
                    _loadCurrentTabData();
                  },
                ),
              ],
            ),
          ),
        Expanded(
          child: ListView.builder(
            itemCount: _expenses.length,
            itemBuilder: (context, index) {
              final expense = _expenses[index];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: ListTile(
                  title: Text(expense['description'] ?? 'Unknown'),
                  subtitle: Text(
                    '₦${_formatKobo(expense['amount'] ?? 0)} - ${expense['payment_method'] ?? ''}',
                  ),
                  trailing: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(expense['transaction_date'] ?? expense['date'] ?? ''),
                      const SizedBox(height: 4),
                      _buildStatusChip(expense['status'] ?? 'Pending'),
                    ],
                  ),
                  leading: const Icon(Icons.trending_down, color: Colors.red),
                  onTap: canApprove &&
                          (expense['status']?.toString() ?? '').toLowerCase() == 'pending'
                      ? () => _showExpenseApprovalDialog(expense)
                      : null,
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPayrollTab(bool canRecord, bool canApprove, bool canSetMonthlyGross) {
    // Salary configuration health check: find active staff with no monthly gross and no payroll for current month.
    final now = DateTime.now();
    final currentMonthPrefix = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    final staffNeedingConfig = _staffProfiles.where((p) {
      final id = p['id']?.toString() ?? '';
      if (id.isEmpty) return false;
      final monthly = p['monthly_salary'];
      final monthlyKobo = monthly is int ? monthly : int.tryParse(monthly?.toString() ?? '') ?? 0;
      if (monthlyKobo > 0) return false;
      final hasPayrollThisMonth = _payrollRecords.any((r) {
        final staffId = r['staff_id']?.toString() ?? '';
        final month = r['month']?.toString() ?? '';
        return staffId == id && month.startsWith(currentMonthPrefix);
      });
      return !hasPayrollThisMonth;
    }).toList();

    return Column(
      children: [
        if (canRecord)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                if (canSetMonthlyGross &&
                    staffNeedingConfig.isNotEmpty &&
                    !_dismissPayrollConfigWarning)
                  Card(
                    color: Colors.orange[50],
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.warning_amber, color: Colors.orange[700], size: 18),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Configuration warning',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.orange[800],
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close, size: 18),
                                color: Colors.orange[800],
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                tooltip: 'Dismiss',
                                onPressed: () {
                                  setState(() => _dismissPayrollConfigWarning = true);
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'These active staff have no basic salary set and no payroll recorded for this month:',
                            style: TextStyle(fontSize: 12),
                          ),
                          const SizedBox(height: 4),
                          for (final p in staffNeedingConfig.take(5))
                            Text(
                              '• ${p['full_name'] ?? 'Unknown'}',
                              style: const TextStyle(fontSize: 12),
                            ),
                          if (staffNeedingConfig.length > 5)
                            Text(
                              '+ ${staffNeedingConfig.length - 5} more staff...',
                              style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                            ),
                        ],
                      ),
                    ),
                  ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (canSetMonthlyGross)
                      ElevatedButton.icon(
                        onPressed: () => _showSetMonthlyGrossDialog(),
                        icon: const Icon(Icons.attach_money),
                        label: const Text('Set basic salary'),
                      ),
                    if (canSetMonthlyGross) const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: () => _showAddPayrollDialog(),
                      icon: const Icon(Icons.add),
                      label: const Text('Record Payroll'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Filter by approval',
                style: TextStyle(fontSize: 12, color: Colors.grey[700]),
              ),
              const SizedBox(height: 6),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    FilterChip(
                      label: const Text('All'),
                      selected: _payrollListFilter == 'all',
                      onSelected: (_) => setState(() => _payrollListFilter = 'all'),
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      label: const Text('Pending'),
                      selected: _payrollListFilter == 'pending',
                      onSelected: (_) => setState(() => _payrollListFilter = 'pending'),
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      label: const Text('Approved'),
                      selected: _payrollListFilter == 'approved',
                      onSelected: (_) => setState(() => _payrollListFilter = 'approved'),
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      label: const Text('Rejected'),
                      selected: _payrollListFilter == 'rejected',
                      onSelected: (_) => setState(() => _payrollListFilter = 'rejected'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Builder(
            builder: (context) {
              final filtered = _payrollListForFilter();
              if (filtered.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _payrollRecords.isEmpty
                          ? 'No payroll rows in this date range.'
                          : 'No rows match this filter.',
                      style: TextStyle(color: Colors.grey[600]),
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }
              return ListView.builder(
                itemCount: filtered.length,
                itemBuilder: (context, index) {
                  final payroll = filtered[index];
                  final approvalLabel = payroll['approval_status']?.toString() ?? payroll['status']?.toString() ?? '';
                  return Card(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: ListTile(
                      title: Text(payroll['staff_name'] ?? 'Unknown'),
                      subtitle: Text(
                        '₦${_formatKobo(payroll['amount'] ?? 0)} · ${payroll['month'] ?? ''} · tap for details',
                        style: const TextStyle(fontSize: 12),
                      ),
                      trailing: Chip(
                        label: Text(approvalLabel),
                        backgroundColor: _payrollStatusChipColor(payroll['approval_status']?.toString()),
                      ),
                      leading: const Icon(Icons.payment, color: Colors.blue),
                      onTap: () => _showPayrollRecordDetail(payroll, canApprove: canApprove),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCashDepositsTab(bool canRecord) {
    final cashSalesInflow = (_financialSummary['cash_sales_inflow'] as num?)?.toInt() ?? 0;
    final cashOtherIncome = (_financialSummary['cash_other_income'] as num?)?.toInt() ?? 0;
    final cashTotalInflow = (_financialSummary['cash_total_inflow'] as num?)?.toInt() ?? 0;
    final cashExpenses = (_financialSummary['cash_expenses'] as num?)?.toInt() ?? 0;
    final cashDeposits = (_financialSummary['cash_deposits'] as num?)?.toInt() ?? 0;
    final availableCash = (_financialSummary['available_cash'] as num?)?.toInt() ?? 0;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Cash Reconciliation (Selected Range)',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 8),
                  _buildSummaryMetricRow('Cash Sales Inflow', '₦${_formatKobo(cashSalesInflow)}', Colors.green),
                  _buildSummaryMetricRow('Other Cash Income', '₦${_formatKobo(cashOtherIncome)}', Colors.green),
                  _buildSummaryMetricRow('Total Cash Inflow', '₦${_formatKobo(cashTotalInflow)}', Colors.green),
                  _buildSummaryMetricRow('Cash Expenses', '₦${_formatKobo(cashExpenses)}', Colors.red),
                  _buildSummaryMetricRow('Cash Deposits', '₦${_formatKobo(cashDeposits)}', Colors.purple),
                  const Divider(),
                  _buildSummaryMetricRow(
                    'Expected Available Cash',
                    '₦${_formatKobo(availableCash)}',
                    availableCash >= 0 ? Colors.blue : Colors.red,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (canRecord)
          Padding(
            padding: const EdgeInsets.all(16),
            child: ElevatedButton.icon(
              onPressed: () => _showAddCashDepositDialog(),
              icon: const Icon(Icons.add),
              label: const Text('Record Cash Deposit'),
            ),
          ),
        Expanded(
          child: ListView.builder(
            itemCount: _cashDeposits.length,
            itemBuilder: (context, index) {
              final deposit = _cashDeposits[index];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: ListTile(
                  title: Text('${deposit['bank_name']} - ${deposit['account_type']}'),
                  subtitle: Text('₦${_formatKobo(deposit['amount'] ?? 0)} (Net: ₦${_formatKobo(deposit['net_amount'] ?? 0)})'),
                  trailing: Text(deposit['date'] ?? ''),
                  leading: const Icon(Icons.account_balance, color: Colors.purple),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  List<Map<String, dynamic>> _getFilteredAuditLogs() {
    var list = _auditLogs;
    if ((_auditFilterTable != null && _auditFilterTable != 'All') && _auditFilterTable!.isNotEmpty) {
      list = list.where((e) => (e['table_name'] as String? ?? '') == _auditFilterTable).toList();
    }
    if ((_auditFilterAction != null && _auditFilterAction != 'All') && _auditFilterAction!.isNotEmpty) {
      list = list.where((e) => (e['action'] as String? ?? '') == _auditFilterAction).toList();
    }
    return list;
  }

  Future<void> _downloadAuditCsv() async {
    try {
      final filtered = _getFilteredAuditLogs();
      final buffer = StringBuffer();
      final r = _effectiveSummaryRange;
      final rangeLabel = '${r.start.toIso8601String().split('T')[0]}_to_${r.end.toIso8601String().split('T')[0]}';
      buffer.writeln('Audit Log,PZed Homes Finance');
      buffer.writeln('Period,$rangeLabel');
      buffer.writeln('Generated,${DateTime.now().toIso8601String()}');
      buffer.writeln('');
      buffer.writeln('created_at,audit_stream,action,table_name,description,quantity,unit_price_kobo,line_total_kobo,actor');
      for (final log in filtered) {
        final actor = (log['actor'] as Map?)?['full_name'] ?? log['actor_name'] ?? 'Unknown';
        buffer.writeln(
          '${log['created_at']?.toString() ?? ''},'
          '${_escapeCsv(log['audit_stream']?.toString() ?? '')},'
          '${_escapeCsv(log['action']?.toString() ?? '')},'
          '${_escapeCsv(log['table_name']?.toString() ?? '')},'
          '${_escapeCsv(log['description']?.toString() ?? '')},'
          '${log['quantity']?.toString() ?? ''},'
          '${log['unit_price']?.toString() ?? ''},'
          '${log['line_total']?.toString() ?? ''},'
          '${_escapeCsv(actor.toString())}',
        );
      }
      final filename = 'PZed_Homes_Audit_Log_$rangeLabel.csv';
      await triggerCsvDownload(buffer.toString(), filename);
      if (mounted) {
        ErrorHandler.showSuccessMessage(
          context,
          kIsWeb ? 'Audit log downloaded' : 'Audit log copied to clipboard.',
        );
      }
    } catch (e, stackTrace) {
      if (kDebugMode) debugPrint('DEBUG export audit CSV: $e\n$stackTrace');
      if (mounted) {
        ErrorHandler.handleError(
          context,
          e,
          customMessage: 'Failed to export audit log.',
          stackTrace: stackTrace,
        );
      }
    }
  }

  Widget _buildAuditTab() {
    if (_isLoadingData) {
      return const Center(child: CircularProgressIndicator());
    }
    final filtered = _getFilteredAuditLogs();
    final tables = _auditLogs.map((e) => e['table_name']?.toString() ?? '').where((s) => s.isNotEmpty).toSet().toList()..sort();
    final actions = _auditLogs.map((e) => e['action']?.toString() ?? '').where((s) => s.isNotEmpty).toSet().toList()..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Filter & Export',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: (_auditFilterTable != null && tables.contains(_auditFilterTable)) ? _auditFilterTable! : 'All',
                          decoration: const InputDecoration(
                            labelText: 'Table',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: [
                            const DropdownMenuItem(value: 'All', child: Text('All tables')),
                            ...tables.map((t) => DropdownMenuItem(value: t, child: Text(t))),
                          ],
                          onChanged: (v) => setState(() => _auditFilterTable = (v == null || v == 'All') ? null : v),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: (_auditFilterAction != null && actions.contains(_auditFilterAction)) ? _auditFilterAction! : 'All',
                          decoration: const InputDecoration(
                            labelText: 'Action',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: [
                            const DropdownMenuItem(value: 'All', child: Text('All actions')),
                            ...actions.map((a) => DropdownMenuItem(value: a, child: Text(a))),
                          ],
                          onChanged: (v) => setState(() => _auditFilterAction = (v == null || v == 'All') ? null : v),
                        ),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton.icon(
                        onPressed: _auditLogs.isEmpty ? null : _downloadAuditCsv,
                        icon: const Icon(Icons.download, size: 18),
                        label: const Text('Export CSV'),
                      ),
                    ],
                  ),
                  if (filtered.length != _auditLogs.length)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Showing ${filtered.length} of ${_auditLogs.length} entries',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        if (filtered.isEmpty)
          Expanded(
            child: Center(
              child: Text(
                _auditLogs.isEmpty
                    ? 'No audit/sales activity in the selected period.'
                    : 'No audit/sales activity matches the selected filters.',
              ),
            ),
          )
        else
          Expanded(
            child: ListView.builder(
              itemCount: filtered.length,
              itemBuilder: (context, index) {
                final log = filtered[index];
                final actor = (log['actor'] as Map?)?['full_name'] ?? log['actor_name'] ?? 'Unknown';
                final createdAt = log['created_at']?.toString() ?? '';
                final qty = log['quantity']?.toString() ?? '';
                final unit = (log['unit_price'] as num?)?.toInt();
                final line = (log['line_total'] as num?)?.toInt();
                final stream = log['audit_stream']?.toString() ?? '';
                final description = log['description']?.toString() ?? '';
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: ListTile(
                    leading: const Icon(Icons.security),
                    title: Text('${log['action']} on ${log['table_name']}'),
                    subtitle: Text(
                      '$stream\n'
                      '${description.isEmpty ? 'No details' : description}\n'
                      'Qty: ${qty.isEmpty ? '-' : qty} | Unit: ${unit == null ? '-' : '₦${_formatKobo(unit)}'} | Total: ${line == null ? '-' : '₦${_formatKobo(line)}'}\n'
                      'By $actor',
                    ),
                    isThreeLine: true,
                    trailing: Text(createdAt.length > 19 ? createdAt.substring(0, 19) : createdAt),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  // Dialog methods
  void _showAddDebtDialog() {
    _debtorType = 'customer';
    _debtDepartment = 'all';
    showDialog(
      context: context,
      builder: (context) => FinanceRecordDialog(
        title: 'Record New Debt',
        formFields: [
          TextField(
            controller: _debtorNameController,
            decoration: const InputDecoration(
              labelText: 'Debtor Name *',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _debtorPhoneController,
            decoration: const InputDecoration(
              labelText: 'Debtor Phone *',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _debtorType,
            decoration: const InputDecoration(
              labelText: 'Debtor Type *',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'customer', child: Text('Customer')),
              DropdownMenuItem(value: 'supplier', child: Text('Supplier')),
              DropdownMenuItem(value: 'staff', child: Text('Staff')),
              DropdownMenuItem(value: 'other', child: Text('Other')),
            ],
            onChanged: (value) {
              setState(() {
                _debtorType = value ?? 'customer';
              });
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _debtAmountController,
            decoration: const InputDecoration(
              labelText: 'Amount (₦) *',
              border: OutlineInputBorder(),
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _debtDescriptionController,
            decoration: const InputDecoration(
              labelText: 'Reason/Description *',
              border: OutlineInputBorder(),
            ),
            maxLines: 2,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _debtDueDateController,
            decoration: const InputDecoration(
              labelText: 'Due Date',
              border: OutlineInputBorder(),
              hintText: 'Optional',
              suffixIcon: Icon(Icons.calendar_today),
            ),
            readOnly: true,
            onTap: () async {
              final now = DateTime.now();
              final picked = await showDatePicker(
                context: context,
                firstDate: now.subtract(const Duration(days: 1)),
                lastDate: now.add(const Duration(days: 365)),
                initialDate: _selectedDebtDueDate ?? now.add(const Duration(days: 30)),
              );
              if (picked != null) {
                setState(() {
                  _selectedDebtDueDate = picked;
                  _debtDueDateController.text = picked.toIso8601String().split('T')[0];
                });
              }
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _debtDepartment,
            decoration: const InputDecoration(
              labelText: 'Department',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'all', child: Text('All Departments')),
              DropdownMenuItem(value: 'reception', child: Text('Reception')),
              DropdownMenuItem(value: 'vip_bar', child: Text('VIP Bar')),
              DropdownMenuItem(value: 'outside_bar', child: Text('Outside Bar')),
              DropdownMenuItem(value: 'restaurant', child: Text('Restaurant')),
              DropdownMenuItem(value: 'mini_mart', child: Text('Mini Mart')),
            ],
            onChanged: (value) {
              setState(() {
                _debtDepartment = value ?? 'all';
              });
            },
          ),
        ],
        onSave: _recordDebt,
        onSuccess: _clearDebtForm,
      ),
    );
  }

  Future<bool> _recordDebt() async {
    if (_debtorNameController.text.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enter debtor name.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return false;
    }
    if (_debtorPhoneController.text.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enter debtor phone.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return false;
    }
    if (_debtAmountController.text.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enter amount.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return false;
    }
    if (_debtDescriptionController.text.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enter reason/description.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return false;
    }
    final authService = Provider.of<AuthService>(context, listen: false);
    final userId = authService.currentUser?.id;
    if (userId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You must be logged in to record debts.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return false;
    }
    final amountInNaira = double.tryParse(_debtAmountController.text.trim());
    if (amountInNaira == null || amountInNaira <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enter a valid amount greater than zero.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return false;
    }
    final amountInKobo = PaymentService.nairaToKobo(amountInNaira);
    final dueDate = _selectedDebtDueDate ?? DateTime.now().add(const Duration(days: 30));
    final debt = {
      'debtor_name': InputSanitizer.sanitizeText(_debtorNameController.text.trim()),
      'debtor_phone': InputSanitizer.sanitizePhone(_debtorPhoneController.text.trim()),
      'debtor_type': _debtorType,
      'amount': amountInKobo,
      'owed_to': 'P-ZED Luxury Hotels & Suites',
      'department': _debtDepartment,
      'source_department': _debtDepartment,
      'reason': InputSanitizer.sanitizeDescription(_debtDescriptionController.text.trim()),
      'date': DateTime.now().toIso8601String().split('T')[0],
      'due_date': dueDate.toIso8601String().split('T')[0],
      'status': 'outstanding',
      'notes': null,
      'created_by': userId,
      'sold_by': userId,
    };
    await _dataService.recordDebt(debt);
    if (mounted) {
      ErrorHandler.showSuccessMessage(context, 'Debt recorded successfully!');
      try {
        await _loadCurrentTabData();
      } catch (_) {
        if (mounted) {
          ErrorHandler.showSuccessMessage(
            context,
            'Debt recorded! (Failed to refresh list, please refresh manually.)',
          );
        }
      }
    }
    return true;
  }

  void _showAddIncomeDialog() {
    showDialog(
      context: context,
      builder: (context) => FinanceRecordDialog(
        title: 'Record Income',
        formFields: [
          TextField(
            controller: _incomeDescriptionController,
            decoration: const InputDecoration(labelText: 'Description'),
          ),
          TextField(
            controller: _incomeAmountController,
            decoration: const InputDecoration(labelText: 'Amount'),
            keyboardType: TextInputType.number,
          ),
          TextField(
            controller: _incomeSourceController,
            decoration: const InputDecoration(labelText: 'Source'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _incomeDepartment,
            decoration: const InputDecoration(labelText: 'Department'),
            items: const [
              DropdownMenuItem(value: 'other', child: Text('Other (Miscellaneous)')),
              DropdownMenuItem(value: 'finance', child: Text('Finance')),
              DropdownMenuItem(value: 'reception', child: Text('Reception')),
              DropdownMenuItem(value: 'vip_bar', child: Text('VIP Bar')),
              DropdownMenuItem(value: 'outside_bar', child: Text('Outside Bar')),
              DropdownMenuItem(value: 'kitchen', child: Text('Kitchen')),
              DropdownMenuItem(value: 'mini_mart', child: Text('Mini Mart')),
            ],
            onChanged: (value) {
              setState(() {
                _incomeDepartment = value ?? 'finance';
              });
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _incomePaymentMethod,
            decoration: const InputDecoration(labelText: 'Payment Method'),
            items: const [
              DropdownMenuItem(value: 'cash', child: Text('Cash')),
              DropdownMenuItem(value: 'bank_transfer', child: Text('Bank Transfer')),
              DropdownMenuItem(value: 'card', child: Text('Card')),
            ],
            onChanged: (value) {
              setState(() {
                _incomePaymentMethod = value ?? 'cash';
              });
            },
          ),
        ],
        onSave: _saveIncomeRecord,
        onSuccess: _clearIncomeForm,
      ),
    );
  }

  void _showAddExpenseDialog() {
    showDialog(
      context: context,
      builder: (context) => FinanceRecordDialog(
        title: 'Record Expense',
        formFields: [
          TextField(
            controller: _expenseDescriptionController,
            decoration: const InputDecoration(labelText: 'Description'),
          ),
          TextField(
            controller: _expenseAmountController,
            decoration: const InputDecoration(labelText: 'Amount'),
            keyboardType: TextInputType.number,
          ),
          TextField(
            controller: _expenseCategoryController,
            decoration: const InputDecoration(labelText: 'Category'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _expenseDepartment,
            decoration: const InputDecoration(labelText: 'Department'),
            items: const [
              DropdownMenuItem(value: 'all', child: Text('All Departments')),
              DropdownMenuItem(value: 'reception', child: Text('Reception')),
              DropdownMenuItem(value: 'vip_bar', child: Text('VIP Bar')),
              DropdownMenuItem(value: 'outside_bar', child: Text('Outside Bar')),
              DropdownMenuItem(value: 'kitchen', child: Text('Kitchen')),
              DropdownMenuItem(value: 'mini_mart', child: Text('Mini Mart')),
            ],
            onChanged: (value) {
              setState(() {
                _expenseDepartment = value ?? 'all';
              });
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _expensePaymentMethod,
            decoration: const InputDecoration(labelText: 'Payment Method'),
            items: const [
              DropdownMenuItem(value: 'cash', child: Text('Cash')),
              DropdownMenuItem(value: 'bank_transfer', child: Text('Bank Transfer')),
              DropdownMenuItem(value: 'card', child: Text('Card')),
            ],
            onChanged: (value) {
              setState(() {
                _expensePaymentMethod = value ?? 'cash';
              });
            },
          ),
        ],
        onSave: _saveExpense,
        onSuccess: _clearExpenseForm,
      ),
    );
  }

  void _showSetMonthlyGrossDialog() {
    _selectedSalaryStaffId = null;
    _salaryAmountController.clear();
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Set basic salary'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Set the expected monthly basic salary for a staff. This pre-fills “Record payroll” and helps spot missing configuration. '
                    'Dashboard totals and P&L use only approved payroll rows, not this figure.',
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedSalaryStaffId ?? '',
                    decoration: const InputDecoration(labelText: 'Staff'),
                    items: [
                      const DropdownMenuItem(value: '', child: Text('Select staff')),
                      ..._staffProfiles.map((profile) {
                        final id = profile['id']?.toString() ?? '';
                        final name = profile['full_name']?.toString() ?? 'Unknown';
                        final kobo = (profile['monthly_salary'] is int) ? (profile['monthly_salary'] as int) : (int.tryParse(profile['monthly_salary']?.toString() ?? '') ?? 0);
                        return DropdownMenuItem(
                          value: id,
                          child: Text(kobo > 0 ? '$name (₦${PaymentService.koboToNaira(kobo).toStringAsFixed(0)})' : name),
                        );
                      }),
                    ],
                    onChanged: (value) {
                      setDialogState(() {
                        _selectedSalaryStaffId = (value == null || value.isEmpty) ? null : value;
                        if (_selectedSalaryStaffId != null) {
                          final list = _staffProfiles.where((p) => (p['id']?.toString()) == _selectedSalaryStaffId).toList();
                          final profile = list.isEmpty ? null : list.first;
                          if (profile != null) {
                            final kobo = (profile['monthly_salary'] is int) ? (profile['monthly_salary'] as int) : (int.tryParse(profile['monthly_salary']?.toString() ?? '') ?? 0);
                            _salaryAmountController.text = kobo > 0 ? PaymentService.koboToNaira(kobo).toStringAsFixed(2) : '';
                          }
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _salaryAmountController,
                    decoration: const InputDecoration(labelText: 'Basic salary (₦)'),
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setDialogState(() {}),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
              FilledButton(
                onPressed: () async {
                  final staffId = _selectedSalaryStaffId;
                  if (staffId == null || staffId.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select a staff')));
                    return;
                  }
                  final naira = double.tryParse(_salaryAmountController.text.trim());
                  if (naira == null || naira < 0) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid amount')));
                    return;
                  }
                  try {
                    final amountKobo = PaymentService.nairaToKobo(naira);
                    await _dataService.updateStaffMonthlySalary(staffId, amountKobo);

                    if (context.mounted) {
                      final auth = Provider.of<AuthService>(context, listen: false);
                      final actor = auth.currentUser;
                      final staffProfile = _staffProfiles.firstWhere(
                        (p) => (p['id']?.toString() ?? '') == staffId,
                        orElse: () => <String, dynamic>{},
                      );
                      final staffName = staffProfile['full_name']?.toString() ?? 'Unknown';
                      final actorName = actor?.name ?? 'Unknown';
                      final details =
                          '$actorName updated $staffName\'s basic salary to ₦${amountKobo > 0 ? PaymentService.koboToNaira(amountKobo).toStringAsFixed(2) : '0'}';
                      await _dataService.logActivity(
                        actor?.id,
                        'Salary Update',
                        'HR/Payroll',
                        details,
                      );

                      if (!context.mounted) return;
                      Navigator.of(context).pop();
                      ErrorHandler.showSuccessMessage(context, 'Basic salary saved.');
                      _loadCurrentTabData();
                    }
                  } catch (e) {
                    if (context.mounted) ErrorHandler.handleError(context, e);
                  }
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showAddPayrollDialog() {
    showDialog(
      context: context,
      builder: (context) => FinanceRecordDialog(
        title: 'Record Payroll',
        formFields: [
          TextField(
            controller: _staffIdController,
            decoration: const InputDecoration(labelText: 'Staff ID (legacy)'),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _selectedPayrollStaffId ?? '',
            decoration: const InputDecoration(labelText: 'Staff'),
            items: [
              const DropdownMenuItem(value: '', child: Text('Select staff')),
              ..._staffProfiles.map((profile) {
                final id = profile['id']?.toString() ?? '';
                final name = profile['full_name']?.toString() ?? 'Unknown';
                return DropdownMenuItem(value: id, child: Text(name));
              }),
            ],
            onChanged: (value) {
              setState(() {
                _selectedPayrollStaffId = (value == null || value.isEmpty) ? null : value;
                if (_selectedPayrollStaffId != null) {
                  final list = _staffProfiles.where((p) => (p['id']?.toString()) == _selectedPayrollStaffId).toList();
                  final profile = list.isEmpty ? null : list.first;
                  if (profile != null) {
                    final kobo = (profile['monthly_salary'] is int)
                        ? (profile['monthly_salary'] as int)
                        : (int.tryParse(profile['monthly_salary']?.toString() ?? '') ?? 0);
                    _payrollAmountController.text =
                        kobo > 0 ? PaymentService.koboToNaira(kobo).toStringAsFixed(2) : '';
                  } else {
                    _payrollAmountController.clear();
                  }
                } else {
                  _payrollAmountController.clear();
                }
              });
              _maybeShowDuplicatePayrollWarning();
            },
          ),
          TextField(
            controller: _payrollAmountController,
            decoration: const InputDecoration(
              labelText: 'Amount',
              hintText: 'Defaults to basic salary; edit for overtime/deductions',
            ),
            keyboardType: TextInputType.number,
          ),
          TextField(
            controller: _payrollMonthController,
            decoration: const InputDecoration(
              labelText: 'Month',
              suffixIcon: Icon(Icons.calendar_today),
            ),
            readOnly: true,
            onTap: () async {
              final now = DateTime.now();
              final picked = await showDatePicker(
                context: context,
                firstDate: DateTime(now.year - 1, 1, 1),
                lastDate: DateTime(now.year + 1, 12, 31),
                initialDate: _selectedPayrollMonth ?? DateTime(now.year, now.month, 1),
              );
              if (picked != null) {
                setState(() {
                  _selectedPayrollMonth = DateTime(picked.year, picked.month, 1);
                  _payrollMonthController.text =
                      '${picked.year}-${picked.month.toString().padLeft(2, '0')}-01';
                });
                _maybeShowDuplicatePayrollWarning();
              }
            },
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _payrollPaymentMethod,
            decoration: const InputDecoration(labelText: 'Payment Method'),
            items: const [
              DropdownMenuItem(value: 'bank_transfer', child: Text('Bank Transfer')),
              DropdownMenuItem(value: 'cash', child: Text('Cash')),
            ],
            onChanged: (value) {
              setState(() {
                _payrollPaymentMethod = value ?? 'bank_transfer';
              });
            },
          ),
        ],
        onSave: _savePayrollRecord,
        onSuccess: _clearPayrollForm,
      ),
    );
  }

  void _showAddCashDepositDialog() {
    showDialog(
      context: context,
      builder: (context) => FinanceRecordDialog(
        title: 'Record Cash Deposit',
        formFields: [
          TextField(
            controller: _depositAmountController,
            decoration: const InputDecoration(labelText: 'Amount'),
            keyboardType: TextInputType.number,
          ),
          TextField(
            controller: _bankChargesController,
            decoration: const InputDecoration(labelText: 'Bank Charges'),
            keyboardType: TextInputType.number,
          ),
          TextField(
            controller: _bankNameController,
            decoration: const InputDecoration(labelText: 'Bank Name'),
          ),
          TextField(
            controller: _accountTypeController,
            decoration: const InputDecoration(labelText: 'Account Type'),
          ),
          TextField(
            controller: _depositDescriptionController,
            decoration: const InputDecoration(labelText: 'Description'),
          ),
        ],
        onSave: _saveCashDeposit,
        onSuccess: _clearDepositForm,
      ),
    );
  }

  // Save methods
  Future<bool> _saveIncomeRecord() async {
    final description = _incomeDescriptionController.text.trim();
    if (description.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enter a description.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return false;
    }
    final amountInNaira = double.tryParse(_incomeAmountController.text.trim());
    if (amountInNaira == null || amountInNaira <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enter a valid amount greater than zero.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return false;
    }
    if (amountInNaira > 1000000000) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Amount is too large. Please verify the amount.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return false;
    }
    final authService = Provider.of<AuthService>(context, listen: false);
    final userId = authService.currentUser?.id;
    if (userId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You must be logged in to record income.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return false;
    }
    final amountInKobo = PaymentService.nairaToKobo(amountInNaira);
    final income = {
      'description': description,
      'amount': amountInKobo,
      'source': _incomeSourceController.text.trim(),
      'date': DateTime.now().toIso8601String().split('T')[0],
      'department': _incomeDepartment,
      'payment_method': _incomePaymentMethod,
      'staff_id': userId,
      'created_by': userId,
    };
    await _dataService.addIncomeRecord(income);
    if (mounted) {
      ErrorHandler.showSuccessMessage(context, 'Income record saved successfully!');
      _loadCurrentTabData();
    }
    return true;
  }

  Future<bool> _saveExpense() async {
    // Validation: description not empty
    final description = _expenseDescriptionController.text.trim();
    if (description.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enter a description.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return false;
    }

    // Validation: amount valid and greater than zero
    final amountInNaira = double.tryParse(_expenseAmountController.text.trim());
    if (amountInNaira == null || amountInNaira <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enter a valid amount greater than zero.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return false;
    }

    final authService = Provider.of<AuthService>(context, listen: false);
    final userId = authService.currentUser?.id;
    if (userId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You must be logged in to record expenses.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return false;
    }

    final amountInKobo = PaymentService.nairaToKobo(amountInNaira);
    final expense = {
      'description': description,
      'amount': amountInKobo,
      'category': _expenseCategoryController.text.trim(),
      'date': DateTime.now().toIso8601String().split('T')[0],
      'department': _expenseDepartment,
      'payment_method': _expensePaymentMethod,
      'profile_id': userId,
    };

    await _dataService.addExpense(expense);
    if (mounted) {
      ErrorHandler.showSuccessMessage(context, 'Expense saved successfully!');
      _loadCurrentTabData();
    }
    return true;
  }

  Future<bool> _savePayrollRecord() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final userId = authService.currentUser?.id;
    if (userId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You must be logged in to record payroll.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return false;
    }
    final staffId = _selectedPayrollStaffId ?? _staffIdController.text.trim();
    if (staffId.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please select a staff member.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return false;
    }
    if (_selectedPayrollMonth == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please select payroll month.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return false;
    }
    final amountInNaira = double.tryParse(_payrollAmountController.text.trim());
    if (amountInNaira == null || amountInNaira <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enter a valid amount greater than zero.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return false;
    }
    final amountInKobo = PaymentService.nairaToKobo(amountInNaira);
    final payroll = {
      'staff_id': staffId,
      'amount': amountInKobo,
      'month': _selectedPayrollMonth!.toIso8601String().split('T')[0],
      'status': 'pending',
      'payment_method': _payrollPaymentMethod,
      'processed_by': userId,
    };
    await _dataService.addPayrollRecord(payroll);
    if (mounted) {
      ErrorHandler.showSuccessMessage(context, 'Payroll record saved successfully!');
      _loadCurrentTabData();
    }
    return true;
  }

  Future<bool> _saveCashDeposit() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final userId = authService.currentUser?.id;
    if (userId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You must be logged in to record cash deposits.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return false;
    }
    final amountInNaira = double.tryParse(_depositAmountController.text.trim());
    final bankChargesInNaira = double.tryParse(_bankChargesController.text.trim());
    if (amountInNaira == null || amountInNaira <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enter a valid amount greater than zero.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return false;
    }
    if (bankChargesInNaira == null || bankChargesInNaira < 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bank charges must be zero or greater.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return false;
    }
    final amountInKobo = PaymentService.nairaToKobo(amountInNaira);
    final bankChargesInKobo = PaymentService.nairaToKobo(bankChargesInNaira);
    final netAmountInKobo = amountInKobo - bankChargesInKobo;
    if (amountInKobo > 100000000000) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Amount is too large. Please verify the amount.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return false;
    }
    if (bankChargesInKobo > amountInKobo) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bank charges cannot exceed the deposit amount.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return false;
    }
    if (netAmountInKobo < 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Net amount cannot be negative.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return false;
    }
    final deposit = {
      'amount': amountInKobo,
      'bank_name': _bankNameController.text.trim(),
      'account_type': _accountTypeController.text.trim(),
      'bank_charges': bankChargesInKobo,
      'net_amount': netAmountInKobo,
      'date': DateTime.now().toIso8601String().split('T')[0],
      'description': _depositDescriptionController.text.trim(),
      'staff_id': userId,
      'created_by': userId,
    };
    await _dataService.addCashDeposit(deposit);
    if (mounted) {
      ErrorHandler.showSuccessMessage(context, 'Cash deposit saved successfully!');
      _loadCurrentTabData();
    }
    return true;
  }

  Future<void> _showRecordPaymentDialog(Map<String, dynamic> debt) async {
    final screenContext = context;
    showDialog(
      context: screenContext,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Record Payment'),
        content: Builder(
          builder: (context) {
            _paymentAmountController.clear();
            _paymentNotesController.clear();
            _paymentMethod = 'cash';
            _paymentDate = DateTime.now();
            
            final totalAmount = int.tryParse(debt['amount']?.toString() ?? '') ?? 0;
            final paidAmount = int.tryParse(debt['paid_amount']?.toString() ?? '') ?? 0;
            final remaining = totalAmount - paidAmount;
            
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Debtor: ${debt['debtor_name']}'),
                  const SizedBox(height: 8),
                  Text('Total Amount: ₦${PaymentService.koboToNaira(totalAmount)}'),
                  Text('Paid So Far: ₦${PaymentService.koboToNaira(paidAmount)}'),
                  Text('Remaining: ₦${PaymentService.koboToNaira(remaining)}', 
                    style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange[700])),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _paymentAmountController,
                    decoration: const InputDecoration(
                      labelText: 'Payment Amount (₦)',
                      border: OutlineInputBorder(),
                      prefixText: '₦',
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: _paymentMethod,
                    decoration: const InputDecoration(
                      labelText: 'Payment Method',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'cash', child: Text('Cash')),
                      DropdownMenuItem(value: 'transfer', child: Text('Transfer')),
                      DropdownMenuItem(value: 'card', child: Text('Card')),
                      DropdownMenuItem(value: 'other', child: Text('Other')),
                    ],
                    onChanged: (value) => setState(() => _paymentMethod = value!),
                  ),
                  const SizedBox(height: 16),
                  ListTile(
                    title: const Text('Payment Date'),
                    subtitle: Text(_paymentDate != null 
                      ? '${_paymentDate!.day}/${_paymentDate!.month}/${_paymentDate!.year}'
                      : 'Select date'),
                    trailing: const Icon(Icons.calendar_today),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _paymentDate ?? DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null) {
                        setState(() => _paymentDate = picked);
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _paymentNotesController,
                    decoration: const InputDecoration(
                      labelText: 'Notes (Optional)',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
                  ),
                ],
              ),
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final amountText = _paymentAmountController.text.trim();
              if (amountText.isEmpty) {
                ErrorHandler.showWarningMessage(context, 'Please enter payment amount');
                return;
              }
              
              final amountInNaira = double.tryParse(amountText.replaceAll(',', ''));
              if (amountInNaira == null || amountInNaira <= 0) {
                ErrorHandler.showWarningMessage(context, 'Please enter a valid amount greater than zero');
                return;
              }
              
              final totalAmount = int.tryParse(debt['amount']?.toString() ?? '') ?? 0;
              final paidAmount = int.tryParse(debt['paid_amount']?.toString() ?? '') ?? 0;
              final remaining = totalAmount - paidAmount;
              
              if (amountInNaira > PaymentService.koboToNaira(remaining)) {
                ErrorHandler.showWarningMessage(context, 'Payment amount cannot exceed remaining debt');
                return;
              }
              
              try {
                final authService = Provider.of<AuthService>(context, listen: false);
                final userId = authService.currentUser?.id ?? 'system';
                
                await _dataService.recordDebtPayment(
                  debtId: debt['id']?.toString() ?? '',
                  amount: PaymentService.nairaToKobo(amountInNaira),
                  paymentMethod: _paymentMethod,
                  collectedBy: userId,
                  createdBy: userId,
                  paymentDate: _paymentDate,
                  notes: _paymentNotesController.text.trim().isEmpty ? null : _paymentNotesController.text.trim(),
                );
                if (!dialogContext.mounted) return;
                Navigator.pop(dialogContext);
                if (!screenContext.mounted) return;
                ErrorHandler.showSuccessMessage(screenContext, 'Payment recorded successfully!');
                try {
                  if (!screenContext.mounted) return;
                  await _loadCurrentTabData();
                } catch (_) {
                  if (screenContext.mounted) {
                    ErrorHandler.showSuccessMessage(
                      screenContext,
                      'Payment recorded! (Failed to refresh list, please refresh manually.)',
                    );
                  }
                }
              } catch (e, stackTrace) {
                if (kDebugMode) debugPrint('DEBUG record payment: $e\n$stackTrace');
                if (screenContext.mounted) {
                  ErrorHandler.handleError(
                    screenContext,
                    e,
                    customMessage: 'Failed to record payment. Please try again.',
                    stackTrace: stackTrace,
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('Record Payment'),
          ),
        ],
      ),
    );
  }

  void _clearDebtForm() {
    _debtorNameController.clear();
    _debtorPhoneController.clear();
    _debtAmountController.clear();
    _debtDescriptionController.clear();
    _debtDueDateController.clear();
    _debtorType = 'customer';
    _debtDepartment = 'all';
    _selectedDebtDueDate = null;
  }

  void _clearIncomeForm() {
    _incomeDescriptionController.clear();
    _incomeAmountController.clear();
    _incomeSourceController.clear();
    _incomeDepartment = 'finance';
    _incomePaymentMethod = 'cash';
  }

  void _clearExpenseForm() {
    _expenseDescriptionController.clear();
    _expenseAmountController.clear();
    _expenseCategoryController.clear();
    _expenseDepartment = 'all';
    _expensePaymentMethod = 'cash';
  }

  void _clearPayrollForm() {
    _staffIdController.clear();
    _payrollAmountController.clear();
    _payrollMonthController.clear();
    _selectedPayrollStaffId = null;
    _selectedPayrollMonth = null;
    _payrollPaymentMethod = 'bank_transfer';
  }

  void _clearDepositForm() {
    _depositAmountController.clear();
    _bankChargesController.clear();
    _bankNameController.clear();
    _accountTypeController.clear();
    _depositDescriptionController.clear();
  }

  Future<void> _downloadFinanceCsv() async {
    _isExporting.value = true;
    try {
      await _loadDataForExport();
      if (!mounted) return;
      final csv = _buildFinanceCsv();
      final r = _effectiveSummaryRange;
      final rangeLabel = '${r.start.toIso8601String().split('T')[0]}_to_${r.end.toIso8601String().split('T')[0]}';
      final filename = 'PZed_Homes_Finance_$rangeLabel.csv';
      await triggerCsvDownload(csv, filename);
      if (mounted) {
        ErrorHandler.showSuccessMessage(
          context,
          kIsWeb ? 'CSV downloaded as $filename' : 'CSV copied to clipboard. Paste into a spreadsheet to save.',
        );
      }
    } catch (e, stackTrace) {
      if (kDebugMode) debugPrint('DEBUG export CSV: $e\n$stackTrace');
      if (mounted) {
        ErrorHandler.handleError(
          context,
          e,
          customMessage: 'Failed to export CSV. Please try again.',
          stackTrace: stackTrace,
        );
      }
    } finally {
      _isExporting.value = false;
    }
  }

  Future<void> _exportAuditorPackPdf() async {
    _isExporting.value = true;
    try {
      await _loadDataForExport();
      if (!mounted) return;
      final pdf = await _buildAuditorPackPdf();
      final r = _effectiveSummaryRange;
      final rangeStr = '${r.start.toIso8601String().split('T')[0]}_to_${r.end.toIso8601String().split('T')[0]}';
      await Printing.sharePdf(
        bytes: Uint8List.fromList(pdf),
        filename: 'PZed_Homes_Auditor_Pack_$rangeStr.pdf',
      );
      if (mounted) {
        ErrorHandler.showSuccessMessage(context, 'Auditor Pack PDF ready to save or share.');
      }
    } catch (e, stackTrace) {
      if (kDebugMode) debugPrint('DEBUG auditor pack PDF: $e\n$stackTrace');
      if (mounted) {
        ErrorHandler.handleError(
          context,
          e,
          customMessage: 'Failed to generate Auditor Pack PDF. Please try again.',
          stackTrace: stackTrace,
        );
      }
    } finally {
      _isExporting.value = false;
    }
  }

  Future<List<int>> _buildAuditorPackPdf() async {
    final pdf = pw.Document();
    final r = _effectiveSummaryRange;
    final rangeLabel = '${r.start.toIso8601String().split('T')[0]} to ${r.end.toIso8601String().split('T')[0]}';
    final generatedAt = DateFormat('MMMM dd, yyyy – HH:mm').format(DateTime.now());
    final totalIncome = (_financialSummary['total_income'] as num?)?.toInt() ?? 0;
    final totalExpenses = (_financialSummary['total_expenses'] as num?)?.toInt() ?? 0;
    final netProfit = (_financialSummary['net_profit'] as num?)?.toInt() ?? 0;

    pdf.addPage(
      pw.MultiPage(
        build: (context) {
          return [
            pw.Text('PZed Homes', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold, color: PdfColors.green800)),
            pw.SizedBox(height: 4),
            pw.Text('Financial Auditor Pack', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 8),
            pw.Text('Selected date range (audit period):', style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
            pw.Text(rangeLabel, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Text('Generated: $generatedAt', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
            pw.Divider(thickness: 2, color: PdfColors.green800),
            pw.SizedBox(height: 12),
            pw.Text('Summary', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 6),
            _pdfSummaryRow('Total Income', totalIncome),
            _pdfSummaryRow('Total Expenses', totalExpenses),
            _pdfSummaryRow('Net Profit', netProfit),
            pw.SizedBox(height: 16),
            _buildPdfTable(
              title: 'Income Records',
              headers: ['Date', 'Description', 'Amount (₦)', 'Department', 'Payment'],
              rows: _incomeRecords.map((r) {
                final amt = (r['amount'] as num?)?.toInt() ?? 0;
                return [
                  r['date']?.toString() ?? '',
                  (r['description']?.toString() ?? '').replaceAll('\n', ' '),
                  _formatKobo(amt),
                  r['department']?.toString() ?? '',
                  r['payment_method']?.toString() ?? '',
                ];
              }).toList(),
            ),
            _buildPdfTable(
              title: 'Expenses',
              headers: ['Date', 'Description', 'Amount (₦)', 'Department', 'Status'],
              rows: _expenses.map((r) {
                final amt = (r['amount'] as num?)?.toInt() ?? 0;
                return [
                  r['transaction_date']?.toString() ?? '',
                  (r['description']?.toString() ?? '').replaceAll('\n', ' '),
                  _formatKobo(amt),
                  r['department']?.toString() ?? '',
                  r['status']?.toString() ?? '',
                ];
              }).toList(),
            ),
            _buildPdfTable(
              title: 'Debts',
              headers: ['Date', 'Debtor', 'Amount (₦)', 'Paid', 'Status'],
              rows: _debts.map((r) {
                final amt = (r['amount'] as num?)?.toInt() ?? 0;
                final paid = (r['paid_amount'] as num?)?.toInt() ?? 0;
                return [
                  r['date']?.toString() ?? '',
                  r['debtor_name']?.toString() ?? '',
                  _formatKobo(amt),
                  _formatKobo(paid),
                  r['status']?.toString() ?? '',
                ];
              }).toList(),
            ),
            _buildPdfTable(
              title: 'Payroll',
              headers: ['Month', 'Staff', 'Amount (₦)', 'Approval', 'Rejection note'],
              rows: _payrollRecords.map((r) {
                final amt = (r['amount'] as num?)?.toInt() ?? 0;
                return [
                  r['month']?.toString() ?? '',
                  r['staff_name']?.toString() ?? '',
                  _formatKobo(amt),
                  r['approval_status']?.toString() ?? '',
                  (r['rejection_reason']?.toString() ?? '').replaceAll('\n', ' '),
                ];
              }).toList(),
            ),
            _buildPdfTable(
              title: 'Cash Deposits',
              headers: ['Date', 'Bank', 'Amount (₦)', 'Net'],
              rows: _cashDeposits.map((r) {
                final amt = (r['amount'] as num?)?.toInt() ?? 0;
                final net = (r['net_amount'] as num?)?.toInt() ?? 0;
                return [
                  r['date']?.toString() ?? '',
                  r['bank_name']?.toString() ?? '',
                  _formatKobo(amt),
                  _formatKobo(net),
                ];
              }).toList(),
            ),
            _buildPdfTable(
              title: 'Audit & Sales Activity',
              headers: ['Timestamp', 'Stream', 'Action', 'Source', 'Description', 'Qty', 'Unit (₦)', 'Line Total (₦)', 'Actor'],
              rows: _auditLogs.map((log) {
                final actor = (log['actor'] as Map?)?['full_name'] ?? log['actor_name'] ?? 'Unknown';
                final unit = (log['unit_price'] as num?)?.toInt();
                final qty = log['quantity']?.toString() ?? '';
                final lineTotal = ((log['line_total'] as num?)?.toInt()) ?? ((log['amount'] as num?)?.toInt());
                return [
                  log['created_at']?.toString() ?? '',
                  log['audit_stream']?.toString() ?? '',
                  log['action']?.toString() ?? '',
                  log['table_name']?.toString() ?? '',
                  (log['description']?.toString() ?? '').replaceAll('\n', ' '),
                  qty,
                  unit == null ? '' : _formatKobo(unit),
                  lineTotal == null ? '' : _formatKobo(lineTotal),
                  actor.toString(),
                ];
              }).toList(),
            ),
            pw.SizedBox(height: 12),
            pw.Text('Audit: ${_auditLogs.length} log entries in period.', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
            pw.SizedBox(height: 8),
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text('PZed Homes – Financial Auditor Pack – $generatedAt', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
            ),
          ];
        },
      ),
    );
    return pdf.save();
  }

  pw.Widget _pdfSummaryRow(String label, int amountKobo) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: const pw.TextStyle(fontSize: 12)),
          pw.Text('₦${_formatKobo(amountKobo)}', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
        ],
      ),
    );
  }

  String _buildFinanceCsv() {
    final buffer = StringBuffer();
    final r = _effectiveSummaryRange;
    final rangeLabel = '${r.start.toIso8601String().split('T')[0]} to ${r.end.toIso8601String().split('T')[0]}';

    buffer.writeln('PZed Homes – Finance Export for Auditors');
    buffer.writeln('Selected Date Range (Audit Period),$rangeLabel');
    buffer.writeln('Generated At,${DateTime.now().toIso8601String()}');
    buffer.writeln('');
    buffer.writeln('Summary');
    buffer.writeln('Total Income,${_financialSummary['total_income'] ?? 0}');
    buffer.writeln('Total Expenses,${_financialSummary['total_expenses'] ?? 0}');
    buffer.writeln('Net Profit,${_financialSummary['net_profit'] ?? 0}');
    buffer.writeln('');

    void writeSection(String title, List<String> headers, List<List<String>> rows) {
      buffer.writeln(title);
      buffer.writeln(headers.join(','));
      for (final row in rows) {
        buffer.writeln(row.map(_escapeCsv).join(','));
      }
      buffer.writeln('');
    }

    writeSection(
      'Income Records',
      ['date', 'description', 'amount', 'department', 'payment_method'],
      _incomeRecords.map((r) {
        return [
          r['date']?.toString() ?? '',
          r['description']?.toString() ?? '',
          r['amount']?.toString() ?? '0',
          r['department']?.toString() ?? '',
          r['payment_method']?.toString() ?? '',
        ];
      }).toList(),
    );

    writeSection(
      'Expenses',
      ['transaction_date', 'description', 'amount', 'department', 'status'],
      _expenses.map((r) {
        return [
          r['transaction_date']?.toString() ?? '',
          r['description']?.toString() ?? '',
          r['amount']?.toString() ?? '0',
          r['department']?.toString() ?? '',
          r['status']?.toString() ?? '',
        ];
      }).toList(),
    );

    writeSection(
      'Debts',
      ['date', 'debtor_name', 'amount', 'paid_amount', 'status', 'due_date'],
      _debts.map((r) {
        return [
          r['date']?.toString() ?? '',
          r['debtor_name']?.toString() ?? '',
          r['amount']?.toString() ?? '0',
          r['paid_amount']?.toString() ?? '0',
          r['status']?.toString() ?? '',
          r['due_date']?.toString() ?? '',
        ];
      }).toList(),
    );

    writeSection(
      'Payroll',
      ['month', 'staff', 'amount', 'approval_status', 'payment_method', 'rejection_reason'],
      _payrollRecords.map((r) {
        return [
          r['month']?.toString() ?? '',
          r['staff_name']?.toString() ?? '',
          r['amount']?.toString() ?? '0',
          r['approval_status']?.toString() ?? '',
          r['payment_method']?.toString() ?? '',
          r['rejection_reason']?.toString() ?? '',
        ];
      }).toList(),
    );

    writeSection(
      'Cash Deposits',
      ['date', 'bank_name', 'amount', 'net_amount'],
      _cashDeposits.map((r) {
        return [
          r['date']?.toString() ?? '',
          r['bank_name']?.toString() ?? '',
          r['amount']?.toString() ?? '0',
          r['net_amount']?.toString() ?? '0',
        ];
      }).toList(),
    );

    writeSection(
      'Audit and Sales Activity',
      ['created_at', 'audit_stream', 'action', 'table_name', 'description', 'quantity', 'unit_price_kobo', 'line_total_kobo', 'actor'],
      _auditLogs.map((log) {
        final actor = (log['actor'] as Map?)?['full_name'] ?? log['actor_name'] ?? 'Unknown';
        return [
          log['created_at']?.toString() ?? '',
          log['audit_stream']?.toString() ?? '',
          log['action']?.toString() ?? '',
          log['table_name']?.toString() ?? '',
          log['description']?.toString() ?? '',
          log['quantity']?.toString() ?? '',
          log['unit_price']?.toString() ?? '',
          log['line_total']?.toString() ?? log['amount']?.toString() ?? '',
          actor.toString(),
        ];
      }).toList(),
    );

    return buffer.toString();
  }

  String _escapeCsv(String value) {
    final needsQuotes = value.contains(',') || value.contains('"') || value.contains('\n');
    if (!needsQuotes) return value;
    final escaped = value.replaceAll('"', '""');
    return '"$escaped"';
  }

  pw.Widget _buildPdfTable({
    required String title,
    required List<String> headers,
    required List<List<String>> rows,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(height: 8),
        pw.Text(title, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        pw.TableHelper.fromTextArray(headers: headers, data: rows),
      ],
    );
  }

}
