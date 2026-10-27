import 'package:url_launcher/url_launcher.dart';

import '../../../core/error/app_failure.dart';
import '../../../core/validators/validators.dart';

/// Abre una URL en una aplicación externa. Se abstrae para poder probar sin
/// plataforma.
abstract interface class UrlOpener {
  /// Devuelve `false` si no hay aplicación que pueda abrirla.
  Future<bool> open(Uri uri);
}

class UrlLauncherOpener implements UrlOpener {
  @override
  Future<bool> open(Uri uri) =>
      launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// Mensaje de bienvenida por WhatsApp mediante un enlace `wa.me` (sin la API
/// de WhatsApp Business ni servicios de pago). Abre WhatsApp con el texto
/// escrito y el administrador lo envía a mano.
///
/// El mensaje NUNCA incluye contraseñas ni enlaces de activación: esos llegan
/// solo al correo del trabajador.
class WhatsAppInvite {
  const WhatsAppInvite(this._opener);

  final UrlOpener _opener;

  static const countryCode = '51';

  static String message(String nombres) =>
      'Hola ${nombres.trim()}, te damos la bienvenida a La Granja Azul. '
      'Te enviamos dos correos a tu dirección registrada: uno para crear tu '
      'contraseña y otro para verificar tu correo. Complétalos (revisa también '
      'spam) y luego inicia sesión en la app con tu correo y tu nueva contraseña.';

  /// `https://wa.me/51XXXXXXXXX?text=...`. Lanza [AppFailure] si el celular
  /// no es válido.
  static Uri uriFor({required String celular, required String nombres}) {
    final error = Validators.celular(celular);
    if (error != null) throw AppFailure(error);
    return Uri.https(
      'wa.me',
      '/$countryCode${celular.trim()}',
      {'text': message(nombres)},
    );
  }

  Future<void> send({required String celular, required String nombres}) async {
    final uri = uriFor(celular: celular, nombres: nombres);
    final opened = await _opener.open(uri);
    if (!opened) {
      throw const AppFailure(
          'No se pudo abrir WhatsApp. Verifica que esté instalado.');
    }
  }
}
