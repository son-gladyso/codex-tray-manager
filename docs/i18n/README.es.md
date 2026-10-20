# Codex Tray Manager

[简体中文](../../README.md) · [English](README.en.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Español](README.es.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · [Português (Brasil)](README.pt-BR.md)

**Varias instancias de Codex, un único acceso desde la bandeja. Encuentra la ventana, comprende qué sigue en segundo plano y decide cómo cerrarlo.**

Pensado para quienes ya utilizan scripts de inicio aislado en Windows, Codex Tray Manager reúne el inicio, el cambio de ventana, el reinicio y el cierre para reducir los saltos entre la barra de tareas, los scripts y el Administrador de tareas. Gestiona instancias existentes; no crea cuentas, migra conversaciones ni configura un entorno aislado por ti.

> Esta es una herramienta comunitaria no oficial, sin afiliación con OpenAI ni respaldo de OpenAI.

Requiere Windows 10/11, PowerShell 7 y uno o varios scripts de PowerShell capaces de iniciar instancias aisladas de Codex. El gestor identifica a qué instancia pertenece cada proceso mediante el argumento `--user-data-dir`, único para cada instancia.

[Inicio rápido](#快速开始) · [Flujo de uso](#先看一个典型使用流程) · [Preguntas frecuentes](#常见问题) · [Verificación](#验证) · [Contribuir](#一起改进)

<a id="它解决什么问题"></a>

## Qué problemas resuelve

Cuando un equipo Windows ejecuta varias instancias aisladas de Codex de escritorio, suele ser necesario alternar entre la barra de tareas, el Administrador de tareas y varios scripts de inicio. Las ventanas ocultas son difíciles de encontrar; un cierre normal puede cerrar solo la ventana y dejar procesos en segundo plano. Terminar todo el árbol de procesos puede matar accidentalmente scripts de actualización que esperan a que salga la aplicación, terminales u otras tareas.

Codex Tray Manager ofrece un acceso unificado desde la bandeja y trata por separado «los procesos en segundo plano de la propia aplicación» y «las tareas secundarias cuyo propósito no está confirmado». Sus principales objetivos son:

- Ofrecer un estado de ejecución y controles comunes para varias instancias de Codex.
- Facilitar la localización y recuperación en primer plano de ventanas ocultas o procesos en segundo plano sin ventana.
- Gestionar procesos de Electron, app-server y otros que pueden quedar tras una salida normal.
- Evitar que un cierre indiscriminado del árbol interrumpa actualizaciones, terminales o trabajo en curso.
- Recuperar la combinación de versiones que se ejecutaba antes al reiniciar instancias con varias versiones.

<a id="功能概览"></a>

## Resumen de funciones

- Genera los menús de instancias dinámicamente a partir de la configuración JSON y coloca automáticamente las instancias activas al principio.
- Verifica que el proceso principal funciona de forma estable tras iniciarlo, sin declarar éxito basándose solo en el valor devuelto por el script.
- Enumera ventanas de nivel superior de Electron ocultas, intenta restaurarlas y traerlas al frente, y comprueba el resultado.
- Primero solicita una salida normal de la ventana y después verifica y limpia individualmente los procesos residuales confirmados como propios de la aplicación.
- Vincula la identidad de proceso al PID y a la hora de creación para reducir errores por reutilización de PID.
- Bloquea el cierre normal si descubre tareas secundarias de propósito desconocido y muestra nombre, PID y hora de creación para revisarlas.
- Ofrece cierre de emergencia con segunda confirmación y cierre en lote con resultados por instancia.
- Admite las versiones `Standard` y `UICanary`, y restaura las versiones anteriores al reiniciar.
- Actualiza estados y espera los cierres en hilos de fondo para mantener la respuesta del menú.
- Escribe registros de diagnóstico JSONL con rotación automática, sin guardar líneas de comandos completas ni credenciales de acceso.

<a id="先看一个典型使用流程"></a>

## Un flujo de uso habitual

1. Configura al menos una instancia aislada. Si hay varias, verifica que cada una tenga un directorio de datos de usuario diferente.
2. Consulta en la bandeja qué instancias están activas y trae al frente la ventana que necesitas.
3. Antes de salir, revisa los procesos y las comprobaciones de cierre para distinguir el fondo de la aplicación de las tareas secundarias no confirmadas.
4. Usa el cierre normal. Si aparecen tareas no confirmadas, investiga primero; no lo evites mediante el cierre de emergencia.
5. Revisa los resultados recientes para confirmar qué se completó realmente.

Esta página todavía no incluye capturas ni vídeos del menú de bandeja en un equipo real. Lo anterior explica una secuencia de uso, no una demostración ya grabada, ni implica que se hayan verificado todos los scripts y entornos Windows.

<a id="快速开始"></a>

## Inicio rápido

Prepara estos tres requisitos:

- Windows 10/11 y PowerShell 7 (`pwsh`), no únicamente el antiguo Windows PowerShell.
- Un script de PowerShell existente capaz de iniciar por sí solo el Codex deseado.
- Rutas absolutas de los scripts y directorios de datos de usuario únicos para cada versión. No copies sin cambios rutas de ejemplo como `D:\codex4`.

Si el script de inicio aún no funciona correctamente, soluciónalo antes de integrarlo con el gestor.

Los usuarios pueden descargar el ZIP portátil para Windows desde [Releases](https://github.com/son-gladyso/codex-tray-manager/releases), descomprimirlo, copiar `manager.settings.example.json` como `manager.settings.json` e introducir sus rutas locales.

Los desarrolladores también pueden clonar el repositorio:

```powershell
git clone https://github.com/son-gladyso/codex-tray-manager.git
cd codex-tray-manager
Copy-Item manager.settings.example.json manager.settings.json
notepad manager.settings.json
pwsh -NoProfile -File .\CodexTrayManager.ps1 -ValidateOnly
```

Tras superar la validación, haz doble clic en `Start Codex Tray Manager.cmd`. Salir del gestor no cierra Codex.

**Criterio del primer éxito:** el menú muestra las instancias configuradas y distingue las activas de las detenidas tras actualizar el estado. Prueba «Traer al frente» con una instancia de prueba activa y visible y comprueba el resultado. Validar la configuración no significa que el cambio de ventana o el cierre hayan superado pruebas de aceptación en un equipo real. Familiarízate con las comprobaciones y los mensajes de resultado antes de probar el cierre.

<a id="日常操作"></a>

## Operaciones cotidianas

- Gestiona conjuntamente las instancias configuradas de Codex (números 4–25), con las activas al principio.
- Puede agrupar la versión normal y la versión piloto de UI de una misma instancia. El cierre procesa ambas; el reinicio restaura las versiones anteriores; si ninguna está activa, inicia la normal de forma predeterminada.
- «Iniciar / Traer al frente»: verifica el proceso principal tras el inicio. Si ya existe una ventana, intenta restaurarla y verifica el primer plano. Informa con precisión si hay procesos de fondo pero ninguna ventana.
- «Cerrar (incluido el fondo de la aplicación)»: solicita una salida normal, espera hasta 3 segundos y termina uno a uno los procesos residuales cuya identidad se ha verificado.
- «Ver procesos y comprobaciones de cierre»: muestra nombre, PID y hora de creación de los procesos de aplicación y de las tareas secundarias que requieren revisión.
- «Cierre de emergencia (interrumpir todas las tareas secundarias)»: tras una segunda confirmación, termina todas las tareas descubiertas cuya identidad puede verificarse, incluidos los scripts de actualización. Úsalo solo si realmente quieres interrumpirlas.
- «Cerrar todos los Codex»: resume los resultados por instancia; un fallo no impide procesar las siguientes. Consulta los detalles en «Ver resultados de operaciones recientes».

<a id="更新脚本与其他子任务"></a>

## Scripts de actualización y otras tareas secundarias

Si el cierre normal o el reinicio encuentra tareas secundarias de propósito no confirmado, se bloquea antes de enviar la solicitud de cierre y enumera sus PID. Los scripts de actualización, terminales y servicios MCP no pueden considerarse automáticamente parte del fondo de la aplicación por su relación padre-hijo. Actualmente se reconocen como fondo los procesos Electron del mismo directorio de aplicación, app-server iniciado directamente por Electron y code-mode host del mismo directorio. Los demás requieren revisión; que el nombre contenga update o powershell no permite deducir su propósito.

**Esta versión no implementa un ejecutor independiente de actualizaciones ni una interfaz de transferencia automática.** Bloquear no es hacerse cargo de la ejecución ni garantiza que un script continúe tras salir de la aplicación. El gestor no puede identificar automáticamente scripts de actualización separados del árbol de la instancia; no pulses reiniciar hasta que terminen esas actualizaciones. Revisa primero el script concreto y su forma de ejecución para evitar que scripts antiguos y nuevos actualicen simultáneamente. El cierre de emergencia sí interrumpe las tareas que siguen dentro del árbol.

<a id="更快的刷新与更稳妥的关闭"></a>

## Actualización más rápida y cierre más seguro

- Obtiene relaciones entre procesos y horas de creación con instantáneas nativas de Windows; consulta los argumentos de inicio solo al descubrir una nueva identidad de aplicación.
- La caché de argumentos usa PID + hora de creación como clave y se limpia cuando el proceso termina; reutilizar un PID padre no hereda la pertenencia antigua.
- Crea índices compartidos de procesos, relaciones padre-hijo y directorios de usuario; las actualizaciones rutinarias de estado no enumeran ventanas.
- Ejecuta consultas de ventanas, actualizaciones de procesos, esperas de cierre y verificaciones de inicio en hilos independientes, sin espera síncrona de la interfaz.
- De forma predeterminada actualiza cada 10 segundos con el menú cerrado y cada 2 segundos con él abierto; también al abrir el menú, pulsar actualizar y completar una operación.
- Conserva los identificadores de proceso verificados durante el cierre para rastrear procesos de fondo huérfanos tras salir el principal, y revisa todos los objetivos conocidos al final.
- Ya no llama a `taskkill /T`. Cada terminación forzada comprueba la hora de creación y termina el proceso usando el mismo identificador de proceso.
- Desactiva acciones duplicadas durante una operación e informa de errores de permisos, cierres incompletos, tiempos de inicio agotados y fallos al traer al frente.
- La ausencia de un script no impide que arranque todo el gestor. Al intentar iniciar la versión afectada se muestra un error específico.

Las instantáneas tienen límites temporales. No puede demostrarse automáticamente la pertenencia de procesos de fondo que ya eran huérfanos antes de iniciar el gestor y no tienen marcadores de configuración. La pertenencia observada se conserva solo en la sesión actual y no se deduce entre reinicios del gestor. Windows también puede limitar la activación en primer plano; por eso un fallo se comunica y no se presenta como éxito.

<a id="配置与诊断"></a>

## Configuración y diagnóstico

Copia `manager.settings.example.json` como `manager.settings.json` y rellena directorios de instancia, scripts/directorios de datos por versión, iconos, intervalos de actualización y tiempos máximos de inicio. Git ignora la ruta local predeterminada, pero revisa los cambios preparados antes de confirmar para no publicar configuraciones privadas ya rastreadas, añadidas por la fuerza o guardadas en otra ubicación. Configura al menos una instancia y reinicia el gestor para aplicar cambios. Se validan números, versiones, rutas absolutas y directorios duplicados. El gestor no modifica scripts de inicio, archivos de aplicación, inicios de sesión, configuración de Codex ni espacios de trabajo.

«Abrir registros de diagnóstico» abre `logs`. `manager.jsonl` guarda resultados, errores y duraciones; al superar 2 MB rota a `manager.previous.jsonl`. No se registran líneas de comandos completas ni credenciales. Los fallos de inicio por configuración o dependencias se registran en `startup-error.log` y muestran un mensaje de error.

<a id="常见问题"></a>

## Preguntas frecuentes

**¿Crea instancias aisladas o cambia de cuenta por mí?** No. Debes preparar tus propios scripts y directorios de datos independientes. El gestor no modifica accesos, configuración de Codex ni espacios de trabajo.

**¿Salir del gestor cierra también mis instancias de trabajo?** No. Salir del gestor y cerrar instancias de Codex son operaciones distintas.

**¿Por qué se bloqueó el cierre normal?** Se encontraron tareas secundarias de propósito no confirmado. Revisa nombre, PID y hora de creación para saber si son actualizaciones, terminales u otro trabajo; no uses el cierre de emergencia solo para quitar el aviso.

**El menú indica actividad en segundo plano, ¿por qué no encuentro una ventana?** Puede quedar únicamente fondo sin ventana, o Windows puede haber limitado la activación. Consulta el resultado: un proceso existente no equivale a una ventana disponible.

**¿Por qué no se aplica mi cambio de configuración?** Reinicia el gestor después de modificar tu `manager.settings.json` local. Comprueba antes números, versiones y rutas con `-ValidateOnly`.

**¿Pueden transferirse automáticamente los scripts de actualización al gestor para que sigan ejecutándose?** No. No existe actualmente un ejecutor independiente ni una interfaz de transferencia. Consulta [Scripts de actualización y otras tareas secundarias](#更新脚本与其他子任务).

<a id="开发者从哪里读起"></a>

## Por dónde empezar como desarrollador

| Archivo | Enfoque | Qué comprobar al modificarlo |
| --- | --- | --- |
| `CodexTrayManager.ps1` | Entrada de bandeja y organización de operaciones | Clics repetidos, esperas en segundo plano, errores y respuesta del menú. |
| `CodexTrayManager.Core.psm1` | Lógica de gestión compartida | Regresiones en configuración, pertenencia y resultados. |
| `CodexTrayManager.Native.cs` / `CodexTrayManager.Process.cs` | Límites nativos de procesos y ventanas de Windows | Identidad, carreras al salir y fallos de permisos, no solo el caso correcto. |
| `manager.settings.example.json` | Ejemplo de configuración | Rutas ficticias y compatibilidad con una instancia y varias versiones. |
| `tests/` | Simulaciones, integración y muestreo de rendimiento | Distinguir simulaciones aprobadas, pruebas con procesos temporales y observaciones de uso diario. |

<a id="验证"></a>

## Verificación

```powershell
# 模拟回归，不关闭真实应用
pwsh -NoProfile -File .\tests\Test-CodexTrayManager.ps1

# 含临时进程、临时窗口的行为验证
pwsh -NoProfile -STA -File .\tests\Test-CodexTrayManager.ps1 -Integration

# 人为延迟后台工作，确认 UI 定时器仍能响应；自动退出
pwsh -NoProfile -STA -File .\CodexTrayManager.ps1 -SmokeTestSeconds 18 -SmokeWorkerDelaySeconds 3

# 完整刷新性能采样，须在具备本机进程查询权限的 PowerShell 中执行
pwsh -NoProfile -File .\tests\Measure-CodexTrayManager.ps1 -ModulePath "$PWD\CodexTrayManager.Core.psm1" -Iterations 20
```

<a id="缓存加固"></a>

## Refuerzo de la caché

La eliminación de entradas ahora precede a la consulta de identidad, evitando omitir la limpieza si la consulta tiene éxito parcial y después lanza un error. Antes de reutilizar el hilo de fondo en cada ciclo se vacían los flujos de diagnóstico, incluidos errores y advertencias. El registro principal conserva el archivo actual y uno rotado; el registro de errores de inicio también rota al superar 256 KB y conserva solo un archivo anterior. El último registro puede superar ligeramente el umbral.

En una regresión con 1000 fallos parciales consecutivos y cambios de identidad de proceso, la lógica anterior acumulaba 1000 entradas. La nueva conserva como máximo 1 entrada actual y 0 cuando todos los procesos terminan.

<a id="安全边界"></a>

## Límites de seguridad

El cierre normal se bloquea ante tareas secundarias de propósito no confirmado. El «Cierre de emergencia» del menú interrumpe, tras una segunda confirmación, todas las tareas descubiertas dentro del árbol de esa instancia. Úsalo únicamente cuando necesites expresamente interrumpir actualizaciones, terminales u otro trabajo.

<a id="一起改进"></a>

## Contribuir

Se agradecen correcciones documentales concretas, reproducciones de problemas y pruebas de regresión. Puedes empezar por un escenario específico sin conocer todo el proyecto:

- Mejorar avisos de errores de configuración, tiempos de inicio agotados o fallos de cambio de ventana.
- Añadir pruebas de reutilización de PID, ventanas ocultas, tareas secundarias desconocidas y casos similares.
- Comprobar resultados en distintos entornos Windows y detallar versiones y pasos de reproducción.
- Facilitar el seguimiento del inicio rápido y del diagnóstico.

Lee primero «Verificación» y «Límites de seguridad». Para cambios de pertenencia de procesos o lógica de cierre, prioriza simulaciones y procesos temporales; no actúes por defecto sobre instancias de trabajo cotidiano. En el PR explica el problema, los cambios, las comprobaciones ejecutadas y lo que sigue sin verificarse. Debate cambios grandes de comportamiento primero en [Issues](https://github.com/son-gladyso/codex-tray-manager/issues).

No envíes configuraciones reales, datos de cuentas, líneas de comandos completas ni capturas de diagnóstico con rutas privadas. No se deben «corregir» fallos debilitando la verificación de identidad, omitiendo confirmaciones o forzando la terminación de tareas desconocidas.

<a id="许可证"></a>

## Licencia

Este proyecto utiliza la [MIT License](../../LICENSE). Puedes usarlo, copiarlo, modificarlo, combinarlo, publicarlo y distribuirlo conservando los avisos originales de derechos de autor y permiso. El software se proporciona «tal cual», sin garantía de ningún tipo.
