import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/reservation_repository.dart';
import '../../models/deal.dart';
import '../../models/reservation.dart';
import '../shared/app_theme.dart';
import 'deal_details_viewmodel.dart';

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

        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) Navigator.of(context).pop(viewModel.deal);
          },
          child: Scaffold(
            appBar: AppBar(title: const Text('Deal details')),
            body: SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          deal.title,
                          key: const Key('detail-title'),
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            height: 1.25,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      _StatusBadge(status: deal.status),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _Pill(label: deal.category.label),
                      const SizedBox(width: 8),
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
                        height: 1.5,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),

                  // The number that decides whether a student joins.
                  _CostCard(deal: deal),
                  const SizedBox(height: 20),

                  _SectionLabel('Slots'),
                  _SlotsRow(deal: deal),
                  const SizedBox(height: 24),

                  _SectionLabel('Who is in'),
                  _Participants(
                    key: const Key('detail-participants'),
                    participants: viewModel.participants,
                  ),
                  const SizedBox(height: 24),

                  _SectionLabel('Organised by'),
                  _HostRow(deal: deal),
                  const SizedBox(height: 24),

                  _SectionLabel('Pickup'),
                  _DetailRow(
                    icon: Icons.storefront_outlined,
                    label: deal.pickupLocation,
                    keyValue: const Key('detail-pickup-location'),
                  ),
                  const SizedBox(height: 8),
                  _DetailRow(
                    icon: Icons.event_outlined,
                    label: deal.deadlineLabel,
                    keyValue: const Key('detail-deadline'),
                  ),
                  const SizedBox(height: 32),

                  if (viewModel.errorMessage != null) ...[
                    _Banner(
                      key: const Key('detail-reservation-error'),
                      message: viewModel.errorMessage!,
                    ),
                    const SizedBox(height: 12),
                  ],

                  if (viewModel.isHost)
                    Container(
                      key: const Key('detail-host-slot-note'),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: theme.colorScheme.outlineVariant,
                        ),
                      ),
                      child: Text(
                        'You are organising this buy, so one slot is yours. '
                        'To pull out you would have to cancel the whole deal.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  else
                    FilledButton(
                      key: const Key('detail-reserve-button'),
                      onPressed: viewModel.isUpdating
                          ? null
                          : viewModel.holdsSlot
                          ? (viewModel.canCancel ? viewModel.cancel : null)
                          : (viewModel.canReserve ? viewModel.reserve : null),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                        backgroundColor: AppTheme.accent,
                        foregroundColor: Colors.white,
                        textStyle: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      child: Text(_actionLabel(viewModel)),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _actionLabel(DealDetailsViewModel viewModel) {
    if (viewModel.holdsSlot) {
      return viewModel.deadlinePassed ? 'Slot locked in' : 'Cancel my slot';
    }
    if (viewModel.isFull) return 'No slots left';
    if (viewModel.deadlinePassed) return 'Deadline passed';
    return 'Reserve a slot';
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
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'YOUR SHARE',
                      style: theme.textTheme.labelSmall?.copyWith(
                        letterSpacing: 0.8,
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      formatPeso(deal.pricePerShare),
                      key: const Key('detail-cost-per-slot'),
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      deal.physicalShare.shareLabel,
                      key: const Key('detail-physical-share'),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'Total ${formatPeso(deal.totalPrice)}',
                    key: const Key('detail-total-price'),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
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
              ),
            ],
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
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 8,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
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
  const _Participants({super.key, required this.participants});

  final List<Reservation> participants;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Icon(
                  participant.isHost
                      ? Icons.star_outline
                      : Icons.person_outline,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text(
                  participant.displayName,
                  style: theme.textTheme.bodyMedium,
                ),
                if (participant.isHost) ...[
                  const SizedBox(width: 6),
                  Text(
                    '(organiser)',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
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

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final DealStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (background, foreground) = switch (status) {
      DealStatus.open => (const Color(0xFFDCEFE3), const Color(0xFF173E28)),
      DealStatus.fillingFast => (
        const Color(0xFFFDECC8),
        const Color(0xFF6B4A00),
      ),
      DealStatus.full => (const Color(0xFFF3D6D6), const Color(0xFF6B1D1D)),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.label,
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w800,
          color: foreground,
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.error_outline,
            size: 18,
            color: theme.colorScheme.onErrorContainer,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onErrorContainer,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
