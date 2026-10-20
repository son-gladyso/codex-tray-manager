# Codex Tray Manager

[简体中文](../../README.md) · [English](README.en.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Español](README.es.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · [Português (Brasil)](README.pt-BR.md)

**Várias instâncias do Codex, um único acesso pela bandeja. Encontre a janela, entenda o que está em segundo plano e decida como encerrar.**

Para quem já usa scripts de inicialização isolada no Windows, o Codex Tray Manager reúne inicialização, troca de janela, reinicialização e encerramento, reduzindo as idas e vindas entre barra de tarefas, scripts e Gerenciador de Tarefas. Ele gerencia instâncias existentes; não cria contas, migra conversas nem monta um ambiente isolado para você.

> Esta é uma ferramenta comunitária não oficial, sem vínculo com a OpenAI nem endosso da OpenAI.

Requer Windows 10/11, PowerShell 7 e um ou mais scripts PowerShell capazes de iniciar instâncias isoladas do Codex. O gerenciador identifica a qual instância cada processo pertence pelo argumento `--user-data-dir`, exclusivo de cada instância.

[Início rápido](#快速开始) · [Fluxo de uso](#先看一个典型使用流程) · [Perguntas frequentes](#常见问题) · [Verificação](#验证) · [Como contribuir](#一起改进)

<a id="它解决什么问题"></a>

## Quais problemas ele resolve

Quando várias instâncias isoladas do Codex para desktop rodam no mesmo computador Windows, é comum alternar entre barra de tarefas, Gerenciador de Tarefas e vários scripts de inicialização. Janelas ocultas são difíceis de encontrar; um encerramento normal pode fechar apenas a janela e deixar processos em segundo plano. Por outro lado, encerrar toda a árvore de processos pode interromper acidentalmente scripts de atualização que aguardam a saída do aplicativo, terminais ou outras tarefas.

O Codex Tray Manager oferece um acesso centralizado na bandeja e trata separadamente “processos em segundo plano do próprio aplicativo” e “tarefas filhas cuja finalidade não foi confirmada”. Os principais problemas atendidos são:

- Falta de uma visão de estado e de controles unificados para várias instâncias do Codex.
- Dificuldade para localizar janelas ocultas ou processos sem janela e voltar ao primeiro plano.
- Processos de Electron, app-server e outros que podem permanecer após uma saída normal.
- Atualizações, terminais e trabalho em andamento interrompidos pelo encerramento indiscriminado da árvore.
- Dificuldade para recuperar a combinação de versões que estava em execução ao reiniciar instâncias com várias versões.

<a id="功能概览"></a>

## Visão geral dos recursos

- Gera menus de instâncias dinamicamente a partir da configuração JSON e coloca automaticamente as instâncias em execução no topo.
- Verifica se o processo principal está estável após a inicialização, sem declarar sucesso apenas pelo retorno do script.
- Enumera janelas de nível superior do Electron que estão ocultas, tenta restaurá-las e trazê-las para a frente e confere o resultado.
- Primeiro solicita a saída normal da janela, depois verifica e limpa individualmente os processos restantes confirmados como pertencentes ao aplicativo.
- Vincula a identidade do processo ao PID e ao horário de criação para reduzir erros causados pela reutilização de PID.
- Bloqueia o encerramento normal quando encontra tarefas filhas de finalidade desconhecida e mostra nome, PID e horário de criação para inspeção.
- Oferece encerramento de emergência com uma segunda confirmação e encerramento em lote com resultados por instância.
- Aceita as versões `Standard` e `UICanary` e restaura as versões anteriormente em execução ao reiniciar.
- Atualiza estados e aguarda encerramentos em threads de segundo plano para manter o menu responsivo.
- Grava logs de diagnóstico JSONL com rotação automática, sem registrar linhas de comando completas nem credenciais de acesso.

<a id="先看一个典型使用流程"></a>

## Um fluxo de uso típico

1. Configure pelo menos uma instância isolada. Se houver várias, confirme que cada uma usa um diretório de dados de usuário diferente.
2. Veja na bandeja quais instâncias estão em execução e traga a janela necessária para a frente.
3. Antes de sair, examine os processos e as verificações de encerramento para diferenciar o segundo plano do aplicativo das tarefas filhas não confirmadas.
4. Use o encerramento normal. Se forem encontradas tarefas não confirmadas, investigue primeiro em vez de contornar a verificação com o encerramento de emergência.
5. Consulte os resultados recentes para confirmar o que realmente foi concluído.

Esta página ainda não inclui capturas de tela nem vídeos do menu da bandeja em uma máquina real. O texto acima descreve uma sequência de uso, não uma demonstração já gravada, e não significa que todos os scripts e ambientes Windows foram verificados.

<a id="快速开始"></a>

## Início rápido

Prepare três requisitos:

- Windows 10/11 e PowerShell 7 (`pwsh`), não apenas o antigo Windows PowerShell.
- Um script PowerShell existente capaz de iniciar o Codex desejado de forma independente.
- Caminhos absolutos dos scripts e diretórios de dados exclusivos para cada versão. Não copie sem alterações caminhos de exemplo como `D:\codex4`.

Se o script de inicialização ainda não funciona corretamente, resolva isso antes de integrá-lo ao gerenciador.

Usuários podem baixar o ZIP portátil para Windows em [Releases](https://github.com/son-gladyso/codex-tray-manager/releases), extrair, copiar `manager.settings.example.json` para `manager.settings.json` e preencher os caminhos locais.

Desenvolvedores também podem clonar o repositório:

```powershell
git clone https://github.com/son-gladyso/codex-tray-manager.git
cd codex-tray-manager
Copy-Item manager.settings.example.json manager.settings.json
notepad manager.settings.json
pwsh -NoProfile -File .\CodexTrayManager.ps1 -ValidateOnly
```

Depois que a validação passar, clique duas vezes em `Start Codex Tray Manager.cmd`. Sair do gerenciador não encerra o Codex.

**Critério para o primeiro sucesso:** o menu mostra as instâncias configuradas e distingue as que estão em execução das paradas após atualizar o estado. Teste “Trazer para a frente” em uma instância de teste em execução e visível, depois confira o resultado. Passar na validação de configuração não significa que a troca de janela ou o encerramento passaram por testes de aceitação em uma máquina real. Familiarize-se com as verificações e mensagens de resultado antes de tentar encerrar.

<a id="日常操作"></a>

## Operações do dia a dia

- Gerencia em conjunto as instâncias configuradas do Codex (números 4–25), com as que estão em execução no topo.
- Pode reunir a versão normal e a versão piloto de UI da mesma instância. O encerramento trata ambas; a reinicialização restaura as versões anteriores; se nenhuma estiver rodando, inicia a normal por padrão.
- “Iniciar / Trazer para a frente”: verifica o processo principal após iniciar. Se já existe uma janela, tenta restaurá-la e verifica o primeiro plano. Informa corretamente quando há segundo plano, mas nenhuma janela.
- “Encerrar (incluindo o segundo plano do aplicativo)”: solicita uma saída normal, aguarda até 3 segundos e encerra os processos restantes um a um, após verificar suas identidades.
- “Ver processos e verificações de encerramento”: mostra nome, PID e horário de criação dos processos do aplicativo e das tarefas filhas que precisam de análise.
- “Encerramento de emergência (interromper todas as tarefas filhas)”: após uma segunda confirmação, encerra todas as tarefas descobertas cujas identidades podem ser verificadas, incluindo scripts de atualização. Use apenas quando realmente quiser interrompê-las.
- “Encerrar todos os Codex”: resume os resultados por instância; uma falha não impede o processamento das seguintes. Consulte os detalhes em “Ver resultados de operações recentes”.

<a id="更新脚本与其他子任务"></a>

## Scripts de atualização e outras tarefas filhas

Se o encerramento normal ou a reinicialização encontrar tarefas filhas cuja finalidade não pode ser confirmada, bloqueia a operação antes de enviar a solicitação de encerramento e lista os PIDs. Scripts de atualização, terminais e serviços MCP não podem ser considerados segundo plano do aplicativo apenas pela relação pai-filho. Atualmente, são confirmados os processos Electron no mesmo diretório do aplicativo, app-server iniciado diretamente pelo Electron e code-mode host no mesmo diretório. Os demais exigem análise; nomes contendo update ou powershell não comprovam a finalidade.

**Esta versão não implementa um executor independente de atualizações nem uma interface de transferência automática.** Bloquear não é assumir a execução e não garante que um script continue após a saída do aplicativo. Scripts de atualização que saíram da árvore da instância não podem ser identificados automaticamente pelo gerenciador; não clique em reiniciar antes de essas atualizações terminarem. Confira o script específico e sua forma de execução para evitar que scripts antigos e novos atualizem ao mesmo tempo. O encerramento de emergência interrompe explicitamente tarefas que ainda estão na árvore.

<a id="更快的刷新与更稳妥的关闭"></a>

## Atualizações de estado mais rápidas e encerramento mais seguro

- Usa snapshots nativos do Windows para obter relações entre processos e horários de criação; consulta argumentos de inicialização apenas ao descobrir uma nova identidade de aplicativo.
- O cache de argumentos usa PID + horário de criação como chave e é limpo quando o processo sai; a reutilização do PID pai não herda uma associação antiga.
- Cria índices compartilhados de processos, relações pai-filho e diretórios de usuário; atualizações rotineiras de estado não enumeram janelas.
- Consultas de janelas, atualizações de processos, esperas de encerramento e verificações de início rodam em threads de trabalho separadas; a interface não espera de forma síncrona.
- Por padrão, atualiza a cada 10 segundos com o menu fechado e a cada 2 segundos com ele aberto; também atualiza prontamente ao abrir o menu, clicar em atualizar e concluir uma operação.
- Mantém handles de processos verificados durante o encerramento para rastrear processos de fundo que ficam órfãos após a saída do principal; verifica todos os alvos conhecidos no final.
- Não chama mais `taskkill /T`. Toda finalização forçada verifica o horário de criação e encerra usando o mesmo handle de processo.
- Desativa ações duplicadas durante uma operação e informa erros de permissão, encerramentos incompletos, tempo de inicialização esgotado e falhas ao trazer para a frente.
- A falta de um script não impede que todo o gerenciador inicie. A tentativa de iniciar a versão afetada ainda apresenta um erro específico.

Snapshots de processos têm limites temporais. Não é possível comprovar automaticamente a associação de processos já órfãos antes de o gerenciador iniciar e sem marcadores de configuração. As associações observadas são mantidas apenas na sessão atual e não são inferidas entre reinicializações do gerenciador. O Windows também pode limitar a ativação em primeiro plano; por isso, a falha é informada em vez de ser anunciada como sucesso.

<a id="配置与诊断"></a>

## Configuração e diagnóstico

Copie `manager.settings.example.json` para `manager.settings.json` e preencha diretórios de instâncias, scripts/diretórios de dados por versão, ícones, intervalos de atualização e tempos limite de inicialização. O Git ignora o caminho local padrão, mas revise a área de staging antes do commit para não publicar configurações privadas já rastreadas, adicionadas à força ou salvas em outro lugar. Configure pelo menos uma instância e reinicie o gerenciador para aplicar mudanças. A validação verifica números, versões, caminhos absolutos e diretórios duplicados. O gerenciador não modifica scripts, arquivos do aplicativo, logins, configuração do Codex nem espaços de trabalho.

“Abrir logs de diagnóstico” abre `logs`. `manager.jsonl` guarda resultados, erros e durações e faz rotação para `manager.previous.jsonl` ao superar 2 MB. Os logs não registram linhas de comando completas nem credenciais. Falhas de inicialização por configuração ou dependências são registradas em `startup-error.log` e exibidas em uma mensagem de erro.

<a id="常见问题"></a>

## Perguntas frequentes

**Ele cria instâncias isoladas ou troca contas para mim?** Não. Prepare seus próprios scripts e diretórios de dados de usuário separados. O gerenciador não modifica logins, configuração do Codex nem espaços de trabalho.

**Sair do gerenciador também encerra minhas instâncias de trabalho?** Não. Sair do gerenciador da bandeja e encerrar instâncias do Codex são operações diferentes.

**Por que o encerramento normal foi bloqueado?** Foram encontradas tarefas filhas de finalidade não confirmada. Confira nome, PID e horário de criação para saber se são atualizações, terminais ou outro trabalho. Não use o encerramento de emergência só para eliminar o aviso.

**O menu indica execução em segundo plano. Por que não encontro a janela?** Talvez restem apenas processos sem janela, ou o Windows tenha limitado a ativação em primeiro plano. Consulte o resultado: a existência de um processo não equivale a uma janela disponível.

**Por que minha alteração de configuração não entrou em vigor?** Reinicie o gerenciador depois de alterar o `manager.settings.json` local. Antes, confira números, versões e caminhos com `-ValidateOnly`.

**Scripts de atualização podem ser transferidos automaticamente ao gerenciador para continuar executando?** Não. Atualmente não existe executor independente nem interface de transferência. Consulte [Scripts de atualização e outras tarefas filhas](#更新脚本与其他子任务).

<a id="开发者从哪里读起"></a>

## Por onde começar como desenvolvedor

| Arquivo | Foco | Principais verificações ao alterar |
| --- | --- | --- |
| `CodexTrayManager.ps1` | Entrada da bandeja e organização das operações | Cliques repetidos, esperas de fundo, avisos de erro e resposta do menu. |
| `CodexTrayManager.Core.psm1` | Lógica de gerenciamento compartilhada | Regressões de configuração, associação e resultados. |
| `CodexTrayManager.Native.cs` / `CodexTrayManager.Process.cs` | Limites nativos de processos e janelas no Windows | Identidade, condições de corrida na saída e falhas de permissão, não apenas o caminho de sucesso. |
| `manager.settings.example.json` | Exemplo de configuração | Caminhos fictícios e compatibilidade com instância única e várias versões. |
| `tests/` | Simulações, integração e amostragem de desempenho | Distinguir simulações aprovadas, verificações com processos temporários e observações do uso diário. |

<a id="验证"></a>

## Verificação

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

## Reforço do cache

A remoção de entradas agora acontece antes da consulta de identidade, para que a limpeza não seja ignorada se a consulta tiver sucesso parcial e depois lançar um erro. Fluxos de diagnóstico, como erros e avisos, são limpos antes de reutilizar a thread de fundo a cada ciclo. O log principal mantém o arquivo atual e um arquivo rotacionado; o log de erros de inicialização também gira acima de 256 KB e mantém só um arquivo anterior. O último registro pode ultrapassar um pouco o limite.

Em um cenário de regressão com 1000 falhas parciais consecutivas e mudanças de identidade de processos, a lógica antiga acumulava 1000 entradas. A nova mantém no máximo 1 entrada atual e 0 depois que todos os processos saem.

<a id="安全边界"></a>

## Limites de segurança

O encerramento normal é bloqueado quando encontra tarefas filhas de finalidade não confirmada. Após uma segunda confirmação, o “Encerramento de emergência” interrompe todas as tarefas descobertas na árvore daquela instância. Use somente quando precisar explicitamente interromper atualizações, terminais ou outro trabalho.

<a id="一起改进"></a>

## Como contribuir

Correções pontuais de documentação, reproduções de problemas e testes de regressão são bem-vindos. Você pode começar por um cenário específico sem conhecer o projeto inteiro:

- Melhorar mensagens de configuração incorreta, tempo de inicialização esgotado ou falha de troca de janela.
- Acrescentar testes de reutilização de PID, janelas ocultas, tarefas filhas desconhecidas e casos semelhantes.
- Conferir resultados em diferentes ambientes Windows e detalhar versões e etapas de reprodução.
- Tornar o início rápido e o diagnóstico mais fáceis de acompanhar.

Leia primeiro “Verificação” e “Limites de segurança”. Em mudanças de associação de processos ou lógica de encerramento, priorize simulações e processos temporários, sem atuar por padrão em instâncias de trabalho cotidiano. No PR, explique o problema, as mudanças, as verificações realmente executadas e o que ainda não foi verificado. Discuta mudanças maiores de comportamento primeiro em [Issues](https://github.com/son-gladyso/codex-tray-manager/issues).

Não envie configurações reais, dados de contas, linhas de comando completas nem capturas de diagnóstico com caminhos privados. Não “corrija” falhas enfraquecendo a verificação de identidade, pulando confirmações ou encerrando à força tarefas desconhecidas.

<a id="许可证"></a>

## Licença

Este projeto usa a [MIT License](../../LICENSE). Você pode usar, copiar, modificar, mesclar, publicar e distribuir o projeto, desde que mantenha os avisos originais de direitos autorais e permissão. O software é fornecido “no estado em que se encontra”, sem garantia de qualquer tipo.
