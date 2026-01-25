import 'package:intl/intl.dart';

class Formatters {
  static final _currencyFormat = NumberFormat('#,##0.00', 'en_US');
  
  /// Format a number with comma separators and 2 decimal places
  /// e.g., 1234567.89 -> "1,234,567.89"
  static String formatCurrency(double value) {
    return _currencyFormat.format(value);
  }
  
  /// Format a number with sign prefix
  /// e.g., 150.50 -> "+150.50", -50.25 -> "-50.25"
  static String formatCurrencyWithSign(double value) {
    final formatted = _currencyFormat.format(value.abs());
    return value >= 0 ? '+$formatted' : '-$formatted';
  }
}