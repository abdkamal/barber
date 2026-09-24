/// حالة اتصال تطبيق الطاقم — لشريط الاتصال الدائم (design.md §10).
enum ConnectionStatus { online, syncing, offline }

class ConnectionState {
  const ConnectionState({
    required this.status,
    required this.since,
    required this.pendingCount,
  });

  final ConnectionStatus status;

  /// منذ متى حالة الاتصال الحالية سارية (لعبارة «آخر تحديث: قبل {المدة}»).
  final DateTime since;

  /// عدد الأحداث بانتظار الإرسال في الصندوق.
  final int pendingCount;

  ConnectionState copyWith({
    ConnectionStatus? status,
    DateTime? since,
    int? pendingCount,
  }) =>
      ConnectionState(
        status: status ?? this.status,
        since: since ?? this.since,
        pendingCount: pendingCount ?? this.pendingCount,
      );
}
