# Connecter — checklist para la Mac App Store

Estado a 23 de octubre de 2026. Los textos de la ficha (nombre, subtítulo, descripción, palabras clave, URLs y notas para el revisor, en inglés y español) están en [app-store-metadata.md](app-store-metadata.md).

## Hecho

- [x] App Sandbox activado (`ENABLE_APP_SANDBOX = YES`, entitlement `com.apple.security.app-sandbox`) con `network.client`.
- [x] Sin procesos externos: `nc` → `PortProbe` (sockets BSD), `diskutil` → `FileManager.unmountVolume`.
- [x] Reinicio de NetAuth: la build sandboxed no puede matar procesos; muestra instrucciones (copiar comando / Monitor de Actividad / Reintentar).
- [x] Manifiesto de privacidad `PrivacyInfo.xcprivacy`: UserDefaults con motivo CA92.1; sin tracking ni recogida de datos. Revisado el 23-10-2026: el código no usa ninguna otra API de "motivo obligatorio" (espacio en disco, fechas de ficheros, tiempo de arranque, teclados).
- [x] `ITSAppUsesNonExemptEncryption = NO` en `Info.plist` (evita la pregunta de cifrado en cada subida).
- [x] Copyright en `NSHumanReadableCopyright` (© 2026 J. Guzmán Arce Sáez).
- [x] Icono con los 10 tamaños del catálogo (16 → 1024).
- [x] Categoría `public.app-category.utilities`, `LSUIElement` (app de barra de menús); la ventana principal se abre al arrancar por defecto.
- [x] Localización en String Catalog (en, es, de, fr, it, ja, pt-BR, zh-Hans) con plurales. Las traducciones a de, fr, it, ja, pt-BR y zh-Hans no las ha revisado un nativo.
- [x] Etiquetas de accesibilidad en botones de solo icono y conmutadores.
- [x] Versión 1.0 (build 1).
- [x] Nombre "Connecter" libre: no hay ninguna app con ese nombre en la App Store de Mac ni de iPhone (comprobado en EE. UU. y España el 23-10-2026).
- [x] Páginas de privacidad y soporte en la web (`#privacy`, `#support`, en inglés y español).
- [x] Correo de contacto oficial: dev@arcesaez.com.
- [x] Código público en GitHub (Apache 2.0); feedback en issues y Discussions del repositorio.

## Pendiente, en orden

1. **Cuenta de pago (bloqueo).** Xcode solo tiene el equipo personal gratuito ("J. Guzmán Arce Sáez (Personal Team)") y el único certificado instalado es *Apple Development*. Publicar en la Mac App Store exige el Apple Developer Program (99 €/año) aunque la app sea gratuita; también lo exige distribuirla fuera de la tienda firmada con Developer ID y notarizada. Inscripción en <https://developer.apple.com/programs/enroll/>. Como particular, el vendedor que aparece en la tienda es el nombre legal; para que figure una empresa hace falta una entidad legal con número D-U-N-S.

2. **Cambiar de equipo en Xcode.** Settings → Accounts (aparecerá el equipo de pago) y, en *Signing & Capabilities*, elegirlo como *Team*. Cambia el identificador de equipo (hoy `4XDZ484XHZ`, el del equipo personal). Al archivar con firma automática, Xcode crea el certificado *Apple Distribution* y registra el bundle ID `es.guzman.connecter` en el equipo nuevo.

   Las contraseñas guardadas por la build actual siguen en el llavero de inicio de sesión, pero pertenecen a una app firmada por otro equipo: la primera vez que la build nueva use cada una, macOS pedirá permiso ("Connecter quiere usar tu información confidencial…"). Elige *Permitir siempre*.

3. **Probar la build con sandbox contra el NAS real**: montar, desmontar, "Abrir en el Finder", "Probar conexión" y el aviso de NetAuth (`CONNECTER_SIMULATE_NETAUTH_HANG=1` como variable de entorno en el esquema).

   Comprobar en concreto que, si existe un directorio huérfano `/Volumes/<recurso>`, el recurso se monta ahí y no en `/Volumes/<recurso>-1` (montaje con `mountpath` explícito desde el sandbox, aún sin confirmar). **Si no funciona, quitar de la descripción** la viñeta "Keeps the same mount point…" / "Mantiene el mismo punto de montaje…" en los dos idiomas.

