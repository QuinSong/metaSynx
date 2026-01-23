import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/theme.dart';

class RoomIdDisplay extends StatelessWidget {
  final String roomId;
  final VoidCallback? onCopied;

  const RoomIdDisplay({
    super.key,
    required this.roomId,
    this.onCopied,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 20,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Room: ',
            style: AppTextStyles.body,
          ),
          Text(
            roomId,
            style: AppTextStyles.monoLarge,
          ),
          const SizedBox(width: 12),
          IconButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: roomId));
              onCopied?.call();
            },
            icon: const Icon(
              Icons.copy,
              size: 18,
              color: AppColors.textSecondary,
            ),
            tooltip: 'Copy Room ID',
          ),
        ],
      ),
    );
  }
}
