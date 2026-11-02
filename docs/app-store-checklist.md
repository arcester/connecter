# Connecter — checklist para la Mac App Store

Estado a 2 de noviembre de 2026. Los textos de la ficha (nombre, subtítulo, descripción, palabras clave, URLs y notas para el revisor, en inglés y español) están en [app-store-metadata.md](app-store-metadata.md).

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
- [x] Versión 1.0 (build 3; la 1 se rechazó por la firma, ver *Subida*; la 2 mostraba "Montado" hasta 30 s después de expulsar un recurso en el Finder). La build de Release compila sin avisos del compilador con el SDK de macOS 27 (comprobado el 1-11-2026).
- [x] Recursos agrupados por servidor, con credenciales compartidas (o propias por recurso) y pausa por servidor.
- [x] Nombre en la tienda: **Connecter SMB** ("Connecter" a secas lo tiene reservado otra cuenta en App Store Connect, aunque no hay ninguna app publicada con ese nombre). En el Mac la app sigue llamándose Connecter (`CFBundleDisplayName`).
- [x] Páginas de privacidad y soporte en la web (`#privacy`, `#support`, en inglés y español).
- [x] Correo de contacto oficial: dev@arcesaez.com.
- [x] Código público en GitHub (Apache 2.0); feedback en issues y Discussions del repositorio.
- [x] Apple Developer Program activo (2-11-2026), cuenta *Individual*. El Team ID es el mismo del equipo personal (`4XDZ484XHZ`), así que el proyecto no cambia. Archivo y exportación para App Store Connect comprobados con `xcodebuild -allowProvisioningUpdates`: Xcode creó los certificados *Apple Distribution* y *3rd Party Mac Developer Installer* y el perfil *Mac Team Store Provisioning Profile: es.guzman.connecter*; la app exportada lleva `application-identifier` y no `get-task-allow`.

## Pendiente, en orden

1. **Probar la build con sandbox** contra el NAS real: montar, desmontar, "Abrir en el Finder", "Probar conexión" y el aviso de NetAuth (`CONNECTER_SIMULATE_NETAUTH_HANG=1` como variable de entorno en el esquema).

   La primera vez que la build de la tienda use cada contraseña guardada, macOS puede pedir permiso ("Connecter quiere usar tu información confidencial…"), porque la firma de distribución no es la de desarrollo. Elige *Permitir siempre*. Mirar también en el registro si las contraseñas nuevas se guardan como sincronizables: con el perfil de distribución la app ya lleva `application-identifier` y el `-34018` podría desaparecer, con lo que pasarían al llavero de iCloud.

   Comprobar en concreto que, si existe un directorio huérfano `/Volumes/<recurso>`, el recurso se monta ahí y no en `/Volumes/<recurso>-1` (montaje con `mountpath` explícito desde el sandbox, aún sin confirmar). **Si no funciona, quitar de la descripción** la viñeta "Keeps the same mount point…" / "Mantiene el mismo punto de montaje…" en los dos idiomas.

2. **Migrar tu configuración local** (solo en tu Mac). La app sandboxed guarda sus ajustes en `~/Library/Containers/es.guzman.connecter/`, no en `~/Library/Preferences`. Si la lista de recursos sale vacía la primera vez, copia las preferencias antes de abrir la build nueva:

   ```bash
   defaults export es.guzman.connecter - | defaults import ~/Library/Containers/es.guzman.connecter/Data/Library/Preferences/es.guzman.connecter -
   ```

   Alternativa sin comando: la app guarda cada recurso en el llavero al arrancar, así que la lista vacía ofrece **Recuperar del llavero** (también en Ajustes → Llavero). Las contraseñas guardadas por el Finder siguen funcionando: macOS pide permiso una vez por servidor.

3. **LuLu**: la app abre conexiones TCP directamente (comprobación del puerto 445). LuLu preguntará la primera vez; permite Connecter.

