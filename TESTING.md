# Qué probar en el Mac

Orden de prueba: primero lo estable (**Prioridad 1 y 2**), después lo experimental (**Prioridad 3**), un módulo cada vez. Los módulos experimentales vienen desactivados y llevan la etiqueta «Experimental» en Ajustes.

## 0. Preparación

Compila y firma siempre con el mismo certificado (ver `README.md`), o macOS volverá a pedir los permisos:

```sh
git pull
SIGN_ID="Ligero Dev" scripts/bundle.sh
pkill Ligero; rm -rf /Applications/Ligero.app
cp -R build/Ligero.app /Applications/ && open /Applications/Ligero.app
```

Logs mientras pruebas (puedes filtrar con `AND category == "scroll"`, `"modules"`, `"snap"`…):

```sh
log stream --predicate 'subsystem == "app.allinone"' --level info
```

## 1. Medición de batería (para cada módulo)

Procedimiento para cada módulo:
1. En Ajustes → General → Módulos, deja activado **solo ese módulo** (y luego repite la medición con todos los estables activados a la vez).
2. Cierra la ventana de Ajustes y el menú de Ligero, y deja el Mac 60 s sin tocar ratón ni teclado.
3. Ejecuta:

```sh
top -l 30 -s 2 -stats pid,command,cpu,idlew,power -pid $(pgrep Ligero)
```

| Métrica | Límite |
|---|---|
| `cpu` | 0,0 % en todas las muestras salvo la primera |
| `idlew` | < 1 por segundo. En `top -l` la columna es **acumulada** desde que arrancó el proceso: usa (última muestra − primera) / 60 s |
| RAM (Monitor de Actividad → Memoria) | < 60 MB con todo activado |
| Hilos (`ps -M $(pgrep Ligero) \| wc -l`) | Sin hilos propios vivos en reposo |

Condiciones concretas por módulo (anota los valores en esta tabla). Medido el 24-11 (15 s tras arrancar, 60 s de `top`, más `footprint` y `ps -M`), solo con ese módulo activo; sin módulos: 0,00 %, 0,03/s, 12 MB, 3 hilos (todos del sistema):

| Módulo | Medir con… | cpu | idlew | RAM |
|---|---|---|---|---|
| Snap | en reposo | 0,00 % | 0,02/s | 12 MB |
| Scroll | sin ratón **y** con ratón conectado sin tocarlo | 0,00 % (sin ratón) | 0,03/s (sin ratón) | 12 MB · *con ratón: pendiente* |
| Downloads | sin descargas en curso | 0,00 % | 0,03/s | 42 MB con Ajustes abiertos (vista previa sin aceptar) · *con FSEvents activo: pendiente* |
| Shelf | en reposo (sin arrastrar) | 0,00 % | 0,02/s | 12 MB |
| Uninstall | ventana cerrada | 0,00 % | 0,02/s | 12 MB |
| Capture | en reposo, tras hacer 3 capturas | 0,00 % (recién arrancado) | 0,02/s | 12 MB · *tras capturas: pendiente* |
| Monitor | submenú **cerrado** (abierto, 1 muestra/s es lo esperado) | 0,00 % | 0,03/s | 12 MB |
| Monitor + lectura en la barra | ≥ 10 s de intervalo: idlew ≈ 0,1/s es lo esperado | | | |
| Switcher | en reposo, tras abrirlo 3 veces | 0,00 % (sin abrirlo) | 0,03/s | 12 MB · *tras abrirlo: pendiente* |
| Dock Previews | ratón fuera del Dock | 0,00 % | 0,02/s | 12 MB |
| MenuBar | iconos ocultos | | | |
| Audio | todo al 100 % (0 taps) **y** con una app al 50 % sonando | | | |
| Ribbon | modo apagado **y** modo encendido sin tocar nada | 0,00 % (apagado) | 0,03/s (apagado) | 12 MB · *encendido: pendiente* |
| **Todos los estables a la vez** | en reposo | 0,00 % | 0,02/s | 42 MB (con Ajustes abiertos, ver Downloads) |

---

## Prioridad 1 — base, Snap y Scroll

