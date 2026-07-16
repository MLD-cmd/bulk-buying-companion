import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

enum ReportTargetType {
  deal('deal', 'Deal'),
  user('user', 'Organiser');

  const ReportTargetType(this.value, this.label);

  final String value;
  final String label;
}

enum ReportReason {
  suspicious('suspicious', 'Suspicious deal'),
  inappropriate('inappropriate', 'Inappropriate content'),
  problematicUser('problematic_user', 'Problematic user'),
  other('other', 'Other');

  const ReportReason(this.value, this.label);

  final String value;
  final String label;
}

class ReportDraft {
  const ReportDraft({
    required this.dealId,
    required this.targetType,
    required this.reason,
    this.reportedUserId,
    this.explanation,
  });

  final String dealId;
  final ReportTargetType targetType;
  final ReportReason reason;
  final String? reportedUserId;
  final String? explanation;
}

class Report {
  const Report({
    required this.id,
    required this.reporterId,
    required this.dealId,
    required this.targetType,
    required this.reason,
    required this.status,
    required this.createdAt,
    this.reportedUserId,
    this.explanation,
  });

  final String id;
  final String reporterId;
  final String dealId;
  final ReportTargetType targetType;
  final ReportReason reason;
  final String status;
  final DateTime createdAt;
  final String? reportedUserId;
  final String? explanation;
}

abstract class ReportRepository {
  Future<void> submitReport(ReportDraft draft);

  Stream<List<Report>> watchReports();
}

class ReportFailure implements Exception {
  const ReportFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract class SupabaseReportGateway {
  Future<List<Map<String, dynamic>>> getReports(String reporterId);

  Future<void> insertReport(Map<String, dynamic> values);
}

class PostgrestSupabaseReportGateway implements SupabaseReportGateway {
  PostgrestSupabaseReportGateway(this._client);

  final SupabaseClient _client;

  @override
  Future<List<Map<String, dynamic>>> getReports(String reporterId) async {
    final rows = await _client
        .from('reports')
        .select()
        .eq('reporter_id', reporterId)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows);
  }

  @override
  Future<void> insertReport(Map<String, dynamic> values) async {
    await _client.from('reports').insert(values);
  }
}

abstract class ReportInvalidationSource {
  Stream<void> watchReports(String reporterId);
}

class SupabaseReportInvalidationSource implements ReportInvalidationSource {
  SupabaseReportInvalidationSource(this._client);

  final SupabaseClient _client;

  @override
  Stream<void> watchReports(String reporterId) {
    late final RealtimeChannel channel;
    final controller = StreamController<void>();

    void invalidate(PostgresChangePayload _) {
      if (!controller.isClosed) controller.add(null);
    }

    controller.onListen = () {
      channel = _client
          .channel(
            'reports:$reporterId:${DateTime.now().microsecondsSinceEpoch}',
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'reports',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'reporter_id',
              value: reporterId,
            ),
            callback: invalidate,
          )
          .subscribe((status, error) {
            if (controller.isClosed) return;
            if (status == RealtimeSubscribeStatus.channelError ||
                status == RealtimeSubscribeStatus.timedOut) {
              controller.addError(
                error ?? const RealtimeReportSubscriptionFailure(),
              );
            }
          });
    };

    controller.onCancel = () async {
      await channel.unsubscribe();
    };
    return controller.stream;
  }
}

class RealtimeReportSubscriptionFailure implements Exception {
  const RealtimeReportSubscriptionFailure();

  @override
  String toString() => 'Realtime report subscription failed.';
}

class SupabaseReportRepository implements ReportRepository {
  const SupabaseReportRepository({
    required SupabaseReportGateway gateway,
    required String Function() currentUserId,
    ReportInvalidationSource? invalidationSource,
  }) : _gateway = gateway,
       _currentUserId = currentUserId,
       _invalidationSource = invalidationSource;

  final SupabaseReportGateway _gateway;
  final String Function() _currentUserId;
  final ReportInvalidationSource? _invalidationSource;

  @override
  Future<void> submitReport(ReportDraft draft) async {
    try {
      await _gateway.insertReport({
        'reporter_id': _currentUserId(),
        'deal_id': draft.dealId,
        'reported_user_id': draft.targetType == ReportTargetType.user
            ? draft.reportedUserId
            : null,
        'target_type': draft.targetType.value,
        'reason': draft.reason.value,
        'explanation': _optionalText(draft.explanation),
      });
    } on PostgrestException catch (error) {
      throw ReportFailure(_messageFor(error));
    }
  }

  @override
  Stream<List<Report>> watchReports() async* {
    final reporterId = _currentUserId();
    yield await _getReports(reporterId);

    final invalidationSource = _invalidationSource;
    if (invalidationSource == null) return;

    await for (final _ in invalidationSource.watchReports(reporterId)) {
      yield await _getReports(reporterId);
    }
  }

  String _messageFor(PostgrestException error) {
    if (error.code == '42501') {
      return 'You do not have permission to report this deal.';
    }
    if (error.code == '23503') {
      return 'That deal or user no longer exists.';
    }
    if (error.code == '23514') {
      return 'Choose a report target and reason, then try again.';
    }
    return 'Could not submit the report. Please try again.';
  }

  Future<List<Report>> _getReports(String reporterId) async {
    final rows = await _gateway.getReports(reporterId);
    return rows.map(_reportFromRow).toList();
  }
}

class MockReportRepository implements ReportRepository {
  final submittedReports = <ReportDraft>[];

  @override
  Future<void> submitReport(ReportDraft draft) async {
    submittedReports.add(draft);
  }

  @override
  Stream<List<Report>> watchReports() async* {
    yield const [];
  }
}

String? _optionalText(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

Report _reportFromRow(Map<String, dynamic> row) {
  return Report(
    id: row['id'] as String,
    reporterId: row['reporter_id'] as String,
    dealId: row['deal_id'] as String,
    reportedUserId: row['reported_user_id'] as String?,
    targetType: _targetTypeFromValue(row['target_type'] as String),
    reason: _reasonFromValue(row['reason'] as String),
    explanation: row['explanation'] as String?,
    status: row['status'] as String,
    createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
  );
}

ReportTargetType _targetTypeFromValue(String value) {
  return ReportTargetType.values.firstWhere(
    (type) => type.value == value,
    orElse: () => throw StateError('Unknown report target "$value".'),
  );
}

ReportReason _reasonFromValue(String value) {
  return ReportReason.values.firstWhere(
    (reason) => reason.value == value,
    orElse: () => throw StateError('Unknown report reason "$value".'),
  );
}
