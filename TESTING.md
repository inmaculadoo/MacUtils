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
