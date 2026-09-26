/// Client ID de tipo "Aplicación web" creado en Google Cloud Console para
/// Google Sign-In. No es un secreto -- es un identificador público (a
/// diferencia de un "client secret", que este flujo nativo no usa en
/// ningún momento) -- por eso es seguro que viva embebido en la app.
///
/// Se usa como `serverClientId` de [GoogleSignIn]: hace que el ID token
/// que entrega Google tenga como destinatario (`audience`) a ESTE backend,
/// que es justamente lo que verifica `GOOGLE_WEB_CLIENT_ID` en el `.env`
/// del servidor -- ambos valores deben ser el mismo Client ID.
class GoogleAuthConfig {
  GoogleAuthConfig._();

  static const String webClientId =
      '131344811660-r7hv2ps3dasdlvos4719i674sfn30eus.apps.googleusercontent.com';
}
