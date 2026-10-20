# Codex Tray Manager

[简体中文](../../README.md) · [English](README.en.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Español](README.es.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · [Português (Brasil)](README.pt-BR.md) · [Русский](README.ru.md) · [繁體中文](README.zh-TW.md)

**Mehrere Codex-Instanzen, ein Zugang im Infobereich. Fenster finden, Hintergrundprozesse verstehen und dann entscheiden, wie sie beendet werden.**

Codex Tray Manager richtet sich an Nutzer, die unter Windows bereits Skripte für isolierte Starts verwenden. Er bündelt Starten, Fensterwechsel, Neustart und Beenden und reduziert das Suchen zwischen Taskleiste, Skripten und Task-Manager. Er verwaltet vorhandene Instanzen, erstellt aber keine Konten, migriert keine Chats und richtet keine isolierte Umgebung ein.

> Dies ist ein inoffizielles Community-Werkzeug, das weder mit OpenAI verbunden ist noch von OpenAI unterstützt wird.

Vorausgesetzt werden Windows 10/11, PowerShell 7 und mindestens ein PowerShell-Skript, das isolierte Codex-Instanzen starten kann. Der Manager erkennt die Instanzzugehörigkeit eines Prozesses anhand des für jede Instanz eindeutigen Arguments `--user-data-dir`.

[Schnellstart](#快速开始) · [Ablauf](#先看一个典型使用流程) · [Häufige Fragen](#常见问题) · [Überprüfung](#验证) · [Mitwirken](#一起改进)

<a id="它解决什么问题"></a>

## Welche Probleme werden gelöst?

Wenn auf einem Windows-PC mehrere isolierte Codex-Desktop-Instanzen laufen, müssen Nutzer oft zwischen Taskleiste, Task-Manager und mehreren Startskripten wechseln. Verborgene Fenster sind schwer zu finden. Normales Schließen kann nur das Fenster schließen und Hintergrundprozesse zurücklassen. Das Beenden des gesamten Prozessbaums kann dagegen versehentlich Updateskripte, die auf das Anwendungsende warten, Terminals oder andere Aufgaben abbrechen.

Codex Tray Manager bietet einen gemeinsamen Zugang im Infobereich und behandelt „anwendungseigene Hintergrundprozesse“ getrennt von „Unteraufgaben mit ungeklärtem Zweck“. Im Mittelpunkt stehen:

- Fehlende gemeinsame Statusanzeige und Bedienung mehrerer Codex-Instanzen.
- Schwierigkeiten, verborgene Fenster oder fensterlose Hintergrundprozesse zu finden und wieder in den Vordergrund zu gelangen.
- Electron-, app-server- und andere Hintergrundprozesse, die nach normalem Beenden zurückbleiben können.
- Unterbrochene Updates, Terminals oder laufende Arbeit durch pauschales Beenden eines Prozessbaums.
- Die schwierige Wiederherstellung der zuvor tatsächlich laufenden Versionskombination bei Instanzen mit mehreren Versionen.

<a id="功能概览"></a>

## Funktionsübersicht

- Erzeugt Instanzmenüs dynamisch aus der JSON-Konfiguration und sortiert laufende Instanzen automatisch nach oben.
- Prüft nach dem Start, ob der Hauptprozess stabil läuft, statt allein anhand des Skriptrückgabewerts Erfolg zu melden.
- Erfasst verborgene Electron-Fenster der obersten Ebene, versucht sie wiederherzustellen und in den Vordergrund zu bringen und überprüft das Ergebnis.
- Fordert zuerst das normale Schließen des Fensters an und prüft und bereinigt anschließend einzeln bestätigte Restprozesse der Anwendung.
- Verknüpft die Prozessidentität mit PID und Erstellungszeit, um Fehlaktionen bei wiederverwendeten PIDs zu verringern.
- Blockiert normales Beenden bei Unteraufgaben mit unbekanntem Zweck und zeigt Name, PID und Erstellungszeit zur Prüfung an.
- Bietet Notfallbeenden mit zweiter Bestätigung sowie Sammelbeenden mit Ergebnissen pro Instanz.
- Unterstützt `Standard` und `UICanary` und stellt beim Neustart die zuvor laufenden Versionen wieder her.
- Aktualisiert Zustände und wartet auf das Beenden in Hintergrundthreads, damit das Menü bedienbar bleibt.
- Schreibt automatisch rotierende JSONL-Diagnoseprotokolle, ohne vollständige Prozessbefehlszeilen oder Anmeldedaten aufzuzeichnen.

<a id="先看一个典型使用流程"></a>

## Ein typischer Ablauf

1. Konfiguriere zunächst mindestens eine isolierte Instanz. Bei mehreren muss jede ein eigenes Benutzerdatenverzeichnis verwenden.
2. Prüfe im Infobereich die laufenden Instanzen und bringe das benötigte Fenster in den Vordergrund.
3. Sieh dir vor dem Beenden Prozesse und Beendigungsprüfungen an, um Anwendungshintergrund und ungeklärte Unteraufgaben zu unterscheiden.
4. Verwende normales Beenden. Werden ungeklärte Aufgaben gefunden, prüfe zuerst die Ursache, statt die Sperre per Notfallbeenden zu umgehen.
5. Kontrolliere die letzten Aktionsergebnisse, um zu sehen, was tatsächlich abgeschlossen wurde.

Diese Seite enthält noch keine Screenshots oder Aufzeichnungen des Menüs auf einem echten Rechner. Die Beschreibung ist ein Ablauf, keine bereits aufgezeichnete Demonstration. Sie bedeutet auch nicht, dass alle Startskripte und Windows-Umgebungen geprüft wurden.

<a id="快速开始"></a>

## Schnellstart

Bereite drei Voraussetzungen vor:

- Windows 10/11 und PowerShell 7 (`pwsh`), nicht nur die ältere Windows PowerShell.
- Ein vorhandenes PowerShell-Skript, das das gewünschte Codex selbstständig starten kann.
- Absolute Startskriptpfade und eindeutige Benutzerdatenverzeichnisse pro Version. Beispielpfade wie `D:\codex4` dürfen nicht unverändert übernommen werden.

Falls das Startskript selbst noch nicht funktioniert, behebe das vor der Einbindung in den Manager.

Nutzer können die portable Windows-ZIP unter [Releases](https://github.com/son-gladyso/codex-tray-manager/releases) herunterladen und entpacken, `manager.settings.example.json` nach `manager.settings.json` kopieren und lokale Pfade eintragen.

Entwickler können auch das Repository klonen:

```powershell
git clone https://github.com/son-gladyso/codex-tray-manager.git
cd codex-tray-manager
Copy-Item manager.settings.example.json manager.settings.json
notepad manager.settings.json
pwsh -NoProfile -File .\CodexTrayManager.ps1 -ValidateOnly
```

Nach erfolgreicher Validierung doppelklicke auf `Start Codex Tray Manager.cmd`. Das Beenden des Managers schließt Codex nicht.

**Kriterium für den ersten Erfolg:** Das Menü zeigt die konfigurierten Instanzen und unterscheidet nach einer Statusaktualisierung zwischen laufenden und gestoppten. Probiere „In den Vordergrund“ an einer laufenden, sichtbaren Testinstanz aus und prüfe das Ergebnis. Eine bestandene Konfigurationsprüfung ist keine abgeschlossene Abnahme von Fensterwechsel oder Beenden auf einem echten Rechner. Mache dich erst mit Prüfungen und Ergebnismeldungen vertraut, bevor du das Beenden ausprobierst.

<a id="日常操作"></a>

## Tägliche Bedienung

- Verwaltet die konfigurierten Codex-Instanzen gemeinsam (Nummern 4–25), laufende Instanzen stehen oben.
- Normale und UI-Testversion derselben Instanz können zusammen verwaltet werden. Beenden betrifft beide; Neustart stellt die zuvor laufenden Versionen wieder her; läuft keine, startet standardmäßig die normale Version.
- „Starten / In den Vordergrund“: prüft nach dem Start den Hauptprozess. Bei vorhandenem Fenster wird die Wiederherstellung versucht und der Vordergrundstatus überprüft. Hintergrundprozesse ohne Fenster werden ehrlich gemeldet.
- „Beenden (einschließlich Anwendungshintergrund)“: fordert normales Schließen an, wartet höchstens 3 Sekunden und beendet dann verbliebene Anwendungsprozesse einzeln nach Identitätsprüfung.
- „Prozesse und Beendigungsprüfung anzeigen“: zeigt Namen, PIDs und Erstellungszeiten von Anwendungsprozessen und zu prüfenden Unteraufgaben.
- „Notfallbeenden (alle Unteraufgaben abbrechen)“: beendet nach zweiter Bestätigung alle gefundenen Unteraufgaben mit prüfbarer Identität, einschließlich Updateskripten. Nur verwenden, wenn diese Aufgaben ausdrücklich abgebrochen werden sollen.
- „Alle Codex beenden“: fasst Ergebnisse pro Instanz zusammen; ein Fehler verhindert die Verarbeitung weiterer Instanzen nicht. Einzelheiten stehen unter „Letzte Aktionsergebnisse anzeigen“.

<a id="更新脚本与其他子任务"></a>

## Updateskripte und andere Unteraufgaben

Treffen normales Beenden oder Neustart auf Unteraufgaben mit ungeklärtem Zweck, wird vor dem Senden einer Beendigungsanforderung blockiert und ihre PID aufgelistet. Updateskripte, Terminals und MCP-Dienste sind nicht allein aufgrund einer Eltern-Kind-Beziehung Anwendungshintergrund. Derzeit bestätigt sind Electron-Prozesse im selben Anwendungsverzeichnis, direkt von Electron gestarteter app-server sowie code-mode host im selben Verzeichnis. Andere Prozesse müssen geprüft werden. Aus update oder powershell im Namen lässt sich ihr Zweck nicht ableiten.

**Diese Version bietet weder einen unabhängigen Update-Executor noch eine Schnittstelle zur automatischen Übernahme.** Blockieren ist keine Übernahme und garantiert nicht, dass ein Skript nach dem Anwendungsende weiterlaufen kann. Updateskripte, die den Prozessbaum der Instanz verlassen haben, werden nicht automatisch erkannt; klicke nicht auf Neustart, bevor solche Updates fertig sind. Prüfe das konkrete Skript und seine Ausführung, damit alte und neue Skripte nicht gleichzeitig aktualisieren. Notfallbeenden unterbricht ausdrücklich noch im Instanzbaum befindliche Aufgaben.

<a id="更快的刷新与更稳妥的关闭"></a>

## Schnellere Aktualisierung und sichereres Beenden

- Native Windows-Momentaufnahmen liefern Prozessbeziehungen und Erstellungszeiten. Startargumente werden nur beim Erkennen einer neuen Anwendungsidentität abgefragt.
- Der Argumentcache verwendet PID + Erstellungszeit als Schlüssel und wird beim Prozessende bereinigt; eine wiederverwendete Eltern-PID übernimmt keine alte Zuordnung.
- Gemeinsame Indizes für Prozesse, Eltern-Kind-Beziehungen und Benutzerverzeichnisse werden aufgebaut. Reguläre Statusaktualisierungen zählen keine Fenster auf.
- Fensterabfragen, Prozessaktualisierungen, Beendigungswartezeiten und Startprüfungen laufen in separaten Arbeitsthreads; die Oberfläche wartet nicht mehr synchron.
- Standardmäßig wird bei geschlossenem Menü alle 10 Sekunden und bei geöffnetem alle 2 Sekunden aktualisiert, außerdem zeitnah beim Öffnen, manuellen Aktualisieren und Abschluss einer Aktion.
- Beim Beenden bleiben Handles geprüfter Prozesse erhalten, um nach dem Hauptprozessende verwaiste Hintergrundprozesse zu verfolgen. Am Ende werden alle bekannten Ziele geprüft.
- `taskkill /T` wird nicht mehr aufgerufen. Jede erzwungene Beendigung prüft die Erstellungszeit und beendet über dasselbe Prozesshandle.
- Doppelte Aktionen werden während eines Vorgangs deaktiviert. Berechtigungsfehler, unvollständiges Beenden, Startzeitüberschreitungen und fehlgeschlagene Vordergrundwechsel werden gemeldet.
- Ein fehlendes Startskript verhindert nicht den Start des gesamten Managers. Der Startversuch der betroffenen Version liefert weiterhin einen konkreten Fehler.

Prozessmomentaufnahmen haben zeitliche Grenzen. Hintergrundprozessen, die schon vor dem Managerstart verwaist waren und keine Konfigurationsmarker haben, kann die Zugehörigkeit nicht automatisch nachgewiesen werden. Beobachtete Zuordnungen gelten nur innerhalb der aktuellen Managersitzung und werden nicht über Managerneustarts hinweg abgeleitet. Windows kann zudem Vordergrundaktivierungen beschränken; ein Fehlschlag wird deshalb gemeldet und nicht als Erfolg ausgegeben.

<a id="配置与诊断"></a>

## Konfiguration und Diagnose

Kopiere `manager.settings.example.json` nach `manager.settings.json` und trage Instanzverzeichnisse, Startskripte/Benutzerdatenverzeichnisse pro Version, Symbole, Aktualisierungsintervalle und Startzeitlimits ein. Git ignoriert den lokalen Standardpfad. Prüfe trotzdem vor dem Commit den Staging-Bereich, damit bereits verfolgte, erzwungen hinzugefügte oder anders gespeicherte private Konfigurationen nicht veröffentlicht werden. Mindestens eine Instanz ist nötig. Änderungen werden nach einem Neustart des Managers wirksam. Geprüft werden Nummern, Versionen, absolute Pfade und doppelte Verzeichnisse. Der Manager ändert keine Startskripte, Anwendungsarchive, Anmeldungen, Codex-Konfigurationen oder Arbeitsbereiche.

„Diagnoseprotokolle öffnen“ öffnet `logs`. `manager.jsonl` speichert Ergebnisse, Fehler und Laufzeiten und rotiert oberhalb von 2 MB nach `manager.previous.jsonl`. Vollständige Prozessbefehlszeilen und Anmeldedaten werden nicht protokolliert. Konfigurations- oder abhängigkeitsbedingte Startfehler werden in `startup-error.log` festgehalten und als Fehlermeldung angezeigt.

<a id="常见问题"></a>

## Häufige Fragen

**Erstellt das Tool isolierte Instanzen oder wechselt Konten?** Nein. Eigene Startskripte und getrennte Benutzerdatenverzeichnisse müssen zuerst vorhanden sein. Anmeldungen, Codex-Konfiguration und Arbeitsbereiche werden nicht geändert.

**Werden meine Arbeitsinstanzen beim Schließen des Managers ebenfalls beendet?** Nein. Das Beenden des Tray-Managers und das Schließen von Codex-Instanzen sind getrennte Aktionen.

**Warum wurde normales Beenden blockiert?** Es wurden Unteraufgaben mit ungeklärtem Zweck gefunden. Prüfe Name, PID und Erstellungszeit, um Updates, Terminals oder andere Arbeit zu erkennen. Nutze Notfallbeenden nicht nur, um die Meldung loszuwerden.

**Das Menü meldet laufenden Hintergrund. Warum gibt es kein Fenster?** Es können nur noch fensterlose Prozesse vorhanden sein, oder Windows hat den Vordergrundwechsel eingeschränkt. Prüfe das Aktionsergebnis. Ein vorhandener Prozess ist nicht gleichbedeutend mit einem verfügbaren Fenster.

**Warum greift meine Konfigurationsänderung noch nicht?** Starte den Manager nach Änderung der lokalen `manager.settings.json` neu. Prüfe Nummern, Versionen und Pfade vorher mit `-ValidateOnly`.

**Kann der Manager Updateskripte automatisch übernehmen und weiter ausführen?** Nein. Derzeit gibt es weder einen unabhängigen Update-Executor noch eine Übernahmeschnittstelle. Siehe [Updateskripte und andere Unteraufgaben](#更新脚本与其他子任务).

<a id="开发者从哪里读起"></a>

## Einstieg für Entwickler

| Datei | Schwerpunkt | Wichtige Prüfungen bei Änderungen |
| --- | --- | --- |
| `CodexTrayManager.ps1` | Tray-Einstieg und Aktionssteuerung | Wiederholte Klicks, Hintergrundwartezeiten, Fehlerrückmeldungen und Menüreaktion. |
| `CodexTrayManager.Core.psm1` | Gemeinsame Verwaltungslogik | Regressionen bei Konfiguration, Zugehörigkeit und Ergebnissen. |
| `CodexTrayManager.Native.cs` / `CodexTrayManager.Process.cs` | Native Windows-Prozess- und Fenstergrenzen | Prozessidentität, Wettläufe beim Beenden und Berechtigungsfehler, nicht nur Erfolgsfälle. |
| `manager.settings.example.json` | Beispielkonfiguration | Fiktive Pfade sowie Unterstützung einzelner Instanzen und mehrerer Versionen. |
| `tests/` | Simulationen, Integration und Leistungsmessungen | Bestandene Simulationen, Prüfungen mit temporären Prozessen und Alltagsbeobachtungen unterscheiden. |

<a id="验证"></a>

## Überprüfung

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

## Härtung des Caches

Cacheeinträge werden bereits vor der Identitätsabfrage entfernt, damit eine teilweise erfolgreiche und anschließend fehlschlagende Abfrage die Bereinigung nicht überspringt. Vor jeder Wiederverwendung des Hintergrundthreads werden Diagnosekanäle wie Fehler und Warnungen geleert. Das Hauptprotokoll behält die aktuelle und eine rotierte Datei. Auch das Startfehlerprotokoll rotiert oberhalb von 256 KB und behält nur eine Vorgängerdatei. Der letzte Eintrag darf den Schwellenwert geringfügig überschreiten.

In einem Regressionstest mit 1000 aufeinanderfolgenden Teilfehlern und wechselnden Prozessidentitäten sammelte die alte Logik 1000 Einträge. Die neue behält höchstens 1 aktuellen Eintrag und nach dem Ende aller Prozesse 0.

<a id="安全边界"></a>

## Sicherheitsgrenzen

Normales Beenden wird bei Unteraufgaben mit ungeklärtem Zweck blockiert. „Notfallbeenden“ im Menü unterbricht nach zweiter Bestätigung alle gefundenen Aufgaben im Baum dieser Instanz. Verwende es nur, wenn Updates, Terminals oder andere Arbeit ausdrücklich abgebrochen werden sollen.

<a id="一起改进"></a>

## Mitwirken

Gezielte Dokumentationskorrekturen, Fehlerreproduktionen und Regressionstests sind willkommen. Auch ohne Kenntnis des gesamten Projekts kannst du bei einem konkreten Szenario beginnen:

- Meldungen zu Konfigurationsfehlern, Startzeitüberschreitungen oder fehlgeschlagenem Fensterwechsel verbessern.
- Regressionstests für PID-Wiederverwendung, verborgene Fenster, unbekannte Unteraufgaben und ähnliche Fälle ergänzen.
- Ergebnisse unter verschiedenen Windows-Umgebungen prüfen und Versionen sowie Reproduktionsschritte festhalten.
- Schnellstart und Diagnose leichter nachvollziehbar machen.

Lies zuerst „Überprüfung“ und „Sicherheitsgrenzen“. Bei Prozesszugehörigkeit oder Beendigungslogik haben Simulationen und temporäre Prozesse Vorrang; bearbeite nicht standardmäßig alltägliche Arbeitsinstanzen. Beschreibe im PR das Problem, die Änderungen, tatsächlich ausgeführte Prüfungen und noch ungeprüfte Fälle. Besprich größere Verhaltensänderungen zunächst unter [Issues](https://github.com/son-gladyso/codex-tray-manager/issues).

Reiche keine echten Konfigurationen, Kontodaten, vollständigen Befehlszeilen oder Diagnosebilder mit privaten Pfaden ein. Fehler dürfen nicht durch abgeschwächte Identitätsprüfungen, übersprungene Bestätigungen oder erzwungenes Beenden unbekannter Aufgaben „behoben“ werden.

<a id="许可证"></a>

## Lizenz

Das Projekt verwendet die [MIT License](../../LICENSE). Nutzung, Kopieren, Ändern, Zusammenführen, Veröffentlichen und Verteilen sind erlaubt, sofern die ursprünglichen Urheberrechts- und Genehmigungshinweise erhalten bleiben. Die Software wird ohne jegliche Gewährleistung „wie besehen“ bereitgestellt.
