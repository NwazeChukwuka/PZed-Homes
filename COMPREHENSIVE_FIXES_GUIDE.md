# Comprehensive Fixes Guide - Role Assumption, Dashboards, Navigation & Payments

## ✅ Completed Fixes

### 1. **Fixed Minimart Sales History Null Error**
**File**: `lib/presentation/screens/mini_mart_screen.dart`
- ✅ Added null safety to `payment_method` display
- ✅ Added null safety to `sale_date` parsing
- ✅ Added null safety to `total_amount` formatting

### 2. **Fixed Inventory Screen Role Assumption**
**File**: `lib/presentation/screens/inventory_screen.dart`
- ✅ Changed to use `Consumer<MockAuthService>` to rebuild when role changes
- ✅ Tab controller now rebuilds when bartender role is assumed
- ✅ Make Sale tab now appears when Owner/Manager assumes bartender role
- ✅ Added context-aware role button (shows "Assume Bartender Role")

### 3. **Created Context-Aware Role Button Widget**
**File**: `lib/presentation/widgets/context_aware_role_button.dart`
- ✅ Reusable widget that shows appropriate role button based on screen context
- ✅ Shows "Assume [Role] Role" or "Return to [Original Role]"
- ✅ Only visible to Owner/Manager
- ✅ Helper function to determine suggested role based on context

---

## 🔧 Required Fixes

### **CRITICAL ISSUE: Role Assumption Should NOT Restrict Access**

**Current Problem**: When Owner/Manager assumes a role, they lose access to other parts of the app.

**Solution**: Role assumption should be ADDITIVE, not RESTRICTIVE.

#### Changes Needed in `main_screen.dart`:

```dart
// WRONG (Current):
final effectiveRole = authService.isRoleAssumed ? authService.assumedRole : authService.userRole;

// CORRECT (Should be):
// Owner/Manager should ALWAYS have access to all features
// Role assumption should only ADD functionality, not remove it

List<String> getAccessibleFeatures(AppUser? user, MockAuthService authService) {
  final isOwnerOrManager = user?.roles.any((r) => r == AppRole.owner || r == AppRole.manager) ?? false;
  
  if (isOwnerOrManager) {
    // Owner/Manager ALWAYS have access to everything
    return [
      'dashboard',
      'housekeeping',
      'inventory',
      'kitchen',
      'finance',
      'hr',
      'reporting',
      'store_view',
      // Add ALL features
    ];
  }
  
  // For other users, return features based on their actual role
  // ...existing logic
}
```

---

## 📋 Files That Need Context-Aware Role Buttons

Add `ContextAwareRoleButton` to these screens:

### 1. **Housekeeping Screen**
**File**: `lib/presentation/screens/housekeeping_screen.dart`
```dart
// Add to AppBar actions:
actions: [
  const ContextAwareRoleButton(suggestedRole: AppRole.housekeeper),
  // ...existing actions
],
```

### 2. **Kitchen Screen**
**File**: `lib/presentation/screens/kitchen_dispatch_screen.dart`
```dart
actions: [
  const ContextAwareRoleButton(suggestedRole: AppRole.kitchen_staff),
  // ...existing actions
],
```

### 3. **Storekeeper Dashboard**
**File**: `lib/presentation/screens/storekeeper_dashboard_screen.dart`
```dart
actions: [
  const ContextAwareRoleButton(suggestedRole: AppRole.storekeeper),
  // ...existing actions
],
```

### 4. **Purchasing Screen**
**File**: `lib/presentation/screens/confirm_purchases_screen.dart`
```dart
actions: [
  const ContextAwareRoleButton(suggestedRole: AppRole.purchaser),
  // ...existing actions
],
```

### 5. **Finance Screen**
**File**: `lib/presentation/screens/comprehensive_finance_screen.dart`
```dart
actions: [
  const ContextAwareRoleButton(suggestedRole: AppRole.accountant),
  // ...existing actions
],
```

### 6. **HR Screen**
**File**: `lib/presentation/screens/hr_screen.dart`
```dart
actions: [
  const ContextAwareRoleButton(suggestedRole: AppRole.hr),
  // ...existing actions
],
```

### 7. **Minimart Screen**
**File**: `lib/presentation/screens/mini_mart_screen.dart`
```dart
actions: [
  const ContextAwareRoleButton(suggestedRole: AppRole.receptionist),
  // ...existing actions
],
```

### 8. **Booking/Reception Screens**
**File**: `lib/presentation/widgets/booking_form_bottom_sheet.dart`
- Add role button to show "Assume Receptionist Role"
- When assumed, Owner/Manager can create bookings

---

## 🎯 Department-Specific Dashboards

### **Problem**: All staff see the room booking dashboard

