// Location: lib/core/services/data_service.dart

import '../services/database_service.dart';
import '../../data/mock_data.dart';

class DataService {
  static final DataService _instance = DataService._internal();
  factory DataService() => _instance;
  DataService._internal();

  final DatabaseService _databaseService = DatabaseService();
  bool _useMockData = true; // Set to false when ready to use real database

  // Mock data methods
  Future<List<Map<String, dynamic>>> getBookings() async {
    if (_useMockData) {
      return MockData.getBookings();
    }
    return await _databaseService.getBookings();
  }

  Future<List<Map<String, dynamic>>> getRooms() async {
    if (_useMockData) {
      return MockData.getRooms();
    }
    return await _databaseService.getRooms();
  }

  Future<List<Map<String, dynamic>>> getStaffProfiles() async {
    if (_useMockData) {
      return MockData.getStaffProfiles();
    }
    // For now, return mock data even when not using mock data
    return MockData.getStaffProfiles();
  }

  Future<List<Map<String, dynamic>>> getInventoryItems() async {
    if (_useMockData) {
      return MockData.getInventoryItems();
    }
    // For now, return mock data even when not using mock data
    return MockData.getInventoryItems();
  }

  Future<List<Map<String, dynamic>>> getStockTransactions() async {
    if (_useMockData) {
      return MockData.getStockTransactions();
    }
    // For now, return mock data even when not using mock data
    return MockData.getStockTransactions();
  }

  Future<List<Map<String, dynamic>>> getRecentPurchases() async {
    if (_useMockData) {
      return MockData.getRecentPurchases();
    }
    return MockData.getRecentPurchases();
  }

  Future<List<Map<String, dynamic>>> getDebts() async {
    if (_useMockData) {
      return MockData.getDebts();
    }
    return MockData.getDebts();
  }

  Future<List<Map<String, dynamic>>> getCheckedInGuests() async {
    if (_useMockData) {
      return MockData.getCheckedInGuests();
    }
    return MockData.getCheckedInGuests();
  }

  Future<List<Map<String, dynamic>>> getDepartmentSales(String department) async {
    if (_useMockData) {
      return MockData.getDepartmentSales(department);
    }
    return MockData.getDepartmentSales(department);
  }

  Future<List<Map<String, dynamic>>> getExpenses() async {
    if (_useMockData) {
      return MockData.getExpenses();
    }
    // For now, return mock data even when not using mock data
    return MockData.getExpenses();
  }

  Future<List<Map<String, dynamic>>> getIncomeRecords() async {
    if (_useMockData) {
      return MockData.getIncomeRecords();
    }
    // For now, return mock data even when not using mock data
    return MockData.getIncomeRecords();
  }

  Future<List<Map<String, dynamic>>> getPayrollRecords() async {
    if (_useMockData) {
      return MockData.getPayrollRecords();
    }
    // For now, return mock data even when not using mock data
    return MockData.getPayrollRecords();
  }

  Future<List<Map<String, dynamic>>> getCashDeposits() async {
    if (_useMockData) {
      return MockData.getCashDeposits();
    }
    // For now, return mock data even when not using mock data
    return MockData.getCashDeposits();
  }

  // Financial data methods
  Future<Map<String, dynamic>> getFinancialSummary() async {
    if (_useMockData) {
      return MockData.getFinancialSummary();
    }
    // For now, return mock data even when not using mock data
    return MockData.getFinancialSummary();
  }

  Future<List<Map<String, dynamic>>> getDepartmentPerformance() async {
    if (_useMockData) {
      return MockData.getDepartmentPerformance();
    }
    // For now, return mock data even when not using mock data
    return MockData.getDepartmentPerformance();
  }

  // HR methods
  Future<void> assignRoleToStaff(String staffId, String role, {bool isTemporary = false, DateTime? expiryDate}) async {
    if (_useMockData) {
      MockData.assignRoleToStaff(staffId, role, isTemporary: isTemporary, expiryDate: expiryDate);
    } else {
      // For now, use mock data even when not using mock data
      MockData.assignRoleToStaff(staffId, role, isTemporary: isTemporary, expiryDate: expiryDate);
    }
  }

  Future<List<Map<String, dynamic>>> getStaffRoleAssignments() async {
    if (_useMockData) {
      return MockData.getStaffRoleAssignments();
    }
    // For now, return mock data even when not using mock data
    return MockData.getStaffRoleAssignments();
  }

