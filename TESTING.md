# Qué probar en el Mac

Antes de nada, compila y firma siempre con el mismo certificado (ver `README.md`):

```sh
git pull
SIGN_ID="Ligero Dev" scripts/bundle.sh
pkill Ligero; rm -rf /Applications/Ligero.app
cp -R build/Ligero.app /Applications/ && open /Applications/Ligero.app
```

Para ver los logs mientras pruebas:

```sh
log stream --predicate 'subsystem == "app.allinone"' --level info
```

## Medición de batería (en todas las fases)

Con todos los módulos activados, deja el Mac en reposo (sin tocar ratón ni teclado) y ejecuta:

```sh
top -l 30 -s 2 -stats pid,command,cpu,idlew,power -pid $(pgrep Ligero)
```

| Métrica | Límite |
|---|---|
| `cpu` | 0,0 % en todas las muestras (salvo la primera) |
| `idlew` | < 1 por segundo |
| RAM (Monitor de Actividad → Memoria) | < 60 MB |
| Hilos (Monitor de Actividad → doble clic → Hilos o `ps -M $(pgrep Ligero) \| wc -l`) | Sin hilos propios vivos en reposo |

Anota los valores en el PR o en el CHANGELOG. Repite la medición con el ratón externo conectado y desconectado (Fase 1).

## Fase 0 — esqueleto

### Arranque y barra de menús
- [ ] Al abrir Ligero aparece un icono en la barra de menús y **no** aparece en el Dock ni en ⌘Tab.
- [ ] Al hacer clic en el icono se abre el menú con las secciones «Módulos» y «Permisos», «Abrir al iniciar sesión», «Ajustes…» y «Salir de Ligero».
- [ ] «Salir de Ligero» (⌘Q con el menú abierto) cierra la app.
- [ ] Al abrir otra vez la app desde Finder o Spotlight con la app ya abierta, se muestran los Ajustes.

### Permisos
- [ ] En el menú, «Accesibilidad» y «Grabación de pantalla» aparecen como «no concedido» la primera vez. Al pulsar en ellos se abre el panel correcto de Ajustes del Sistema → Privacidad y seguridad.
- [ ] Concede Accesibilidad y vuelve al menú: ahora dice «concedido» sin reiniciar la app.
- [ ] Quita el permiso de Accesibilidad: el menú vuelve a decir «no concedido».
- [ ] Recompila con `SIGN_ID="Ligero Dev"`, reinstala y comprueba que **no** se pierden los permisos.

### Ajustes
- [ ] «Ajustes…» abre una ventana con la pestaña General: Idioma, Arranque, Módulos y Permisos.
- [ ] Cierra la ventana y vuelve a abrirla: se abre bien (se recrea cada vez).
- [ ] Con la ventana cerrada, la RAM de Ligero vuelve aproximadamente al valor anterior a abrirla.

### Idioma
- [ ] Con el selector en «Sistema», la app sigue el idioma de macOS.
- [ ] Cambia a «English»: aparece el aviso y el botón «Reiniciar ahora». Al pulsarlo, la app se reinicia en inglés (menú y Ajustes).
- [ ] Cambia a «Español» y reinicia: todo en español.
- [ ] Vuelve a «Sistema» y reinicia: sigue el idioma del sistema.
- [ ] No hay ningún texto que aparezca como clave (por ejemplo, `menu.settings`).

### Abrir al iniciar sesión
- [ ] Activa «Abrir al iniciar sesión» (desde el menú o desde Ajustes). Aparece en Ajustes del Sistema → General → Elementos de inicio. Si macOS pide aprobación, la app muestra el aviso y el botón para abrir Ajustes.
- [ ] Cierra la sesión y vuelve a entrar: Ligero arranca solo.
- [ ] Desactívalo: desaparece de Elementos de inicio.

### Batería
- [ ] Medición de reposo con `top` (arriba): CPU 0,0 %, idlew < 1/s, RAM < 60 MB.

## Fase 1 — Snap

Requisito: Accesibilidad concedida. Si no lo está, el menú muestra «Snap — encaje de ventanas (falta permiso)» y el módulo arranca solo en cuanto lo concedes, sin reiniciar.

### Atajos por defecto
| Acción | Atajo |
|---|---|
| Mitad izquierda / derecha / superior / inferior | ⌃⌥← / ⌃⌥→ / ⌃⌥↑ / ⌃⌥↓ |
| Cuartos: sup. izq. / sup. der. / inf. izq. / inf. der. | ⌃⌥U / ⌃⌥I / ⌃⌥J / ⌃⌥K |
| Primer / central / último tercio | ⌃⌥D / ⌃⌥F / ⌃⌥G |
| Dos primeros / dos últimos tercios | ⌃⌥E / ⌃⌥T |
| Maximizar / maximizar altura / centrar | ⌃⌥↩ / ⌃⌥⇧↑ / ⌃⌥C |
| Pantalla siguiente / anterior | ⌃⌥⌘→ / ⌃⌥⌘← |
| Restaurar tamaño anterior | ⌃⌥⌫ |