4. **Migrar tu configuración local** (solo en tu Mac). La app sandboxed guarda sus ajustes en `~/Library/Containers/es.guzman.connecter/`, no en `~/Library/Preferences`. Si la lista de recursos sale vacía la primera vez, copia las preferencias antes de abrir la build nueva:

   ```bash
   defaults export es.guzman.connecter - | defaults import ~/Library/Containers/es.guzman.connecter/Data/Library/Preferences/es.guzman.connecter -
   ```

   Alternativa sin comando: la app guarda cada recurso en el llavero al arrancar, así que la lista vacía ofrece **Recuperar del llavero** (también en Ajustes → Llavero). Las contraseñas guardadas por el Finder siguen funcionando: macOS pide permiso una vez por servidor.

5. **LuLu**: la app abre conexiones TCP directamente (comprobación del puerto 445). LuLu preguntará la primera vez; permite Connecter.

6. **Capturas de pantalla** (16:10; 1280×800, 1440×900, 2560×1600 o 2880×1800). Lista sugerida en [app-store-metadata.md](app-store-metadata.md#screenshots-1610-at-least-one-up-to-ten). Usar nombres de servidor y direcciones inventados. Hechas: cuatro de 2880×1800 en inglés y en español, en [docs/app-store/screenshots/](app-store/screenshots/) (`en/` para el idioma principal; los demás idiomas usan esas). Se sacaron con la build de Debug en modo demo (`CONNECTER_DEMO=1`, datos inventados) y `-AppleLanguages`/`-app.appearance` al arrancar.

7. **Vídeo corto para el revisor** (montar, ver el estado, expulsar en el Finder y ver cómo vuelve a montarse) publicado como vídeo oculto, y su enlace en lugar de `[VIDEO URL]` en las notas para el revisor. Sin servidor SMB el revisor no puede probar la app, y "no hemos podido revisar la app" es un motivo de rechazo habitual.

8. **Icono Liquid Glass (opcional, recomendable en macOS 26/27)**: abrir `AppIcon-512@2x.png` en *Icon Composer* (Xcode → Open Developer Tool), separar carpeta y puntos en capas y guardar `AppIcon.icon` en el catálogo. El PNG actual es válido; el sistema le aplica el contorno automáticamente.

## En App Store Connect

1. *Apps* → *+* → *New App*: plataforma macOS, nombre "Connecter", idioma principal English (U.S.), bundle ID `es.guzman.connecter`, SKU libre (por ejemplo `connecter-mac`).
2. Rellenar la versión 1.0 con los textos de [app-store-metadata.md](app-store-metadata.md) y añadir la localización Spanish (Spain).
3. *App Privacy*: "Data Not Collected". *Pricing and Availability*: gratis, todos los países. *Age Rating*: 4+. Categoría: Utilities.
4. *Business* / *Agreements*: declarar el estado de comerciante de la Ley de Servicios Digitales de la UE. Con una app gratuita y sin actividad comercial lo normal es *no comerciante*, y entonces Apple no publica datos de contacto en la ficha de la UE.
5. *App Review Information*: contacto dev@arcesaez.com (el teléfono solo lo ve Apple), sin inicio de sesión, y las notas de [app-store-metadata.md](app-store-metadata.md#app-review-information).

## Subida

1. Product → Archive (Release).
2. En Organizer: *Validate App* (detecta problemas de entitlements, icono y privacidad) y después *Distribute App → App Store Connect*.
3. Al terminar el procesado, elegir la build en la versión 1.0 y enviar a revisión.
4. Para builds fuera de la tienda: mismo archivo, *Direct Distribution* (Developer ID + notarización). Si se quiere el reinicio automático de NetAuth, desactivar App Sandbox solo en esa configuración.

## Fuera de la 1.0

- **Agrupación por servidor**, con credenciales compartidas y posibilidad de sobrescribirlas por recurso: candidata para la 1.1.
- **Sincronización por iCloud** (requiere la cuenta de pago):
  - Los ítems del llavero se crean como sincronizables, pero macOS lo rechaza (`-34018`, falta entitlement) si la app no lleva identificador de aplicación; hoy se guardan en local. Al activar la capability **Keychain Sharing** en *Signing & Capabilities* (Xcode genera el perfil y añade `keychain-access-groups`), las contraseñas nuevas pasan a sincronizarse con el llavero de iCloud y "Recuperar del llavero" funciona en otro Mac. Las guardadas antes siguen en local hasta que se vuelvan a guardar.
  - Para sincronizar también la lista con sus estados (activado/desactivado) está esbozado el uso de `NSUbiquitousKeyValueStore` en `ShareConfig`/`AppSettings` (capability iCloud → Key-value storage).
