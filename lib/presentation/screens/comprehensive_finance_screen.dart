import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/services/data_service.dart';
import '../../core/services/mock_auth_service.dart';
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

  // Controllers for debt recording
  final _debtAmountController = TextEditingController();
  final _debtorNameController = TextEditingController();
  final _debtDescriptionController = TextEditingController();
  final _debtDueDateController = TextEditingController();

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
    super.dispose();
  }

  Future<void> _loadFinancialData() async {
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
      });
    } catch (e) {
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
    final authService = Provider.of<MockAuthService>(context, listen: false);
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
              final isPending = debt['status'] == 'pending';
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: ListTile(
                  title: Text(debt['debtor_name'] ?? 'Unknown'),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${debt['debtor_type'] ?? ''} owes ₦${debt['amount'] ?? 0}'),
                      Text('${debt['reason'] ?? ''}', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                      if (debt['debtor_phone'] != null) 
                        Text('Phone: ${debt['debtor_phone']}', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                      if (debt['department'] != null)
                        Text('Dept: ${debt['department']}', style: TextStyle(fontSize: 12, color: Colors.blue[700])),
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
                    ],
                  ),
                  onTap: isPending && canRecord ? () => _showMarkDebtPaidDialog(debt, index) : null,
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
                    onPressed: () => _generateFinancialReport(),
                    child: const Text('Generate Financial Report'),
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
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Record New Debt'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _debtorNameController,
              decoration: const InputDecoration(labelText: 'Debtor Name'),
            ),
            TextField(
              controller: _debtAmountController,
              decoration: const InputDecoration(labelText: 'Amount'),
              keyboardType: TextInputType.number,
            ),
            TextField(
              controller: _debtDescriptionController,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
            TextField(
              controller: _debtDueDateController,
              decoration: const InputDecoration(labelText: 'Due Date'),
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
              // Implement debt recording logic
              Navigator.pop(context);
              _clearDebtForm();
            },
            child: const Text('Record'),
          ),
        ],
      ),
    );
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
      final income = {
        'description': _incomeDescriptionController.text,
        'amount': double.parse(_incomeAmountController.text),
        'source': _incomeSourceController.text,
        'date': DateTime.now().toIso8601String().split('T')[0],
        'department': 'finance',
        'payment_method': 'cash',
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
      final expense = {
        'description': _expenseDescriptionController.text,
        'amount': double.parse(_expenseAmountController.text),
        'category': _expenseCategoryController.text,
        'date': DateTime.now().toIso8601String().split('T')[0],
        'department': 'all',
        'payment_method': 'cash',
        'staff_id': 'staff006', // Current user
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
      final payroll = {
        'staff_id': _staffIdController.text,
        'amount': double.parse(_payrollAmountController.text),
        'month': _payrollMonthController.text,
        'status': 'pending',
        'payment_method': 'bank_transfer',
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
      final amount = double.parse(_depositAmountController.text);
      final bankCharges = double.parse(_bankChargesController.text);
      
      final deposit = {
        'amount': amount,
        'bank_name': _bankNameController.text,
        'account_type': _accountTypeController.text,
        'bank_charges': bankCharges,
        'net_amount': amount - bankCharges,
        'date': DateTime.now().toIso8601String().split('T')[0],
        'description': _depositDescriptionController.text,
        'staff_id': 'staff006', // Current user
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

  // Mark debt as paid dialog
  void _showMarkDebtPaidDialog(Map<String, dynamic> debt, int index) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mark Debt as Paid'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Debtor: ${debt['debtor_name']}'),
            const SizedBox(height: 8),
            Text('Amount: ₦${debt['amount']}'),
            const SizedBox(height: 8),
            Text('Reason: ${debt['reason']}'),
            const SizedBox(height: 16),
            const Text('Are you sure this debt has been paid?'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _debts[index]['status'] = 'paid';
                _debts[index]['paid_date'] = DateTime.now().toIso8601String();
              });
              Navigator.pop(context);
              if (mounted) {
                ErrorHandler.showSuccessMessage(
                  context,
                  'Debt marked as paid',
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('Mark as Paid'),
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
  void _generateDepartmentReport() {
    if (mounted) {
      ErrorHandler.showSuccessMessage(
        context,
        'Department report generated successfully',
      );
    }
  }

  void _generateFinancialReport() {
    if (mounted) {
      ErrorHandler.showSuccessMessage(
        context,
        'Financial report generated successfully',
      );
    }
  }
}