### **Solution**: Create role-specific dashboard views

#### Dashboard Screen Changes Needed:

**File**: `lib/presentation/screens/dashboard_screen.dart`

```dart
Widget _buildRoleSpecificDashboard(BuildContext context, AppUser user) {
  // Get the ACTUAL role (not assumed role for dashboard purposes)
  final actualRole = user.role;
  
  switch (actualRole) {
    case AppRole.owner:
    case AppRole.manager:
      return _buildManagementDashboard(context);
    
    case AppRole.receptionist:
      return _buildReceptionistDashboard(context);
    
    case AppRole.bartender:
      return _buildBartenderDashboard(context);
    
    case AppRole.kitchen_staff:
      return _buildKitchenDashboard(context);
    
    case AppRole.housekeeper:
    case AppRole.cleaner:
    case AppRole.laundry_attendant:
      return _buildHousekeepingDashboard(context);
    
    case AppRole.storekeeper:
      return _buildStorekeeperDashboard(context);
    
    case AppRole.purchaser:
      return _buildPurchaserDashboard(context);
    
    case AppRole.accountant:
      return _buildAccountantDashboard(context);
    
    case AppRole.hr:
      return _buildHRDashboard(context);
    
    default:
      return _buildGenericDashboard(context);
  }
}

// Bartender Dashboard - Department Specific
Widget _buildBartenderDashboard(BuildContext context) {
  // Get bartender's assigned bar (VIP or Outside)
  final assignedBar = _getAssignedBar(); // 'vip_bar' or 'outside_bar'
  
  return Column(
    children: [
      Text('${assignedBar == 'vip_bar' ? 'VIP Bar' : 'Outside Bar'} Dashboard'),
      // Show ONLY their bar's data
      _buildBarSalesCard(assignedBar),
      _buildBarInventoryCard(assignedBar),
      _buildBarShiftStatus(assignedBar),
      // NO access to other bar's data
      // NO room booking information
    ],
  );
}

// Receptionist Dashboard
Widget _buildReceptionistDashboard(BuildContext context) {
  return Column(
    children: [
      Text('Reception Dashboard'),
      _buildTodayCheckIns(),
      _buildTodayCheckOuts(),
      _buildPendingBookings(),
      _buildRoomAvailability(),
      _buildMiniMartSummary(), // Minimart is managed by reception
      // NO kitchen data
      // NO bar data
    ],
  );
}

// Kitchen Dashboard
Widget _buildKitchenDashboard(BuildContext context) {
  return Column(
    children: [
      Text('Kitchen Dashboard'),
      _buildPendingOrders(),
      _buildKitchenInventory(),
      _buildDispatchHistory(),
      // NO room bookings
      // NO bar data
    ],
  );
}
```

---

## 🔙 Add Back Buttons to Forms

### Files That Need Back Buttons:

1. **Booking Form**
   - `lib/presentation/widgets/booking_form_bottom_sheet.dart`
   - Add back button to AppBar or as a cancel button

2. **Add Item Dialogs** (All screens with forms)
   - Inventory screen
   - Minimart screen
   - Kitchen screen
   - Finance screen

**Pattern**:
```dart
AppBar(
  leading: IconButton(
    icon: const Icon(Icons.arrow_back),
    onPressed: () => Navigator.of(context).pop(),
  ),
  title: const Text('Create Booking'),
)

// OR for dialogs:
actions: [
  TextButton(
    onPressed: () => Navigator.of(context).pop(),
    child: const Text('Cancel'),
  ),
  ElevatedButton(
    onPressed: _submitForm,
    child: const Text('Submit'),
  ),
],
```

---

## 💳 Add Credit Payment Method

### Files That Need Credit Payment:

1. **Inventory Screen** (Make Sale)
2. **Minimart Screen** (Make Sale)
3. **Booking Form** (Room Payment)
4. **Kitchen Screen** (If applicable)

### Implementation Pattern:

