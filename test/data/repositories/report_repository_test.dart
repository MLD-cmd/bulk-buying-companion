import 'dart:async';

import 'package:bulk_buying_companion/data/repositories/report_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test(
    'SupabaseReportRepository inserts a deal report for the signed-in user',
    () async {
      final gateway = _ReportGatewayStub();
      final repository = SupabaseReportRepository(
        gateway: gateway,
        currentUserId: () => 'reporter',
      );

      await repository.submitReport(
        const ReportDraft(
          dealId: 'deal-1',
          targetType: ReportTargetType.deal,
          reason: ReportReason.suspicious,
          explanation: 'The price looks fake.',
        ),
      );

      expect(gateway.insertedValues, {
        'reporter_id': 'reporter',
        'deal_id': 'deal-1',
        'reported_user_id': null,
        'target_type': 'deal',
        'reason': 'suspicious',
        'explanation': 'The price looks fake.',
      });
    },
  );

  test(
    'SupabaseReportRepository reports permission failures clearly',
    () async {
      final repository = SupabaseReportRepository(
        gateway: _ReportGatewayStub(
          error: const PostgrestException(message: 'denied', code: '42501'),
        ),
        currentUserId: () => 'reporter',
      );

      expect(
        () => repository.submitReport(
          const ReportDraft(
            dealId: 'deal-1',
            targetType: ReportTargetType.deal,
            reason: ReportReason.inappropriate,
          ),
        ),
        throwsA(
          isA<ReportFailure>().having(
            (failure) => failure.message,
            'message',
            'You do not have permission to report this deal.',
          ),
        ),
      );
    },
  );

  test(
    'watchReports re-emits reports when realtime invalidation arrives',
    () async {
      final invalidations = StreamController<void>();
      addTearDown(invalidations.close);
      final gateway = _ReportGatewayStub(
        rows: [_reportRow(id: 'report-1', reason: 'suspicious')],
      );
      final repository = SupabaseReportRepository(
        gateway: gateway,
        currentUserId: () => 'reporter',
        invalidationSource: _InvalidationStub(invalidations.stream),
      );
      final iterator = StreamIterator(repository.watchReports());
      addTearDown(iterator.cancel);

      expect(await iterator.moveNext(), isTrue);
      expect(iterator.current.map((report) => report.id), ['report-1']);

      gateway.rows = [
        _reportRow(id: 'report-2', reason: 'inappropriate'),
        _reportRow(id: 'report-1', reason: 'suspicious'),
      ];
      invalidations.add(null);

      expect(await iterator.moveNext(), isTrue);
      expect(iterator.current.map((report) => report.id), [
        'report-2',
        'report-1',
      ]);
    },
  );
}

Map<String, dynamic> _reportRow({required String id, required String reason}) {
  return {
    'id': id,
    'reporter_id': 'reporter',
    'deal_id': 'deal-1',
    'reported_user_id': null,
    'target_type': 'deal',
    'reason': reason,
    'explanation': null,
    'status': 'open',
    'created_at': '2026-07-16T10:00:00Z',
  };
}

class _ReportGatewayStub implements SupabaseReportGateway {
  _ReportGatewayStub({this.error, this.rows = const []});

  final PostgrestException? error;
  List<Map<String, dynamic>> rows;
  Map<String, dynamic>? insertedValues;

  @override
  Future<List<Map<String, dynamic>>> getReports(String reporterId) async {
    return rows;
  }

  @override
  Future<void> insertReport(Map<String, dynamic> values) async {
    final error = this.error;
    if (error != null) throw error;
    insertedValues = values;
  }
}

class _InvalidationStub implements ReportInvalidationSource {
  const _InvalidationStub(this.stream);

  final Stream<void> stream;

  @override
  Stream<void> watchReports(String reporterId) => stream;
}
