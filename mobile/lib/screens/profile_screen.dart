import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../models/auth.dart';
import '../state/auth_controller.dart';
import '../state/coverage_controller.dart';
import '../state/preferences_controller.dart';
import '../widgets/scope_note.dart';
import 'pick_location_screen.dart';
import 'add_store_screen.dart';
import 'auth_screen.dart';
import 'data_source_screen.dart';
import 'export_history_sheet.dart';

/// Perfil: quién es el usuario, sus opciones de cuenta y, si es
/// administrador, sus herramientas. La información de referencia (fuente de
/// los datos) queda un nivel más adentro para no saturar la pantalla.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();

    return Scaffold(
      appBar: AppBar(title: Text('Perfil', style: AppText.screenTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.horizontalPage),
          children: [
            if (auth.status == AuthStatus.loading)
              const LinearProgressIndicator()
            else if (auth.status == AuthStatus.loggedIn)
              _UserHeader(user: auth.currentUser!)
            else
              const _GuestHeader(),
            if (auth.status == AuthStatus.loggedIn) ...[
              const SizedBox(height: AppSpacing.xxl),
              Text('CUENTA', style: AppText.caption),
              const SizedBox(height: AppSpacing.sm),
              _Tile(
                icon: Icons.edit_outlined,
                title: 'Editar nombre',
                subtitle: auth.currentUser!.hasName
                    ? 'Así te saludamos: ${auth.currentUser!.firstName}'
                    : 'Aún no tienes un nombre; añádelo para el saludo',
                onTap: () => _editName(context, auth),
              ),
            ],
            const SizedBox(height: AppSpacing.xxl),
            Text('PREFERENCIAS', style: AppText.caption),
            const SizedBox(height: AppSpacing.sm),
            const _SuggestionPreferenceCard(),
            const SizedBox(height: AppSpacing.sm),
            const _LocationCard(),
            const SizedBox(height: AppSpacing.sm),
            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: _cardDecoration(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Distancia máxima a las tiendas', style: AppText.productName),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Solo comparamos los supermercados con una tienda dentro de esta distancia.',
                    style: AppText.caption,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const RangePanel(),
                ],
              ),
            ),
            if (auth.isAdmin) ...[
              const SizedBox(height: AppSpacing.xxl),
              Text('ADMINISTRACIÓN', style: AppText.caption),
              const SizedBox(height: AppSpacing.sm),
              _Tile(
                icon: Icons.add_location_alt_outlined,
                title: 'Agregar establecimiento',
                subtitle: 'Registra una tienda que aún no aparece en el mapa',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AddStoreScreen()),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              _Tile(
                icon: Icons.download_outlined,
                title: 'Exportar historiales (CSV)',
                subtitle: 'Precios registrados, por supermercado y periodo',
                onTap: () => ExportHistorySheet.show(context),
              ),
            ],
            const SizedBox(height: AppSpacing.xxl),
            Text('INFORMACIÓN', style: AppText.caption),
            const SizedBox(height: AppSpacing.sm),
            _Tile(
              icon: Icons.update_rounded,
              title: 'Fuente de datos',
              subtitle: 'Cuándo se actualizó cada supermercado',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DataSourceScreen()),
              ),
            ),
            if (auth.status == AuthStatus.loggedIn) ...[
              const SizedBox(height: AppSpacing.xxl),
              OutlinedButton.icon(
                onPressed: auth.logout,
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Cerrar sesión'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.error,
                  side: const BorderSide(color: AppColors.errorSurface),
                  minimumSize: const Size.fromHeight(AppSpacing.buttonHeight),
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.xl),
            Center(child: Text('Convenia — versión 0.1.0', style: AppText.caption)),
          ],
        ),
      ),
    );
  }
}

Future<void> _editName(BuildContext context, AuthController auth) async {
  final controller = TextEditingController(text: auth.currentUser!.hasName ? auth.currentUser!.displayName : '');
  final name = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Editar nombre'),
      content: TextField(
        controller: controller,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(labelText: 'Nombre'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancelar')),
        ElevatedButton(
          onPressed: () => Navigator.of(dialogContext).pop(controller.text.trim()),
          child: const Text('Guardar'),
        ),
      ],
    ),
  );
  if (name != null && name.isNotEmpty) await auth.updateName(name);
}

BoxDecoration _cardDecoration() => BoxDecoration(
  color: AppColors.white,
  borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
  border: Border.all(color: AppColors.mist),
);

class _UserHeader extends StatelessWidget {
  final AuthUser user;