### Arranque y menú
- [x] Aparece el icono en la barra de menús y **no** en el Dock ni en ⌘Tab. *(24-11: `LSUIElement`, política accessory)*
- [x] El menú muestra «Módulos», las entradas de los módulos activos, «Permisos», «Abrir al iniciar sesión», «Ajustes…» y «Salir de Ligero».
- [x] Volver a abrir la app desde Finder con ella ya abierta muestra los Ajustes.

### Permisos
- [ ] «Accesibilidad» y «Grabación de pantalla» aparecen como «no concedido» la primera vez y, al pulsarlos, abren el panel correcto de Ajustes del Sistema.
- [ ] Al conceder Accesibilidad, el menú dice «concedido» sin reiniciar y Snap/Scroll arrancan solos.
- [x] Al recompilar con `SIGN_ID="Ligero Dev"` y reinstalar, **no** se pierden los permisos. *(24-11: 8 reinstalaciones)*

### Ajustes, idioma y arranque
- [x] «Ajustes…» abre la ventana con una pestaña por módulo (Uninstall y Audio no tienen opciones). Al cerrarla, la RAM vuelve aproximadamente a lo de antes. *(24-11: 42 → 39 MB)*
- [ ] Idioma *(24-11: inglés y español sin claves sueltas en el menú ni en las 11 pestañas, cambiando `AppleLanguages`; falta probar el selector y «Reiniciar ahora»)*: «English» → «Reiniciar ahora» → todo en inglés; «Español» → todo en español; «Sistema» → sigue a macOS. No aparece ninguna clave del tipo `menu.settings`.
- [ ] «Abrir al iniciar sesión» aparece en Ajustes del Sistema → General → Elementos de inicio, y Ligero arranca solo al iniciar sesión.

### Snap
| Acción | Atajo |
|---|---|
| Mitades izq. / der. / sup. / inf. | ⌃⌥← / ⌃⌥→ / ⌃⌥↑ / ⌃⌥↓ |
| Cuartos | ⌃⌥U / ⌃⌥I / ⌃⌥J / ⌃⌥K |
| Tercios: primero / central / último | ⌃⌥D / ⌃⌥F / ⌃⌥G |
| Dos tercios: primeros / últimos | ⌃⌥E / ⌃⌥T |
| Maximizar / maximizar altura / centrar | ⌃⌥↩ / ⌃⌥⇧↑ / ⌃⌥C |
| Pantalla siguiente / anterior | ⌃⌥⌘→ / ⌃⌥⌘← |
| Restaurar | ⌃⌥⌫ |

- [x] Cada atajo de la tabla en Safari, Finder, Terminal y una app Electron: se mueve de golpe y respeta el notch y el Dock. *(24-11: también TextEdit y Discord; ventanas con tamaño mínimo se quedan dentro de la pantalla)*
- [x] ⌃⌥← tres veces: ½ → ⅔ → ⅓. Desactivando la opción en Ajustes → Snap, siempre ½.
- [x] Dos snaps seguidos y ⌃⌥⌫: vuelve al tamaño de antes del primero.
- [ ] Con pantalla externa, ⌃⌥⌘→/← conserva la posición relativa.
- [x] Separación de 10 pt entre ventanas y bordes.
- [x] Grabar atajo: Esc cancela, Borrar lo quita, ⇧A solo no se acepta, un atajo repetido se quita de la otra acción. Mientras grabas, ⌃⌥← no mueve ventanas.
- [x] *(0.3.3)* Menú de Ligero → "Colocar ventana de <app>": cada opción coloca la ventana activa y muestra su atajo al lado. *(25-11: probado con TextEdit)*
- [ ] *(0.3.3)* Con el modo Ribbon activo, un atajo de Snap saca esa ventana de la tira y la deja donde la pone Snap; las demás columnas cierran el hueco. *(25-11: probado con atajos sintéticos)*
- [ ] Colocar con el ratón: Snap no tiene zonas de arrastre propias (gastaría eventos en cada arrastre). Para eso usa el mosaico de macOS: activa en Ajustes del Sistema → Escritorio y Dock "Arrastrar ventanas a los bordes de la pantalla para organizarlas en mosaico" y arrastra la ventana a un borde o con ⌥ pulsada.

