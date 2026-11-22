# Ligero

Utilidad personal de barra de menús para macOS. Ver `SPEC.md`.

## Primera vez en el Mac (una sola vez)
1. Instala Xcode desde la App Store, ábrelo una vez y acepta la licencia.
2. Crea el certificado para que los permisos no se pierdan al recompilar:
   - Abre Acceso a Llaveros.
   - En el menú, ve a Acceso a Llaveros → Asistente para certificados → Crear un certificado.
   - Nombre: `Ligero Dev`. Tipo de identidad: Raíz autofirmada. Tipo de certificado: **Firma de código**.
3. Clona el repo y ejecuta:
   ```sh
   SIGN_ID="Ligero Dev" scripts/bundle.sh
   cp -R build/Ligero.app /Applications/
   open /Applications/Ligero.app
   ```
4. Concede Accesibilidad y Grabación de pantalla cuando te lo pida. Con el mismo certificado, solo tendrás que hacerlo una vez.

## Medir batería
```sh
top -l 30 -s 2 -stats pid,command,cpu,idlew,power -pid $(pgrep Ligero)
```
Con el Mac en reposo, `cpu` debe estar a 0,0 e `idlew` por debajo de 1.
