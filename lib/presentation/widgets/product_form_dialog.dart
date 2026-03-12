import 'package:flutter/material.dart';
import 'package:pzed_homes/core/config/product_catalog_config.dart';
import 'package:pzed_homes/core/services/payment_service.dart';

/// Generic edit dialog for product catalog (Name, Price(s), Category).
/// Adapts to table via [tableName] using [ProductCatalogConfig.priceFieldsByTable].
/// Prices are entered in Naira and saved as Kobo via [PaymentService].
/// When a price changes, [onSave] is called with optional [priceChangeDetails] for auditing.
class ProductFormDialog extends StatefulWidget {
  final String tableName;
  final Map<String, dynamic> product;
  /// Called with [updates] and optionally [priceChangeDetails] when any price changed (e.g. "Changed X price from ₦1,500 to ₦1,800").
  final Future<void> Function(Map<String, dynamic> updates, [String? priceChangeDetails]) onSave;

  const ProductFormDialog({
    super.key,
    required this.tableName,
    required this.product,
    required this.onSave,
  });

  @override
  State<ProductFormDialog> createState() => _ProductFormDialogState();
}

class _ProductFormDialogState extends State<ProductFormDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _categoryController;
  final Map<String, TextEditingController> _priceControllers = {};

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.product['name']?.toString() ?? '',
    );
    _categoryController = TextEditingController(
      text: widget.product['category']?.toString() ?? '',
    );
    final priceFields = ProductCatalogConfig.priceFieldsByTable[widget.tableName] ?? [];
    for (final f in priceFields) {
      final kobo = (widget.product[f.key] as num?)?.toInt() ?? 0;
      final naira = PaymentService.koboToNaira(kobo);
      _priceControllers[f.key] = TextEditingController(
        text: naira > 0 ? naira.toStringAsFixed(2) : '',
      );
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _categoryController.dispose();
    for (final c in _priceControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name is required')),
      );
      return;
    }
    final updates = <String, dynamic>{
      'name': name,
      'category': _categoryController.text.trim().isEmpty ? null : _categoryController.text.trim(),
    };
    final priceFields = ProductCatalogConfig.priceFieldsByTable[widget.tableName] ?? [];
    for (final f in priceFields) {
      final c = _priceControllers[f.key];
      if (c != null && c.text.trim().isNotEmpty) {
        final naira = double.tryParse(c.text.trim());
        if (naira != null && naira >= 0) {
          updates[f.key] = PaymentService.nairaToKobo(naira);
        }
      }
    }
    // Build audit log for price changes (e.g. "Changed [Item Name] price from ₦1,500 to ₦1,800")
    String? priceChangeDetails;
    final itemName = widget.product['name']?.toString() ?? 'Item';
    final lines = <String>[];
    for (final f in priceFields) {
      final oldKobo = (widget.product[f.key] as num?)?.toInt() ?? 0;
      final newKobo = updates[f.key] as int?;
      if (newKobo != null && newKobo != oldKobo) {
        final oldNaira = PaymentService.koboToNaira(oldKobo);
        final newNaira = PaymentService.koboToNaira(newKobo);
        lines.add(
          'Changed $itemName ${f.label.replaceAll(' (₦)', '')} from ₦${oldNaira.toStringAsFixed(2)} to ₦${newNaira.toStringAsFixed(2)}',
        );
      }
    }
    if (lines.isNotEmpty) {
      priceChangeDetails = lines.join('\n');
    }
    await widget.onSave(updates, priceChangeDetails);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final priceFields = ProductCatalogConfig.priceFieldsByTable[widget.tableName] ?? [];
    return AlertDialog(
      title: const Text('Edit Product'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Name',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _categoryController,
              decoration: const InputDecoration(
                labelText: 'Category',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.words,
            ),
            ...priceFields.map((f) {
              final c = _priceControllers[f.key];
              if (c == null) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 16),
                child: TextField(
                  controller: c,
                  decoration: InputDecoration(
                    labelText: f.label,
                    border: const OutlineInputBorder(),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
              );
            }),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _submit,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// Shows a standard "Are you sure?" confirmation before deleting a product.
/// When user taps Delete, [onConfirm] is awaited; dialog shows loading and only closes on success.
Future<void> showDeleteProductConfirmation(
  BuildContext context, {
  required String productName,
  required Future<void> Function() onConfirm,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _DeleteProductConfirmationDialog(
      productName: productName,
      onConfirm: onConfirm,
    ),
  );
  // Dialog pops with true only after onConfirm completed successfully; no follow-up needed
  if (confirmed == true && context.mounted) {
    // Caller already refreshed in onConfirm
  }
}

class _DeleteProductConfirmationDialog extends StatefulWidget {
  final String productName;
  final Future<void> Function() onConfirm;

  const _DeleteProductConfirmationDialog({
    required this.productName,
    required this.onConfirm,
  });

  @override
  State<_DeleteProductConfirmationDialog> createState() =>
      _DeleteProductConfirmationDialogState();
}

class _DeleteProductConfirmationDialogState
    extends State<_DeleteProductConfirmationDialog> {
  bool _isDeleting = false;
  String? _errorMessage;

  Future<void> _onDeletePressed() async {
    if (_isDeleting) return;
    setState(() {
      _isDeleting = true;
      _errorMessage = null;
    });
    try {
      await widget.onConfirm();
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDeleting = false;
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Delete Product'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Are you sure you want to delete "${widget.productName}"? This action cannot be undone.',
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 12),
            Text(
              _errorMessage!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isDeleting ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _isDeleting ? null : _onDeletePressed,
          style: TextButton.styleFrom(foregroundColor: Colors.red),
          child: _isDeleting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Delete'),
        ),
      ],
    );
  }
}
