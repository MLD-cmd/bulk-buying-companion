import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/reservation_repository.dart';
import '../../data/repositories/report_repository.dart';
import '../../models/deal.dart';
import '../../models/reservation.dart';
import '../shared/app_banner.dart';
import '../shared/deal_action_bar.dart';
import '../shared/app_theme.dart';
import 'deal_details_viewmodel.dart';
import 'widgets/deal_status_badge.dart';

/// Everything a student needs before committing money to a bulk buy: what it
/// is, who is organising it, what their share costs, whether there is room
/// left, and where to collect it.
class DealDetailsScreen extends StatelessWidget {
  const DealDetailsScreen({super.key});

  /// Pops with the deal as it stands after any slot change, so the Split Board
  /// can show the new count instead of the one it pushed with.
  static Route<Deal> route(Deal deal) {
    return MaterialPageRoute<Deal>(
      builder: (context) => ChangeNotifierProvider(
        create: (context) => DealDetailsViewModel(
          reservationRepository: context.read<ReservationRepository>(),
          deal: deal,
          currentUserId: context.read<AuthRepository>().currentUser?.uid,
        ),
        child: const DealDetailsScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DealDetailsViewModel>(
      builder: (context, viewModel, _) {
        final theme = Theme.of(context);
        final deal = viewModel.deal;
        final showActionBar =
            !viewModel.isHost ||
            viewModel.canMarkPurchased ||
            viewModel.canCancelDeal;

        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) Navigator.of(context).pop(viewModel.deal);
          },
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Deal details'),
              actions: [
                TextButton.icon(
                  key: const Key('detail-report-button'),
                  onPressed: () => _showReportSheet(context, viewModel),
                  icon: const Icon(Icons.flag_outlined),
                  label: const Text('Report'),
                ),
              ],
            ),
            body: SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 680),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            deal.title,
                            key: const Key('detail-title'),
                            style: theme.textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              DealStatusBadge(deal: deal),
                              _Pill(label: deal.category.label),
                              _Pill(label: deal.physicalShare.totalLabel),
                            ],
                          ),
                          if (deal.description != null &&
                              deal.description!.trim().isNotEmpty) ...[
                            const SizedBox(height: 16),
                            Text(
                              deal.description!.trim(),
                              key: const Key('detail-description'),
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                          const SizedBox(height: 24),
                          _CostCard(deal: deal),
                          if (viewModel.isHost || viewModel.holdsSlot) ...[
                            const SizedBox(height: 24),
                            const _SectionLabel('Payment'),
                            _PaymentInfo(deal: deal),
                          ],
                          const SizedBox(height: 24),
                          const _SectionLabel('Slots'),
                          _SlotsRow(deal: deal),
                          const SizedBox(height: 28),
                          const _SectionLabel('Pickup'),
                          _DetailRow(
                            icon: Icons.storefront_outlined,
                            label: deal.pickupLocation,
                            keyValue: const Key('detail-pickup-location'),
                          ),
                          const SizedBox(height: 10),
                          _DetailRow(
                            icon: Icons.event_outlined,
                            label: deal.deadlineLabel,
                            keyValue: const Key('detail-deadline'),
                          ),
                          const SizedBox(height: 28),
                          _SectionLabel(
                            viewModel.isPurchased
                                ? 'Pickup checklist'
                                : 'Who is in',
                          ),
                          _Participants(
                            key: const Key('detail-participants'),
                            viewModel: viewModel,
                          ),
                          const SizedBox(height: 28),
                          const _SectionLabel('Organised by'),
                          _HostRow(deal: deal),
                          if (viewModel.errorMessage != null) ...[
                            const SizedBox(height: 20),
                            AppBanner.error(
                              key: const Key('detail-reservation-error'),
                              message: viewModel.errorMessage!,
                            ),
                          ],
                          if (viewModel.isHost) ...[
                            const SizedBox(height: 20),
                            const AppBanner.notice(
                              key: Key('detail-host-slot-note'),
                              message:
                                  'You are organising this buy, so one slot is yours.',
                              icon: Icons.star_outline,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            bottomNavigationBar: showActionBar
                ? DealActionBar(
                    key: const Key('detail-action-bar'),
                    child: _LifecycleActions(
                      viewModel: viewModel,
                      onCancelDeal: () => _confirmCancel(context, viewModel),
                    ),
                  )
                : null,
          ),
        );
      },
    );
  }

  /// The app never moves money. What it refuses to do is let the host cancel
  /// while pretending nobody paid.
  Future<void> _confirmCancel(
    BuildContext context,
    DealDetailsViewModel viewModel,
  ) async {
    final warning = viewModel.refundWarning;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel this deal?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (warning != null) ...[
              Text(
                warning,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              const Text(
                'Cancelling does not refund them — you will have to hand it '
                'back yourself.',
              ),
            ] else
              const Text(
                'Nobody has paid you yet, so there is nothing to hand back. '
                'The deal will close and its slots will be released.',
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep the deal'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Cancel the deal'),
          ),
        ],
      ),
    );

    if (confirmed == true) await viewModel.cancelDeal();
  }

  Future<void> _showReportSheet(
    BuildContext context,
    DealDetailsViewModel viewModel,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final repository = context.read<ReportRepository>();
    final deal = viewModel.deal;

    final submitted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => _ReportSheet(
        deal: deal,
        currentUserId: viewModel.currentUserId,
        participants: viewModel.participants,
        repository: repository,
      ),
    );

    if (submitted == true) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Report submitted. Thanks for helping keep this hub safe.',
          ),
        ),
      );
    }
  }
}

