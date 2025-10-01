// Location: lib/presentation/widgets/inventory_list_item.dart

import 'package:flutter/material.dart';
import 'package:pzed_homes/data/data.dart';

class InventoryListItem extends StatelessWidget {
  final StockItem item;
  final VoidCallback onTap;

  const InventoryListItem({
    super.key,
    required this.item,
    required this.onTap, 
  });

  @override
  Widget build(BuildContext context) {
    final isLowStock = item.currentQuantity <= item.reorderLevel;

    return ListTile(
      onTap: onTap,
      leading: Icon(
        isLowStock ? Icons.warning_amber_rounded : Icons.inventory_2_outlined,
        color: isLowStock ? Colors.red : Colors.grey[600],
      ),
      title: Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text('Reorder at ${item.reorderLevel} ${item.unit}'),
      trailing: Text(
        '${item.currentQuantity} ${item.unit}',
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: isLowStock ? Colors.red : Theme.of(context).textTheme.bodyLarge?.color,
        ),
      ),
    );
  }
}