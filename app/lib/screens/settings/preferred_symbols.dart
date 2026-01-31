import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../../core/theme.dart';

class PreferredSymbolsScreen extends StatefulWidget {
  final Set<String> selectedPairs;
  final Function(Set<String>) onPairsUpdated;

  const PreferredSymbolsScreen({
    super.key,
    required this.selectedPairs,
    required this.onPairsUpdated,
  });

  @override
  State<PreferredSymbolsScreen> createState() => _PreferredSymbolsScreenState();
}

class _PreferredSymbolsScreenState extends State<PreferredSymbolsScreen> {
  late Set<String> _selectedPairs;
  final TextEditingController _customPairController = TextEditingController();
  Set<String> _customPairs = {};

  // Popular MT4/MT5 trading pairs organized by category
  static const Map<String, List<String>> _pairCategories = {
    'Forex Majors': [
      'EURUSD', 'GBPUSD', 'USDJPY', 'USDCHF', 'AUDUSD', 'USDCAD', 'NZDUSD',
    ],
    'Forex Minors': [
      'EURGBP', 'EURJPY', 'GBPJPY', 'EURAUD', 'EURCAD', 'EURCHF', 'EURNZD',
      'GBPAUD', 'GBPCAD', 'GBPCHF', 'GBPNZD', 'AUDCAD', 'AUDCHF', 'AUDJPY',
      'AUDNZD', 'CADJPY', 'CADCHF', 'CHFJPY', 'NZDCAD', 'NZDCHF', 'NZDJPY',
    ],
    'Forex Exotics': [
      'USDMXN', 'USDZAR', 'USDTRY', 'USDSGD', 'USDHKD', 'USDNOK', 'USDSEK',
      'USDPLN', 'USDDKK', 'USDCZK', 'USDHUF', 'EURPLN', 'EURTRY', 'EURNOK',
      'EURSEK', 'GBPSGD', 'GBPTRY',
    ],
    'Metals': [
      'XAUUSD', 'XAGUSD', 'XAUEUR', 'XAGEUR', 'XPTUSD', 'XPDUSD',
    ],
    'Crypto': [
      'BTCUSD', 'ETHUSD', 'LTCUSD', 'XRPUSD', 'BCHUSD', 'ADAUSD', 'DOTUSD',
      'LINKUSD', 'SOLUSD', 'DOGEUSD', 'MATICUSD', 'AVAXUSD',
    ],
    'Indices': [
      'US30', 'US500', 'NAS100', 'US2000', 'UK100', 'GER40', 'FRA40', 'ESP35',
      'EU50', 'JPN225', 'AUS200', 'HK50', 'CHINA50',
    ],
    'Commodities': [
      'USOIL', 'UKOIL', 'NGAS', 'COPPER', 'COCOA', 'COFFEE', 'COTTON', 'SUGAR',
    ],
  };

  @override
  void initState() {
    super.initState();
    _selectedPairs = Set.from(widget.selectedPairs);
    _loadCustomPairs();
  }

  Future<void> _loadCustomPairs() async {
    final prefs = await SharedPreferences.getInstance();
    final customJson = prefs.getString('custom_pairs');
    if (customJson != null) {
      final List<dynamic> decoded = jsonDecode(customJson);
      setState(() {
        _customPairs = decoded.map((e) => e.toString()).toSet();
      });
    }
  }

