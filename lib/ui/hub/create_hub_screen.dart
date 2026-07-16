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

  HubType _type = HubType.dormitory;

  @override
  void dispose() {
    _nameController.dispose();
    _latitudeController.dispose();
    _longitudeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Register a hub')),
      body: SafeArea(
        child: Consumer<CreateHubViewModel>(
          builder: (context, viewModel, _) {
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
                              textCapitalization: TextCapitalization.words,
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                labelText: 'Hub name',
                                hintText: 'e.g. Magallanes Residence',
                                prefixIcon: Icon(Icons.apartment_outlined),
                              ),
                              validator: viewModel.validateName,
                            ),
                            const SizedBox(height: 18),
                            Text('Hub type', style: theme.textTheme.labelLarge),
                            const SizedBox(height: 8),
                            _TypeSelector(
                              type: _type,
                              onChanged: viewModel.isSubmitting
                                  ? null
                                  : (type) => setState(() => _type = type),
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
                              onPressed: viewModel.isSubmitting
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
                              : const Icon(Icons.add_location_alt_outlined),
                          label: Text(
                            viewModel.isSubmitting
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
    );
  }

  Future<void> _useMyLocation(CreateHubViewModel viewModel) async {
    FocusScope.of(context).unfocus();
    await viewModel.useMyLocation();
    final location = viewModel.capturedLocation;
    if (location == null) return;
    _latitudeController.text = location.latitude.toStringAsFixed(6);
    _longitudeController.text = location.longitude.toStringAsFixed(6);
  }

  Future<void> _submit(CreateHubViewModel viewModel) async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final hub = await viewModel.submit(
      HubDraft(
        name: _nameController.text,
        type: _type,
        latitude: double.parse(_latitudeController.text.trim()),
        longitude: double.parse(_longitudeController.text.trim()),
      ),
    );

    if (hub == null || !mounted) return;
    Navigator.of(context).pop(hub);
  }
}

class _CoordinateFields extends StatelessWidget {
  const _CoordinateFields({
    required this.latitudeController,
    required this.longitudeController,
    required this.validateLatitude,
    required this.validateLongitude,
  });

  final TextEditingController latitudeController;
  final TextEditingController longitudeController;
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
