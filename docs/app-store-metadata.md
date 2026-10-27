# Connecter — App Store Connect metadata

Texts ready to paste into App Store Connect for version 1.0. Primary language: **English (U.S.)**, plus a **Spanish (Spain)** localization. Character limits are App Store Connect's; the counts were checked when these texts were written.

Before submitting, check the note on "same mount point" in [app-store-checklist.md](app-store-checklist.md) (step 3).

---

## English (U.S.) — primary

**Name** (30): Connecter

**Subtitle** (30): Keep your SMB shares mounted

**Promotional text** (170):

> Your NAS and network folders, always there. Connecter mounts your SMB shares, brings them back after sleep or a network change, and shows the status of each one.

**Description** (4000):

> Connecter keeps your SMB network shares mounted. It lives in the menu bar, mounts your folders as soon as it starts, brings them back after your Mac wakes up or changes network, and tells you when something goes wrong.
>
> It's made for anyone who works with a NAS or a shared folder every day — Synology, QNAP, TrueNAS, Unraid, a Windows PC or another Mac — and is tired of reconnecting by hand.
>
> MOUNTED WHEN YOU NEED THEM
> • Mounts every enabled share at launch and keeps checking it in the background
> • Reconnects automatically after sleep, network changes and server restarts
> • Waits while you're offline and retries as soon as the network or the server is back
> • Smart retries that back off progressively, so an unreachable server doesn't keep your Mac busy
> • Keeps the same mount point (/Volumes/share), so your saved paths and aliases keep working
> • Can open at login
>
> AT A GLANCE
> • Menu bar icon with a colour dot that sums up all your shares
> • Each share's status in the menu, with mount and unmount in one click
> • Open in Finder, copy the share's address and test the connection to the server
> • Activity log you can filter and copy, plus optional notifications
>
> PRIVATE BY DESIGN
> • Passwords are stored only in the macOS Keychain, never on disk
> • Can use the passwords Finder already saved for your servers
> • No account, no analytics, no tracking: nothing leaves your Mac
> • Runs inside the App Sandbox
>
> Free and open source. Available in English, Spanish, German, French, Italian, Brazilian Portuguese, Japanese and Simplified Chinese.

**Keywords** (100, comma-separated, no spaces; the app name and category are already indexed):

```
smb,nas,network drive,mount,samba,synology,qnap,truenas,file sharing,auto mount,reconnect,volumes
```

**Support URL**: https://arcester.github.io/connecter/#support

**Marketing URL**: https://arcester.github.io/connecter/

**Privacy Policy URL**: https://arcester.github.io/connecter/#privacy

**Copyright**: © 2026 J. Guzmán Arce Sáez

---

## Spanish (Spain)

**Nombre** (30): Connecter

**Subtítulo** (30): Recursos SMB siempre montados

**Texto promocional** (170):

> Tu NAS y tus carpetas de red, siempre a mano. Connecter monta tus recursos SMB, los recupera al despertar el Mac o cambiar de red y te muestra el estado de cada uno.

**Descripción** (4000):