```dart
// Add to payment method dropdown
String _paymentMethod = 'cash';

DropdownButtonFormField<String>(
  value: _paymentMethod,
  decoration: const InputDecoration(labelText: 'Payment Method'),
  items: const [
    DropdownMenuItem(value: 'cash', child: Text('Cash')),
    DropdownMenuItem(value: 'card', child: Text('Card')),
    DropdownMenuItem(value: 'transfer', child: Text('Transfer')),
    DropdownMenuItem(value: 'credit', child: Text('Credit (Pay Later)')), // NEW
  ],
  onChanged: (value) => setState(() => _paymentMethod = value!),
),

// When credit is selected, show customer info fields
if (_paymentMethod == 'credit') ...[
  TextField(
    controller: _customerNameController,
    decoration: const InputDecoration(
      labelText: 'Customer Name *',
      hintText: 'Required for credit',
    ),
  ),
  TextField(
    controller: _customerPhoneController,
    decoration: const InputDecoration(
      labelText: 'Customer Phone *',
      hintText: 'Required for credit',
    ),
  ),
],

// When submitting with credit:
if (_paymentMethod == 'credit') {
  // Create debt record
  await _dataService.recordDebt({
    'debtor_name': _customerNameController.text,
    'debtor_phone': _customerPhoneController.text,
    'debtor_type': 'customer',
    'amount': _saleTotal,
    'owed_to': 'P-ZED Homes',
    'reason': 'Sale on credit - ${_getSaleDescription()}',
    'date': DateTime.now().toIso8601String(),
    'due_date': DateTime.now().add(Duration(days: 30)).toIso8601String(),
    'status': 'pending',
    'department': _getCurrentDepartment(), // 'minimart', 'vip_bar', etc.
  });
}
```

---

## 💰 Debt Payment/Update System

### Add to Finance Screen:

**File**: `lib/presentation/screens/comprehensive_finance_screen.dart`

```dart
// In Debts Tab, add payment button to each debt
ListTile(
  title: Text(debt['debtor_name']),
  subtitle: Text('₦${debt['amount']} - ${debt['status']}'),
  trailing: debt['status'] == 'pending'
      ? ElevatedButton(
          onPressed: () => _showPayDebtDialog(debt),
          child: const Text('Record Payment'),
        )
      : const Chip(label: Text('PAID')),
),

// Payment Dialog
void _showPayDebtDialog(Map<String, dynamic> debt) {
  final amountController = TextEditingController();
  
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Record Debt Payment'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Debtor: ${debt['debtor_name']}'),
          Text('Total Debt: ₦${debt['amount']}'),
          Text('Remaining: ₦${debt['remaining_amount'] ?? debt['amount']}'),
          const SizedBox(height: 16),
          TextField(
            controller: amountController,
            decoration: const InputDecoration(
              labelText: 'Payment Amount',
              prefixText: '₦',
            ),
            keyboardType: TextInputType.number,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () async {
            final paymentAmount = double.parse(amountController.text);
            await _recordDebtPayment(debt, paymentAmount);
            Navigator.pop(context);
          },
          child: const Text('Record Payment'),
        ),
      ],
    ),
  );
}

Future<void> _recordDebtPayment(Map<String, dynamic> debt, double amount) async {
  // Record the payment
  await _dataService.recordDebtRecovery({
    'debt_id': debt['id'],
    'debtor_name': debt['debtor_name'],
    'amount': amount,
    'date': DateTime.now().toIso8601String(),
    'notes': 'Partial payment',
    'recorded_by': _currentUser.id,
  });
  
  // Update debt status
  final remainingAmount = (debt['remaining_amount'] ?? debt['amount']) - amount;
  if (remainingAmount <= 0) {
    await _dataService.updateDebtStatus(debt['id'], 'paid');
  } else {
    await _dataService.updateDebtRemainingAmount(debt['id'], remainingAmount);
  }
  
  // Reload data
  await _loadFinancialData();
}
```

---

## 📊 Summary of Changes

### Priority 1 (Critical):
1. ✅ Fix minimart null errors
2. ✅ Fix inventory role assumption
3. ✅ Create context-aware role button
4. ⚠️ **Fix role assumption to not restrict access** (MOST IMPORTANT)
5. ⚠️ Add back buttons to all forms
6. ⚠️ Add credit payment method

### Priority 2 (Important):
7. ⚠️ Add role buttons to all screens
8. ⚠️ Create department-specific dashboards
9. ⚠️ Add debt payment system

### Priority 3 (Enhancement):
10. ⚠️ Add booking functionality for assumed receptionist role
11. ⚠️ Improve role assumption UX

---

## 🧪 Testing Checklist

- [ ] Owner can assume bartender role and see Make Sale tab in inventory
- [ ] Owner can assume receptionist role and create bookings
- [ ] Owner can still access all pages when assuming a role
- [ ] Bartender only sees their assigned bar's dashboard
- [ ] Receptionist only sees reception-related dashboard
- [ ] Credit payment creates debt record
- [ ] Debt payment updates debt status correctly
- [ ] All forms have back/cancel buttons
- [ ] No null errors in minimart sales history
- [ ] Role buttons appear on all relevant screens

---

## 📝 Next Steps

1. Fix the main_screen.dart to make role assumption additive
2. Add ContextAwareRoleButton to all screens
3. Create department-specific dashboard views
4. Implement credit payment system
5. Add debt payment functionality
6. Add back buttons to all forms
7. Test thoroughly with different roles
