import 'package:flutter/material.dart';

/// Universal square product card for Inventory, Mini Mart, and Kitchen grids.
/// - Icon area: 65% of card height
/// - Text area: name (max 2 lines, scales down if too long) + price on next line
class ProductCard extends StatelessWidget {
  final String name;
  final String price;
  final IconData icon;
  final Color? backgroundColor;
  final Border? border;
  final VoidCallback onTap;

  const ProductCard({
    super.key,
    required this.name,
    required this.price,
    this.icon = Icons.inventory,
    this.backgroundColor,
    this.border,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: backgroundColor ?? Colors.white,
            border: border,
            borderRadius: BorderRadius.circular(8),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final iconHeight = constraints.maxHeight * 0.65;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: iconHeight,
                    width: double.infinity,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Icon(icon, size: 32),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Name: max 2 lines, uniform base font; scales down if too long
                        SizedBox(
                          height: 28,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w500,
                                fontSize: 11,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.clip,
                            ),
                          ),
                        ),
                        const SizedBox(height: 2),
                        // Price: fixed size, line 2 (short names) or line 3 (long names)
                        Text(
                          price,
                          style: TextStyle(
                            color: Colors.green[700],
                            fontWeight: FontWeight.bold,
                            fontSize: 10,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
