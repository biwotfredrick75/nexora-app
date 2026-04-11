import 'package:flutter/material.dart';
import 'package:wakulima/core/sync/sync_engine.dart';

/// Compact sync status bar — shows online/offline state, pending count,
/// a sync progress indicator, and a manual "Sync Now" button.
class SyncStatusBar extends StatefulWidget {
  const SyncStatusBar({super.key});

  @override
  State<SyncStatusBar> createState() => _SyncStatusBarState();
}

class _SyncStatusBarState extends State<SyncStatusBar> {
  final _engine = SyncEngine();

  SyncStatus _status = SyncStatus.idle;
  int _pending = 0;
  SyncProgress? _progress;

  @override
  void initState() {
    super.initState();
    _status = _engine.status;
    _engine.refreshPendingCount().then((_) {
      if (mounted) setState(() => _pending = _engine.pendingCount);
    });
    _engine.statusStream.listen((s) {
      if (mounted) setState(() => _status = s);
    });
    _engine.pendingCountStream.listen((n) {
      if (mounted) setState(() => _pending = n);
    });
    _engine.progressStream.listen((p) {
      if (mounted) setState(() => _progress = p);
    });
  }

  @override
  Widget build(BuildContext context) {
    final online = _engine.isOnline;
    final isSyncing = _status == SyncStatus.syncing;
    final theme = Theme.of(context);

    final bgColor = online
        ? (isSyncing
            ? theme.colorScheme.primaryContainer
            : (_pending > 0
                ? theme.colorScheme.tertiaryContainer
                : theme.colorScheme.surfaceVariant))
        : theme.colorScheme.errorContainer;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      color: bgColor,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                online ? Icons.wifi : Icons.wifi_off,
                size: 14,
                color: online ? Colors.green : Colors.red,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _statusText(online, isSyncing),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (_pending > 0 && !isSyncing)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.tertiary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$_pending pending',
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.onTertiary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              if (online && !isSyncing && _pending > 0) ...[
                const SizedBox(width: 8),
                InkWell(
                  onTap: () => _engine.syncNow(),
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.sync, size: 14, color: theme.colorScheme.primary),
                        const SizedBox(width: 3),
                        Text(
                          'Sync',
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              if (isSyncing)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          if (isSyncing && _progress != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LinearProgressIndicator(
                    value: _progress!.fraction,
                    minHeight: 3,
                    borderRadius: BorderRadius.circular(2),
                  ),
                  if (_progress!.currentItem != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        _progress!.currentItem!,
                        style: theme.textTheme.bodySmall?.copyWith(fontSize: 10),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _statusText(bool online, bool syncing) {
    if (!online) return 'Offline — changes saved locally';
    if (syncing) return 'Syncing to server...';
    if (_status == SyncStatus.success) return 'All synced';
    if (_status == SyncStatus.failed) return 'Sync failed — will retry';
    if (_pending > 0) return 'Online — $_pending record(s) waiting to sync';
    return 'Online';
  }
}