  const _UserHeader({required this.user});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: _cardDecoration(),
      child: Row(
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: AppColors.lavenderMist,
            child: Text(
              user.displayName[0].toUpperCase(),
              style: AppText.hero.copyWith(color: AppColors.brandIndigo),
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(user.displayName, style: AppText.sectionTitle, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(user.email, style: AppText.body, overflow: TextOverflow.ellipsis),
                const SizedBox(height: AppSpacing.sm),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.lavenderMist,
                    borderRadius: BorderRadius.circular(AppSpacing.chipRadius),
                  ),
                  child: Text(
                    user.isAdmin ? 'Administrador' : 'Usuario',
                    style: AppText.caption.copyWith(color: AppColors.brandIndigo),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GuestHeader extends StatelessWidget {
  const _GuestHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: _cardDecoration(),
      child: Column(
        children: [
          const CircleAvatar(
            radius: 30,
            backgroundColor: AppColors.lavenderMist,
            child: Icon(Icons.person_outline_rounded, size: 30, color: AppColors.brandIndigo),
          ),
          const SizedBox(height: AppSpacing.md),
          Text('Estás como invitado', style: AppText.sectionTitle),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Inicia sesión para guardar tus listas en tu cuenta y conservarlas '
            'si cambias de teléfono.',
            style: AppText.body,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.lg),
          ElevatedButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AuthScreen()),
            ),
            child: const Text('Iniciar sesión o crear cuenta'),
          ),
        ],
      ),
    );
  }
}

/// De dónde sale la ubicación: el GPS del teléfono o un punto que la
/// persona eligió a mano (queda guardado en este teléfono).
class _LocationCard extends StatelessWidget {
  const _LocationCard();

  @override
  Widget build(BuildContext context) {
    final prefs = context.watch<PreferencesController>();
    final manual = prefs.manualLocation;

    Future<void> pick() async {
      final picked = await Navigator.of(context).push<ManualLocation>(
        MaterialPageRoute(builder: (_) => PickLocationScreen(initial: manual)),
      );
      if (picked == null) return;
      await prefs.setManualLocation(picked);
      if (context.mounted) {
        await context.read<CoverageController>().configure(radiusKm: prefs.maxDistanceKm, manual: picked);
      }
    }

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Mi ubicación', style: AppText.productName),
          const SizedBox(height: AppSpacing.xs),
          Text(
            manual == null
                ? 'Usamos el GPS de tu teléfono. Si prefieres no darlo, elige tu ubicación a mano.'
                : 'Ubicación elegida: ${manual.label}. La usamos en lugar del GPS.',
            style: AppText.caption,
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            children: [
              OutlinedButton.icon(
                onPressed: pick,
                icon: const Icon(Icons.edit_location_alt_outlined, size: 18),
                label: Text(manual == null ? 'Elegir ubicación' : 'Cambiar'),
              ),
              if (manual != null)
                TextButton(
                  onPressed: () async {
                    await prefs.setManualLocation(null);
                    if (context.mounted) {
                      await context.read<CoverageController>().configure(radiusKm: prefs.maxDistanceKm, manual: null);
                    }
                  },
                  child: const Text('Usar mi GPS'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Criterio con el que se propone un producto al armar una lista.
class _SuggestionPreferenceCard extends StatelessWidget {
  const _SuggestionPreferenceCard();

  @override
  Widget build(BuildContext context) {
    final prefs = context.watch<PreferencesController>();
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Al armar una lista, proponer los productos…', style: AppText.productName),
          const SizedBox(height: AppSpacing.sm),
          for (final option in SuggestionPreference.values)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              onTap: () => prefs.setSuggestion(option),
              leading: Icon(
                option == prefs.suggestion ? Icons.radio_button_checked : Icons.radio_button_off,
                color: option == prefs.suggestion ? AppColors.brandIndigo : AppColors.inkFaint,
              ),
              title: Text(option.label, style: AppText.body.copyWith(color: AppColors.ink)),
              subtitle: Text(option.description, style: AppText.caption),
            ),
          Text('Siempre puedes cambiar el producto propuesto antes de agregarlo.', style: AppText.caption),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  const _Tile({required this.icon, required this.title, required this.subtitle, this.onTap});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Container(
      decoration: _cardDecoration(),
      child: ListTile(
        enabled: enabled,
        onTap: onTap,
        leading: Icon(icon, color: enabled ? AppColors.brandIndigo : AppColors.inkFaint),
        title: Text(title, style: AppText.productName.copyWith(color: enabled ? AppColors.ink : AppColors.inkFaint)),
        subtitle: Text(subtitle, style: AppText.caption),
        trailing: enabled ? const Icon(Icons.chevron_right_rounded, color: AppColors.inkFaint) : null,
      ),
    );
  }
}
