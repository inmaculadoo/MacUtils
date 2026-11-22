# CLAUDE.md — Ligero

Lee `SPEC.md` antes de tocar nada. Esto es un resumen de las reglas que no se negocian, más el contexto de trabajo.

## Contexto
- App personal de barra de menús para un Mac con Apple Silicon sin ventilador (macOS 26 Tahoe). Swift + AppKit, con SwiftUI solo en Ajustes.
- La prioridad absoluta es la **batería**. Se prefiere una función menos a una función que gaste en reposo.
- Se prefiere autonomía: haz la fase entera de principio a fin, sin pedir confirmación en cada paso. Pregunta solo ante decisiones irreversibles o de diseño que cambien el SPEC.
- Idioma: comentarios y commits en inglés; `TESTING.md` y mensajes al usuario en español.

## Dónde se ejecuta esto
- **Sesión en la nube (Linux)**: aquí NO se puede compilar AppKit ni probar permisos.
  - `swift test` solo para `LigeroCore`. Si no hay toolchain de Swift, instálala (swift.org, release de Linux).
  - La compilación real de la app se verifica con el workflow de GitHub Actions en macOS. Tras cada push, comprueba el resultado del run (`gh run watch` / `gh run view --log-failed` si `gh` está disponible). Si falla, arréglalo antes de seguir.
  - Los minutos de macOS en Actions son caros: no hagas pushes por cada línea. Agrupa los cambios y haz push al cerrar cada sub-paso.
- **En casa (Mac)**: `scripts/bundle.sh`, firmado con el certificado "Ligero Dev", copiar a `/Applications` y probar con `TESTING.md`.

## Reglas duras (ver SPEC §2)
1. Prohibido el polling: nada de `Timer`, `DispatchSourceTimer` ni `while` esperando. Solo eventos (AXObserver, NSWorkspace, FSEvents, IOHIDManager, Carbon hotkeys). Única excepción: el Monitor con el panel abierto.
2. Un módulo desactivado no se instancia. `stop()` deshace todo lo que hizo `start()`.
3. Nada de `SCStream`; solo `SCScreenshotManager` en modo one-shot.
4. Nada de dependencias de terceros ni código de red.
5. Event taps solo cuando hacen falta (ratón conectado, Ribbon activo) y se quitan en cuanto dejan de hacer falta.
6. La lógica pura va en `LigeroCore` (sin AppKit) y con tests.
7. Nunca borrar archivos del usuario: `FileManager.trashItem` siempre.
8. El IOProc de audio es realtime: sin allocs, sin locks y sin async.

## Antes de dar una fase por terminada
- CI en verde y `swift test` en verde.
- Revisa el código del módulo buscando timers, observers que no se quitan en `stop()` y closures que retienen `self`.
- Actualiza `CHANGELOG.md` y añade a `TESTING.md` los pasos para probarlo en el Mac, incluida la medición: `top -l 30 -s 2 -stats pid,command,cpu,idlew,power -pid $(pgrep Ligero)` con el Mac en reposo. Límites: CPU 0,0 %, idlew < 1/s, RAM < 60 MB.

## Comandos
- Tests de la lógica: `swift test --filter LigeroCoreTests`
- Compilar en Mac: `swift build -c release --arch arm64`
- App empaquetada: `SIGN_ID="Ligero Dev" scripts/bundle.sh` (sin `SIGN_ID` firma ad-hoc, solo vale para probar una vez)
