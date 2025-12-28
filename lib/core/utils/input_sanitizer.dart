/// Utility class for sanitizing user inputs to prevent XSS and other security issues
class InputSanitizer {
  /// Sanitize text input by trimming and removing potentially dangerous characters
  /// This helps prevent XSS attacks in user-generated content
  static String sanitizeText(String input) {
    if (input.isEmpty) return input;
    
    // Trim whitespace
    String sanitized = input.trim();
    
    // Remove HTML/XML tags to prevent XSS
    sanitized = sanitized.replaceAll(RegExp(r'<[^>]*>'), '');
    
    // Remove script tags and event handlers
    sanitized = sanitized.replaceAll(RegExp(r'javascript:', caseSensitive: false), '');
    sanitized = sanitized.replaceAll(RegExp(r'on\w+\s*=', caseSensitive: false), '');
    
    return sanitized;
  }

  /// Sanitize email input
  static String sanitizeEmail(String email) {
    return email.trim().toLowerCase();
  }

  /// Sanitize phone number input
  static String sanitizePhone(String phone) {
    // Remove all non-digit characters except + at the start
    String sanitized = phone.trim();
    if (sanitized.startsWith('+')) {
      sanitized = '+' + sanitized.substring(1).replaceAll(RegExp(r'\D'), '');
    } else {
      sanitized = sanitized.replaceAll(RegExp(r'\D'), '');
    }
    return sanitized;
  }

  /// Sanitize numeric input (removes non-numeric characters)
  static String sanitizeNumeric(String input) {
    return input.replaceAll(RegExp(r'\D'), '');
  }

  /// Validate and sanitize amount input
  static double? sanitizeAmount(String input) {
    final cleaned = input.trim().replaceAll(RegExp(r'[^\d.]'), '');
    return double.tryParse(cleaned);
  }

  /// Sanitize description/notes (allows more characters but still removes dangerous ones)
  static String sanitizeDescription(String input) {
    if (input.isEmpty) return input;
    
    String sanitized = input.trim();
    
    // Remove script tags and event handlers
    sanitized = sanitized.replaceAll(RegExp(r'<script[^>]*>.*?</script>', caseSensitive: false, dotAll: true), '');
    sanitized = sanitized.replaceAll(RegExp(r'javascript:', caseSensitive: false), '');
    sanitized = sanitized.replaceAll(RegExp(r'on\w+\s*=', caseSensitive: false), '');
    
    return sanitized;
  }
}