### Scroll
- [x] Sin ratón: el log **no** muestra «Event tap installed». *(24-11: 0 event taps de Ligero en `CGGetEventTapList`)*
- [ ] Al conectar un ratón: «Mouse connected» + «Event tap installed». Al desconectarlo: «Event tap removed».
- [ ] La rueda va al revés que el trackpad; el trackpad (y el Magic Mouse) siguen igual.
- [ ] Scroll horizontal invertido (opción), scroll lineal con 1, 3 y 10 líneas.
- [ ] Botones laterales: Atrás/Adelante en Safari, Chrome y Finder **con el teclado en español**; «Intercambiar» los invierte.
- [ ] Con todas las opciones desactivadas, no se instala la tap ni con ratón.

---

## Prioridad 2 — módulos estables nuevos

### Uninstall (activado por defecto)
- [x] Menú → «Desinstalar una app…» abre la ventana. Arrastra una app de prueba (por ejemplo, una descargada y abierta una vez): lista la app y sus restos en ~/Library con tamaños.
- [x] Desmarcar un elemento lo excluye del total.
- [x] Con la app abierta, avisa y el botón «Salir de la app» la cierra. *(24-11: también si se abre después de cargarla)*
- [x] «Mover a la Papelera»: todo aparece en la Papelera y se puede recuperar con «Recuperar». **Nunca** se borra nada directamente.
- [x] Safari u otra app de Apple: la rechaza. Ligero no se desinstala a sí mismo.
- [ ] Si macOS pide «acceder a datos de otras apps» al tocar ~/Library/Containers, acepta y repite.

### Monitor (activado por defecto)
- [x] Menú → «Monitor»: CPU, memoria, presión, red, batería (%, estado, W, tiempo, salud, ciclos) y «Más energía ahora». Los valores se actualizan cada segundo mientras está abierto.
- [x] Con el submenú cerrado, `top` muestra 0,0 % de CPU (no sigue midiendo).
- [x] Comprueba que los valores cuadran aproximadamente con Monitor de Actividad e Información del sistema → Energía. *(24-11: %, W, ciclos y salud frente a `pmset`/`ioreg`; un proceso al 100 % sale con ~6 W)*
- [x] Ajustes → Monitor → «Mostrar CPU y RAM en la barra»: aparece el texto y se actualiza cada ~10 s. Al desactivarlo, desaparece.

### Downloads (desactivado por defecto)
- [ ] Ajustes → Descargas: la vista previa lista lo que movería sin mover nada.
- [ ] «Activar orden automático» mueve lo de la vista previa y crea las carpetas (Imágenes, Documentos, PDFs, Vídeo, Audio, Comprimidos, Instaladores, Código). macOS puede pedir acceso a Descargas: acepta.
- [ ] Descarga un archivo grande en Safari y en Chrome: no se toca mientras es `.download`/`.crdownload`; se mueve unos 2 s después de terminar.
- [ ] Con un archivo del mismo nombre ya en la carpeta destino, el nuevo se llama «nombre 2.ext». Nada se sobrescribe.
- [ ] Menú → «Deshacer un movimiento» → elige uno: el archivo vuelve a Descargas y **no** se vuelve a mover.
- [ ] Desactivar una categoría o renombrar su carpeta en Ajustes se respeta.

### Shelf (desactivado por defecto)
- [ ] Empieza a arrastrar un archivo en Finder: aparece la bandeja bajo el notch. Arrastrar para seleccionar texto **no** la abre.
- [ ] Suelta archivos, un enlace de Safari y texto: aparecen como iconos. Sácalos arrastrando a otra carpeta o app.
- [ ] Si sueltas el arrastre fuera y la bandeja está vacía, se oculta sola; con cosas, se queda hasta ✕.
- [ ] ⌃⌥⌘S la muestra y la oculta.
- [ ] Carpeta fijada (Ajustes → Bandeja): soltar archivos encima los **copia** allí.

### Capture (desactivado por defecto; necesita Grabación de pantalla)
- [x] ⌃⌥⇧3: oscurece la pantalla, arrastras una región y el PNG queda en el portapapeles (pégalo en Vista Previa → Nuevo desde el portapapeles). Esc o clic derecho cancelan. *(24-11: Esc probado; falta el clic derecho)*
- [x] Con «Guardar un PNG en el Escritorio»: aparece «Captura <fecha>.png».
- [x] ⌃⌥⇧4 sobre texto en español y en inglés: el texto queda en el portapapeles en orden de lectura.
- [ ] ⌃⌥⇧5: la captura queda flotando; se mueve arrastrando y se cierra con Esc o doble clic. *(24-11: aparece en su sitio y se cierra con clic + Esc y con doble clic; falta moverla arrastrando)*
- [ ] Con dos pantallas, captura una región de la externa.
- [ ] Tras capturar, la app que tenías delante sigue activa.