class _LifecycleActions extends StatelessWidget {
  const _LifecycleActions({
    required this.viewModel,
    required this.onCancelDeal,
  });

  final DealDetailsViewModel viewModel;
  final VoidCallback onCancelDeal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final errorStyle = ButtonStyle(
      foregroundColor: WidgetStatePropertyAll(theme.colorScheme.error),
      side: WidgetStatePropertyAll(BorderSide(color: theme.colorScheme.error)),
    );

    if (viewModel.isHost) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (viewModel.canMarkPurchased)
            FilledButton.icon(
              key: const Key('detail-mark-purchased-button'),
              onPressed: viewModel.isUpdating ? null : viewModel.markPurchased,
              icon: const Icon(Icons.shopping_bag_outlined),
              label: const Text("I've bought it"),
            ),
          if (viewModel.canMarkPurchased && viewModel.canCancelDeal)
            const SizedBox(height: 8),
          if (viewModel.canCancelDeal)
            OutlinedButton.icon(
              key: const Key('detail-cancel-deal-button'),
              onPressed: viewModel.isUpdating ? null : onCancelDeal,
              style: errorStyle,
              icon: const Icon(Icons.cancel_outlined),
              label: const Text('Cancel this deal'),
            ),
        ],
      );
    }

    if (viewModel.holdsSlot && viewModel.canCancel) {
      return OutlinedButton.icon(
        key: const Key('detail-reserve-button'),
        onPressed: viewModel.isUpdating ? null : viewModel.cancel,
        style: errorStyle,
        icon: const Icon(Icons.remove_circle_outline),
        label: const Text('Cancel my slot'),
      );
    }

    return FilledButton.icon(
      key: const Key('detail-reserve-button'),
      onPressed: viewModel.isUpdating
          ? null
          : viewModel.holdsSlot
          ? null
          : (viewModel.canReserve ? viewModel.reserve : null),
      icon: Icon(
        viewModel.holdsSlot
            ? Icons.lock_outline
            : viewModel.canReserve
            ? Icons.add_circle_outline
            : Icons.block_outlined,
      ),
      label: Text(_participantActionLabel(viewModel)),
    );
  }

  String _participantActionLabel(DealDetailsViewModel viewModel) {
    if (viewModel.holdsSlot) return 'Slot locked in';
    if (viewModel.isFull) return 'No slots left';
    if (viewModel.deadlinePassed) return 'Deadline passed';
    return 'Reserve a slot';
  }
}

