# Ligero — SPEC

App de barra de menús para macOS, de uso personal, que reúne en una sola app las funciones de Rectangle, AltTab/DockDoor, Ice, SoundSource, Mac Mouse Fix, FileOS (Drop Shelf + orden de Descargas), AppCleaner, Shottr/TextSniper, Stats y Ribbon.

**Objetivo número uno: batería.** Si una función no se puede hacer sin gastar batería en reposo, se hace a demanda o no se hace.

- Mac objetivo: Apple Silicon (sin ventilador, Apple Silicon), macOS 26 Tahoe.
- Mínimo de despliegue: macOS 15.
- Solo arm64. Sin App Store y sin sandbox (Accesibilidad y las taps de audio lo exigen).

---

## 1. Presupuesto de energía (criterios de aceptación)

Se mide con todos los módulos activados y el Mac en reposo durante 60 s:

| Métrica | Límite |
|---|---|
| CPU en reposo | 0,0 % (media de 60 s < 0,1 %) |
| Idle wakeups | < 1 por segundo (`top -stats pid,cpu,idlew,power`) |
| RAM | < 60 MB con todo activado |
| Impacto energético (Monitor de Actividad) | ~0 en reposo |
| Hilos | Sin hilos propios vivos en reposo |

Un módulo que no cumpla este presupuesto no se fusiona en `main`.

## 2. Reglas de arquitectura

1. **Nada de polling.** Prohibido usar `Timer`, `DispatchSourceTimer` o bucles `while` que esperen algo. Todo se dispara por eventos:
   - Ventanas y apps: `AXObserver` y `NSWorkspace.notificationCenter`.
   - Carpetas: FSEvents o `DispatchSource.makeFileSystemObjectSource`.
   - Dispositivos: notificaciones de `IOHIDManager`.
   - Atajos de teclado: Carbon `RegisterEventHotKey`, **no** un event tap.

   Excepción única: el monitor del sistema mientras su panel está abierto (ver §4.10).
2. **Los módulos desactivados no existen.** No se instancian, no registran observers ni piden permisos. Cada módulo cumple este protocolo:
   ```swift
   @MainActor protocol LigeroModule: AnyObject {
       static var id: String { get }
       static var requiredPermissions: Set<Permission> { get }
       func start()   // registra observers y hotkeys
       func stop()    // los quita TODOS; tras stop() no queda nada vivo
   }
   ```
3. **Sin animaciones por defecto.** Mover ventanas por AX cuesta varios ms por llamada entre procesos, así que se mueven de golpe. Si se añade animación, que sea opcional, como máximo 6 pasos y sin display link permanente.
4. **La UI se crea bajo demanda.** El menú de la barra es un `NSMenu`, más barato que un popover SwiftUI. La ventana de ajustes (SwiftUI) se crea al abrirse y se libera al cerrarse. Los paneles (switcher, shelf) se crean una vez y se ocultan, nunca se destruyen y recrean en bucle.
5. **Cero red y cero dependencias de terceros.** Nada de Sparkle, analíticas ni SPM externos. Solo frameworks de Apple.
6. **Capturas solo a demanda.** ScreenCaptureKit se usa en modo one-shot (`SCScreenshotManager`). Prohibido mantener un `SCStream` abierto.
7. **Bilingüe (es + en) desde el primer commit.** No hay ni un texto visible escrito a mano en el código. Todo pasa por `String(localized:bundle: .module)` / `LocalizedStringKey`, con `Resources/es.lproj/Localizable.strings` y `Resources/en.lproj/Localizable.strings` (`defaultLocalization: "en"` en `Package.swift`). Se usan `.strings` clásicos y no `.xcstrings`, para que compile igual con `swift build` y con `bundle.sh` sin depender de Xcode. Por defecto, el idioma sigue al sistema. En Ajustes hay un selector "Sistema / Español / English" que escribe `AppleLanguages` para la app y pide reiniciarla. Coste en ejecución: 0.
8. **Lógica pura separada.** El target `LigeroCore` no importa AppKit. Contiene la matemática de layouts, el motor de reglas de Descargas, el parser de ajustes, etc. Tiene tests con `swift test` que corren también en Linux.

