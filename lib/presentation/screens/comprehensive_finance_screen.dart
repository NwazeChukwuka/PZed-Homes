import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/services/data_service.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/payment_service.dart';
import '../../core/utils/input_sanitizer.dart';
import '../../core/error/error_handler.dart';
import '../../data/models/user.dart';
import '../../presentation/widgets/context_aware_role_button.dart';

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
  List<Map<String, dynamic>> _purchases = [];
  List<Map<String, dynamic>> _incomeRecords = [];
  List<Map<String, dynamic>> _expenses = [];
  List<Map<String, dynamic>> _payrollRecords = [];
  List<Map<String, dynamic>> _cashDeposits = [];
  Map<String, dynamic> _financialSummary = {};
  Map<String, List<Map<String, dynamic>>> _departmentSales = {};
  bool _isLoadingData = false;
  bool _isGeneratingReport = false;

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

  // Controllers for expense recording
  final _expenseAmountController = TextEditingController();
  final _expenseDescriptionController = TextEditingController();
  final _expenseCategoryController = TextEditingController();

  // Controllers for payroll recording
  final _staffIdController = TextEditingController();
  final _payrollAmountController = TextEditingController();
  final _payrollMonthController = TextEditingController();

  // Controllers for cash deposit recording
  final _depositAmountController = TextEditingController();
  final _bankChargesController = TextEditingController();
  final _bankNameController = TextEditingController();
  final _accountTypeController = TextEditingController();
  final _depositDescriptionController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 8, vsync: this);
    _loadFinancialData();
  }

  @override
  void dispose() {
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
    _depositAmountController.dispose();
    _bankChargesController.dispose();
    _bankNameController.dispose();
    _accountTypeController.dispose();
    _depositDescriptionController.dispose();
    _paymentAmountController.dispose();
    _paymentNotesController.dispose();
    super.dispose();
  }

  Future<void> _loadFinancialData() async {
    if (_isLoadingData) return; // Prevent concurrent loads
    
    setState(() => _isLoadingData = true);
    
    try {
      final summary = await _dataService.getFinancialSummary();
      final debts = await _dataService.getDebts();
      final income = await _dataService.getIncomeRecords();
      final expenses = await _dataService.getExpenses();
      final payroll = await _dataService.getPayrollRecords();
      final deposits = await _dataService.getCashDeposits();
      final purchases = await _dataService.getRecentPurchases();
      // Department sales snapshots
      final vipSales = await _dataService.getDepartmentSales('vip_bar');
      final outsideSales = await _dataService.getDepartmentSales('outside_bar');
      final miniMartSales = await _dataService.getDepartmentSales('mini_mart');
      final kitchenSales = await _dataService.getDepartmentSales('kitchen');

      setState(() {
        _financialSummary = summary;
        _debts = debts;
        _purchases = purchases;
        _incomeRecords = income;
        _expenses = expenses;
        _payrollRecords = payroll;
        _cashDeposits = deposits;
        _departmentSales = {
          'VIP Bar': vipSales,
          'Outside Bar': outsideSales,
          'Mini Mart': miniMartSales,
          'Kitchen': kitchenSales,
        };
        _isLoadingData = false;
      });
    } catch (e) {
      setState(() => _isLoadingData = false);
      if (mounted) {
        ErrorHandler.handleError(
          context,
          e,
          customMessage: 'Failed to load financial data. Please check your connection and try again.',
          onRetry: _loadFinancialData,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context, listen: false);
    final user = authService.currentUser;
    final isAccountant = (user?.roles.any((role) => role.name == 'accountant') ?? false);
    final isAssumedAccountant = authService.isRoleAssumed && authService.assumedRole?.name == 'accountant';
    final isOwnerOrManager = user?.roles.any((r) => r.name == 'owner' || r.name == 'manager') ?? false;
    
    // Owner/Manager can only record if they assume accountant role
    final canRecord = (isAccountant || isAssumedAccountant) && !(isOwnerOrManager && !isAssumedAccountant);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Finance & Accounting'),
        backgroundColor: Colors.green[700],
        foregroundColor: Colors.white,
        leading: Navigator.of(context).canPop() ? IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ) : null,
        actions: const [
          ContextAwareRoleButton(suggestedRole: AppRole.accountant),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(text: 'Overview', icon: Icon(Icons.dashboard)),
            Tab(text: 'Debts', icon: Icon(Icons.money_off)),
            Tab(text: 'Purchases', icon: Icon(Icons.shopping_cart)),
            Tab(text: 'Income', icon: Icon(Icons.trending_up)),
            Tab(text: 'Expenses', icon: Icon(Icons.trending_down)),
            Tab(text: 'Payroll', icon: Icon(Icons.payment)),
            Tab(text: 'Cash Deposits', icon: Icon(Icons.account_balance)),
            Tab(text: 'Reports', icon: Icon(Icons.assessment)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildOverviewTab(),
          _buildDebtsTab(canRecord),
          _buildPurchasesTab(canRecord),
          _buildIncomeTab(canRecord),
          _buildExpensesTab(canRecord),
          _buildPayrollTab(canRecord),
          _buildCashDepositsTab(canRecord),
          _buildReportsTab(),
        ],
      ),
    );
  }

  Widget _buildOverviewTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFinancialSummaryCard(),
          const SizedBox(height: 20),
          _buildDepartmentPerformanceCard(),
          const SizedBox(height: 20),
          _buildDepartmentSalesCard(),
          const SizedBox(height: 20),
          _buildCashFlowCard(),
        ],
      ),
    );
  }

  Widget _buildDepartmentSalesCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Department Sales (Today)',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            ..._departmentSales.entries.map((entry) {
              final total = entry.value.fold<num>(0, (s, e) => s + (e['total_amount'] as num));
              final items = entry.value.fold<int>(0, (s, e) => s + (e['quantity'] as int));
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(child: Text(entry.key)),
                    Text('Items: $items'),
                    const SizedBox(width: 16),
                    Text('₦$total', style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
              );
            }).toList(),
          ],
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
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildSummaryItem(
                    'Total Income',
                    '₦${_financialSummary['total_income']?.toStringAsFixed(0) ?? '0'}',
                    Colors.green,
                    Icons.trending_up,
                  ),
                ),
                Expanded(
                  child: _buildSummaryItem(
                    'Total Expenses',
                    '₦${_financialSummary['total_expenses']?.toStringAsFixed(0) ?? '0'}',
                    Colors.red,
                    Icons.trending_down,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildSummaryItem(
                    'Available Cash',
                    '₦${_financialSummary['available_cash']?.toStringAsFixed(0) ?? '0'}',
                    Colors.blue,
                    Icons.account_balance_wallet,
                  ),
                ),
                Expanded(
                  child: _buildSummaryItem(
                    'Net Profit',
                    '₦${_financialSummary['net_profit']?.toStringAsFixed(0) ?? '0'}',
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
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
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

  Widget _buildDepartmentPerformanceCard() {
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
            const SizedBox(height: 16),
            FutureBuilder<List<Map<String, dynamic>>>(
              future: _dataService.getDepartmentPerformance(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }
                final depts = snapshot.data ?? [];
                if (depts.isEmpty) {
                  return const Center(child: Text('No department data available'));
                }
                return Column(
                  children: depts.map((dept) => _buildDepartmentItem(dept)).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDepartmentItem(Map<String, dynamic> dept) {
    final performance = dept['performance'] as String;
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
              '₦${dept['revenue']?.toStringAsFixed(0)}',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            child: Text(
              '₦${dept['profit']?.toStringAsFixed(0)}',
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

  Widget _buildCashFlowCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Cash Flow',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              height: 200,
              child: _buildCashFlowChart(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCashFlowChart() {
    // Simple bar chart representation
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _buildBar('Income', _financialSummary['total_income']?.toDouble() ?? 0, Colors.green),
        _buildBar('Expenses', _financialSummary['total_expenses']?.toDouble() ?? 0, Colors.red),
        _buildBar('Cash', _financialSummary['available_cash']?.toDouble() ?? 0, Colors.blue),
      ],
    );
  }

  Widget _buildBar(String label, double value, Color color) {
    final maxValue = [
      _financialSummary['total_income']?.toDouble() ?? 0,
      _financialSummary['total_expenses']?.toDouble() ?? 0,
      _financialSummary['available_cash']?.toDouble() ?? 0,
    ].reduce((a, b) => a > b ? a : b);
    
    // Ensure minimum height of 5.0 to avoid negative constraints
    final height = maxValue > 0 ? ((value / maxValue) * 150).clamp(5.0, 150.0) : 5.0;
    
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '₦${(value / 1000).toStringAsFixed(0)}k',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 4),
        Container(
          width: 40,
          height: height,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _buildDebtsTab(bool canRecord) {
    return Column(
      children: [
        if (canRecord)
          Padding(
            padding: const EdgeInsets.all(16),
            child: ElevatedButton.icon(
              onPressed: () => _showAddDebtDialog(),
              icon: const Icon(Icons.add),
              label: const Text('Record New Debt'),
            ),
          ),
        Expanded(
          child: ListView.builder(
            itemCount: _debts.length,
            itemBuilder: (context, index) {
              final debt = _debts[index];
              final isPending = debt['status'] == 'outstanding' || debt['status'] == 'partially_paid';
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: ListTile(
                  title: Text(debt['debtor_name'] ?? 'Unknown'),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${debt['debtor_type'] ?? ''} owes ₦${PaymentService.koboToNaira(debt['amount'] as int? ?? 0)}'),
                      if (debt['paid_amount'] != null && (debt['paid_amount'] as int? ?? 0) > 0)
                        Text(
                          'Paid: ₦${PaymentService.koboToNaira(debt['paid_amount'] as int)} | Remaining: ₦${PaymentService.koboToNaira((debt['amount'] as int? ?? 0) - (debt['paid_amount'] as int? ?? 0))}',
                          style: TextStyle(fontSize: 12, color: Colors.green[700], fontWeight: FontWeight.w500),
                        ),
                      Text('${debt['reason'] ?? ''}', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                      if (debt['debtor_phone'] != null) 
                        Text('Phone: ${debt['debtor_phone']}', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                      // Note: department info is stored in reason field, not a separate column
                      if (debt['sold_by'] != null && debt['profiles'] != null)
                        Text('Sold by: ${debt['profiles']?['full_name'] ?? 'Unknown'}', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
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
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPurchasesTab(bool canRecord) {
    return ListView.builder(
      itemCount: _purchases.length,
      itemBuilder: (context, index) {
        final p = _purchases[index];
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: ListTile(
            leading: const Icon(Icons.shopping_bag),
            title: Text(p['item_name'] ?? p['item_id'] ?? 'Item'),
            subtitle: Text('Qty: ${p['quantity']} • Dept: ${p['department']} • Supplier: ${p['supplier']}'),
            trailing: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('₦${p['total_cost']}'),
                const SizedBox(height: 4),
                Text(p['date'] ?? ''),
              ],
            ),
          ),
        );
      },
    );
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
                  subtitle: Text('₦${income['amount'] ?? 0} - ${income['department'] ?? ''}'),
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

  Widget _buildExpensesTab(bool canRecord) {
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
        Expanded(
          child: ListView.builder(
            itemCount: _expenses.length,
            itemBuilder: (context, index) {
              final expense = _expenses[index];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: ListTile(
                  title: Text(expense['description'] ?? 'Unknown'),
                  subtitle: Text('₦${expense['amount'] ?? 0} - ${expense['payment_method'] ?? ''}'),
                  trailing: Text(expense['date'] ?? ''),
                  leading: const Icon(Icons.trending_down, color: Colors.red),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPayrollTab(bool canRecord) {
    return Column(
      children: [
        if (canRecord)
          Padding(
            padding: const EdgeInsets.all(16),
            child: ElevatedButton.icon(
              onPressed: () => _showAddPayrollDialog(),
              icon: const Icon(Icons.add),
              label: const Text('Record Payroll'),
            ),
          ),
        Expanded(
          child: ListView.builder(
            itemCount: _payrollRecords.length,
            itemBuilder: (context, index) {
              final payroll = _payrollRecords[index];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: ListTile(
                  title: Text(payroll['staff_name'] ?? 'Unknown'),
                  subtitle: Text('₦${payroll['amount'] ?? 0} - ${payroll['month'] ?? ''}'),
                  trailing: Chip(
                    label: Text(payroll['status'] ?? ''),
                    backgroundColor: payroll['status'] == 'paid' ? Colors.green : Colors.orange,
                  ),
                  leading: const Icon(Icons.payment, color: Colors.blue),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCashDepositsTab(bool canRecord) {
    return Column(
      children: [
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
                  subtitle: Text('₦${deposit['amount']} (Net: ₦${deposit['net_amount']})'),
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

  Widget _buildReportsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Department Reports',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => _generateDepartmentReport(),
                    child: const Text('Generate Department Report'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Financial Reports',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _isGeneratingReport ? null : () => _generateFinancialReport(),
                    child: _isGeneratingReport
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Generate Financial Report'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Dialog methods
  void _showAddDebtDialog() {
    _debtorType = 'customer'; // Reset to default
    _debtDepartment = 'all'; // Reset to default
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Record New Debt'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
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
                  value: _debtorType,
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
                    setDialogState(() {
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
                    labelText: 'Due Date (YYYY-MM-DD)',
                    border: OutlineInputBorder(),
                    hintText: 'Optional',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _debtDepartment,
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
                    setDialogState(() {
                      _debtDepartment = value ?? 'all';
                    });
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => _recordDebt(),
              child: const Text('Record Debt'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _recordDebt() async {
    // Validate required fields
    if (_debtorNameController.text.trim().isEmpty) {
      ErrorHandler.showWarningMessage(context, 'Please enter debtor name');
      return;
    }
    if (_debtorPhoneController.text.trim().isEmpty) {
      ErrorHandler.showWarningMessage(context, 'Please enter debtor phone');
      return;
    }
    if (_debtAmountController.text.trim().isEmpty) {
      ErrorHandler.showWarningMessage(context, 'Please enter amount');
      return;
    }
    if (_debtDescriptionController.text.trim().isEmpty) {
      ErrorHandler.showWarningMessage(context, 'Please enter reason/description');
      return;
    }

    try {
      // Convert naira to kobo
      final amountInNaira = double.tryParse(_debtAmountController.text.trim());
      if (amountInNaira == null || amountInNaira <= 0) {
        throw Exception('Please enter a valid amount greater than zero');
      }
      final amountInKobo = PaymentService.nairaToKobo(amountInNaira);

      // Parse due date
      DateTime? dueDate;
      if (_debtDueDateController.text.trim().isNotEmpty) {
        try {
          dueDate = DateTime.parse(_debtDueDateController.text.trim());
        } catch (e) {
          throw Exception('Invalid date format. Please use YYYY-MM-DD');
        }
      } else {
        // Default to 30 days from now
        dueDate = DateTime.now().add(const Duration(days: 30));
      }

      final debt = {
        'debtor_name': InputSanitizer.sanitizeText(_debtorNameController.text.trim()),
        'debtor_phone': InputSanitizer.sanitizePhone(_debtorPhoneController.text.trim()),
        'debtor_type': _debtorType,
        'amount': amountInKobo, // Store in kobo
        'owed_to': 'P-ZED Luxury Hotels & Suites',
        'reason': InputSanitizer.sanitizeDescription(_debtDescriptionController.text.trim()) + 
                  (_debtDepartment != 'all' ? ' (Department: $_debtDepartment)' : ''),
        'date': DateTime.now().toIso8601String().split('T')[0],
        'status': 'outstanding', // Use 'outstanding' instead of 'pending' to match schema
        'notes': 'Due date: ${dueDate.toIso8601String().split('T')[0]}', // Store due date in notes since column doesn't exist
      };

      await _dataService.recordDebt(debt);

      Navigator.pop(context);
      if (mounted) {
        ErrorHandler.showSuccessMessage(context, 'Debt recorded successfully!');
        _clearDebtForm();
        _loadFinancialData();
      }
    } catch (e) {
      if (mounted) {
        ErrorHandler.handleError(
          context,
          e,
          customMessage: 'Failed to record debt. Please check all fields and try again.',
        );
      }
    }
  }

  void _showAddIncomeDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Record Income'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              _saveIncomeRecord();
              Navigator.pop(context);
              _clearIncomeForm();
            },
            child: const Text('Record'),
          ),
        ],
      ),
    );
  }

  void _showAddExpenseDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Record Expense'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(labelText: 'Payment Method'),
              items: const [
                DropdownMenuItem(value: 'cash', child: Text('Cash')),
                DropdownMenuItem(value: 'bank_transfer', child: Text('Bank Transfer')),
                DropdownMenuItem(value: 'card', child: Text('Card')),
              ],
              onChanged: (value) {
                // Handle payment method selection
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              _saveExpense();
              Navigator.pop(context);
              _clearExpenseForm();
            },
            child: const Text('Record'),
          ),
        ],
      ),
    );
  }

  void _showAddPayrollDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Record Payroll'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _staffIdController,
              decoration: const InputDecoration(labelText: 'Staff ID'),
            ),
            TextField(
              controller: _payrollAmountController,
              decoration: const InputDecoration(labelText: 'Amount'),
              keyboardType: TextInputType.number,
            ),
            TextField(
              controller: _payrollMonthController,
              decoration: const InputDecoration(labelText: 'Month'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              _savePayrollRecord();
              Navigator.pop(context);
              _clearPayrollForm();
            },
            child: const Text('Record'),
          ),
        ],
      ),
    );
  }

  void _showAddCashDepositDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Record Cash Deposit'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              _saveCashDeposit();
              Navigator.pop(context);
              _clearDepositForm();
            },
            child: const Text('Record'),
          ),
        ],
      ),
    );
  }

  // Save methods
  Future<void> _saveIncomeRecord() async {
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final userId = authService.currentUser?.id;
      
      if (userId == null) {
        throw Exception('User must be logged in to record income');
      }

      // Convert naira input to kobo for database
      final amountInNaira = double.parse(_incomeAmountController.text);
      final amountInKobo = PaymentService.nairaToKobo(amountInNaira);
      
      // Validate amount
      if (amountInKobo <= 0) {
        throw Exception('Amount must be greater than zero');
      }
      if (amountInKobo > 100000000000) { // 1 billion naira = 100 billion kobo
        throw Exception('Amount is too large. Please verify the amount.');
      }

      final income = {
        'description': _incomeDescriptionController.text,
        'amount': amountInKobo, // Store in kobo
        'source': _incomeSourceController.text,
        'date': DateTime.now().toIso8601String().split('T')[0],
        'department': 'finance',
        'payment_method': 'cash',
        'staff_id': userId, // Use current user ID
        'created_by': userId,
      };
      
      await _dataService.addIncomeRecord(income);
      if (mounted) {
        ErrorHandler.showSuccessMessage(context, 'Income record saved successfully!');
        _loadFinancialData();
      }
    } catch (e) {
      if (mounted) {
        ErrorHandler.handleError(
          context,
          e,
          customMessage: 'Failed to save income record. Please try again.',
          onRetry: _saveIncomeRecord,
        );
      }
    }
  }

  Future<void> _saveExpense() async {
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final userId = authService.currentUser?.id;
      
      if (userId == null) {
        throw Exception('User must be logged in to record expenses');
      }

      // Convert naira input to kobo for database
      final amountInNaira = double.parse(_expenseAmountController.text);
      final amountInKobo = PaymentService.nairaToKobo(amountInNaira);
      
      // Validate amount
      if (amountInKobo <= 0) {
        throw Exception('Amount must be greater than zero');
      }

      final expense = {
        'description': _expenseDescriptionController.text,
        'amount': amountInKobo, // Store in kobo
        'category': _expenseCategoryController.text,
        'date': DateTime.now().toIso8601String().split('T')[0],
        'department': 'all',
        'payment_method': 'cash',
        'profile_id': userId, // Use current user ID (expenses table uses profile_id)
      };
      
      await _dataService.addExpense(expense);
      if (mounted) {
        ErrorHandler.showSuccessMessage(context, 'Expense saved successfully!');
        _loadFinancialData();
      }
    } catch (e) {
      if (mounted) {
        ErrorHandler.handleError(
          context,
          e,
          customMessage: 'Failed to save expense. Please try again.',
          onRetry: _saveExpense,
        );
      }
    }
  }

  Future<void> _savePayrollRecord() async {
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final userId = authService.currentUser?.id;
      
      if (userId == null) {
        throw Exception('User must be logged in to record payroll');
      }

      // Convert naira input to kobo for database
      final amountInNaira = double.parse(_payrollAmountController.text);
      final amountInKobo = PaymentService.nairaToKobo(amountInNaira);
      
      // Validate amount
      if (amountInKobo <= 0) {
        throw Exception('Amount must be greater than zero');
      }

      final payroll = {
        'staff_id': _staffIdController.text,
        'amount': amountInKobo, // Store in kobo
        'month': _payrollMonthController.text,
        'status': 'pending',
        'payment_method': 'bank_transfer',
        'processed_by': userId, // Track who recorded this
      };
      
      await _dataService.addPayrollRecord(payroll);
      if (mounted) {
        ErrorHandler.showSuccessMessage(context, 'Payroll record saved successfully!');
        _loadFinancialData();
      }
    } catch (e) {
      if (mounted) {
        ErrorHandler.handleError(
          context,
          e,
          customMessage: 'Failed to save payroll record. Please try again.',
          onRetry: _savePayrollRecord,
        );
      }
    }
  }

  Future<void> _saveCashDeposit() async {
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final userId = authService.currentUser?.id;
      
      if (userId == null) {
        throw Exception('User must be logged in to record cash deposits');
      }

      // Convert naira input to kobo for database
      final amountInNaira = double.parse(_depositAmountController.text);
      final bankChargesInNaira = double.parse(_bankChargesController.text);
      
      final amountInKobo = PaymentService.nairaToKobo(amountInNaira);
      final bankChargesInKobo = PaymentService.nairaToKobo(bankChargesInNaira);
      final netAmountInKobo = amountInKobo - bankChargesInKobo;
      
      // Validate amounts
      if (amountInKobo <= 0) {
        throw Exception('Amount must be greater than zero');
      }
      if (amountInKobo > 100000000000) { // 1 billion naira
        throw Exception('Amount is too large. Please verify the amount.');
      }
      if (bankChargesInKobo < 0) {
        throw Exception('Bank charges cannot be negative');
      }
      if (bankChargesInKobo > amountInKobo) {
        throw Exception('Bank charges cannot exceed the deposit amount');
      }
      if (netAmountInKobo < 0) {
        throw Exception('Net amount cannot be negative');
      }
      
      final deposit = {
        'amount': amountInKobo, // Store in kobo
        'bank_name': _bankNameController.text,
        'account_type': _accountTypeController.text,
        'bank_charges': bankChargesInKobo, // Store in kobo
        'net_amount': netAmountInKobo, // Store in kobo
        'date': DateTime.now().toIso8601String().split('T')[0],
        'description': _depositDescriptionController.text,
        'staff_id': userId, // Use current user ID
        'created_by': userId,
      };
      
      await _dataService.addCashDeposit(deposit);
      if (mounted) {
        ErrorHandler.showSuccessMessage(context, 'Cash deposit saved successfully!');
        _loadFinancialData();
      }
    } catch (e) {
      if (mounted) {
        ErrorHandler.handleError(
          context,
          e,
          customMessage: 'Failed to save cash deposit. Please try again.',
          onRetry: _saveCashDeposit,
        );
      }
    }
  }

  // Record payment dialog
  Future<void> _showRecordPaymentDialog(Map<String, dynamic> debt) async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Record Payment'),
        content: Builder(
          builder: (context) {
            _paymentAmountController.clear();
            _paymentNotesController.clear();
            _paymentMethod = 'cash';
            _paymentDate = DateTime.now();
            
            final totalAmount = debt['amount'] as int? ?? 0;
            final paidAmount = debt['paid_amount'] as int? ?? 0;
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
                    value: _paymentMethod,
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
              
              final totalAmount = debt['amount'] as int? ?? 0;
              final paidAmount = debt['paid_amount'] as int? ?? 0;
              final remaining = totalAmount - paidAmount;
              
              if (amountInNaira > PaymentService.koboToNaira(remaining)) {
                ErrorHandler.showWarningMessage(context, 'Payment amount cannot exceed remaining debt');
                return;
              }
              
              try {
                final authService = Provider.of<AuthService>(context, listen: false);
                final userId = authService.currentUser?.id ?? 'system';
                
                await _dataService.recordDebtPayment(
                  debtId: debt['id'] as String,
                  amount: PaymentService.nairaToKobo(amountInNaira),
                  paymentMethod: _paymentMethod,
                  collectedBy: userId,
                  createdBy: userId,
                  paymentDate: _paymentDate,
                  notes: _paymentNotesController.text.trim().isEmpty ? null : _paymentNotesController.text.trim(),
                );
                
                Navigator.pop(context);
                if (mounted) {
                  ErrorHandler.showSuccessMessage(context, 'Payment recorded successfully!');
                  _loadFinancialData();
                }
              } catch (e) {
                if (mounted) {
                  ErrorHandler.handleError(
                    context,
                    e,
                    customMessage: 'Failed to record payment. Please try again.',
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

  // Clear form methods
  void _clearDebtForm() {
    _debtorNameController.clear();
    _debtAmountController.clear();
    _debtDescriptionController.clear();
    _debtDueDateController.clear();
  }

  void _clearIncomeForm() {
    _incomeDescriptionController.clear();
    _incomeAmountController.clear();
    _incomeSourceController.clear();
  }

  void _clearExpenseForm() {
    _expenseDescriptionController.clear();
    _expenseAmountController.clear();
    _expenseCategoryController.clear();
  }

  void _clearPayrollForm() {
    _staffIdController.clear();
    _payrollAmountController.clear();
    _payrollMonthController.clear();
  }

  void _clearDepositForm() {
    _depositAmountController.clear();
    _bankChargesController.clear();
    _bankNameController.clear();
    _accountTypeController.clear();
    _depositDescriptionController.clear();
  }

  // Report generation methods
  Future<void> _generateDepartmentReport() async {
    if (_isGeneratingReport) return; // Prevent concurrent generation
    
    setState(() => _isGeneratingReport = true);
    
    try {
      // Load department sales data
      final departmentSales = await _dataService.getDepartmentSales();
      
      // Group by department
      final Map<String, Map<String, dynamic>> departmentSummary = {};
      for (final sale in departmentSales) {
        final dept = sale['department'] as String? ?? 'Unknown';
        if (!departmentSummary.containsKey(dept)) {
          departmentSummary[dept] = {
            'department': dept,
            'total_sales': 0,
            'transaction_count': 0,
          };
        }
        final totalSales = (sale['total_sales'] as int? ?? 0);
        final transactionCount = (sale['transaction_count'] as int? ?? 0);
        departmentSummary[dept]!['total_sales'] = 
            (departmentSummary[dept]!['total_sales'] as int) + totalSales;
        departmentSummary[dept]!['transaction_count'] = 
            (departmentSummary[dept]!['transaction_count'] as int) + transactionCount;
      }

      setState(() => _isGeneratingReport = false);
      
      if (mounted) {
        _showReportDialog('Department Sales Report', departmentSummary.values.toList());
      }
    } catch (e) {
      setState(() => _isGeneratingReport = false);
      if (mounted) {
        ErrorHandler.handleError(
          context,
          e,
          customMessage: 'Failed to generate department report. Please try again.',
        );
      }
    }
  }

  Future<void> _generateFinancialReport() async {
    if (_isGeneratingReport) return; // Prevent concurrent generation
    
    setState(() => _isGeneratingReport = true);
    
    try {
      // Load financial summary
      final summary = await _dataService.getFinancialSummary();
      final incomeRecords = await _dataService.getIncomeRecords();
      final expenses = await _dataService.getExpenses();
      
      final reportData = {
        'summary': summary,
        'total_income_records': incomeRecords.length,
        'total_expense_records': expenses.length,
        'income_total': incomeRecords.fold<int>(0, (sum, record) => 
            sum + ((record['amount'] as num?)?.toInt() ?? 0)),
        'expense_total': expenses.fold<int>(0, (sum, expense) => 
            sum + ((expense['amount'] as num?)?.toInt() ?? 0)),
      };

      setState(() => _isGeneratingReport = false);
      
      if (mounted) {
        _showFinancialReportDialog(reportData);
      }
    } catch (e) {
      setState(() => _isGeneratingReport = false);
      if (mounted) {
        ErrorHandler.handleError(
          context,
          e,
          customMessage: 'Failed to generate financial report. Please try again.',
        );
      }
    }
  }

  void _showReportDialog(String title, List<Map<String, dynamic>> data) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final dept in data)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              dept['department'] as String? ?? 'Unknown',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Total Sales: ₦${PaymentService.koboToNaira((dept['total_sales'] as int? ?? 0)).toStringAsFixed(2)}',
                            ),
                            Text(
                              'Transactions: ${dept['transaction_count'] ?? 0}',
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showFinancialReportDialog(Map<String, dynamic> data) {
    final summary = data['summary'] as Map<String, dynamic>;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Financial Report'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildReportRow('Total Income', PaymentService.koboToNaira((summary['total_income'] as int?) ?? 0)),
                _buildReportRow('Total Expenses', PaymentService.koboToNaira((summary['total_expenses'] as int?) ?? 0)),
                _buildReportRow('Net Profit', PaymentService.koboToNaira((summary['net_profit'] as int?) ?? 0)),
                const Divider(),
                Text('Income Records: ${data['total_income_records']}'),
                Text('Expense Records: ${data['total_expense_records']}'),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildReportRow(String label, double amount) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(
            '₦${amount.toStringAsFixed(2)}',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: amount < 0 ? Colors.red : Colors.green,
            ),
          ),
        ],
      ),
    );
  }
}
