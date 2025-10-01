import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:pzed_homes/presentation/screens/add_expense_screen.dart';

class FinanceScreen extends StatefulWidget {
  const FinanceScreen({super.key});

  @override
  State<FinanceScreen> createState() => _FinanceScreenState();
}

class _FinanceScreenState extends State<FinanceScreen> {
  final _supabase = Supabase.instance.client;
  final NumberFormat currencyFormatter = NumberFormat.currency(locale: 'en_NG', symbol: '₦');
  List<Map<String, dynamic>> _expenses = [];
  bool _isLoading = true;
  double _totalExpenses = 0;

  @override
  void initState() {
    super.initState();
    _loadExpenses();
  }

  Future<void> _loadExpenses() async {
    try {
      final expenses = await _supabase
          .from('expenses')
          .select('*, profiles(full_name)')
          .order('transaction_date', ascending: false);

      if (mounted) {
        setState(() {
          _expenses = List<Map<String, dynamic>>.from(expenses);
          _totalExpenses = _calculateTotal(expenses);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading expenses: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  double _calculateTotal(List<dynamic> expenses) {
    return expenses.fold(0.0, (sum, expense) {
      final amount = expense['amount'] is int ? expense['amount'] as int : 0;
      return sum + (amount / 100); // Convert from kobo to naira
    });
  }

  Future<void> _refreshExpenses() async {
    setState(() => _isLoading = true);
    await _loadExpenses();
  }

  Color _getCategoryColor(String? category) {
    switch (category?.toLowerCase()) {
      case 'utilities':
        return Colors.blue.shade700;
      case 'salaries':
        return Colors.orange.shade700;
      case 'supplies':
        return Colors.purple.shade700;
      case 'maintenance':
        return Colors.teal.shade700;
      case 'marketing':
        return Colors.pink.shade700;
      default:
        return Colors.grey.shade700;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Financials'),
        backgroundColor: Colors.green.shade800,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshExpenses,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Summary Card
                Card(
                  margin: const EdgeInsets.all(16),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Total Expenses:',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          currencyFormatter.format(_totalExpenses),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.red,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Expenses List
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _refreshExpenses,
                    child: _expenses.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.money_off, size: 64, color: Colors.grey.shade400),
                                const SizedBox(height: 16),
                                const Text(
                                  'No expenses recorded yet.',
                                  style: TextStyle(fontSize: 16),
                                ),
                              ],
                            ),
                          )
                        : ListView.separated(
                            itemCount: _expenses.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final expense = _expenses[index];
                              return _buildExpenseItem(expense);
                            },
                          ),
                  ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final result = await context.push<bool>('/expense/add');
          if (result == true) {
            await _refreshExpenses();
          }
        },
        label: const Text('Add Expense'),
        icon: const Icon(Icons.add),
        backgroundColor: Colors.green.shade800,
      ),
    );
  }

  Widget _buildExpenseItem(Map<String, dynamic> expense) {
    final amount = expense['amount'] is int ? (expense['amount'] as int) / 100 : 0.0;
    final date = DateTime.tryParse(expense['transaction_date']?.toString() ?? '');
    final formattedDate = date != null ? DateFormat.yMMMd().format(date) : 'No date';
    final category = expense['category']?.toString() ?? 'General';
    final description = expense['description']?.toString() ?? 'No description';
    final department = expense['department']?.toString() ?? 'Unassigned';
    final author = (expense['profiles'] as Map<String, dynamic>?)?['full_name'] ?? 'Unknown';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      elevation: 1,
      child: ListTile(
        leading: Icon(Icons.receipt_long, color: _getCategoryColor(category)),
        title: Text(description),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$category • $department'),
            Text('$formattedDate • By: $author'),
          ],
        ),
        trailing: Text(
          currencyFormatter.format(amount),
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: _getCategoryColor(category),
            fontSize: 16,
          ),
        ),
        onTap: () {
          // Show expense details
        },
      ),
    );
  }
}