## 3. Estructura

```
Package.swift              # SPM: LigeroCore (lib), Ligero (exec), LigeroCoreTests
Sources/LigeroCore/        # sin AppKit, testeable en Linux
Sources/Ligero/
  App/                     # AppDelegate, StatusItem, ModuleRegistry, Settings, Permissions, HotKeys, LoginItem
  Modules/<Modulo>/        # una carpeta por módulo
Resources/Info.plist       # LSUIElement = YES
scripts/bundle.sh          # swift build -c release → Ligero.app + codesign
.github/workflows/build.yml
```

- Ajustes en `UserDefaults` como un único `Codable` por módulo.
- Arranque al iniciar sesión con `SMAppService.mainApp`.
- Logs con `os.Logger`, subsistema `app.allinone`.

## 4. Módulos

El orden sigue el plan de fases (§5). Cada módulo indica su mecanismo y su coste.

### 4.1 Snap — encaje de ventanas (tipo Rectangle)
- Atajos para mitades, tercios, cuartos, ⅔, maximizar, centrar, siguiente pantalla y restaurar el tamaño anterior.
- Mecanismo: hotkey Carbon → ventana enfocada vía AX (`kAXFocusedWindowAttribute`) → `kAXPosition` y `kAXSize`.
- La matemática de rectángulos (visibleFrame, notch, varias pantallas) va en `LigeroCore`.
- Coste en reposo: 0.

### 4.2 Scroll — ratón vs trackpad
- Dirección de scroll del ratón independiente de la del trackpad.
- Scroll lineal opcional (sin aceleración).
- Botones laterales como Atrás/Adelante.
- Mecanismo: `IOHIDManager` detecta que hay un ratón externo conectado y **solo entonces** se instala el `CGEventTap` de `scrollWheel` y `otherMouseDown`. Al desconectarlo, el tap se quita. Para distinguir la rueda del trackpad se usa `kCGScrollWheelEventIsContinuous == 0`.
- Scroll suave: opcional y desactivado por defecto, porque cuesta CPU mientras haces scroll.
- Coste: 0 sin ratón; microsegundos por evento de scroll con ratón.

### 4.3 Downloads — orden automático (tipo FileOS)
- Al terminar una descarga, la mueve a `~/Downloads/<Categoría>/` según su `UTType`: Imágenes, Documentos, PDFs, Vídeo, Audio, Comprimidos, Instaladores (dmg/pkg) y Código.
- Ignora `.crdownload`, `.part`, `.download` y archivos que aún crecen (espera a 2 s de tamaño estable, **lanzado por el evento**, sin timer periódico).
- Historial de deshacer (últimas 50 operaciones) desde el menú.
- Vista previa ("lo que haría") antes de activarlo la primera vez.
- Nunca borra nada.
- Mecanismo: FSEvents con latencia de 2 s solo sobre `~/Downloads`. El motor de reglas va en `LigeroCore` con tests.

### 4.4 Shelf — bandeja de arrastre (tipo Drop Shelf / Dropover)
- Al empezar a arrastrar archivos, texto o URLs, aparece un panel pequeño bajo el notch. Puedes soltar cosas ahí y sacarlas después.
- Carpetas fijadas como destino directo de soltar.
- Mecanismo: monitor global de `leftMouseDragged` (solo dispara durante arrastres). En el primer evento de cada arrastre compara `NSPasteboard(name: .drag).changeCount`. Si cambió, muestra el `NSPanel` no activante.
- También se abre con un atajo.