class _ReportSheet extends StatefulWidget {
  const _ReportSheet({
    required this.deal,
    required this.currentUserId,
    required this.participants,
    required this.repository,
  });

  final Deal deal;
  final String? currentUserId;
  final List<Reservation> participants;
  final ReportRepository repository;

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  final _controller = TextEditingController();
  var _targetType = ReportTargetType.deal;
  String? _reportedUserId;
  ReportReason? _reason;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reportableUsers = _reportableUsers;
    final canReportUser = reportableUsers.isNotEmpty;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + bottomInset),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Report deal or user', style: theme.textTheme.titleLarge),
                const SizedBox(height: 6),
                Text(
                  'Reports help moderators review suspicious deals, inappropriate content, or problematic users.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'What are you reporting?',
                  style: theme.textTheme.titleSmall,
                ),
                RadioListTile<ReportTargetType>(
                  contentPadding: EdgeInsets.zero,
                  value: ReportTargetType.deal,
                  groupValue: _targetType,
                  onChanged: _isSubmitting ? null : _setTargetType,
                  title: const Text('Report this deal'),
                ),
                if (canReportUser)
                  RadioListTile<ReportTargetType>(
                    contentPadding: EdgeInsets.zero,
                    value: ReportTargetType.user,
                    groupValue: _targetType,
                    onChanged: _isSubmitting ? null : _setTargetType,
                    title: const Text('Report a user'),
                  ),
                if (_targetType == ReportTargetType.user && canReportUser) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Who are you reporting?',
                    style: theme.textTheme.titleSmall,
                  ),
                  for (final participant in reportableUsers)
                    RadioListTile<String>(
                      key: Key('report-user-${participant.userId}'),
                      contentPadding: EdgeInsets.zero,
                      value: participant.userId,
                      groupValue: _reportedUserId,
                      onChanged: _isSubmitting ? null : _setReportedUser,
                      title: Text(participant.displayName),
                      subtitle: participant.isHost
                          ? const Text('Organiser')
                          : null,
                    ),
                ],
                const SizedBox(height: 10),
                Text('Reason', style: theme.textTheme.titleSmall),
                for (final item in ReportReason.values)
                  RadioListTile<ReportReason>(
                    contentPadding: EdgeInsets.zero,
                    value: item,
                    groupValue: _reason,
                    onChanged: _isSubmitting ? null : _setReason,
                    title: Text(item.label),
                  ),
                const SizedBox(height: 10),
                TextField(
                  key: const Key('report-explanation-field'),
                  controller: _controller,
                  minLines: 3,
                  maxLines: 5,
                  enabled: !_isSubmitting,
                  decoration: const InputDecoration(
                    labelText: 'Optional explanation',
                    alignLabelWithHint: true,
                    prefixIcon: Icon(Icons.notes_outlined),
                  ),
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 12),
                  AppBanner.error(message: _errorMessage!),
                ],
                const SizedBox(height: 18),
                FilledButton.icon(
                  key: const Key('submit-report-button'),
                  onPressed:
                      _reason == null ||
                          _isSubmitting ||
                          (_targetType == ReportTargetType.user &&
                              _reportedUserId == null)
                      ? null
                      : _submit,
                  icon: _isSubmitting
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.flag_outlined),
                  label: Text(
                    _isSubmitting ? 'Submitting...' : 'Submit report',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _setTargetType(ReportTargetType? value) {
    if (value == null) return;
    setState(() {
      _targetType = value;
      if (value == ReportTargetType.deal) {
        _reportedUserId = null;
      } else {
        final users = _reportableUsers;
        if (_reportedUserId == null && users.isNotEmpty) {
          _reportedUserId = users.first.userId;
        }
      }
    });
  }

  void _setReportedUser(String? value) {
    if (value == null) return;
    setState(() => _reportedUserId = value);
  }

  void _setReason(ReportReason? value) {
    setState(() => _reason = value);
  }

  Future<void> _submit() async {
    final selectedReason = _reason;
    if (selectedReason == null || _isSubmitting) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      await widget.repository.submitReport(
        ReportDraft(
          dealId: widget.deal.id,
          targetType: _targetType,
          reportedUserId: _targetType == ReportTargetType.user
              ? _reportedUserId
              : null,
          reason: selectedReason,
          explanation: _controller.text,
        ),
      );
      if (mounted) Navigator.of(context).pop(true);
    } on ReportFailure catch (failure) {
      setState(() {
        _errorMessage = failure.message;
        _isSubmitting = false;
      });
    } catch (_) {
      setState(() {
        _errorMessage = 'Could not submit the report. Please try again.';
        _isSubmitting = false;
      });
    }
  }

  List<Reservation> get _reportableUsers {
    final byUserId = <String, Reservation>{};
    for (final participant in widget.participants) {
      byUserId.putIfAbsent(participant.userId, () => participant);
    }

    final hostId = widget.deal.createdBy;
    final hostName = widget.deal.hostName;
    if (hostId != null) {
      byUserId.putIfAbsent(
        hostId,
        () => Reservation(
          dealId: widget.deal.id,
          userId: hostId,
          studentName: hostName,
          isHost: true,
          reservedAt: DateTime.fromMillisecondsSinceEpoch(0),
        ),
      );
    }

    final users = byUserId.values.toList();
    users.sort((a, b) {
      if (a.isHost != b.isHost) return a.isHost ? -1 : 1;
      return a.displayName.compareTo(b.displayName);
    });
    return users;
  }
}