### Pruebas
- [ ] Con Safari, Finder, Terminal y una app Electron (VS Code, Slack…), prueba cada atajo de la tabla. La ventana se mueve de golpe, sin animación, y respeta la barra de menús (el notch) y el Dock.
- [ ] Pulsa ⌃⌥← tres veces seguidas: ½ → ⅔ → ⅓ → ½. Lo mismo con ⌃⌥→ anclado a la derecha. Desactiva «Repetir el atajo…» en Ajustes → Snap: ahora siempre es ½.
- [ ] Haz dos snaps seguidos y pulsa ⌃⌥⌫: vuelve al tamaño de **antes del primero**. Mueve una ventana a mano tras un snap, haz otro snap y restaura: vuelve a donde la dejaste a mano.
- [ ] Con el Dock oculto y visible, y con el Dock a un lado: las mitades no quedan debajo del Dock.
- [ ] Con pantalla externa: ⌃⌥⌘→ pasa la ventana a la otra pantalla conservando su posición relativa (una mitad izquierda sigue siendo mitad izquierda); ⌃⌥⌘← vuelve. Prueba la externa a la izquierda, a la derecha y encima.
- [ ] Pantalla en vertical (si tienes): los tercios se apilan de arriba abajo.
- [ ] Ajustes → Snap: separación a 10 pt y comprueba el hueco entre dos mitades y con los bordes.
- [ ] Grabar atajo: haz clic en el atajo de «Centrar», pulsa ⌃⌥X. Funciona al momento. Asigna a otra acción un atajo ya usado: se quita de la acción anterior. Esc cancela, Borrar lo deja en «Ninguno». Una tecla sin ⌘/⌥/⌃ (por ejemplo, solo ⇧A) suena y no se acepta.
- [ ] Mientras grabas un atajo, pulsar ⌃⌥← **no** mueve ninguna ventana. Al cerrar la ventana de Ajustes a mitad de grabación, los atajos vuelven a funcionar.
- [ ] «Restaurar atajos por defecto» los devuelve a la tabla.
- [ ] Desactiva Snap en el menú: ningún atajo hace nada (y otras apps pueden usar ⌃⌥←). Actívalo: vuelven.
- [ ] Ventana sin permiso de redimensionado o diálogo modal: no se cuelga; como mucho se mueve sin cambiar de tamaño. Sin ninguna ventana enfocada (escritorio vacío) suena un pitido.

## Fase 1 — Scroll

Requisito: Accesibilidad. Por defecto: rueda vertical **invertida** respecto al sistema (para tener el trackpad «natural» y el ratón «clásico»), scroll lineal desactivado y botones laterales como Atrás/Adelante.

- [ ] **Sin ratón conectado**: `log stream --predicate 'subsystem == "app.allinone" AND category == "scroll"' --level info` no muestra «Event tap installed».
- [ ] Conecta un ratón USB o Bluetooth: aparece «Mouse connected: <nombre>» y «Event tap installed». Desconéctalo: «Event tap removed».
- [ ] Con el ratón conectado: la rueda va en sentido contrario al trackpad; el trackpad sigue igual que antes. Si tienes Magic Mouse, comprueba que no cambia (va como el trackpad).
- [ ] Desactiva «Invertir la rueda vertical» en Ajustes → Scroll: la rueda vuelve al sentido del sistema al instante.
- [ ] Scroll horizontal (rueda inclinable o ⇧ + rueda) con «Invertir el scroll horizontal».
- [ ] Scroll lineal: con 3 líneas, girar rápido o lento avanza siempre lo mismo por paso. Cambia a 1 y a 10.
- [ ] Botones laterales: en Safari, Chrome y Finder, el botón trasero va Atrás y el delantero Adelante. **Prueba con el teclado en español** (⌘[ / ⌘] se envían con el carácter explícito; si alguna app no responde, apúntala). «Intercambiar Atrás y Adelante» los invierte. Con la opción desactivada, los botones vuelven a su función original.
- [ ] Clic izquierdo, derecho y central no cambian.
- [ ] Desactiva todas las opciones de Scroll: el log no muestra la tap ni con el ratón conectado.
- [ ] Desactiva el módulo Scroll en el menú con el ratón conectado: «Event tap removed», y todo vuelve al comportamiento del sistema.

### Batería (Fase 1)
- [ ] `top -l 30 -s 2 -stats pid,command,cpu,idlew,power -pid $(pgrep Ligero)` con Snap y Scroll activos, en reposo, **sin** ratón: CPU 0,0 %, idlew < 1/s.
- [ ] Lo mismo **con** ratón conectado y sin tocarlo: CPU 0,0 %, idlew < 1/s.
- [ ] Mientras haces scroll con el ratón, la CPU de Ligero sube solo unas décimas y vuelve a 0,0 al parar.
- [ ] RAM < 60 MB con la ventana de Ajustes cerrada.
