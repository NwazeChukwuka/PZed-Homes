import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pzed_homes/core/services/payment_service.dart';

/// Unified sale/transaction list item displaying:
/// Product Name × Quantity, Staff Name, Payment Method, and Timestamp.
class SaleListItem extends StatelessWidget {
  final String productName;
  final int quantity;
  final String staffName;
  final String paymentMethod;
  final String timestamp;
  final int? totalAmountKobo;
  final IconData icon;
  final Color iconColor;

  const SaleListItem({
    super.key,
    required this.productName,
    required this.quantity,
    required this.staffName,
    required this.paymentMethod,
    required this.timestamp,
    this.totalAmountKobo,
    this.icon = Icons.point_of_sale,
    this.iconColor = Colors.orange,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: Icon(icon, color: iconColor),
        title: Text('$productName × $quantity'),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Staff: $staffName'),
            Text('Payment: ${paymentMethod.toUpperCase()}'),
            Text(timestamp, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
          ],
        ),
        trailing: totalAmountKobo != null && totalAmountKobo! > 0
            ? Text(
                '₦${NumberFormat('#,##0.00').format(PaymentService.koboToNaira(totalAmountKobo!))}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              )
            : null,
      ),
    );
  }
}