class _PaymentInfo extends StatelessWidget {
  const _PaymentInfo({required this.deal});

  final Deal deal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _DetailRow(
          icon: Icons.payments_outlined,
          label: 'Amount owed: ${formatPeso(deal.pricePerShare)}',
          keyValue: const Key('detail-payment-amount'),
        ),
        if (deal.hasPaymentInfo) ...[
          if (_hasText(deal.paymentMethod)) ...[
            const SizedBox(height: 10),
            _DetailRow(
              icon: Icons.account_balance_wallet_outlined,
              label: deal.paymentMethod!.trim(),
              keyValue: const Key('detail-payment-method'),
            ),
          ],
          if (_hasText(deal.paymentAccountName)) ...[
            const SizedBox(height: 10),
            _DetailRow(
              icon: Icons.badge_outlined,
              label: deal.paymentAccountName!.trim(),
              keyValue: const Key('detail-payment-account-name'),
            ),
          ],
          if (_hasText(deal.paymentAccountHandle)) ...[
            const SizedBox(height: 10),
            _DetailRow(
              icon: Icons.tag_outlined,
              label: deal.paymentAccountHandle!.trim(),
              keyValue: const Key('detail-payment-account-handle'),
            ),
          ],
          if (_hasText(deal.paymentInstructions)) ...[
            const SizedBox(height: 10),
            _DetailRow(
              icon: Icons.notes_outlined,
              label: deal.paymentInstructions!.trim(),
              keyValue: const Key('detail-payment-instructions'),
            ),
          ],
        ] else ...[
          const SizedBox(height: 8),
          Text(
            'No payment instructions added yet.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

class _CostCard extends StatelessWidget {
  const _CostCard({required this.deal});

  final Deal deal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final split = deal.costSplit;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final textScale = MediaQuery.textScalerOf(context).scale(1);
              final share = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'YOUR SHARE',
                    style: theme.textTheme.labelSmall?.copyWith(
                      letterSpacing: 0.8,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    formatPeso(deal.pricePerShare),
                    key: const Key('detail-cost-per-slot'),
                    style: theme.textTheme.headlineMedium?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    deal.physicalShare.shareLabel,
                    key: const Key('detail-physical-share'),
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ],
              );
              final total = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Total ${formatPeso(deal.totalPrice)}',
                    key: const Key('detail-total-price'),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'split ${deal.totalSlots} ways',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ],
              );