### 4.5 Switcher — AltTab con vista previa
- ⌥Tab (configurable) muestra las ventanas de todas las apps del Space actual con miniatura y título. Se puede buscar escribiendo y cerrar, minimizar o salir de la app con teclas.
- Mecanismo: la lista de ventanas sale de AX (cacheada e invalidada por `AXObserver`: ventana creada, destruida o enfocada). Las miniaturas se capturan con `SCScreenshotManager` **solo al abrir el switcher**, se cachean y se invalidan cuando la ventana cambia. Hay un modo sin miniaturas (sin permiso de Grabación de pantalla).
- Coste en reposo: 0.

### 4.6 Dock Previews (tipo DockDoor)
- Al pasar el ratón por un icono del Dock aparecen las miniaturas de sus ventanas, con acciones de cambiar, cerrar y minimizar.
- Clic en el icono de una app activa: minimiza o muestra (configurable).
- Mecanismo: `AXObserver` sobre el proceso Dock con `kAXSelectedChildrenChangedNotification`. Es como lo hace DockDoor: sin polling del ratón.
- Reutiliza la caché de miniaturas del Switcher.

### 4.7 MenuBar — retirado
- Se quitó en la 0.4.0: en macOS 27 el sistema limita la longitud del separador (5002 pt) y lo coloca fuera de su sitio, así que no oculta los iconos. Alternativa nativa: Ajustes del Sistema → Barra de menús.

### 4.8 Uninstall — desinstalador completo (tipo AppCleaner)
- Se arrastra una `.app` al menú o a la ventana. Busca restos por bundle ID en `~/Library/{Application Support, Caches, Preferences, Containers, Group Containers, Saved Application State, LaunchAgents, Logs, HTTPStorages, WebKit, Cookies}`.
- Muestra la lista con casillas y lo manda **todo a la Papelera** (`FileManager.trashItem`). Nunca `rm`.
- Solo funciona a demanda.

### 4.9 Capture — captura + OCR (tipo Shottr/TextSniper)
- Atajo de captura de región: superposición de selección → PNG al portapapeles o al Escritorio.
- Atajo de texto: región → OCR con Vision (`VNRecognizeTextRequest`, idiomas es y en) → texto al portapapeles.
- Ventana flotante "pin" opcional con la captura.
- Anotaciones: fuera de la v1.
- Solo funciona a demanda.

### 4.10 Monitor — sistema
- Desde el menú: CPU, GPU (uso y memoria en uso), RAM (presión de memoria), batería (ciclos, salud, vatios, tiempo restante), red (subida y bajada) y apps que más energía gastan.
- Mecanismo:
  - CPU con `host_processor_info`, GPU con IOKit (`IOAccelerator` → `PerformanceStatistics`), memoria con `host_statistics64`, batería con IOKit (`AppleSmartBattery`).
  - **Solo muestrea mientras el panel está abierto** (cada 1 s; es la única excepción al "no timers").
  - Lectura en la barra de menús: opcional y desactivada por defecto. Si se activa, cada ≥ 10 s con `tolerance` del 50 %.
  - Temperaturas por SMC: desactivadas por defecto.

### 4.11 Audio — volumen y salida por app (tipo SoundSource)
- Mezclador: un deslizador por app que esté sonando, de 0 a 150 %, más silenciar.
- Salida por app: por ejemplo, música por los altavoces y la llamada por los auriculares.
- Mecanismo: Core Audio process taps (`AudioHardwareCreateProcessTap`, macOS 14.2+), sin driver.
  - **Solo se crea un tap para una app cuyo volumen ≠ 100 % o cuya salida está redirigida.** Si todo está al 100 % y con la salida por defecto, no hay ningún tap activo.
  - El tap se destruye cuando la app deja de sonar o se cierra.
  - El IOProc es realtime: sin asignaciones de memoria, sin locks y sin Swift async dentro.
- Coste: proporcional a las apps con tap activo y solo mientras suenan. Es inevitable, y queda documentado en el menú.

