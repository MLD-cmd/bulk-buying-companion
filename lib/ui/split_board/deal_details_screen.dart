import 'package:flutter/material.dart';

import '../../models/deal.dart';
import '../shared/app_theme.dart';

/// Everything a student needs before committing money to a bulk buy: what it
/// is, who is organising it, what their share costs, whether there is room
/// left, and where to collect it.
class DealDetailsScreen extends StatelessWidget {
  const DealDetailsScreen({super.key, required this.deal});

  final Deal deal;

  static Route<void> route(Deal deal) {
    return MaterialPageRoute<void>(
      builder: (context) => DealDetailsScreen(deal: deal),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isFull = deal.availableSlots == 0;

    return Scaffold(
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
                _Pill(
                  label:
                      '${deal.quantity} ${deal.quantity == 1 ? 'unit' : 'units'}',
                ),
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

            FilledButton(
              key: const Key('detail-reserve-button'),
              onPressed: isFull ? null : () => _reserve(context),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                backgroundColor: AppTheme.accent,
                foregroundColor: Colors.white,
                textStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              child: Text(isFull ? 'No slots left' : 'Reserve a slot'),
            ),
          ],
        ),
      ),
    );
  }

  void _reserve(BuildContext context) {
    // Claiming the slot is the Slot Reservation System card. Saying so beats a
    // button that looks live and silently does nothing.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Reserving a slot is coming soon.')),
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