  Future<void> _saveCustomPairs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('custom_pairs', jsonEncode(_customPairs.toList()));
  }

  Future<void> _savePairs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('preferred_pairs', jsonEncode(_selectedPairs.toList()));
    widget.onPairsUpdated(_selectedPairs);
  }

  Future<void> _saveAndClose() async {
    await _savePairs();
    await _saveCustomPairs();
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Preferred symbols saved'),
          backgroundColor: AppColors.primary,
        ),
      );
      Navigator.pop(context);
    }
  }

  void _togglePair(String pair) {
    setState(() {
      if (_selectedPairs.contains(pair)) {
        _selectedPairs.remove(pair);
      } else {
        _selectedPairs.add(pair);
      }
    });
    _savePairs();
  }

  void _addCustomPair() {
    final pair = _customPairController.text.trim().toUpperCase();
    if (pair.isEmpty) return;
    
    // Check if already exists in predefined or custom
    bool exists = _customPairs.contains(pair);
    if (!exists) {
      for (final category in _pairCategories.values) {
        if (category.contains(pair)) {
          exists = true;
          break;
        }
      }
    }
    
    if (exists) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$pair already exists'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    
    setState(() {
      _customPairs.add(pair);
      _selectedPairs.add(pair);
    });
    _saveCustomPairs();
    _savePairs();
    _customPairController.clear();
    
    // Remove focus from text field (hide keyboard and cursor)
    FocusManager.instance.primaryFocus?.unfocus();
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$pair added'),
        backgroundColor: AppColors.primary,
      ),
    );
  }

  void _removeCustomPair(String pair) {
    setState(() {
      _customPairs.remove(pair);
      _selectedPairs.remove(pair);
    });
    _saveCustomPairs();
    _savePairs();
  }

  @override
  void dispose() {
    _customPairController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: const Text(
          'Preferred Symbols',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          TextButton(
            onPressed: _saveAndClose,
            child: const Text(
              'SAVE',
              style: TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false, // AppBar handles top
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Info section
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.orange.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    color: Colors.orange,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Select your preferred trading symbols to show them in the New Order screen for quick access.',
                      style: TextStyle(
                        color: Colors.orange.shade200,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Add custom symbol section
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Add Custom Symbol',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _customPairController,
                        textCapitalization: TextCapitalization.characters,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'e.g. XAUEUR',
                          hintStyle: TextStyle(color: AppColors.textSecondary.withOpacity(0.5)),
                          filled: true,
                          fillColor: AppColors.background,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: _addCustomPair,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text('Add', style: TextStyle(color: Colors.white)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Selected count
          Text(
            '${_selectedPairs.length} symbols selected',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
            ),
          ),
          
          const SizedBox(height: 8),
          
          // Selected pairs (can deselect)
          if (_selectedPairs.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: (_selectedPairs.toList()..sort()).map((pair) {
                return GestureDetector(
                  onTap: () => _togglePair(pair),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          pair,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.close,
                          size: 14,
                          color: Colors.white70,
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          
          const SizedBox(height: 16),
          const Divider(color: AppColors.border, height: 1),
          const SizedBox(height: 16),
          
          // Custom pairs section (if any)
          if (_customPairs.isNotEmpty) ...[
            _buildCategorySection('Custom Symbols', _customPairs.toList(), isCustom: true),
            const SizedBox(height: 16),
          ],
          
          // Predefined categories
          for (final entry in _pairCategories.entries) ...[
            _buildCategorySection(entry.key, entry.value),
            const SizedBox(height: 16),
          ],
        ],
        ),
      ),
    );
  }

  Widget _buildCategorySection(String title, List<String> pairs, {bool isCustom = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.toUpperCase(),
          style: AppTextStyles.label,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: pairs.map((pair) {
            final isSelected = _selectedPairs.contains(pair);
            return GestureDetector(
              onTap: () => _togglePair(pair),
              onLongPress: isCustom ? () => _showDeleteCustomPairDialog(pair) : null,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.primary : AppColors.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isSelected ? AppColors.primary : AppColors.border,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      pair,
                      style: TextStyle(
                        color: isSelected ? Colors.white : AppColors.textSecondary,
                        fontSize: 13,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                    if (isCustom) ...[
                      const SizedBox(width: 4),
                      Icon(
                        Icons.close,
                        size: 14,
                        color: isSelected ? Colors.white.withOpacity(0.7) : AppColors.textSecondary,
                      ),
                    ],
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  void _showDeleteCustomPairDialog(String pair) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: AppColors.primary.withOpacity(0.3)),
        ),
        title: const Text(
          'Remove Custom Symbol',
          style: TextStyle(color: Colors.white, fontSize: 18),
        ),
        content: Text(
          'Remove $pair from your custom symbols?',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _removeCustomPair(pair);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Remove', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}