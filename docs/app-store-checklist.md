# Connecter — checklist para la Mac App Store

Estado del proyecto tras la revisión de septiembre de 2026. Lo que ya está hecho en el código aparece marcado; el resto son pasos que solo se pueden dar en App Store Connect o en Xcode con la cuenta de desarrollador.

## Hecho en el proyecto

- [x] App Sandbox activado (`ENABLE_APP_SANDBOX = YES`, entitlement `com.apple.security.app-sandbox`) con `network.client`.
- [x] Sin procesos externos: `nc` → `PortProbe` (sockets BSD), `diskutil` → `FileManager.unmountVolume`.
- [x] Reinicio de NetAuth: la build sandboxed no puede matar procesos; muestra instrucciones (copiar comando / Monitor de Actividad / Reintentar).
- [x] Manifiesto de privacidad `PrivacyInfo.xcprivacy` (UserDefaults, motivo CA92.1; sin tracking ni recogida de datos).
- [x] `ITSAppUsesNonExemptEncryption = NO` en `Info.plist` (evita la pregunta de cifrado en cada subida).
- [x] Copyright en `NSHumanReadableCopyright`.
- [x] Icono con los 10 tamaños del catálogo (16 → 1024).
- [x] Categoría `public.app-category.utilities`, `LSUIElement` (app de barra de menús).
- [x] Localización en String Catalog (en, es) con plurales.
- [x] Etiquetas de accesibilidad en botones de solo icono y conmutadores.

## Antes de la primera subida

1. **Cuenta**: Apple Developer Program de pago (99 €/año). La cuenta gratuita no puede subir a la App Store.
2. **Firma**: en *Signing & Capabilities* cambiar la identidad a *Apple Distribution* (Xcode lo hace solo con firma automática al archivar) y comprobar que App Sandbox aparece activado.
3. **Migrar tu configuración local**: la app sandboxed guarda sus ajustes en `~/Library/Containers/es.guzman.connecter/`, no en `~/Library/Preferences`. En tu Mac ya existe un contenedor antiguo (de abril), así que la lista de recursos saldrá vacía la primera vez. Antes de abrir la build nueva, copia las preferencias:

   ```bash
   defaults export es.guzman.connecter - | defaults import ~/Library/Containers/es.guzman.connecter/Data/Library/Preferences/es.guzman.connecter -
   ```

   Alternativa sin comando: si los recursos tienen la contraseña escrita en la app, la lista vacía ofrece **Recuperar del llavero** (también en Ajustes → Llavero) y los vuelve a crear a partir de los ítems del llavero.

   Las contraseñas guardadas por el Finder siguen funcionando: macOS pedirá permiso ("Connecter quiere usar tu información confidencial…") una vez por servidor; elige *Permitir siempre*. Los recursos que dependen de esa contraseña no tienen ítem propio y no se recuperan con el botón; conviene escribir la contraseña en el formulario del recurso.
4. **LuLu**: la app ahora abre conexiones TCP directamente (comprobación del puerto 445). LuLu preguntará la primera vez; permite Connecter.
5. **Prueba de montaje** con la build sandboxed: montar, desmontar, "Abrir en el Finder", "Probar conexión" y el aviso de NetAuth (`CONNECTER_SIMULATE_NETAUTH_HANG=1` como variable de entorno en el esquema).
6. **Icono Liquid Glass (opcional pero recomendable en macOS 26/27)**: abrir `AppIcon-512@2x.png` en *Icon Composer* (Xcode → Open Developer Tool), separar carpeta y puntos en capas y guardar `AppIcon.icon` en el catálogo. El PNG actual es válido; el sistema le aplica el contorno automáticamente.

## Cuando haya cuenta de pago: sincronización por iCloud

- Los ítems del llavero se crean como sincronizables, pero macOS lo rechaza (`-34018`, falta entitlement) si la app no lleva identificador de aplicación; hoy se guardan en local. Al activar la capability **Keychain Sharing** en *Signing & Capabilities* (Xcode genera el perfil y añade `keychain-access-groups`), las contraseñas nuevas pasan a sincronizarse con el llavero de iCloud y "Recuperar del llavero" funciona en otro Mac. Las guardadas antes siguen en local hasta que se vuelvan a guardar.
- Para sincronizar también la lista con sus estados (activado/desactivado) está esbozado el uso de `NSUbiquitousKeyValueStore` en `ShareConfig`/`AppSettings` (capability iCloud → Key-value storage).

## En App Store Connect

- Crear la app con el bundle ID `es.guzman.connecter`, nombre "Connecter" (comprobar disponibilidad; si está cogido, "Connecter – SMB Shares" o similar).
- **Subtítulo** (30 caracteres): "Monta tus recursos SMB solo".
- **Descripción** (borrador):

  > Connecter mantiene conectados tus recursos de red SMB. Vive en la barra de menús, monta las carpetas al arrancar, las reconecta tras dormir el Mac o cambiar de red, y te avisa si algo falla. Las contraseñas se guardan solo en el llavero de macOS.
  >
  > • Montaje automático y reintentos inteligentes con espera progresiva
  > • Estado de cada recurso en la barra de menús, con montar/desmontar en un clic
  > • Detección de red: pausa cuando no hay conexión y reintenta al volver
  > • Notificaciones opcionales de montaje, desconexión y error
  > • Registro de actividad filtrable
  > • Sin analítica, sin telemetría: nada sale de tu Mac

- **Palabras clave**: smb, nas, network share, mount, samba, synology, qnap, menu bar, finder, red
- **Capturas**: mínimo una por tamaño obligatorio (1280×800 o 1440×900, también se aceptan 2560×1600 / 2880×1800). Recomendadas: ventana principal con 3–4 recursos montados, menú de la barra, formulario de nuevo recurso, ajustes.
- **URL de política de privacidad**: obligatoria aunque no se recojan datos. Basta una página (GitHub Pages o un gist) que diga que la app no recoge ni transmite datos y que las credenciales se guardan en el llavero.
- **URL de soporte**: página del repositorio o un correo.
- **App Privacy**: "Data Not Collected".
- **Clasificación por edades**: 4+.
- **Categoría**: Utilidades.
- **Precio**: gratis o de pago; sin compras integradas.
- **Notas para el revisor**: explicar que la app necesita un servidor SMB; indicar que se puede probar con "Compartir archivos" de macOS en otra máquina o con cualquier NAS, y mencionar que el aviso de NetAuth solo aparece si el agente de macOS deja de responder.

## Subida

1. Product → Archive (Release).
2. En Organizer: *Validate App* (detecta problemas de entitlements, icono y privacidad) y después *Distribute App → App Store Connect*.
3. Al terminar el procesado, elegir la build en la versión 1.0 y enviar a revisión.
4. Para builds fuera de la tienda: mismo archivo, *Direct Distribution* (Developer ID + notarización). Si se quiere el reinicio automático de NetAuth, desactivar App Sandbox solo en esa configuración.