---

## Prioridad 3 — experimentales (activar uno a uno)

### MenuBar — validar primero (riesgo de Tahoe)
> **24-11, macOS 27.2: no viable.** El sistema limita el separador a 5002 pt y lo coloca fuera de su sitio; con un icono ⌘-arrastrado a su izquierda, al plegar el icono sigue visible. Déjalo desactivado (ver CHANGELOG). Alternativa nativa: Ajustes del Sistema → Barra de menús.
- [ ] Al activarlo aparecen una flecha y un separador fino. Con ⌘ arrastra varios iconos a la izquierda del separador y deja el de Ligero a la derecha.
- [ ] Clic en la flecha: los iconos de la izquierda desaparecen y vuelven a aparecer. ⌃⌥⌘B hace lo mismo.
- [ ] **Tahoe**: comprueba que el separador largo de verdad los empuja fuera, que no se lleva el icono de Ligero y que no rompe el Centro de control. Si falla, anótalo y desactiva el módulo.
- [ ] Con «Volver a ocultarlos al cambiar de app», al pulsar en otra app se vuelven a ocultar.
- [ ] Sección «siempre oculto»: ⌥-clic en la flecha la muestra.
- [ ] Al desactivar el módulo desaparecen la flecha y los separadores y todo se ve como antes.

### Switcher
- [ ] ⌥Tab muestra las ventanas del Space actual ordenadas por uso reciente; soltar ⌥ cambia a la seleccionada. Un ⌥Tab rápido va a la ventana anterior.
- [ ] Tab / flechas / ⇧Tab navegan; escribir filtra (sin importar tildes); Esc cancela.
- [ ] ⌘W cierra, ⌘M minimiza y ⌘Q sale de la app seleccionada.
- [ ] Con Grabación de pantalla hay miniaturas; sin ella, iconos. La segunda vez que lo abres, las miniaturas salen al momento (caché) y se actualizan si mueves o cambias la ventana.
- [ ] Las ventanas minimizadas aparecen en gris y se restauran al elegirlas.

### Dock Previews
> **24-11:** Se vio que la vista previa se quedaba en pantalla al salir del Dock (con el Dock en ocultación automática). Arreglado: mientras se ve, se oculta en cuanto el ratón sale del panel y del Dock. **Vuelve a probar la primera casilla y «Al salir del icono y del panel, se oculta».**
- [ ] Pasa el ratón por el icono de una app con varias ventanas: aparece el panel encima del Dock con sus ventanas. Con el Dock a un lado, aparece al lado.
- [ ] Clic en una miniatura cambia a esa ventana; los botones cierran y minimizan.
- [ ] Al salir del icono y del panel, se oculta.
- [ ] Opción «Al hacer clic en el icono de la app que está delante» → «Ocultar la app» / «Minimizar sus ventanas»: funciona solo con la app que está delante, y con «Nada» los clics no se interceptan.
- [ ] Reinicia el Dock (`killall Dock`): las vistas previas siguen funcionando.

### Audio
> **24-11:** Ligero salía en la lista del mezclador: arreglado. Subir por encima de 100 % solo se nota con fuentes grabadas bajas: la música ya suena cerca del máximo digital y +50 % (≈ +3,5 dB) se recorta en los picos.
- [ ] Menú → «Mezclador de audio» con Música o Spotify sonando: aparece la app con su deslizador.
- [ ] Al bajar a 50 % baja el volumen; al subir a 150 % sube, sin distorsión exagerada. Silenciar funciona. macOS pedirá permiso de audio la primera vez.
- [ ] «Taps activos» muestra 1 con una app cambiada y 0 cuando la vuelves a 100 % o deja de sonar (también en el log: «Audio tap created/removed»).
- [ ] «Salida de <app>» → auriculares: esa app suena por los auriculares y el resto por los altavoces.
- [ ] Cerrar la app que tiene tap: el tap desaparece. Cambiar la salida por defecto del sistema no corta el sonido.
- [ ] Con todo al 100 % no hay ningún tap (medición de batería).

