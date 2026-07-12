import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/hub_repository.dart';
import '../../data/services/location_service.dart';
import '../../models/hub.dart';
import '../shared/app_theme.dart';
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
    return Scaffold(
      appBar: AppBar(title: const Text('Register a hub')),
      body: SafeArea(
        child: Consumer<CreateHubViewModel>(
          builder: (context, viewModel, _) {
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Add a dormitory or area hub so students nearby can find '
                      'it and split bulk buys together.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      key: const Key('hub-name-field'),
                      controller: _nameController,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Hub name',
                        hintText: 'e.g. Magallanes Residence',
                        prefixIcon: Icon(Icons.apartment_outlined),
                        border: OutlineInputBorder(),
                      ),
                      validator: viewModel.validateName,
                    ),
                    const SizedBox(height: 20),
                    Text('Type', style: _labelStyle(context)),
                    const SizedBox(height: 8),
                    _TypeSelector(
                      type: _type,
                      onChanged: viewModel.isSubmitting
                          ? null
                          : (type) => setState(() => _type = type),
                    ),
                    const SizedBox(height: 24),
                    Text('Location', style: _labelStyle(context)),
                    const SizedBox(height: 8),
                    _UseMyLocationButton(
                      isLocating: viewModel.isLocating,
                      onPressed: viewModel.isSubmitting
                          ? null
                          : () => _useMyLocation(viewModel),
                    ),
                    if (viewModel.locationError != null) ...[
                      const SizedBox(height: 10),
                      _Banner(
                        message: viewModel.locationError!,
                        icon: Icons.location_disabled_outlined,
                        isError: false,
                      ),
                    ],
                    const SizedBox(height: 14),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextFormField(
                            key: const Key('hub-latitude-field'),
                            controller: _latitudeController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                              signed: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Latitude',
                              hintText: '10.2954',
                              border: OutlineInputBorder(),
                            ),
                            validator: viewModel.validateLatitude,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            key: const Key('hub-longitude-field'),
                            controller: _longitudeController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                              signed: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Longitude',
                              hintText: '123.8969',
                              border: OutlineInputBorder(),
                            ),
                            validator: viewModel.validateLongitude,
                          ),
                        ),
                      ],
                    ),
                    if (viewModel.errorMessage != null) ...[
                      const SizedBox(height: 16),
                      _Banner(
                        message: viewModel.errorMessage!,
                        icon: Icons.error_outline,
                        isError: true,
                      ),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      key: const Key('hub-submit-button'),
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
                          : const Text('Register hub'),
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

class _TypeSelector extends StatelessWidget {
  const _TypeSelector({required this.type, required this.onChanged});

  final HubType type;
  final ValueChanged<HubType>? onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 52,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
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
                borderRadius: BorderRadius.circular(10),
                onTap: onChanged == null ? null : () => onChanged!(item),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected ? scheme.surface : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: selected
                        ? const [
                            BoxShadow(
                              color: Color(0x18000000),
                              blurRadius: 8,
                              offset: Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: selected
                          ? scheme.onSurface
                          : scheme.onSurfaceVariant,
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
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        foregroundColor: AppTheme.accent,
        side: BorderSide(color: AppTheme.accent.withValues(alpha: 0.5)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
      icon: isLocating
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2.2),
            )
          : const Icon(Icons.my_location_outlined, size: 20),
      label: Text(isLocating ? 'Locating…' : 'Use my current location'),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.message,
    required this.icon,
    required this.isError,
  });

  final String message;
  final IconData icon;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background = isError
        ? scheme.errorContainer
        : scheme.surfaceContainerHighest;
    final foreground = isError ? scheme.onErrorContainer : scheme.onSurface;

    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: foreground, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(message, style: TextStyle(color: foreground)),
            ),
          ],
        ),
      ),
    );
  }
}