> Connecter mantiene montados tus recursos de red SMB. Vive en la barra de menús, monta tus carpetas en cuanto arranca, las recupera cuando el Mac despierta o cambia de red, y te avisa si algo falla.
>
> Está pensado para quien trabaja a diario con un NAS o una carpeta compartida —Synology, QNAP, TrueNAS, Unraid, un PC con Windows u otro Mac— y está harto de reconectar a mano.
>
> MONTADOS CUANDO LOS NECESITAS
> • Monta todos los recursos activados al arrancar y los sigue comprobando en segundo plano
> • Reconecta solo tras el reposo, los cambios de red y los reinicios del servidor
> • Espera mientras no hay conexión y reintenta en cuanto vuelven la red o el servidor
> • Reintentos inteligentes que se espacian poco a poco, para que un servidor caído no tenga ocupado al Mac
> • Mantiene el mismo punto de montaje (/Volumes/recurso), así que tus rutas y alias guardados siguen funcionando
> • Puede abrirse al iniciar sesión
>
> DE UN VISTAZO
> • Icono en la barra de menús con un punto de color que resume el estado de todos tus recursos
> • El estado de cada recurso en el menú, con montar y desmontar en un clic
> • Abrir en el Finder, copiar la dirección del recurso y probar la conexión con el servidor
> • Registro de actividad que puedes filtrar y copiar, y notificaciones opcionales
>
> PRIVADO DE SERIE
> • Las contraseñas se guardan solo en el llavero de macOS, nunca en el disco
> • Puede usar las contraseñas que el Finder ya guardó para tus servidores
> • Sin cuenta, sin analítica, sin seguimiento: nada sale de tu Mac
> • Funciona dentro del App Sandbox
>
> Gratuita y de código abierto. Disponible en español, inglés, alemán, francés, italiano, portugués de Brasil, japonés y chino simplificado.

**Palabras clave** (100):

```
smb,nas,unidad de red,montar,samba,synology,qnap,truenas,carpeta compartida,reconectar,volumen,red
```

**URL de soporte**: https://arcester.github.io/connecter/es/#support

**URL de marketing**: https://arcester.github.io/connecter/es/

**URL de la política de privacidad**: https://arcester.github.io/connecter/es/#privacy

---

## App Review Information

**Contact**: J. Guzmán Arce Sáez · dev@arcesaez.com · (phone number, only visible to Apple)

**Sign-in required**: No.

**Notes** (4000):

> Connecter is a menu bar utility that mounts SMB network shares (for example a NAS) and keeps them mounted. It does not need an account and collects no data.
>
> Testing it requires an SMB server. The quickest way is a second Mac:
> 1. On the second Mac: System Settings → General → Sharing → turn on File Sharing, add a shared folder and note the address shown (smb://…).
> 2. On the review Mac, open Connecter. The main window appears at launch; the app also has a folder icon in the menu bar and no Dock icon.
> 3. Click + and enter the server address (host name or IP address), the shared folder name, and a user name and password of the second Mac. "Test connection" checks that the server is reachable. Click Add.
> 4. The share mounts within a few seconds: its card shows "Mounted", it appears in Finder under Locations and in /Volumes, and the menu bar menu lists it with a green dot.
> 5. To see the automatic reconnection, eject the volume in Finder: Connecter mounts it again on its next check (every 30 seconds by default).
> 6. Clicking a share in the menu bar menu unmounts and disables it; clicking it again mounts it.
>
> A short video showing these steps: [VIDEO URL]
>
> Notes
> • Passwords are stored in the macOS Keychain. A share can also use a password that Finder already saved for the server; macOS then asks once for permission to use it.
> • On macOS 27 the system's NetAuth agent can occasionally stop answering mount requests. Connecter then shows a warning with instructions. This is not expected during normal testing.
> • Contact: dev@arcesaez.com

---

## Other answers

| Field | Answer |
|---|---|
| Category | Utilities (secondary: none) |
| Price | Free, no in-app purchases |
| Age rating | 4+ (no objectionable content) |
| App Privacy | Data Not Collected |
| Export compliance | Already answered in the build (`ITSAppUsesNonExemptEncryption = NO`) |
| EU Digital Services Act | Non-trader (free app, no commercial activity); Apple then publishes no contact details |
| Availability | All countries |

## Screenshots (16:10, at least one; up to ten)

Accepted sizes: 1280×800, 1440×900, 2560×1600 or 2880×1800. Suggested set, same order in both languages:

1. Main window with 3–4 shares mounted.
2. Menu bar menu open, with status dots.
3. "New share" form, with "Test connection" passed.
4. Settings.
5. Activity log (optional).

Use invented server names and addresses (for example `nas.local`), never the real ones.
