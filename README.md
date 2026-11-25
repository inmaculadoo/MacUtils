# Conde All In One

Utilidad de barra de menús para macOS que reúne en una sola app el encaje de ventanas, el scroll del ratón, el orden de Descargas, una bandeja de arrastre, un desinstalador, capturas con OCR, un monitor del sistema, mantener el Mac despierto y módulos experimentales (selector de ventanas, vistas previas del Dock, volumen por app y ventanas en tira). La prioridad es la batería: sin polling, solo eventos del sistema. El diseño está en `SPEC.md` y los cambios en `CHANGELOG.md`.

## Primera vez en el Mac (una sola vez)
1. Instala Xcode desde la App Store, ábrelo una vez y acepta la licencia.
2. Crea el certificado para que los permisos no se pierdan al recompilar:
   - Abre Acceso a Llaveros.
   - En el menú, ve a Acceso a Llaveros → Asistente para certificados → Crear un certificado.
   - Nombre: `Ligero Dev`. Tipo de identidad: Raíz autofirmada. Tipo de certificado: **Firma de código**.
3. Clona el repo y ejecuta:
   ```sh
   SIGN_ID="Ligero Dev" scripts/bundle.sh
   cp -R "build/Conde All In One.app" /Applications/
   open "/Applications/Conde All In One.app"
   ```
4. Concede Accesibilidad y Grabación de pantalla cuando te lo pida. Con el mismo certificado, solo tendrás que hacerlo una vez.

## Medir batería
```sh
top -l 30 -s 2 -stats pid,command,cpu,idlew,power -pid $(pgrep Ligero)
```
Con el Mac en reposo, `cpu` debe estar a 0,0 e `idlew` por debajo de 1.
