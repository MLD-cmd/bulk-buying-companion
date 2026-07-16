import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/auth_repository.dart';
import '../shared/app_banner.dart';
import 'auth_viewmodel.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmationController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) =>
          AuthViewModel(authRepository: context.read<AuthRepository>()),
      child: Consumer<AuthViewModel>(
        builder: (context, viewModel, _) {
          final isRegistering = viewModel.mode == AuthMode.register;
          return Scaffold(
            body: SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 24,
                    ),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight - 48,
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 440),
                          child: Form(
                            key: _formKey,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const _BrandMark(),
                                const SizedBox(height: 24),
                                Text(
                                  isRegistering
                                      ? 'Create your account'
                                      : 'Welcome back',
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineMedium
                                      ?.copyWith(fontSize: 30),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  isRegistering
                                      ? 'Register with your email to start splitting smarter.'
                                      : 'Log in with your email to continue.',
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context).textTheme.bodyLarge
                                      ?.copyWith(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                        height: 1.4,
                                      ),
                                ),
                                const SizedBox(height: 24),
                                _ModeSelector(
                                  mode: viewModel.mode,
                                  onChanged: viewModel.isSubmitting
                                      ? null
                                      : (mode) {
                                          _formKey.currentState?.reset();
                                          viewModel.setMode(mode);
                                        },
                                ),
                                const SizedBox(height: 24),
                                AnimatedSize(
                                  duration: const Duration(milliseconds: 200),
                                  alignment: Alignment.topCenter,
                                  child: isRegistering
                                      ? Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: 16,
                                          ),
                                          child: TextFormField(
                                            key: const Key('auth-name-field'),
                                            controller: _nameController,
                                            textInputAction:
                                                TextInputAction.next,
                                            autofillHints: const [
                                              AutofillHints.name,
                                            ],
                                            decoration: const InputDecoration(
                                              labelText: 'Full name',
                                              prefixIcon: Icon(
                                                Icons.person_outline,
                                              ),
                                            ),
                                            validator: (value) {
                                              if ((value ?? '')
                                                  .trim()
                                                  .isEmpty) {
                                                return 'Enter your full name.';
                                              }
                                              return null;
                                            },
                                          ),
                                        )
                                      : const SizedBox.shrink(),
                                ),
                                TextFormField(
                                  key: const Key('auth-email-field'),
                                  controller: _emailController,
                                  keyboardType: TextInputType.emailAddress,
                                  textCapitalization: TextCapitalization.none,
                                  textInputAction: TextInputAction.next,
                                  autofillHints: const [AutofillHints.email],
                                  decoration: const InputDecoration(
                                    labelText: 'Email',
                                    hintText: 'you@example.com',
                                    prefixIcon: Icon(Icons.email_outlined),
                                  ),
                                  validator: (value) {
                                    if ((value ?? '').trim().isEmpty) {
                                      return 'Enter your email address.';
                                    }
                                    if (!EmailValidator.isValid(value!)) {
                                      return 'Enter a valid email address.';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 16),
                                TextFormField(
                                  key: const Key('auth-password-field'),
                                  controller: _passwordController,
                                  obscureText: viewModel.obscurePassword,
                                  textInputAction: isRegistering
                                      ? TextInputAction.next
                                      : TextInputAction.done,
                                  autofillHints: [
                                    isRegistering
                                        ? AutofillHints.newPassword
                                        : AutofillHints.password,
                                  ],
                                  onFieldSubmitted:
                                      isRegistering || viewModel.isSubmitting
                                      ? null
                                      : (_) => _submit(viewModel),
                                  decoration: InputDecoration(
                                    labelText: 'Password',
                                    prefixIcon: const Icon(Icons.lock_outline),
                                    suffixIcon: IconButton(
                                      tooltip: viewModel.obscurePassword
                                          ? 'Show password'
                                          : 'Hide password',
                                      onPressed:
                                          viewModel.togglePasswordVisibility,
                                      icon: Icon(
                                        viewModel.obscurePassword
                                            ? Icons.visibility_outlined
                                            : Icons.visibility_off_outlined,
                                      ),
                                    ),
                                  ),
                                  validator: (value) =>
                                      PasswordValidator.errorFor(value ?? ''),
                                ),
                                if (isRegistering) ...[
                                  const SizedBox(height: 16),
                                  TextFormField(
                                    key: const Key(
                                      'auth-confirm-password-field',
                                    ),
                                    controller: _confirmationController,
                                    obscureText: viewModel.obscureConfirmation,
                                    textInputAction: TextInputAction.done,
                                    autofillHints: const [
                                      AutofillHints.newPassword,
                                    ],
                                    onFieldSubmitted: viewModel.isSubmitting
                                        ? null
                                        : (_) => _submit(viewModel),
                                    decoration: InputDecoration(
                                      labelText: 'Confirm password',
                                      prefixIcon: const Icon(
                                        Icons.lock_reset_outlined,
                                      ),
                                      suffixIcon: IconButton(
                                        tooltip: viewModel.obscureConfirmation
                                            ? 'Show confirmation'
                                            : 'Hide confirmation',
                                        onPressed: viewModel
                                            .toggleConfirmationVisibility,
                                        icon: Icon(
                                          viewModel.obscureConfirmation
                                              ? Icons.visibility_outlined
                                              : Icons.visibility_off_outlined,
                                        ),
                                      ),
                                    ),
                                    validator: (value) {
                                      if (value != _passwordController.text) {
                                        return 'Passwords do not match.';
                                      }
                                      return null;
                                    },
                                  ),
                                ],
                                if (viewModel.errorMessage != null) ...[
                                  const SizedBox(height: 16),
                                  AppBanner.error(
                                    message: viewModel.errorMessage!,
                                  ),
                                ],
                                if (viewModel.noticeMessage != null) ...[
                                  const SizedBox(height: 16),
                                  AppBanner.notice(
                                    message: viewModel.noticeMessage!,
                                    icon: Icons.mark_email_read_outlined,
                                  ),
                                ],
                                const SizedBox(height: 20),
                                FilledButton(
                                  onPressed: viewModel.isSubmitting
                                      ? null
                                      : () => _submit(viewModel),
                                  child: viewModel.isSubmitting
                                      ? const SizedBox.square(
                                          dimension: 22,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2.5,
                                          ),
                                        )
                                      : Text(
                                          isRegistering
                                              ? 'Create account'
                                              : 'Log in',
                                        ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _submit(AuthViewModel viewModel) async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;
    await viewModel.submit(
      displayName: _nameController.text,
      email: _emailController.text,
      password: _passwordController.text,
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          key: const Key('auth-brand-mark'),
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.shopping_basket_outlined,
            color: Theme.of(context).colorScheme.onPrimaryContainer,
            size: 32,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Campus Split-Share',
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ],
    );
  }
}

class _ModeSelector extends StatelessWidget {
  const _ModeSelector({required this.mode, required this.onChanged});

  final AuthMode mode;
  final ValueChanged<AuthMode>? onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 52,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: AuthMode.values.map((item) {
          final selected = item == mode;
          final label = item == AuthMode.login ? 'Login' : 'Register';
          return Expanded(
            child: Semantics(
              selected: selected,
              button: true,
              child: InkWell(
                borderRadius: BorderRadius.circular(9),
                onTap: onChanged == null ? null : () => onChanged!(item),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected ? scheme.surface : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                    boxShadow: selected
                        ? const [
                            BoxShadow(
                              color: Color(0x10000000),
                              blurRadius: 6,
                              offset: Offset(0, 1),
                            ),
                          ]
                        : null,
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
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