### Ribbon (el más delicado: pruébalo con pocas ventanas sin importancia)
> **24-11:** probado con 7 ventanas de TextEdit y 2 de Terminal: modo, foco, ancho, mover, apilar/sacar, ventana nueva y restaurar al apagar, todo correcto. Arreglado: las ventanas de apps abiertas con Ligero ya en marcha no entraban en la tira (y su posición guardada podía estar vieja). Sin animaciones a propósito (regla de batería). Las columnas fuera de la vista se aparcan una encima de otra en el borde.
- [ ] ⌃⌥⌘Space activa el modo: las ventanas de cada pantalla se colocan en columnas de izquierda a derecha.
- [ ] Abre una ventana nueva: aparece a la derecha de la enfocada y las demás no cambian de tamaño.
- [ ] ⌃⌥⌘H/L cambia de columna y desplaza la tira si hace falta; las que quedan fuera se ven 1 pt en el borde.
- [ ] ⌃⌥⌘⇧H/L mueve la columna; ⌃⌥⌘R / ⌃⌥⌘⇧R cambia el ancho; ⌃⌥⌘[ apila en la columna izquierda y ⌃⌥⌘] saca de la pila; ⌃⌥⌘K/J se mueve dentro de la pila.
- [ ] ⌃⌥⌘N envía la ventana a la otra pantalla (con pantalla externa). Las ventanas aparcadas no se ven en la otra pantalla.
- [ ] Diálogos, paneles y apps excluidas no se tocan.
- [ ] ⌃⌥⌘Space otra vez: **todas** las ventanas vuelven a donde estaban.
- [ ] Gesto (activado por defecto desde 0.3.2): ⌥ + scroll horizontal con dos dedos desliza la tira, solo con el modo activo.

> **24-11 (0.3.2):** revisado contra Ribbon (meetribbon.app): tira horizontal, columnas de ancho fijo, la ventana nueva junto a la enfocada, ⌥ + scroll. Arreglado: dos ventanas de Safari no entraban en la tira, y al activar una app sus ventanas aparcadas volvían encima de las columnas. Añadido el ratón (probado con arrastres sintéticos; falta tu ratón real). Antes de probar, desactiva en Ajustes del Sistema → Escritorio y Dock → "Arrastrar ventanas a los bordes de la pantalla para organizarlas en mosaico": el mosaico de macOS se queda con la ventana que sueltas.
- [ ] Abre dos ventanas de la misma app (dos de Safari) con el modo activo: las dos entran en la tira.
- [ ] Activa una app con ventanas aparcadas (⌘Tab): no se amontonan encima de las columnas visibles.
- [ ] Arrastra el borde derecho de una ventana de la tira: al soltar, la columna se queda con ese ancho y la de al lado se pega con el hueco. ⌃⌥⌘R vuelve a los anchos fijos.
- [ ] Arrastra una ventana por el título y suéltala sobre otra columna: la tira se reordena y cada ventana vuelve a su hueco.
- [ ] Arrastra una ventana apilada hacia un lado: sale de la pila a su propia columna.

> **25-11 (0.3.3):** menú para organizar sin atajos (probado pulsando el menú por accesibilidad; falta tu ratón). Con el modo activo, el menú de Ligero muestra la lista de columnas en orden y un submenú "Ventana activa".
- [ ] Menú → "Columnas": clic en una columna → la tira se desplaza hasta ella y la enfoca.
- [ ] Menú → "Ventana activa" → "Ancho" (¼ … Completo) y "Mover a la posición" n: la columna cambia y las demás se recolocan.
- [ ] Menú → "Ventana activa" → "Sacar de la tira (flotante)" o ⌃⌥⌘F: la ventana se queda donde está y Ribbon ya no la toca; otra vez ⌃⌥⌘F (o "Volver a meter en la tira") la mete a la derecha de la enfocada.
- [ ] Gesto ⌥ + dos dedos: la tira avanza a saltos de 24 pt en vez de en cada evento (menos trabajo de AX); comprueba que se nota fluido.
- [ ] Con el modo activo y el mosaico de macOS activado, evita soltar ventanas de la tira en los bordes de la pantalla: macOS las encaja y Ribbon las devuelve a su hueco (máximo 3 veces).
