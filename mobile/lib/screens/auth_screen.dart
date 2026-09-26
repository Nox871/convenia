import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../state/auth_controller.dart';

/// Inicio de sesión y registro con correo y contraseña, en una sola
/// pantalla con un enlace para alternar entre los dos modos. Al confirmar,
/// hace `Navigator.pop` -- quien la abrió (Configuración) refleja la
/// sesión sola porque `AuthController` es compartido en toda la app.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _confirmController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isRegisterMode = false;
  bool _submitting = false;
  bool _obscurePassword = true;
  bool _acceptedTerms = false;
  bool _showTermsError = false;

  @override
  void dispose() {
    _nameController.dispose();
    _lastNameController.dispose();
    _confirmController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final valid = _formKey.currentState!.validate();
    if (_isRegisterMode && !_acceptedTerms) setState(() => _showTermsError = true);
    if (!valid || (_isRegisterMode && !_acceptedTerms)) return;

    setState(() => _submitting = true);
    final auth = context.read<AuthController>();
    final success = _isRegisterMode
        ? await auth.register(
            _emailController.text.trim(),
            _passwordController.text,
            name: '${_nameController.text.trim()} ${_lastNameController.text.trim()}'.trim(),
          )
        : await auth.login(_emailController.text.trim(), _passwordController.text);
    setState(() => _submitting = false);

    if (success && mounted) Navigator.of(context).pop();
  }

  Future<void> _continueWithGoogle() async {
    setState(() => _submitting = true);
    final success = await context.read<AuthController>().loginWithGoogle();
    setState(() => _submitting = false);

    if (success && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();

    return Scaffold(
      appBar: AppBar(
        title: Text(_isRegisterMode ? 'Crear cuenta' : 'Iniciar sesión', style: AppText.screenTitle),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.horizontalPage),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _isRegisterMode
                        ? 'Crea una cuenta para conservar tu historial de listas aunque cambies de teléfono.'
                        : 'Inicia sesión para ver tu historial de listas en cualquier dispositivo.',
                    style: AppText.body,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  if (_isRegisterMode) ...[
                    TextFormField(
                      controller: _nameController,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(labelText: 'Nombre'),
                      validator: (value) =>
                          (value == null || value.trim().isEmpty) ? 'Ingresa tu nombre' : null,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    TextFormField(
                      controller: _lastNameController,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(labelText: 'Apellido'),
                      validator: (value) =>
                          (value == null || value.trim().isEmpty) ? 'Ingresa tu apellido' : null,
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Correo'),
                    validator: (value) => (value == null || !value.contains('@'))
                        ? 'Ingresa un correo válido'
                        : null,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      labelText: 'Contraseña',
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                        ),
                        tooltip: _obscurePassword ? 'Mostrar contraseña' : 'Ocultar contraseña',
                        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                      ),
                    ),
                    validator: (value) => (value == null || value.length < 8)
                        ? 'Mínimo 8 caracteres'
                        : null,
                  ),
                  if (_isRegisterMode) ...[
                    const SizedBox(height: AppSpacing.md),
                    TextFormField(
                      controller: _confirmController,
                      obscureText: _obscurePassword,
                      decoration: const InputDecoration(labelText: 'Confirmar contraseña'),
                      validator: (value) =>
                          value != _passwordController.text ? 'Las contraseñas no coinciden' : null,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    CheckboxListTile(
                      value: _acceptedTerms,
                      onChanged: (value) => setState(() {
                        _acceptedTerms = value ?? false;
                        _showTermsError = false;
                      }),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        'Autorizo el tratamiento de mis datos personales para crear y '
                        'mantener mi cuenta.',
                        style: AppText.body,
                      ),
                      subtitle: GestureDetector(
                        onTap: () => _showDataPolicy(context),
                        child: Text(
                          'Ver qué datos guardamos',
                          style: AppText.caption.copyWith(
                            color: AppColors.brandIndigo,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ),
                    if (_showTermsError)
                      Text(
                        'Debes autorizarlo para crear la cuenta.',
                        style: AppText.caption.copyWith(color: AppColors.error),
                      ),
                  ],
                  if (auth.errorMessage != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      auth.errorMessage!,
                      style: const TextStyle(color: AppColors.error),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: AppSpacing.xl),
                  ElevatedButton(
                    onPressed: _submitting ? null : _submit,
                    child: _submitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(_isRegisterMode ? 'Crear cuenta' : 'Iniciar sesión'),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextButton(
                    onPressed: _submitting ? null : () => setState(() => _isRegisterMode = !_isRegisterMode),
                    child: Text(
                      _isRegisterMode
                          ? '¿Ya tienes cuenta? Inicia sesión'
                          : '¿No tienes cuenta? Regístrate',
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                    child: Row(
                      children: [
                        const Expanded(child: Divider()),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                          child: Text('o', style: AppText.caption),
                        ),
                        const Expanded(child: Divider()),
                      ],
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _submitting ? null : _continueWithGoogle,
                    icon: const Icon(Icons.g_mobiledata_rounded, size: 28),
                    label: const Text('Continuar con Google'),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  GestureDetector(
                    onTap: () => _showDataPolicy(context),
                    child: Text(
                      'Al continuar con Google autorizas el tratamiento de tus datos personales. '
                      'Ver qué datos guardamos.',
                      style: AppText.caption,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Qué se guarda y para qué (Ley 1581 de 2012). Sólo lo que la app usa.
void _showDataPolicy(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Datos que guardamos'),
      content: const SingleChildScrollView(
        child: Text(
          'Guardamos únicamente:\n\n'
          '• Tu nombre, para saludarte y mostrarlo en tu perfil.\n'
          '• Tu correo, para que puedas iniciar sesión.\n'
          '• Tu contraseña, cifrada: ni nosotros podemos leerla.\n'
          '• Tus listas de compras y sus presupuestos, para que las conserves si cambias de teléfono.\n'
          '• La fecha en que aceptaste este tratamiento.\n\n'
          'No vendemos ni compartimos tus datos con terceros. Tu ubicación no se asocia a tu cuenta ni se guarda en la base de datos: '
          'solo se usa en el momento para mostrarte tiendas cercanas.\n\n'
          'Puedes actualizar tu nombre en Perfil cuando quieras.',
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Entendido')),
      ],
    ),
  );
}
