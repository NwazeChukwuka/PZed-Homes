// Location: lib/presentation/widgets/booking_form_bottom_sheet.dart

import 'package:flutter/material.dart';

class BookingFormBottomSheet extends StatefulWidget {
  // We'll use a callback to notify the parent screen when booking is confirmed
  final Function(String name, String contact) onConfirm;

  const BookingFormBottomSheet({super.key, required this.onConfirm});

  @override
  State<BookingFormBottomSheet> createState() => _BookingFormBottomSheetState();
}

class _BookingFormBottomSheetState extends State<BookingFormBottomSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _contactController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _contactController.dispose();
    super.dispose();
  }

  void _submitForm() {
    // This validates the form fields
    if (_formKey.currentState!.validate()) {
      // If valid, call the onConfirm callback with the entered data
      widget.onConfirm(_nameController.text, _contactController.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Padding to account for the keyboard
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 16,
          right: 16,
          top: 16),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min, // Make the sheet only as tall as its content
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Enter Your Details',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Full Name',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter your name';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _contactController,
              decoration: const InputDecoration(
                labelText: 'Email or Phone Number',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter your contact details';
                }
                return null;
              },
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                padding: const EdgeInsets.symmetric(vertical: 16),
                textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              onPressed: _submitForm,
              child: const Text('Confirm Booking'),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}