### 4.12 Ribbon — ventanas en tira horizontal (tipo Ribbon / PaperWM)
- Por pantalla, las ventanas forman una fila de columnas. Cada columna tiene ancho fijo (¼, ⅓, ½, ⅔, ¾, completo).
- Una ventana nueva se abre a la derecha de la enfocada, y las demás no cambian de tamaño.
- Atajos: enfocar columna izquierda o derecha, mover columna, cambiar ancho cíclicamente, apilar en la columna de la izquierda, enviar a la siguiente pantalla.
- Gesto opcional: ⌥ + scroll horizontal de dos dedos desliza la tira. Usa el tap del módulo Scroll **solo si Ribbon está activo**.
- Mecanismo:
  - Modelo de la tira (columnas, anchos, desplazamiento) en `LigeroCore` con tests.
  - Al desplazar, se recolocan con AX solo las ventanas cuya posición cambia. Las que quedan fuera se aparcan en el borde, como AeroSpace, dejando 1 px visible, porque macOS no deja sacar ventanas del todo de la pantalla.
  - Observers AX para ventanas creadas o destruidas y cambio de foco.
  - Sin animación por defecto.
- Modo activable o desactivable con atajo. Al desactivarlo, restaura las posiciones originales.
- Excluir apps (lista) y ventanas flotantes (paneles, diálogos, `AXSubrole` ≠ `AXStandardWindow`).
- **Es el módulo más difícil.** Va el último y se prototipa antes de pulirlo.

### 4.13 Despierto — evitar que el Mac se duerma (tipo Amphetamine)
- Desde el menú: 30 min, 1 h, 2 h, 5 h o hasta apagarlo; atajo ⌃⌥⌘A para "hasta apagarlo".
- Mientras una o varias apps elegidas estén abiertas.
- Opción de mantener también la pantalla encendida (desactivada por defecto: es lo que más batería ahorra).
- Mecanismo: aserciones de IOKit (`IOPMAssertionCreateWithProperties`). Una sesión con duración entrega el tiempo al sistema (`kIOPMAssertionTimeoutKey` + `TimeoutActionRelease`), así que la app no usa ningún timer. Las apps se siguen con las notificaciones de NSWorkspace de abrir/cerrar app, solo si hay alguna elegida.
- Fuera de alcance: disparadores por uso de CPU, red o descargas (exigirían muestrear) y el modo tapa cerrada sin pantalla externa (necesita privilegios).
- Coste en reposo: 0.

## 5. Fases

| Fase | Contenido | Dónde |
|---|---|---|
| 0 | Esqueleto: SPM, `bundle.sh`, CI, StatusItem + NSMenu, ModuleRegistry, Settings, HotKeys (Carbon), Permissions (Accesibilidad / Grabación de pantalla, con explicación y enlace a Ajustes), LoginItem. `LigeroCore` con tests. | Nube |
| 1 | Snap + Scroll | Nube (código) → casa (probar) |
| 2 | Downloads + Shelf | Nube → casa |
| 3 | Switcher + Dock Previews | Nube → casa |
| 4 | MenuBar + Uninstall + Capture | Nube → casa |
| 5 | Monitor + Audio | Nube → casa |
| 6 | Ribbon | Prototipo en nube, iteración sobre todo en casa |

Cada fase termina con CI en verde, tests de `LigeroCore` en verde, una entrada en `CHANGELOG.md` y una lista de "qué probar en el Mac" (`TESTING.md`).

## 6. Permisos

| Permiso | Módulos |
|---|---|
| Accesibilidad | Snap, Switcher, Dock Previews, Ribbon, Scroll (event tap activo) |
| Grabación de pantalla | Miniaturas de Switcher y Dock, Capture |
| Audio (el sistema lo pide al crear el tap) | Audio |

macOS ata los permisos a la firma del código. En casa hay que firmar **siempre** con el mismo certificado autofirmado (ver `README.md`), o los permisos se pierden en cada compilación.

## 7. Fuera de alcance
- Lanzador ⌘K y portapapeles (Tahoe ya trae historial en Spotlight).
- Sincronización, cuentas, red y actualizaciones automáticas.