4. **Capturas de pantalla** (16:10; 1280×800, 1440×900, 2560×1600 o 2880×1800). Lista sugerida en [app-store-metadata.md](app-store-metadata.md#screenshots-1610-at-least-one-up-to-ten). Usar nombres de servidor y direcciones inventados. Hechas: cuatro de 2880×1800 en inglés y en español, en [docs/app-store/screenshots/](app-store/screenshots/) (`en/` para el idioma principal; los demás idiomas usan esas). Se sacaron con la build de Debug en modo demo (`CONNECTER_DEMO=1`, datos inventados) y `-AppleLanguages`/`-app.appearance` al arrancar.

5. **Vídeo corto para el revisor** (montar, ver el estado, expulsar en el Finder y ver cómo vuelve a montarse) publicado como vídeo oculto, y su enlace en lugar de `[VIDEO URL]` en las notas para el revisor. Sin servidor SMB el revisor no puede probar la app, y "no hemos podido revisar la app" es un motivo de rechazo habitual.

6. **Icono Liquid Glass (opcional, recomendable en macOS 26/27)**: abrir `AppIcon-512@2x.png` en *Icon Composer* (Xcode → Open Developer Tool), separar carpeta y puntos en capas y guardar `AppIcon.icon` en el catálogo. El PNG actual es válido; el sistema le aplica el contorno automáticamente.

## En App Store Connect

1. *Apps* → *+* → *New App*: plataforma macOS, nombre "Connecter SMB", idioma principal English (U.S.), bundle ID `es.guzman.connecter`, SKU libre (por ejemplo `connecter-mac`).
2. Rellenar la versión 1.0 con los textos de [app-store-metadata.md](app-store-metadata.md) y añadir la localización Spanish (Spain).
3. *App Privacy*: "Data Not Collected". *Pricing and Availability*: gratis, todos los países. *Age Rating*: 4+. Categoría: Utilities.
4. *Business* / *Agreements*: declarar el estado de comerciante de la Ley de Servicios Digitales de la UE. Con una app gratuita y sin actividad comercial lo normal es *no comerciante*, y entonces Apple no publica datos de contacto en la ficha de la UE.
5. *App Review Information*: contacto dev@arcesaez.com (el teléfono solo lo ve Apple), sin inicio de sesión, y las notas de [app-store-metadata.md](app-store-metadata.md#app-review-information).

## Subida

**No usar *Distribute App* del Organizer ni `xcodebuild -exportArchive`.** La exportación escribe el requisito de firma con el nombre del certificado ("José Guzmán Arce Sáez") con las tildes descompuestas, no coincide con el certificado y App Store Connect rechaza la build (ITMS-90238, build 1 del 2-11-2026).

1. Subir `CURRENT_PROJECT_VERSION` (App Store Connect no acepta un número de build repetido).
2. `tools/release/app-store-pkg.sh <carpeta>`: archiva, vuelve a firmar con *Apple Distribution* y un requisito por Team ID, incrusta el perfil de la tienda, comprueba la firma y crea `Connecter-<build>.pkg` firmado con *3rd Party Mac Developer Installer*. Necesita los dos certificados en el llavero (Xcode → Settings → Accounts → Manage Certificates) y que el perfil gestionado por Xcode los incluya.
3. Subir el `.pkg` con **Transporter**.
4. Al terminar el procesado, elegir la build en la versión 1.0 y enviar a revisión.
5. Para builds fuera de la tienda: mismo archivo, *Direct Distribution* (Developer ID + notarización). Si se quiere el reinicio automático de NetAuth, desactivar App Sandbox solo en esa configuración. Sin probar: es probable que la exportación con Developer ID tenga el mismo fallo de las tildes.

## Fuera de la 1.0

- **Sincronización por iCloud** (requiere la cuenta de pago):
  - Los ítems del llavero se crean como sincronizables, pero macOS lo rechaza (`-34018`, falta entitlement) si la app no lleva identificador de aplicación; hoy se guardan en local. Al activar la capability **Keychain Sharing** en *Signing & Capabilities* (Xcode genera el perfil y añade `keychain-access-groups`), las contraseñas nuevas pasan a sincronizarse con el llavero de iCloud y "Recuperar del llavero" funciona en otro Mac. Las guardadas antes siguen en local hasta que se vuelvan a guardar.
  - Para sincronizar también la lista con sus estados (activado/desactivado) está esbozado el uso de `NSUbiquitousKeyValueStore` en `ShareConfig`/`AppSettings` (capability iCloud → Key-value storage).
