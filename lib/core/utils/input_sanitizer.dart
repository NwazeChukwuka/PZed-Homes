class InputSanitizer {
  static String sanitizeText(String input) {
    if (input.isEmpty) return input;
    
    String sanitized = input.trim();
    
    sanitized = sanitized.replaceAll(RegExp(r'<[^>]*>'), '');
    
    sanitized = sanitized.replaceAll(RegExp(r'javascript:', caseSensitive: false), '');
    sanitized = sanitized.replaceAll(RegExp(r'on\w+\s*=', caseSensitive: false), '');
    
    return sanitized;
  }

  static String sanitizeEmail(String email) {
    return email.trim().toLowerCase();
  }

  static String sanitizePhone(String phone) {
    String sanitized = phone.trim();
    if (sanitized.startsWith('+')) {
      sanitized = '+${sanitized.substring(1).replaceAll(RegExp(r'\D'), '')}';
    } else {
      sanitized = sanitized.replaceAll(RegExp(r'\D'), '');
    }
    return sanitized;
  }

  static String sanitizeNumeric(String input) {
    return input.replaceAll(RegExp(r'\D'), '');
  }

  static double? sanitizeAmount(String input) {
    final cleaned = input.trim().replaceAll(RegExp(r'[^\d.]'), '');
    return double.tryParse(cleaned);
  }

  static String sanitizeDescription(String input) {
    if (input.isEmpty) return input;
    
    String sanitized = input.trim();
    
    sanitized = sanitized.replaceAll(RegExp(r'<script[^>]*>.*?</script>', caseSensitive: false, dotAll: true), '');
    sanitized = sanitized.replaceAll(RegExp(r'javascript:', caseSensitive: false), '');
    sanitized = sanitized.replaceAll(RegExp(r'on\w+\s*=', caseSensitive: false), '');
    
    return sanitized;
  }
}



