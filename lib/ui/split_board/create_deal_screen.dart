import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/deal_repository.dart';
import '../../models/cost_split.dart';
import '../../models/deal.dart';
import '../../models/deal_unit.dart';
import '../../models/physical_share.dart';
import '../shared/app_banner.dart';
import '../shared/app_form_section.dart';
import 'create_deal_viewmodel.dart';

class CreateDealScreen extends StatefulWidget {
  const CreateDealScreen({
    super.key,
    required this.hubId,
    required this.hubName,
  });

  final String hubId;
  final String hubName;

  /// Pops with the published [Deal], or null when the student backs out.
  static Route<Deal> route(String hubId, String hubName) {
    return MaterialPageRoute<Deal>(
      builder: (context) => ChangeNotifierProvider(
        create: (context) =>
            CreateDealViewModel(dealRepository: context.read<DealRepository>()),
        child: CreateDealScreen(hubId: hubId, hubName: hubName),
      ),
    );
  }

  @override
  State<CreateDealScreen> createState() => _CreateDealScreenState();
}

class _CreateDealScreenState extends State<CreateDealScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _totalPriceController = TextEditingController();
  final _amountController = TextEditingController();
  final _totalSlotsController = TextEditingController();
  final _pickupLocationController = TextEditingController();
  final _paymentMethodController = TextEditingController();
  final _paymentAccountNameController = TextEditingController();
  final _paymentAccountHandleController = TextEditingController();
  final _paymentInstructionsController = TextEditingController();

  DealCategory _category = DealCategory.grocery;
  DealUnit _unit = DealUnit.kg;
  DateTime? _closesAt;
  String? _deadlineError;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _totalPriceController.dispose();
    _amountController.dispose();
    _totalSlotsController.dispose();
    _pickupLocationController.dispose();
    _paymentMethodController.dispose();
    _paymentAccountNameController.dispose();
    _paymentAccountHandleController.dispose();
    _paymentInstructionsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Post a deal')),
      body: SafeArea(
        child: Consumer<CreateDealViewModel>(
          builder: (context, viewModel, _) {
            final split = viewModel.previewSplit(
              totalPrice: _totalPriceController.text,
              totalSlots: _totalSlotsController.text,
            );
            final share = viewModel.previewShare(
              amount: _amountController.text,
              unit: _unit,
              totalSlots: _totalSlotsController.text,
            );
            final showReview =
                _titleController.text.trim().isNotEmpty ||
                split != null ||
                _pickupLocationController.text.trim().isNotEmpty;

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Buying in bulk for ${widget.hubName}? Share the details so hubmates can claim a portion.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 20),
                        AppFormSection(
                          title: 'Product',
                          description: 'Tell members what the group is buying.',
                          icon: Icons.inventory_2_outlined,
                          children: [
                            TextFormField(
                              key: const Key('deal-title-field'),
                              controller: _titleController,
                              textCapitalization: TextCapitalization.words,
                              textInputAction: TextInputAction.next,
                              onChanged: (_) => setState(() {}),
                              decoration: const InputDecoration(
                                labelText: 'Product name',
                                hintText: 'e.g. 25kg Rice Sack',
                                prefixIcon: Icon(Icons.inventory_2_outlined),
                              ),
                              validator: viewModel.validateTitle,
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              key: const Key('deal-description-field'),
                              controller: _descriptionController,
                              textCapitalization: TextCapitalization.sentences,
                              maxLines: 3,
                              decoration: const InputDecoration(
                                labelText: 'Description (optional)',
                                hintText:
                                    'Brand, size, where you are buying it…',
                                alignLabelWithHint: true,
                              ),
                              validator: viewModel.validateDescription,
                            ),
                            const SizedBox(height: 18),
                            Text('Category', style: theme.textTheme.labelLarge),
                            const SizedBox(height: 8),
                            _CategorySelector(
                              category: _category,
                              onChanged: viewModel.isSubmitting
                                  ? null
                                  : (category) =>
                                        setState(() => _category = category),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        AppFormSection(
                          title: 'Split',
                          description:
                              'Set the total purchase and what each member receives.',
                          icon: Icons.call_split_outlined,
                          children: [
                            _AdaptivePair(
                              first: TextFormField(
                                key: const Key('deal-total-price-field'),
                                controller: _totalPriceController,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(
                                    RegExp(r'[0-9.]'),
                                  ),
                                ],
                                onChanged: (_) => setState(() {}),
                                decoration: const InputDecoration(
                                  labelText: 'Total price',
                                  hintText: '900',
                                  prefixText: 'P ',
                                ),
                                validator: viewModel.validateTotalPrice,
                              ),
                              second: TextFormField(
                                key: const Key('deal-amount-field'),
                                controller: _amountController,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(
                                    RegExp(r'[0-9.]'),
                                  ),
                                ],
                                onChanged: (_) => setState(() {}),
                                decoration: const InputDecoration(
                                  labelText: 'Total amount',
                                  hintText: '25',
                                ),
                                validator: (value) =>
                                    viewModel.validateAmount(value, _unit),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text('Unit', style: theme.textTheme.labelLarge),
                            const SizedBox(height: 8),
                            _UnitSelector(
                              unit: _unit,
                              onChanged: viewModel.isSubmitting
                                  ? null
                                  : (unit) => setState(() => _unit = unit),
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              key: const Key('deal-total-slots-field'),
                              controller: _totalSlotsController,
                              keyboardType: TextInputType.number,
                              onChanged: (_) => setState(() {}),
                              autovalidateMode:
                                  AutovalidateMode.onUserInteraction,
                              decoration: const InputDecoration(
                                labelText: 'Slots',
                                hintText: 'How many students split this?',
                                prefixIcon: Icon(Icons.groups_outlined),
                              ),
                              validator: (value) =>
                                  viewModel.validateTotalSlots(
                                    value,
                                    amount: _amountController.text,
                                    unit: _unit,
                                  ),
                            ),
                            _SplitPreview(split: split),
                            _SharePreview(share: share),
                          ],
                        ),
                        const SizedBox(height: 16),
                        AppFormSection(
                          title: 'Pickup',
                          description:
                              'Choose where members collect and when claims close.',
                          icon: Icons.storefront_outlined,
                          children: [
                            TextFormField(
                              key: const Key('deal-pickup-location-field'),
                              controller: _pickupLocationController,
                              textCapitalization: TextCapitalization.words,
                              onChanged: (_) => setState(() {}),
                              decoration: const InputDecoration(
                                labelText: 'Pickup location',
                                hintText: 'e.g. USJR Main Gate',
                                prefixIcon: Icon(Icons.place_outlined),
                              ),
                              validator: viewModel.validatePickupLocation,
                            ),
                            const SizedBox(height: 18),
                            Text('Deadline', style: theme.textTheme.labelLarge),
                            const SizedBox(height: 8),
                            _DeadlinePicker(
                              closesAt: _closesAt,
                              errorText: _deadlineError,
                              onPressed: viewModel.isSubmitting
                                  ? null
                                  : _pickDeadline,
                              onCleared: _closesAt == null
                                  ? null
                                  : () => setState(() {
                                      _closesAt = null;
                                      _deadlineError = null;
                                    }),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        AppFormSection(
                          title: 'Payment',
                          description:
                              'Add manual payment instructions for students who claim a slot.',
                          icon: Icons.payments_outlined,
                          children: [
                            _AdaptivePair(
                              first: TextFormField(
                                key: const Key('deal-payment-method-field'),
                                controller: _paymentMethodController,
                                textCapitalization: TextCapitalization.words,
                                textInputAction: TextInputAction.next,
                                decoration: const InputDecoration(
                                  labelText: 'Payment method (optional)',
                                  hintText: 'GCash, Maya, bank transfer, cash',
                                  prefixIcon: Icon(
                                    Icons.account_balance_wallet_outlined,
                                  ),
                                ),
                                validator: viewModel.validatePaymentMethod,
                              ),
                              second: TextFormField(
                                key: const Key(
                                  'deal-payment-account-name-field',
                                ),
                                controller: _paymentAccountNameController,
                                textCapitalization: TextCapitalization.words,
                                textInputAction: TextInputAction.next,
                                decoration: const InputDecoration(
                                  labelText: 'Account name (optional)',
                                  hintText: 'Name students should pay',
                                ),
                                validator: viewModel.validatePaymentAccountName,
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              key: const Key(
                                'deal-payment-account-handle-field',
                              ),
                              controller: _paymentAccountHandleController,
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                labelText:
                                    'Account number or handle (optional)',
                                hintText:
                                    'Mobile number, bank account, or username',
                                prefixIcon: Icon(Icons.tag_outlined),
                              ),
                              validator: viewModel.validatePaymentAccountHandle,
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              key: const Key('deal-payment-instructions-field'),
                              controller: _paymentInstructionsController,
                              textCapitalization: TextCapitalization.sentences,
                              maxLines: 2,
                              decoration: const InputDecoration(
                                labelText: 'Payment instructions (optional)',
                                hintText:
                                    'e.g. Send a screenshot after paying.',
                                alignLabelWithHint: true,
                              ),
                              validator: viewModel.validatePaymentInstructions,
                            ),
                          ],
                        ),
                        if (showReview) ...[
                          const SizedBox(height: 16),
                          AppFormSection(
                            key: const Key('deal-review'),
                            title: 'Review',
                            description: 'Confirm the share before publishing.',
                            icon: Icons.fact_check_outlined,
                            children: [
                              _ReviewSummary(
                                title: _titleController.text,
                                category: _category,
                                split: split,
                                share: share,
                                pickupLocation: _pickupLocationController.text,
                                closesAt: _closesAt,
                              ),
                            ],
                          ),
                        ],
                        if (viewModel.errorMessage != null) ...[
                          const SizedBox(height: 16),
                          AppBanner.error(message: viewModel.errorMessage!),
                        ],
                        const SizedBox(height: 20),
                        FilledButton.icon(
                          key: const Key('deal-submit-button'),
                          onPressed: viewModel.isSubmitting
                              ? null
                              : () => _submit(viewModel),
                          icon: viewModel.isSubmitting
                              ? const SizedBox.square(
                                  dimension: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.4,
                                  ),
                                )
                              : const Icon(Icons.publish_outlined),
                          label: Text(
                            viewModel.isSubmitting
                                ? 'Publishing…'
                                : 'Publish deal',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _pickDeadline() async {
    FocusScope.of(context).unfocus();
    final now = DateTime.now();

    final picked = await showDatePicker(
      context: context,
      initialDate: _closesAt ?? now.add(const Duration(days: 3)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked == null) return;

    setState(() {
      // The picker returns midnight; a deal closes at the end of the day it
      // was set to, otherwise picking today would close it immediately.
      _closesAt = DateTime(picked.year, picked.month, picked.day, 23, 59);
      _deadlineError = null;
    });
  }

  Future<void> _submit(CreateDealViewModel viewModel) async {
    FocusScope.of(context).unfocus();

    final deadlineError = viewModel.validateDeadline(_closesAt);
    setState(() => _deadlineError = deadlineError);

    if (!(_formKey.currentState?.validate() ?? false) ||
        deadlineError != null) {
      return;
    }

    final draft = DealDraft(
      hubId: widget.hubId,
      title: _titleController.text,
      description: _descriptionController.text.trim().isEmpty
          ? null
          : _descriptionController.text,
      category: _category,
      totalPrice: double.parse(_totalPriceController.text.trim()),
      amount: double.parse(_amountController.text.trim()),
      unit: _unit,
      totalSlots: int.parse(_totalSlotsController.text.trim()),
      pickupLocation: _pickupLocationController.text,
      paymentMethod: _paymentMethodController.text,
      paymentAccountName: _paymentAccountNameController.text,
      paymentAccountHandle: _paymentAccountHandleController.text,
      paymentInstructions: _paymentInstructionsController.text,
      closesAt: _closesAt,
    );

    final deal = await viewModel.submit(draft);
    if (deal == null || !mounted) return;

    Navigator.of(context).pop(deal);
  }
}

class _AdaptivePair extends StatelessWidget {
  const _AdaptivePair({required this.first, required this.second});

  final Widget first;
  final Widget second;

  @override
  Widget build(BuildContext context) {
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 420 || textScale > 1.3) {
          return Column(children: [first, const SizedBox(height: 12), second]);
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: first),
            const SizedBox(width: 12),
            Expanded(child: second),
          ],
        );
      },
    );
  }
}

class _ReviewSummary extends StatelessWidget {
  const _ReviewSummary({
    required this.title,
    required this.category,
    required this.split,
    required this.share,
    required this.pickupLocation,
    required this.closesAt,
  });

  final String title;
  final DealCategory category;
  final CostSplit? split;
  final PhysicalShare? share;
  final String pickupLocation;
  final DateTime? closesAt;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[
      if (title.trim().isNotEmpty)
        _ReviewRow(
          icon: Icons.inventory_2_outlined,
          label: title.trim(),
          supporting: category.label,
        ),
      if (split != null)
        _ReviewRow(
          icon: Icons.payments_outlined,
          label: '${formatPeso(split!.pricePerShare)} per share',
          supporting: split!.isEven
              ? '${split!.slots} equal shares'
              : '${split!.slots} rounded shares',
        ),
      if (share != null && share!.dividesEvenly)
        _ReviewRow(
          icon: Icons.scale_outlined,
          label: '${share!.shareLabel} each',
          supporting: share!.totalLabel,
        ),
      if (pickupLocation.trim().isNotEmpty)
        _ReviewRow(
          icon: Icons.place_outlined,
          label: pickupLocation.trim(),
          supporting: closesAt == null
              ? 'No claim deadline'
              : 'Closes ${closesAt!.month}/${closesAt!.day}/${closesAt!.year}',
        ),
    ];

    return Column(
      children: [
        for (var index = 0; index < rows.length; index++) ...[
          rows[index],
          if (index != rows.length - 1) ...[
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 12),
          ],
        ],
      ],
    );
  }
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow({
    required this.icon,
    required this.label,
    required this.supporting,
  });

  final IconData icon;
  final String label;
  final String supporting;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 2),
              Text(
                supporting,
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
}

class _CategorySelector extends StatelessWidget {
  const _CategorySelector({required this.category, required this.onChanged});

  final DealCategory category;
  final ValueChanged<DealCategory>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final option in DealCategory.values)
          ChoiceChip(
            key: Key('deal-category-${option.name}'),
            label: Text(option.label),
            selected: option == category,
            onSelected: onChanged == null
                ? null
                : (selected) {
                    if (selected) onChanged!(option);
                  },
          ),
      ],
    );
  }
}

