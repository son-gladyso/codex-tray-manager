# Codex Tray Manager

[简体中文](../../README.md) · [English](README.en.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Español](README.es.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · [Português (Brasil)](README.pt-BR.md)

**Plusieurs instances de Codex, un seul accès dans la zone de notification. Retrouvez la fenêtre, identifiez ce qui tourne en arrière-plan, puis choisissez comment fermer.**

Destiné aux utilisateurs qui emploient déjà des scripts de lancement isolé sous Windows, Codex Tray Manager rassemble lancement, changement de fenêtre, redémarrage et fermeture pour limiter les allers-retours entre barre des tâches, scripts et Gestionnaire des tâches. Il gère des instances existantes ; il ne crée pas de comptes, ne migre pas les conversations et ne construit pas votre environnement isolé.

> Cet outil communautaire non officiel n'est ni affilié à OpenAI ni approuvé par OpenAI.

Il nécessite Windows 10/11, PowerShell 7 et au moins un script PowerShell capable de lancer une instance isolée de Codex. Le gestionnaire identifie l'appartenance des processus grâce à l'argument `--user-data-dir`, unique à chaque instance.

[Démarrage rapide](#快速开始) · [Déroulement](#先看一个典型使用流程) · [Questions fréquentes](#常见问题) · [Vérification](#验证) · [Contribuer](#一起改进)

<a id="它解决什么问题"></a>

## Les problèmes traités

Quand plusieurs instances isolées de Codex Desktop tournent sur un même PC Windows, il faut souvent passer de la barre des tâches au Gestionnaire des tâches et à plusieurs scripts de lancement. Les fenêtres masquées sont difficiles à retrouver ; une fermeture normale peut ne fermer que la fenêtre en laissant des processus en arrière-plan. À l'inverse, terminer tout l'arbre des processus risque d'arrêter accidentellement des scripts de mise à jour qui attendent la sortie de l'application, des terminaux ou d'autres tâches.

Codex Tray Manager fournit un accès unique dans la zone de notification et distingue « les processus d'arrière-plan propres à l'application » des « tâches enfants dont le rôle n'est pas confirmé ». Il répond principalement aux difficultés suivantes :

- L'absence d'un état d'exécution et de commandes centralisés pour plusieurs instances de Codex.
- La difficulté à localiser les fenêtres masquées ou les processus sans fenêtre et à retrouver le premier plan.
- La persistance possible d'Electron, d'app-server et d'autres processus après une sortie normale.
- L'interruption de mises à jour, de terminaux ou de travaux en cours lors d'une terminaison brutale de l'arbre.
- La difficulté à restaurer la combinaison de versions précédemment exécutée lors du redémarrage d'instances multiversions.

<a id="功能概览"></a>

## Fonctionnalités

- Génère dynamiquement les menus d'instances à partir de la configuration JSON et place les instances actives en tête.
- Vérifie que le processus principal reste stable après le lancement au lieu d'annoncer un succès à partir du seul code de retour du script.
- Énumère les fenêtres Electron de premier niveau masquées, tente de les restaurer et de les passer au premier plan, puis vérifie le résultat.
- Demande d'abord une sortie normale de la fenêtre, puis vérifie et nettoie individuellement les processus résiduels dont l'appartenance à l'application est confirmée.
- Associe PID et heure de création à l'identité du processus afin de réduire les erreurs dues à la réutilisation d'un PID.
- Bloque la fermeture normale en présence de tâches enfants de rôle inconnu et affiche nom, PID et heure de création pour inspection.
- Propose une fermeture d'urgence avec seconde confirmation et une fermeture groupée avec bilan par instance.
- Prend en charge `Standard` et `UICanary` et restaure les versions précédemment actives au redémarrage.
- Actualise l'état et attend les fermetures sur des threads d'arrière-plan pour préserver la réactivité du menu.
- Écrit des journaux de diagnostic JSONL à rotation automatique, sans lignes de commande complètes ni identifiants de connexion.

<a id="先看一个典型使用流程"></a>

## Exemple de déroulement

1. Configurez au moins une instance isolée. S'il y en a plusieurs, vérifiez que chacune utilise un répertoire de données utilisateur différent.
2. Consultez les instances actives dans la zone de notification et ramenez la fenêtre souhaitée au premier plan.
3. Avant de quitter, inspectez les processus et les contrôles de fermeture pour distinguer l'arrière-plan de l'application des tâches enfants non confirmées.
4. Utilisez la fermeture normale. Si des tâches non confirmées sont détectées, examinez la cause plutôt que de contourner le contrôle avec la fermeture d'urgence.
5. Consultez les derniers résultats pour vérifier ce qui s'est effectivement terminé.

Cette page ne contient pas encore de capture ni de vidéo du menu sur une machine réelle. Il s'agit d'une description des étapes, pas d'une démonstration déjà enregistrée, ni d'une garantie de validation de tous les scripts et environnements Windows.

<a id="快速开始"></a>

## Démarrage rapide

Préparez trois éléments :

- Windows 10/11 et PowerShell 7 (`pwsh`), et pas seulement l'ancien Windows PowerShell.
- Un script PowerShell existant capable de lancer seul le Codex visé.
- Pour chaque version, le chemin absolu du script et un répertoire de données utilisateur unique. Ne reprenez pas tels quels les chemins d'exemple comme `D:\codex4`.

Si le script de lancement ne fonctionne pas encore, corrigez-le avant de l'intégrer au gestionnaire.

Les utilisateurs peuvent télécharger le ZIP portable Windows dans [Releases](https://github.com/son-gladyso/codex-tray-manager/releases), l'extraire, copier `manager.settings.example.json` vers `manager.settings.json` et renseigner leurs chemins locaux.

Les développeurs peuvent aussi cloner le dépôt :

```powershell
git clone https://github.com/son-gladyso/codex-tray-manager.git
cd codex-tray-manager
Copy-Item manager.settings.example.json manager.settings.json
notepad manager.settings.json
pwsh -NoProfile -File .\CodexTrayManager.ps1 -ValidateOnly
```

Après validation, double-cliquez sur `Start Codex Tray Manager.cmd`. Quitter le gestionnaire ne ferme pas Codex.

**Premier critère de réussite :** le menu affiche les instances configurées et, après actualisation, distingue celles qui sont actives de celles qui sont arrêtées. Essayez « Passer au premier plan » sur une instance de test active et visible, puis vérifiez le résultat. Une configuration validée ne signifie pas que le changement de fenêtre ou la fermeture ont été validés sur une machine réelle. Familiarisez-vous avec les contrôles et les messages de résultat avant d'essayer de fermer.

<a id="日常操作"></a>

## Utilisation quotidienne

- Gère ensemble les instances Codex configurées (numéros 4–25), en plaçant les actives en tête.
- Regroupe les versions normale et pilote UI d'une même instance. La fermeture traite les deux ; le redémarrage restaure les versions précédentes ; si aucune ne tourne, la version normale démarre par défaut.
- « Lancer / Passer au premier plan » : vérifie le processus principal après lancement. Si une fenêtre existe, tente de la restaurer et contrôle le premier plan. Signale fidèlement la présence de processus sans fenêtre.
- « Fermer (arrière-plan de l'application inclus) » : demande une sortie normale, attend au maximum 3 secondes, puis termine un à un les processus résiduels après vérification de leur identité.
- « Voir les processus et contrôles de fermeture » : affiche nom, PID et heure de création des processus de l'application et des tâches enfants à examiner.
- « Fermeture d'urgence (interrompre toutes les tâches enfants) » : après seconde confirmation, termine toutes les tâches découvertes dont l'identité peut être vérifiée, y compris les scripts de mise à jour. À utiliser uniquement pour les interrompre délibérément.
- « Fermer tous les Codex » : récapitule les résultats par instance ; un échec n'empêche pas le traitement des suivantes. Les détails sont dans « Voir les derniers résultats d'opérations ».

<a id="更新脚本与其他子任务"></a>

## Scripts de mise à jour et autres tâches enfants

Si une fermeture normale ou un redémarrage rencontre des tâches enfants dont le rôle ne peut être confirmé, l'opération est bloquée avant l'envoi de la demande de fermeture et leurs PID sont listés. Scripts de mise à jour, terminaux et services MCP ne sont pas automatiquement de l'arrière-plan applicatif du seul fait de leur lien parent-enfant. Les processus actuellement reconnus comprennent Electron dans le même répertoire d'application, app-server lancé directement par Electron et code-mode host dans le même répertoire. Les autres doivent être examinés ; la présence de update ou powershell dans le nom ne suffit pas à déduire leur rôle.

**Cette version n'implémente ni exécuteur de mise à jour indépendant ni interface de reprise automatique.** Bloquer n'est pas reprendre l'exécution, et ne garantit pas qu'un script pourra continuer après la sortie de l'application. Les scripts détachés de l'arbre de l'instance ne peuvent pas être identifiés automatiquement ; ne cliquez pas sur redémarrer avant la fin de ces mises à jour. Vérifiez d'abord le script précis et sa méthode d'exécution pour éviter que les anciens et nouveaux scripts mettent à jour simultanément. La fermeture d'urgence interrompt explicitement les tâches encore dans l'arbre.

<a id="更快的刷新与更稳妥的关闭"></a>

## Actualisation plus rapide et fermeture plus sûre

- Des instantanés Windows natifs donnent les relations entre processus et les heures de création ; les arguments de lancement ne sont interrogés qu'à la découverte d'une nouvelle identité applicative.
- Le cache des arguments utilise PID + heure de création et est nettoyé à la sortie du processus ; un PID parent réutilisé n'hérite pas d'une ancienne appartenance.
- Des index partagés des processus, relations parent-enfant et répertoires utilisateur sont créés ; une actualisation d'état courante n'énumère pas les fenêtres.
- Requêtes de fenêtres, actualisations de processus, attentes de fermeture et vérifications de lancement utilisent des threads distincts ; l'interface n'attend plus de façon synchrone.
- Par défaut, l'actualisation a lieu toutes les 10 secondes menu fermé et toutes les 2 secondes menu ouvert, ainsi qu'à l'ouverture, à l'actualisation manuelle et à la fin d'une opération.
- Les handles des processus vérifiés sont conservés pendant la fermeture pour suivre l'arrière-plan devenu orphelin après la sortie du principal ; toutes les cibles connues sont vérifiées à la fin.
- `taskkill /T` n'est plus appelé. Chaque terminaison forcée vérifie l'heure de création puis termine le processus sur le même handle.
- Les actions en double sont désactivées pendant une opération ; erreurs de permission, fermetures incomplètes, délais de lancement dépassés et échecs de premier plan sont signalés.
- L'absence d'un script n'empêche pas tout le gestionnaire de démarrer. Le lancement de la version concernée affiche néanmoins une erreur précise.

Les instantanés ont une limite temporelle. L'appartenance d'un processus déjà orphelin avant le lancement du gestionnaire et sans marqueur de configuration ne peut pas être prouvée automatiquement. L'appartenance observée ne vaut que pour la session actuelle, sans déduction d'un redémarrage du gestionnaire à l'autre. Windows peut aussi limiter la prise du premier plan ; un échec est donc signalé, pas présenté comme une réussite.

<a id="配置与诊断"></a>

## Configuration et diagnostic

Copiez `manager.settings.example.json` vers `manager.settings.json`, puis renseignez répertoires d'instances, scripts/répertoires de données par version, icônes, intervalles d'actualisation et délais de lancement. Git ignore le chemin local par défaut ; inspectez malgré tout l'index avant un commit pour éviter de publier une configuration privée déjà suivie, ajoutée de force ou enregistrée ailleurs. Configurez au moins une instance ; redémarrez le gestionnaire pour appliquer les changements. La validation contrôle numéros, versions, chemins absolus et répertoires dupliqués. Le gestionnaire ne modifie ni scripts de lancement, ni archives applicatives, ni connexions, ni configuration Codex, ni espaces de travail.

« Ouvrir les journaux de diagnostic » ouvre `logs`. `manager.jsonl` stocke résultats, erreurs et durées et devient `manager.previous.jsonl` au-delà de 2 MB. Les journaux ne contiennent pas de lignes de commande complètes ni d'identifiants de connexion. Les échecs de démarrage dus à la configuration ou aux dépendances sont consignés dans `startup-error.log` et accompagnés d'un message d'erreur.

<a id="常见问题"></a>

## Questions fréquentes

**Peut-il créer des instances isolées ou changer de compte ?** Non. Préparez d'abord vos scripts et des répertoires de données utilisateur séparés. Le gestionnaire ne modifie pas les connexions, la configuration Codex ou les espaces de travail.

**Quitter le gestionnaire ferme-t-il mes instances de travail ?** Non. Quitter le gestionnaire de notification et fermer les instances Codex sont deux opérations distinctes.

**Pourquoi la fermeture normale est-elle bloquée ?** Des tâches enfants de rôle non confirmé ont été trouvées. Inspectez nom, PID et heure de création pour déterminer s'il s'agit de mises à jour, de terminaux ou d'autres travaux ; n'utilisez pas la fermeture d'urgence simplement pour supprimer l'alerte.

**Le menu indique une activité en arrière-plan, pourquoi aucune fenêtre ?** Il ne reste peut-être que des processus sans fenêtre, ou Windows a limité le passage au premier plan. Consultez le résultat : l'existence d'un processus ne garantit pas une fenêtre disponible.

**Pourquoi ma configuration modifiée n'est-elle pas appliquée ?** Redémarrez le gestionnaire après modification du fichier local `manager.settings.json`. Vérifiez d'abord numéros, versions et chemins avec `-ValidateOnly`.

**Le gestionnaire peut-il reprendre automatiquement les scripts de mise à jour ?** Non. Il n'existe actuellement ni exécuteur indépendant ni interface de reprise. Voir [Scripts de mise à jour et autres tâches enfants](#更新脚本与其他子任务).

<a id="开发者从哪里读起"></a>

## Par où commencer pour développer

| Fichier | Sujet | Points à vérifier lors des modifications |
| --- | --- | --- |
| `CodexTrayManager.ps1` | Entrée de notification et orchestration | Clics répétés, attentes de fond, retours d'erreur et réactivité du menu. |
| `CodexTrayManager.Core.psm1` | Logique de gestion partagée | Régressions de configuration, d'appartenance et de résultats. |
| `CodexTrayManager.Native.cs` / `CodexTrayManager.Process.cs` | Limites natives Windows des processus et fenêtres | Identité, courses à la sortie et refus de permission, pas uniquement le cas nominal. |
| `manager.settings.example.json` | Exemple de configuration | Chemins fictifs, compatibilité mono-instance et multiversion. |
| `tests/` | Simulations, intégration et mesures de performance | Distinguer simulations réussies, vérifications sur processus temporaires et observations quotidiennes. |

<a id="验证"></a>

## Vérification

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

## Renforcement du cache

L'éviction du cache intervient avant la requête d'identité pour éviter de sauter le nettoyage lorsqu'une requête réussit partiellement puis échoue. Les flux de diagnostic, notamment erreurs et avertissements, sont vidés avant chaque réutilisation du thread de fond. Le journal principal conserve le fichier actuel et un fichier de rotation ; le journal des erreurs de démarrage tourne aussi au-delà de 256 KB et ne conserve qu'un prédécesseur. La dernière entrée peut légèrement dépasser le seuil.

Dans un scénario de régression de 1000 échecs partiels consécutifs avec changements d'identité de processus, l'ancienne logique accumulait 1000 entrées ; la nouvelle conserve au maximum 1 entrée courante, puis 0 après la sortie de tous les processus.

<a id="安全边界"></a>

## Limites de sécurité

La fermeture normale est bloquée si des tâches enfants ont un rôle non confirmé. Après seconde confirmation, « Fermeture d'urgence » interrompt toutes les tâches découvertes dans l'arbre de cette instance. Ne l'utilisez que si vous souhaitez expressément interrompre mises à jour, terminaux ou autres travaux.

<a id="一起改进"></a>

## Contribuer

Les corrections documentaires ciblées, reproductions de problèmes et tests de régression sont les bienvenus. Sans connaître tout le projet, vous pouvez commencer par un cas précis :

- Améliorer les messages d'erreur de configuration, de délai de lancement ou d'échec de changement de fenêtre.
- Ajouter des régressions pour PID réutilisés, fenêtres masquées, tâches enfants inconnues, etc.
- Vérifier les résultats sous différents environnements Windows et préciser versions et étapes de reproduction.
- Rendre le démarrage rapide et le diagnostic plus faciles à suivre.

Lisez d'abord « Vérification » et « Limites de sécurité ». Pour l'appartenance des processus ou la logique de fermeture, privilégiez simulations et processus temporaires, sans cibler par défaut les instances de travail quotidien. Dans une PR, décrivez problème, modifications, contrôles réellement exécutés et points encore non vérifiés. Discutez les changements de comportement importants dans [Issues](https://github.com/son-gladyso/codex-tray-manager/issues) au préalable.

Ne soumettez pas de configurations réelles, de données de compte, de lignes de commande complètes ni de captures de diagnostic contenant des chemins privés. Ne « corrigez » pas un échec en affaiblissant l'identification, en omettant les confirmations ou en terminant de force des tâches inconnues.

<a id="许可证"></a>

## Licence

Ce projet est sous [MIT License](../../LICENSE). Vous pouvez l'utiliser, le copier, le modifier, le fusionner, le publier et le distribuer en conservant les mentions originales de droits d'auteur et d'autorisation. Le logiciel est fourni « en l'état », sans aucune garantie.