              if (constraints.maxWidth < 420 || textScale > 1.3) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [share, const SizedBox(height: 14), total],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: share),
                  const SizedBox(width: 16),
                  total,
                ],
              );
            },
          ),
          // The share rounds up, so the shares collect slightly more than the
          // item cost. Say so, rather than leaving two figures that do not
          // reconcile sitting next to each other.
          if (!split.isEven) ...[
            const SizedBox(height: 10),
            Text(
              'Shares round up, so the ${split.slots} of you pay '
              '${formatPeso(split.collected)} in total — '
              '${formatPeso(split.surplus)} over the item cost, kept by the host.',
              key: const Key('detail-split-surplus'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

bool _hasText(String? value) => value?.trim().isNotEmpty == true;

class _SlotsRow extends StatelessWidget {
  const _SlotsRow({required this.deal});

  final Deal deal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final taken = deal.totalSlots - deal.availableSlots;
    final progress = deal.totalSlots == 0 ? 0.0 : taken / deal.totalSlots;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          deal.availableSlotsLabel,
          key: const Key('detail-available-slots'),
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Semantics(
          key: const Key('detail-slot-progress'),
          label: '$taken of ${deal.totalSlots} slots claimed',
          value: '${(progress * 100).round()} percent',
          readOnly: true,
          child: ExcludeSemantics(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '$taken of ${deal.totalSlots} already claimed',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _Participants extends StatelessWidget {
  const _Participants({super.key, required this.viewModel});

  final DealDetailsViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final participants = viewModel.participants;

    if (participants.isEmpty) {
      return Text(
        'Nobody has claimed a share yet.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final participant in participants)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _ParticipantRow(
              viewModel: viewModel,
              participant: participant,
            ),
          ),
        const SizedBox(height: 4),
        Text(
          viewModel.paymentLabel,
          key: const Key('detail-payment-label'),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (viewModel.pickupProgressLabel != null) ...[
          const SizedBox(height: 6),
          Text(
            viewModel.pickupProgressLabel!,
            key: const Key('detail-pickup-progress-label'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }
}

class _ParticipantRow extends StatelessWidget {
  const _ParticipantRow({required this.viewModel, required this.participant});

  final DealDetailsViewModel viewModel;
  final Reservation participant;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final identity = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          participant.isHost ? Icons.star_outline : Icons.person_outline,
          size: 18,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(participant.displayName, style: theme.textTheme.bodyMedium),
              if (participant.isHost)
                Text(
                  '(organiser)',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              if (participant.collectedAt != null)
                Text(
                  _collectedAtLabel(participant.collectedAt!),
                  key: Key('collected-at-${participant.userId}'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
    final controls = _ParticipantControls(
      viewModel: viewModel,
      participant: participant,
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 360 || textScale > 1.3) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                identity,
                const SizedBox(height: 10),
                Align(alignment: Alignment.centerLeft, child: controls),
              ],
            );
          }

          return Row(
            children: [
              Expanded(child: identity),
              const SizedBox(width: 12),
              controls,
            ],
          );
        },
      ),
    );
  }
}

class _ParticipantControls extends StatelessWidget {
  const _ParticipantControls({
    required this.viewModel,
    required this.participant,
  });

  final DealDetailsViewModel viewModel;
  final Reservation participant;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _PaidControl(viewModel: viewModel, participant: participant),
        if (viewModel.isPurchased)
          _CollectedControl(viewModel: viewModel, participant: participant),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 520 || textScale > 1.3) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              identity,
              const SizedBox(height: 6),
              Align(alignment: Alignment.centerRight, child: controls),
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: identity),
            const SizedBox(width: 12),
            controls,
          ],
        );
      },
    );
  }
}

