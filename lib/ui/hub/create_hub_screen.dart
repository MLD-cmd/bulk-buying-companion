import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/hub_repository.dart';
import '../../data/services/location_service.dart';
import '../../models/hub.dart';
import '../shared/app_banner.dart';
import '../shared/app_form_section.dart';
import 'create_hub_viewmodel.dart';

class CreateHubScreen extends StatefulWidget {
  const CreateHubScreen({super.key});

  /// Pops with the registered [Hub], or null when the student backs out.
  static Route<Hub> route() {
    return MaterialPageRoute<Hub>(
      builder: (context) => ChangeNotifierProvider(
        create: (context) => CreateHubViewModel(
          hubRepository: context.read<HubRepository>(),
          locationService: context.read<LocationService>(),
        ),
        child: const CreateHubScreen(),
      ),
    );
  }

  @override
  State<CreateHubScreen> createState() => _CreateHubScreenState();
}

class _CreateHubScreenState extends State<CreateHubScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _latitudeController = TextEditingController();
  final _longitudeController = TextEditingController();
  final _nameFocusNode = FocusNode();
  final _latitudeFocusNode = FocusNode();
  final _longitudeFocusNode = FocusNode();

  HubType _type = HubType.dormitory;
  bool _allowPop = false;
  bool _discardDialogOpen = false;
  bool _locationFlowActive = false;
  bool _registrationFlowActive = false;
  String? _lockedName;
  String? _lockedLatitude;
  String? _lockedLongitude;

  bool get _operationActive => _locationFlowActive || _registrationFlowActive;

  bool get _hasChangedDetails =>
      _nameController.text.isNotEmpty ||
      _latitudeController.text.isNotEmpty ||
      _longitudeController.text.isNotEmpty ||
      _type != HubType.dormitory;

  @override
  void dispose() {
    _nameController.dispose();
    _latitudeController.dispose();
    _longitudeController.dispose();
    _nameFocusNode.dispose();
    _latitudeFocusNode.dispose();
    _longitudeFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope<Hub>(
      canPop: _allowPop || (!_operationActive && !_hasChangedDetails),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_operationActive) _confirmDiscard();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Register a hub')),
        body: SafeArea(
          child: Consumer<CreateHubViewModel>(
            builder: (context, viewModel, _) {
              final registrationLocked =
                  _registrationFlowActive || viewModel.isSubmitting;
              final operationLocked =
                  _operationActive ||
                  viewModel.isSubmitting ||
                  viewModel.isLocating;

              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Add a dormitory or area hub so nearby students can find it and split bulk buys together.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 20),
                          AppFormSection(
                            title: 'Hub details',
                            description: 'Use the name students know locally.',
                            icon: Icons.home_work_outlined,
                            children: [
                              TextFormField(
                                key: const Key('hub-name-field'),
                                controller: _nameController,
                                focusNode: _nameFocusNode,
                                enabled: !operationLocked,
                                textCapitalization: TextCapitalization.words,
                                textInputAction: TextInputAction.next,
                                onChanged: _handleFieldChanged,
                                onFieldSubmitted: (_) =>
                                    _requestFocus(_latitudeFocusNode),
                                decoration: const InputDecoration(
                                  labelText: 'Hub name',
                                  hintText: 'e.g. Magallanes Residence',
                                  prefixIcon: Icon(Icons.apartment_outlined),
                                ),
                                validator: viewModel.validateName,
                              ),
                              const SizedBox(height: 18),
                              Text(
                                'Hub type',
                                style: theme.textTheme.labelLarge,
                              ),
                              const SizedBox(height: 8),
                              _TypeSelector(
                                type: _type,
                                onChanged: operationLocked ? null : _updateType,
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          AppFormSection(
                            title: 'Pickup area',
                            description:
                                'Use your location or enter the saved coordinates.',
                            icon: Icons.location_on_outlined,
                            children: [
                              _UseMyLocationButton(
                                isLocating: viewModel.isLocating,
                                onPressed: operationLocked
                                    ? null
                                    : () => _useMyLocation(viewModel),
                              ),
                              if (viewModel.locationError != null) ...[
                                const SizedBox(height: 12),
                                AppBanner.notice(
                                  message: viewModel.locationError!,
                                  icon: Icons.location_disabled_outlined,
                                ),
                              ],
                              const SizedBox(height: 16),
                              _CoordinateFields(
                                latitudeController: _latitudeController,
                                longitudeController: _longitudeController,
                                latitudeFocusNode: _latitudeFocusNode,
                                longitudeFocusNode: _longitudeFocusNode,
                                enabled: !operationLocked,
                                onChanged: _handleFieldChanged,
                                onLatitudeSubmitted: () =>
                                    _requestFocus(_longitudeFocusNode),
                                onLongitudeSubmitted: _unfocusFields,
                                validateLatitude: viewModel.validateLatitude,
                                validateLongitude: viewModel.validateLongitude,
                              ),
                            ],
                          ),
                          if (viewModel.errorMessage != null) ...[
                            const SizedBox(height: 16),
                            AppBanner.error(message: viewModel.errorMessage!),
                          ],
                          const SizedBox(height: 20),
                          FilledButton.icon(
                            key: const Key('hub-submit-button'),
                            onPressed: operationLocked
                                ? null
                                : () => _submit(viewModel),
                            icon: registrationLocked
                                ? const SizedBox.square(
                                    dimension: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.4,
                                    ),
                                  )
                                : const Icon(Icons.add_location_alt_outlined),
                            label: Text(
                              registrationLocked
                                  ? 'Registering…'
                                  : 'Register hub',
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
      ),
    );
  }

  void _handleFieldChanged(String _) {
    if (!mounted) return;
    if (_operationActive) {
      _restoreLockedFields();
      return;
    }
    setState(() {});
  }

  void _captureLockedFields() {
    _lockedName = _nameController.text;
    _lockedLatitude = _latitudeController.text;
    _lockedLongitude = _longitudeController.text;
  }

  void _restoreLockedFields() {
    _restoreController(_nameController, _lockedName);
    _restoreController(_latitudeController, _lockedLatitude);
    _restoreController(_longitudeController, _lockedLongitude);
  }

  void _restoreController(
    TextEditingController controller,
    String? lockedValue,
  ) {
    if (lockedValue == null || controller.text == lockedValue) return;
    controller.value = TextEditingValue(
      text: lockedValue,
      selection: TextSelection.collapsed(offset: lockedValue.length),
    );
  }

  void _clearLockedFields() {
    _lockedName = null;
    _lockedLatitude = null;
    _lockedLongitude = null;
  }

  void _updateType(HubType type) {
    if (!mounted ||
        _operationActive ||
        _discardDialogOpen ||
        type == _type ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    setState(() => _type = type);
  }

  void _requestFocus(FocusNode focusNode) {
    if (!mounted ||
        _operationActive ||
        _discardDialogOpen ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    focusNode.requestFocus();
  }

  void _unfocusFields() {
    if (!mounted ||
        _operationActive ||
        _discardDialogOpen ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    FocusScope.of(context).unfocus();
  }

  Future<void> _confirmDiscard() async {
    if (!mounted ||
        !_hasChangedDetails ||
        _allowPop ||
        _discardDialogOpen ||
        _operationActive ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }

    _discardDialogOpen = true;
    bool? discard;
    try {
      discard = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Discard these details?'),
          content: const Text(
            'Your unpublished hub details will be lost if you leave now.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Keep editing'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Discard'),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) _discardDialogOpen = false;
    }

    if (!mounted ||
        discard != true ||
        _operationActive ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }

    setState(() => _allowPop = true);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
    Navigator.of(context).pop();
  }

  Future<void> _useMyLocation(CreateHubViewModel viewModel) async {
    if (!mounted ||
        _operationActive ||
        _discardDialogOpen ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }

    FocusScope.of(context).unfocus();
    _captureLockedFields();
    setState(() => _locationFlowActive = true);
    await viewModel.useMyLocation();
    if (!mounted) return;

    final location = viewModel.capturedLocation;
    setState(() {
      if (location != null && viewModel.locationError == null) {
        _latitudeController.text = location.latitude.toStringAsFixed(6);
        _longitudeController.text = location.longitude.toStringAsFixed(6);
      }
      _locationFlowActive = false;
      _clearLockedFields();
    });
  }

  Future<void> _submit(CreateHubViewModel viewModel) async {
    if (!mounted ||
        _operationActive ||
        _discardDialogOpen ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }

    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) {
      await _focusFirstInvalid(viewModel);
      return;
    }

    _captureLockedFields();
    setState(() => _registrationFlowActive = true);
    final hub = await viewModel.submit(
      HubDraft(
        name: _nameController.text,
        type: _type,
        latitude: double.parse(_latitudeController.text.trim()),
        longitude: double.parse(_longitudeController.text.trim()),
      ),
    );

    if (!mounted) return;
    if (hub == null) {
      setState(() {
        _registrationFlowActive = false;
        _clearLockedFields();
      });
      return;
    }

    setState(() => _allowPop = true);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
    Navigator.of(context).pop(hub);
  }

  Future<void> _focusFirstInvalid(CreateHubViewModel viewModel) async {
    FocusNode? firstInvalid;
    if (viewModel.validateName(_nameController.text) != null) {
      firstInvalid = _nameFocusNode;
    } else if (viewModel.validateLatitude(_latitudeController.text) != null) {
      firstInvalid = _latitudeFocusNode;
    } else if (viewModel.validateLongitude(_longitudeController.text) != null) {
      firstInvalid = _longitudeFocusNode;
    }

    if (firstInvalid == null) return;
    firstInvalid.requestFocus();
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    final fieldContext = firstInvalid.context;
    if (fieldContext != null && fieldContext.mounted) {
      await Scrollable.ensureVisible(
        fieldContext,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        alignment: 0.2,
      );
    }
  }
}

class _CoordinateFields extends StatelessWidget {
  const _CoordinateFields({
    required this.latitudeController,
    required this.longitudeController,
    required this.latitudeFocusNode,
    required this.longitudeFocusNode,
    required this.enabled,
    required this.onChanged,
    required this.onLatitudeSubmitted,
    required this.onLongitudeSubmitted,
    required this.validateLatitude,
    required this.validateLongitude,
  });

  final TextEditingController latitudeController;
  final TextEditingController longitudeController;
  final FocusNode latitudeFocusNode;
  final FocusNode longitudeFocusNode;
  final bool enabled;
  final ValueChanged<String> onChanged;
  final VoidCallback onLatitudeSubmitted;
  final VoidCallback onLongitudeSubmitted;
  final FormFieldValidator<String> validateLatitude;
  final FormFieldValidator<String> validateLongitude;

  @override
  Widget build(BuildContext context) {
    final textScale = MediaQuery.textScalerOf(context).scale(1);

    return LayoutBuilder(
      builder: (context, constraints) {
        final stack = constraints.maxWidth < 360 || textScale > 1.3;
        final fields = [
          TextFormField(
            key: const Key('hub-latitude-field'),
            controller: latitudeController,
            focusNode: latitudeFocusNode,
            enabled: enabled,
            textInputAction: TextInputAction.next,
            onChanged: onChanged,
            onFieldSubmitted: (_) => onLatitudeSubmitted(),
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
              signed: true,
            ),
            decoration: const InputDecoration(
              labelText: 'Latitude',
              hintText: '10.2954',
            ),
            validator: validateLatitude,
          ),
          TextFormField(
            key: const Key('hub-longitude-field'),
            controller: longitudeController,
            focusNode: longitudeFocusNode,
            enabled: enabled,
            textInputAction: TextInputAction.done,
            onChanged: onChanged,
            onFieldSubmitted: (_) => onLongitudeSubmitted(),
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
              signed: true,
            ),
            decoration: const InputDecoration(
              labelText: 'Longitude',
              hintText: '123.8969',
            ),
            validator: validateLongitude,
          ),
        ];

        if (stack) {
          return Column(
            children: [fields.first, const SizedBox(height: 12), fields.last],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: fields.first),
            const SizedBox(width: 12),
            Expanded(child: fields.last),
          ],
        );
      },
    );
  }
}

class _TypeSelector extends StatelessWidget {
  const _TypeSelector({required this.type, required this.onChanged});

  final HubType type;
  final ValueChanged<HubType>? onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: HubType.values.map((item) {
          final selected = item == type;
          final label = item == HubType.dormitory ? 'Dormitory' : 'Area hub';
          return Expanded(
            child: Semantics(
              key: Key('hub-type-${item.name}'),
              selected: selected,
              button: true,
              child: InkWell(
                borderRadius: BorderRadius.circular(9),
                onTap: onChanged == null ? null : () => onChanged!(item),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  constraints: const BoxConstraints(minHeight: 44),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected ? scheme.surface : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                    border: selected
                        ? Border.all(color: scheme.outlineVariant)
                        : null,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 10,
                    ),
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: selected
                            ? scheme.onSurface
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _UseMyLocationButton extends StatelessWidget {
  const _UseMyLocationButton({
    required this.isLocating,
    required this.onPressed,
  });

  final bool isLocating;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      key: const Key('hub-use-location-button'),
      onPressed: isLocating ? null : onPressed,
      style: const ButtonStyle(alignment: Alignment.center),
      icon: isLocating
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2.2),
            )
          : const Icon(Icons.my_location_outlined),
      label: Text(isLocating ? 'Locating…' : 'Use my current location'),
    );
  }
}
