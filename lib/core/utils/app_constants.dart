import 'package:intl/intl.dart';

class AppConstants {
 // API
 static const String apiBaseUrl     = 'https://nexora-backend.kindocean-79553321.southafricanorth.azurecontainerapps.io';
 static const String appVersion     = '3.1.118';
 static const String appName        = 'Nexora';
 // Hive box names
 static const String authBox        = 'auth';
 static const String settingsBox    = 'settings';
 static const String customersBox   = 'customers';
 // BLE
 static const String weightServiceUuid = '00001808-0000-1000-8000-00805f9b34fb';
 static const String weightCharUuid    = '00002a98-0000-1000-8000-00805f9b34fb';
 static const double bleStableThreshold = 0.05; // kg
 static const int    bleBufferSize      = 5;
 // Collection
 static const List<String> milkGrades   = ['A', 'B', 'C'];
 static const double defaultPricePerKg  = 50.0;
 // Inventory categories
 static const List<String> inventoryCategories = [
   'raw_milk', 'processed', 'packaging',
   'feed', 'vet_supplies', 'equipment', 'other'
 ];
 // Payment methods
 static const List<String> paymentMethods = ['mpesa', 'cash', 'bank', 'credit'];
 // Date formats
 static final DateFormat dateFormat      = DateFormat('dd MMM yyyy');
 static final DateFormat dateTimeFormat  = DateFormat('dd MMM yyyy, HH:mm');
 static final DateFormat timeFormat      = DateFormat('HH:mm');
 static final DateFormat apiDateFormat   = DateFormat('yyyy-MM-dd');
}
class AppFormatters {
  static final _kes = NumberFormat.currency(
    locale: 'en_KE',
    symbol: 'KSh ',
    decimalDigits: 2,
  );
static final _kesCompact = NumberFormat.compactCurrency(
    locale: 'en_KE',
    symbol: 'KSh ',
    decimalDigits: 1,
  );
static final _number = NumberFormat('#,##0.##');
  /// Format as KSh 1,234.50
static String currency(double amount) => _kes.format(amount);
  /// Format as KSh 1.2k or KSh 1.2M
static String currencyCompact(double amount) => _kesCompact.format(amount);
  /// Format number with commas
static String number(double value) => _number.format(value);
  /// Format weight
static String weight(double kg) => '${_number.format(kg)} kg';
  /// Format date
static String date(DateTime dt) => AppConstants.dateFormat.format(dt);
  /// Format datetime
static String dateTime(DateTime dt) => AppConstants.dateTimeFormat.format(dt);
  /// Format time only
static String time(DateTime dt) => AppConstants.timeFormat.format(dt);
  /// Relative time (e.g. "2 hours ago")
static String relative(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60)  return 'Just now';
    if (diff.inMinutes < 60)  return '${diff.inMinutes}m ago';
    if (diff.inHours < 24)    return '${diff.inHours}h ago';
    if (diff.inDays < 7)      return '${diff.inDays}d ago';
    return date(dt);
  }
  /// Initials from full name (e.g. "Peter Muriithi" → "PM")
static String initials(String name) {
    final parts = name.trim().split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase();
  }
}
class AppValidators {
  static String? required(String? value, [String field = 'This field']) {
      if (value == null || value.trim().isEmpty) return '$field is required';
      return null;
    }
  static String? phone(String? value) {
      if (value == null || value.isEmpty) return 'Phone number required';
      final clean = value.replaceAll(RegExp(r'[\s\-\+]'), '');
      if (!RegExp(r'^[0-9]{9,12}$').hasMatch(clean)) return 'Invalid phone number';
      return null;
    }
  static String? positiveNumber(String? value, [String field = 'Value']) {
      if (value == null || value.isEmpty) return '$field is required';
      final n = double.tryParse(value);
      if (n == null) return 'Enter a valid number';
      if (n <= 0) return '$field must be greater than 0';
      return null;
    }
  static String? email(String? value) {
      if (value == null || value.isEmpty) return 'Email is required';
      if (!RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(value)) return 'Invalid email address';
      return null;
    }
}
