import 'package:flutter/material.dart';
import '../core/theme.dart';

class ActivityLog extends StatelessWidget {
  final List<String> logs;
  final VoidCallback onClear;

  const ActivityLog({
    super.key,
    required this.logs,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              const Text(
                'ACTIVITY LOG',
                style: AppTextStyles.label,
              ),
              const Spacer(),
              TextButton(
                onPressed: onClear,
                child: const Text(
                  'Clear',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: logs.length,
            itemBuilder: (context, index) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  logs[index],
                  style: AppTextStyles.logEntry,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