/// Weights and volumes divide freely; countable goods do not. Picking the unit
/// is how the poster tells the app which kind of thing this is.
class _UnitSelector extends StatelessWidget {
  const _UnitSelector({required this.unit, required this.onChanged});

  final DealUnit unit;
  final ValueChanged<DealUnit>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final option in DealUnit.values)
          ChoiceChip(
            key: Key('deal-unit-${option.name}'),
            label: Text(option.label),
            selected: option == unit,
            onSelected: onChanged == null
                ? null
                : (selected) {
                    if (selected) onChanged!(option);
                  },
          ),
      ],
    );
  }
}

/// The whole point of the app: what one student actually pays.
class _SplitPreview extends StatelessWidget {
  const _SplitPreview({required this.split});

  final CostSplit? split;

  @override
  Widget build(BuildContext context) {
    final split = this.split;
    if (split == null) return const SizedBox.shrink();

    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.call_split,
                size: 16,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Each student pays ${formatPeso(split.pricePerShare)}',
                  key: const Key('deal-split-preview'),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
          // An uneven split is stated, not hidden: the shares round up, so they
          // collect a few centavos more than the item costs.
          if (!split.isEven) ...[
            const SizedBox(height: 4),
            Text(
              '${split.slots} shares collect ${formatPeso(split.collected)} — '
              '${formatPeso(split.surplus)} over. The difference stays with you.',
              key: const Key('deal-split-surplus'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The other half of what a student needs to know: not just what they pay, but
/// what they actually get.
class _SharePreview extends StatelessWidget {
  const _SharePreview({required this.share});

  final PhysicalShare? share;

  @override
  Widget build(BuildContext context) {
    final share = this.share;
    // A split that does not divide is an error, not a preview — the slots field
    // is already saying so, and repeating it as a cheerful summary would be odd.
    if (share == null || !share.dividesEvenly) return const SizedBox.shrink();

    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.inventory_2_outlined,
            size: 16,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Each student gets ${share.shareLabel}',
              key: const Key('deal-share-preview'),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DeadlinePicker extends StatelessWidget {
  const _DeadlinePicker({
    required this.closesAt,
    required this.errorText,
    required this.onPressed,
    required this.onCleared,
  });

  final DateTime? closesAt;
  final String? errorText;
  final VoidCallback? onPressed;
  final VoidCallback? onCleared;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final deadline = closesAt;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                key: const Key('deal-deadline-button'),
                onPressed: onPressed,
                icon: const Icon(Icons.event_outlined, size: 18),
                label: Text(
                  deadline == null
                      ? 'Set a deadline (optional)'
                      : 'Closes ${deadline.month}/${deadline.day}/${deadline.year}',
                ),
                style: const ButtonStyle(alignment: Alignment.centerLeft),
              ),
            ),
            if (onCleared != null) ...[
              const SizedBox(width: 8),
              IconButton(
                onPressed: onCleared,
                icon: const Icon(Icons.close),
                tooltip: 'Clear deadline',
              ),
            ],
          ],
        ),
        if (errorText != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 12),
            child: Text(
              errorText!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
      ],
    );
  }
}
