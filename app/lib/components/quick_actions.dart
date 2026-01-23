import 'package:flutter/material.dart';
import '../core/theme.dart';

class QuickActions extends StatelessWidget {
  final VoidCallback onAccountsTap;
  final VoidCallback onPositionsTap;
  final VoidCallback onNewOrderTap;
  final VoidCallback onHistoryTap;

  const QuickActions({
    super.key,
    required this.onAccountsTap,
    required this.onPositionsTap,
    required this.onNewOrderTap,
    required this.onHistoryTap,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.5,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        _ActionCard(
          icon: Icons.account_balance_wallet,
          label: 'Accounts',
          onTap: onAccountsTap,
        ),
        _ActionCard(
          icon: Icons.candlestick_chart,
          label: 'Positions',
          onTap: onPositionsTap,
        ),
        _ActionCard(
          icon: Icons.add_circle_outline,
          label: 'New Order',
          onTap: onNewOrderTap,
        ),
        _ActionCard(
          icon: Icons.history,
          label: 'History',
          onTap: onHistoryTap,
        ),
      ],
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppColors.border,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: AppColors.primary,
              size: 28,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
