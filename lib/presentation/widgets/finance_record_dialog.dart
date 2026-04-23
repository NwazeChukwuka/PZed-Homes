import 'package:flutter/material.dart';
import '../../core/error/error_handler.dart';

class _FinanceDialogColors {
  static const Color emeraldGreen = Color(0xFF009B77);
  static const Color goldAccent = Color(0xFFD4AF37);
}

class FinanceRecordDialog extends StatefulWidget {
  final String title;
  final List<Widget> formFields;
  final Future<bool> Function() onSave;
  final VoidCallback? onSuccess;

  const FinanceRecordDialog({
    super.key,
    required this.title,
    required this.formFields,
    required this.onSave,
    this.onSuccess,
  });

  @override
  State<FinanceRecordDialog> createState() => _FinanceRecordDialogState();
}

class _FinanceRecordDialogState extends State<FinanceRecordDialog> {
  bool _isSaving = false;

  Future<void> _handleRecord() async {
    if (_isSaving) return;
    if (!mounted) return;
    setState(() => _isSaving = true);

    try {
      final success = await widget.onSave();
      if (success && mounted) {
        widget.onSuccess?.call();
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ErrorHandler.getFriendlyErrorMessage(e)),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: widget.formFields,
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isSaving ? null : _handleRecord,
          style: ElevatedButton.styleFrom(
            backgroundColor: _FinanceDialogColors.emeraldGreen,
            foregroundColor: Colors.white,
          ),
          child: _isSaving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(_FinanceDialogColors.goldAccent),
                  ),
                )
              : const Text('Record'),
        ),
      ],
    );
  }
}

