enum ConnectivityState { online, offline, degraded }

enum DraftSyncState {
  localOnly,
  queued,
  synchronizing,
  synced,
  conflicted,
  failed,
}

final class DraftConflict {
  const DraftConflict({
    required this.entityId,
    required this.localVersion,
    required this.serverVersion,
    required this.localPayload,
    required this.serverPayload,
  });

  final String entityId;
  final int localVersion;
  final int serverVersion;
  final Map<String, Object?> localPayload;
  final Map<String, Object?> serverPayload;
}

final class OfflinePolicy {
  const OfflinePolicy._();

  static bool canRunAuthoritativeCommand({
    required ConnectivityState connectivity,
    required bool serverConfirmed,
  }) => connectivity == ConnectivityState.online && serverConfirmed;
}