  // Inventory methods
  Future<void> addInventoryItem(Map<String, dynamic> item) async {
    if (_useMockData) {
      MockData.addInventoryItem(item);
    } else {
      // For now, use mock data even when not using mock data
      MockData.addInventoryItem(item);
    }
  }

  Future<void> recordStockTransaction(Map<String, dynamic> transaction) async {
    if (_useMockData) {
      MockData.recordStockTransaction(transaction);
    } else {
      // For now, use mock data even when not using mock data
      MockData.recordStockTransaction(transaction);
    }
  }

  // Financial recording methods
  Future<void> addExpense(Map<String, dynamic> expense) async {
    if (_useMockData) {
      MockData.addExpense(expense);
    } else {
      // For now, use mock data even when not using mock data
      MockData.addExpense(expense);
    }
  }

  Future<void> addIncomeRecord(Map<String, dynamic> income) async {
    if (_useMockData) {
      MockData.addIncomeRecord(income);
    } else {
      // For now, use mock data even when not using mock data
      MockData.addIncomeRecord(income);
    }
  }

  Future<void> addCashDeposit(Map<String, dynamic> deposit) async {
    if (_useMockData) {
      MockData.addCashDeposit(deposit);
    } else {
      // For now, use mock data even when not using mock data
      MockData.addCashDeposit(deposit);
    }
  }

  Future<void> addPayrollRecord(Map<String, dynamic> payroll) async {
    if (_useMockData) {
      MockData.addPayrollRecord(payroll);
    } else {
      // For now, use mock data even when not using mock data
      MockData.addPayrollRecord(payroll);
    }
  }

  Future<void> recordDebt(Map<String, dynamic> debt) async {
    if (_useMockData) {
      MockData.recordDebt(debt);
    } else {
      // For now, use mock data even when not using mock data
      MockData.recordDebt(debt);
    }
  }

  // Dashboard statistics
  Future<Map<String, dynamic>> getDashboardStats() async {
    if (_useMockData) {
      return MockData.getDashboardStats();
    }
    // For now, return mock data even when not using mock data
    return MockData.getDashboardStats();
  }

  Future<List<Map<String, dynamic>>> getRecentActivities() async {
    if (_useMockData) {
      return MockData.getRecentActivities();
    }
    // For now, return mock data even when not using mock data
    return MockData.getRecentActivities();
  }

  // Booking methods
  Future<void> updateBookingStatus(String bookingId, String newStatus) async {
    if (_useMockData) {
      MockData.updateBookingStatus(bookingId, newStatus);
    } else {
      // For now, use mock data even when not using mock data
      MockData.updateBookingStatus(bookingId, newStatus);
    }
  }

  Future<void> createBooking(Map<String, dynamic> booking) async {
    if (_useMockData) {
      MockData.createBooking(booking);
    } else {
      // For now, use mock data even when not using mock data
      MockData.createBooking(booking);
    }
  }

  // Mini Mart methods
  Future<List<Map<String, dynamic>>> getMiniMartItems() async {
    if (_useMockData) {
      return MockData.getMiniMartItems();
    }
    return MockData.getMiniMartItems();
  }

  Future<List<Map<String, dynamic>>> getMiniMartSales() async {
    if (_useMockData) {
      return MockData.getMiniMartSales();
    }
    return MockData.getMiniMartSales();
  }

  // Kitchen methods
  Future<List<Map<String, dynamic>>> getKitchenOrders() async {
    if (_useMockData) {
      return MockData.getKitchenOrders();
    }
    return MockData.getKitchenOrders();
  }

  Future<List<Map<String, dynamic>>> getMenuItems() async {
    if (_useMockData) {
      return MockData.getMenuItems();
    }
    return MockData.getMenuItems();
  }

  // POS methods
  Future<List<Map<String, dynamic>>> getPosMenuItems() async {
    if (_useMockData) {
      return MockData.getMenuItems();
    }
    return MockData.getMenuItems();
  }

  Future<List<Map<String, dynamic>>> getPosCheckedInGuests() async {
    if (_useMockData) {
      return MockData.getCheckedInGuests();
    }
    return MockData.getCheckedInGuests();
  }
}