String _collectedAtLabel(DateTime collectedAt) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final hour12 = collectedAt.hour % 12 == 0 ? 12 : collectedAt.hour % 12;
  final minute = collectedAt.minute.toString().padLeft(2, '0');
  final period = collectedAt.hour < 12 ? 'AM' : 'PM';

  return 'Collected ${months[collectedAt.month - 1]} ${collectedAt.day}, '
      '${collectedAt.year} at $hour12:$minute $period';
}

/// The host taps to mark a payment; everyone else just reads it.
class _PaidControl extends StatelessWidget {
  const _PaidControl({required this.viewModel, required this.participant});

  final DealDetailsViewModel viewModel;
  final Reservation participant;

  @override
  Widget build(BuildContext context) {
    // The host's own slot is paid from the moment the deal exists, and they
    // cannot unpay themselves.
    if (!viewModel.canMarkPaid || participant.isHost) {
      return _StateChip(
        label: participant.hasPaid ? 'Paid' : 'Unpaid',
        on: participant.hasPaid,
      );
    }

    return TextButton(
      key: Key('mark-paid-${participant.userId}'),
      onPressed: viewModel.isUpdating
          ? null
          : () => viewModel.setPaid(
              participant.userId,
              paid: !participant.hasPaid,
            ),
      child: _StateChip(
        label: participant.hasPaid ? 'Paid' : 'Mark paid',
        on: participant.hasPaid,
      ),
    );
  }
}

/// The host taps to mark a pickup; everyone else just reads it.
class _CollectedControl extends StatelessWidget {
  const _CollectedControl({required this.viewModel, required this.participant});

  final DealDetailsViewModel viewModel;
  final Reservation participant;

  @override
  Widget build(BuildContext context) {
    if (!viewModel.canMarkCollected || participant.isHost) {
      return _StateChip(
        label: participant.hasCollected ? 'Collected' : 'Not collected',
        on: participant.hasCollected,
      );
    }

    return TextButton(
      key: Key('mark-collected-${participant.userId}'),
      onPressed: viewModel.isUpdating
          ? null
          : () => viewModel.setCollected(
              participant.userId,
              collected: !participant.hasCollected,
            ),
      child: _StateChip(
        label: participant.hasCollected ? 'Collected' : 'Mark collected',
        on: participant.hasCollected,
      ),
    );
  }
}

class _StateChip extends StatelessWidget {
  const _StateChip({required this.label, required this.on});

  final String label;
  final bool on;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: on
            ? theme.brightness == Brightness.light
                  ? AppTheme.successContainer
                  : theme.colorScheme.primaryContainer
            : theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: on
              ? theme.brightness == Brightness.light
                    ? AppTheme.success.withValues(alpha: 0.35)
                    : theme.colorScheme.primary.withValues(alpha: 0.35)
              : theme.colorScheme.outlineVariant,
        ),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: on
              ? theme.brightness == Brightness.light
                    ? AppTheme.onSuccessContainer
                    : theme.colorScheme.onPrimaryContainer
              : theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _HostRow extends StatelessWidget {
  const _HostRow({required this.deal});

  final Deal deal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final host = deal.hostLabel;

    return Row(
      children: [
        CircleAvatar(
          radius: 20,
          backgroundColor: theme.colorScheme.secondaryContainer,
          child: Text(
            _initials(host),
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: theme.colorScheme.onSecondaryContainer,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                host,
                key: const Key('detail-host-name'),
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                'Organising this buy',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length == 1) {
      return parts.first.characters.take(2).toString().toUpperCase();
    }
    return '${parts.first.characters.first}${parts.last.characters.first}'
        .toUpperCase();
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        label.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          letterSpacing: 0.8,
          fontWeight: FontWeight.w700,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.keyValue,
  });

  final IconData icon;
  final String label;
  final Key keyValue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 10),
        Expanded(
          child: Text(label, key: keyValue, style: theme.textTheme.bodyMedium),
        ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
