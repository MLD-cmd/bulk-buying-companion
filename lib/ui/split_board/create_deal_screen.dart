import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/deal_repository.dart';
import '../../models/cost_split.dart';
import '../../models/deal.dart';
import '../shared/app_theme.dart';
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
  final _quantityController = TextEditingController();
  final _totalSlotsController = TextEditingController();
  final _pickupLocationController = TextEditingController();

  DealCategory _category = DealCategory.grocery;
  DateTime? _closesAt;
  String? _deadlineError;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _totalPriceController.dispose();
    _quantityController.dispose();
    _totalSlotsController.dispose();
    _pickupLocationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Post a deal')),
      body: SafeArea(
        child: Consumer<CreateDealViewModel>(
          builder: (context, viewModel, _) {
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Buying in bulk for ${widget.hubName}? Post it here and '
                      'let your hubmates claim a share.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      key: const Key('deal-title-field'),
                      controller: _titleController,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Product name',
                        hintText: 'e.g. 25kg Rice Sack',
                        prefixIcon: Icon(Icons.inventory_2_outlined),
                        border: OutlineInputBorder(),
                      ),
                      validator: viewModel.validateTitle,
                    ),
                    const SizedBox(height: 20),
                    TextFormField(
                      key: const Key('deal-description-field'),
                      controller: _descriptionController,
                      textCapitalization: TextCapitalization.sentences,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Description (optional)',
                        hintText: 'Brand, size, where you are buying it…',
                        border: OutlineInputBorder(),
                        alignLabelWithHint: true,
                      ),
                      validator: viewModel.validateDescription,
                    ),
                    const SizedBox(height: 20),
                    Text('Category', style: _labelStyle(context)),
                    const SizedBox(height: 8),
                    _CategorySelector(
                      category: _category,
                      onChanged: viewModel.isSubmitting
                          ? null
                          : (category) => setState(() => _category = category),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextFormField(
                            key: const Key('deal-total-price-field'),
                            controller: _totalPriceController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            // keyboardType is only a hint — a paste, or a
                            // desktop keyboard, will happily put 'Infinity' or
                            // '1e400' in here, and both parse to a double the
                            // centavo arithmetic cannot use.
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
                              border: OutlineInputBorder(),
                            ),
                            validator: viewModel.validateTotalPrice,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            key: const Key('deal-quantity-field'),
                            controller: _quantityController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Quantity',
                              hintText: '1',
                              border: OutlineInputBorder(),
                            ),
                            validator: viewModel.validateQuantity,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    TextFormField(
                      key: const Key('deal-total-slots-field'),
                      controller: _totalSlotsController,
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Slots',
                        hintText: 'How many students split this?',
                        prefixIcon: Icon(Icons.groups_outlined),
                        border: OutlineInputBorder(),
                      ),
                      validator: viewModel.validateTotalSlots,
                    ),
                    _SplitPreview(
                      split: viewModel.previewSplit(
                        totalPrice: _totalPriceController.text,
                        totalSlots: _totalSlotsController.text,
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextFormField(
                      key: const Key('deal-pickup-location-field'),
                      controller: _pickupLocationController,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Pickup location',
                        hintText: 'e.g. USJR Main Gate',
                        prefixIcon: Icon(Icons.storefront_outlined),
                        border: OutlineInputBorder(),
                      ),
                      validator: viewModel.validatePickupLocation,
                    ),
                    const SizedBox(height: 20),
                    Text('Deadline', style: _labelStyle(context)),
                    const SizedBox(height: 8),
                    _DeadlinePicker(
                      closesAt: _closesAt,
                      errorText: _deadlineError,
                      onPressed: viewModel.isSubmitting ? null : _pickDeadline,
                      onCleared: _closesAt == null
                          ? null
                          : () => setState(() {
                              _closesAt = null;
                              _deadlineError = null;
                            }),
                    ),
                    if (viewModel.errorMessage != null) ...[
                      const SizedBox(height: 16),
                      _Banner(message: viewModel.errorMessage!),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      key: const Key('deal-submit-button'),
                      onPressed: viewModel.isSubmitting
                          ? null
                          : () => _submit(viewModel),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                        backgroundColor: AppTheme.accent,
                        foregroundColor: Colors.white,
                        textStyle: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      child: viewModel.isSubmitting
                          ? const SizedBox.square(
                              dimension: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Publish deal'),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  TextStyle? _labelStyle(BuildContext context) {
    return Theme.of(
      context,
    ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700);
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
      quantity: int.parse(_quantityController.text.trim()),
      totalSlots: int.parse(_totalSlotsController.text.trim()),
      pickupLocation: _pickupLocationController.text,
      closesAt: _closesAt,
    );

    final deal = await viewModel.submit(draft);
    if (deal == null || !mounted) return;

    Navigator.of(context).pop(deal);
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
            children: [
              Icon(Icons.call_split, size: 16, color: theme.colorScheme.primary),
              const SizedBox(width: 6),
              Text(
                'Each student pays ${formatPeso(split.pricePerShare)}',
                key: const Key('deal-split-preview'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.primary,
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
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
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

class _Banner extends StatelessWidget {
  const _Banner({required this.message});

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
