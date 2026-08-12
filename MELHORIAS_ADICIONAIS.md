# Análise de Melhorias Adicionais - Multi Migrador

> **v2** — revisado em 2026-08-12: status de cada item conferido contra o
> código atual (3 das 5 de ALTA prioridade já foram implementadas desde a
> versão anterior deste documento, mas não estavam marcadas). Adicionada a
> seção [Processo Padrão](#-processo-padrão-de-release-e-novo-migrador), que
> documenta o fluxo que já vem sendo seguido nos commits (bump de versão,
> `gerar_recursos.bat`, estrutura de pasta de migrador) para ele parar de
> viver só na cabeça de quem commitou e virar checklist.

## 🔍 Melhorias Identificadas (Além das 11 Já Implementadas)

---

## **ALTA PRIORIDADE** 🔴

### ✅ **1. Sistema de Cache de Versão** — IMPLEMENTADO
**Arquivo**: `UAtualizador.pas` (bloco de `TRegistry`, comentário "cache ainda válido (< 24 horas)")
**Status**: timestamp da última checagem é gravado no Registry e a consulta ao GitHub só é refeita depois de 24h.

---

### ✅ **2. Validação de Integridade do Download** — IMPLEMENTADO
**Arquivo**: `UAtualizador.pas` - `CalcularSHA256Arquivo` + validação em `BaixarEInstalar`
**Status**: o SHA256 do exe baixado é conferido contra o valor informado no release; falha de hash aborta a instalação sem tocar no exe atual.

---

### **3. Gerenciador de Múltiplas Instâncias**
**Arquivo**: `MultiMigrador.dpr`
**Problema**: Pode abrir múltiplas instâncias do launcher
**Impacto**: Confusão do usuário, consumo de memória
**Solução Proposta**:
```
- Implementar mutex ou named pipe
- Se já está aberto, trazer janela para frente
- Evitar múltiplas instâncias
```

---

### ✅ **4. Sistema de Relatório de Crash** — IMPLEMENTADO
**Arquivo**: `UCrash.pas`
**Status**: `Application.OnException` captura exceções não tratadas, salva log em `%TEMP%\MultiMigrador_Crash_*.log` e orienta o usuário a usar "Reportar Problema".

---

### **5. Verificação de Espaço em Disco**
**Arquivo**: `UMigradores.pas` - função `ExtrairMigradores`
**Problema**: Não verifica se há espaço livre antes de extrair
**Impacto**: Extração interrompida, estado inconsistente
**Solução Proposta**:
```
- Verificar espaço livre antes de extrair
- Se < 100MB, avisar e cancelar
- Evita corrupção de arquivos
```

---

---

## **MÉDIA PRIORIDADE** 🟡

### **6. Limpeza de Arquivos Antigos**
**Arquivo**: `ULogger.pas`
**Problema**: Logs crescem indefinidamente
**Impacto**: Consumo de disco ao longo do tempo
**Solução Proposta**:
```
- Apagar logs com > 30 dias
- Manter apenas últimos 30 dias
- Executar na inicialização ou mensalmente
```

---

### **7. Compressão de Logs Antigos**
**Arquivo**: `ULogger.pas`
**Problema**: Logs ocupam muito espaço
**Impacto**: Lentidão para ler/escrever log grande
**Solução Proposta**:
```
- Compactar logs com > 7 dias em .zip
- Manter última semana descompactada
- Economiza ~80% de espaço
```

---

### **8. Ícone no Notification Center**
**Arquivo**: `UNotificacoes.pas`
**Problema**: Notificações não têm ícone customizado
**Impacto**: Menos profissional, mistura com outras apps
**Solução Proposta**:
```
- Extrair ícone do Multi Migrador
- Usar em notificações Toast
- Deixa mais identificável
```

---

### **9. Detectar Rede Disponível**
**Arquivo**: `UAtualizador.pas`, `UReportarProblema.pas`
**Problema**: Tenta enviar email/download sem verificar conexão
**Impacto**: Erros confusos para usuário offline
**Solução Proposta**:
```
- Verificar conectividade antes de ação
- Mostrar mensagem clara "Sem conexão"
- Implementar retry ao reconectar
```

---

### **10. Otimização de Temas**
**Arquivo**: `UPrincipal.pas`, `UReportarProblema.pas`
**Problema**: Carrega tema a cada inicialização de formulário
**Impacto**: Pequeno overhead, poderia ser singleton
**Solução Proposta**:
```
- Criar UTemaNativo.pas com singleton
- Carregar tema uma única vez
- Compartilhar entre formulários
- Economiza chamadas ao Registry
```

---

### **11. Sistema de Preferências**
**Arquivo**: Criar `UPreferencias.pas`
**Problema**: Sem forma centralizada de guardar configs
**Impacto**: Dados espalhados entre Registry e .ini
**Solução Proposta**:
```
- Criar classe de preferências singleton
- Guardar: tema, tamanho window, último sistema aberto, etc
- Interface única para ler/escrever
```

---

### **12. Tratamento de Timeout na UI**
**Arquivo**: `UReportarProblema.pas`
**Problema**: Se conexão morrer, fica 15 segundos travado
**Impacto**: UI não responsiva
**Solução Proposta**:
```
- Implementar deadline em thread
- Mostrar barra de progresso
- Permitir cancelamento
```

---

---

## **MÉDIA-BAIXA PRIORIDADE** 🟠

### **13. Histórico de Problemas Reportados**
**Arquivo**: Criar `UHistorico.pas`
**Problema**: Sem rastreabilidade dos problemas que enviou
**Impacto**: Usuário não sabe se já reportou
**Solução Proposta**:
```
- Guardar em arquivo JSON cada reporte
- Mostrar histórico em dialog
- Data, sistema, status
```

---

### **14. Validação de Campos Customizada**
**Arquivo**: `UReportarProblema.pas`
**Problema**: Validação básica, sem feedback visual
**Impacto**: Experiência de usuário menor
**Solução Proposta**:
```
- Cor de borda de campo em vermelho se inválido
- Ícone de check/X ao lado
- Validação em tempo real
```

---

### **15. Expandir Filtro**
**Arquivo**: `UPrincipal.pas`
**Problema**: Filtro só busca por nome
**Impacto**: Não consegue filtrar por outra coisa
**Solução Proposta**:
```
- Adicionar checkbox: "Mostrar apenas sem exe"
- Filtrar por data de modificação
- Mostrar cards com exe destacado
```

---

### **16. Modo Silencioso**
**Arquivo**: `MultiMigrador.dpr`
**Problema**: Sem modo silencioso para scripts
**Impacto**: Não dá para automatizar
**Solução Proposta**:
```
- Parâmetro /silent para não abrir UI
- Parâmetro /run:sistema para abrir migrador
- Usar para automação em CI/CD
```

---

### **17. Suporte a Temas Customizáveis**
**Arquivo**: `UPrincipal.pas`
**Problema**: Cores hardcoded, sem configuração
**Impacto**: Não dá customizar cores da empresa
**Solução Proposta**:
```
- Arquivo tema.json com cores
- Opção de tema claro/escuro/customizado
- Salvar preferência do usuário
```

---

### **18. Melhor Formatação de Log**
**Arquivo**: `ULogger.pas`
**Problema**: Formato básico, difícil fazer parse/análise
**Impacto**: Logs não estruturados
**Solução Proposta**:
```
- Opção de formato JSON
- Stack trace em linhas separadas
- Severidade: DEBUG, INFO, WARN, ERROR
```

---

---

## **BAIXA PRIORIDADE** 🟢

### **19. Integração com Gerenciador de Tarefas**
**Arquivo**: Criar `UAgendador.pas`
**Problema**: Sem forma de agendar reporte automático
**Impacto**: Requer ação manual
**Solução Proposta**:
```
- Agenda verificação de atualizações diárias
- Agenda limpeza de logs
- Usar Windows Task Scheduler
```

---

### **20. Tradução Internacionalização (i18n)**
**Arquivo**: Criar `UTraducao.pas`
**Problema**: Tudo em português hardcoded
**Impacto**: Inacessível para empresas internacionais
**Solução Proposta**:
```
- Criar arquivo traduções.json
- Suportar EN, ES, FR, PT
- Detectar idioma do Windows
```

---

### **21. Exportar Log Como ZIP**
**Arquivo**: `UPrincipal.pas`
**Problema**: Difícil compartilhar log com suporte
**Impacto**: Suporte precisa acessar pasta
**Solução Proposta**:
```
- Botão "Exportar Logs"
- Cria ZIP com últimos 7 dias
- Facilita envio
```

---

### **22. Estatísticas de Uso**
**Arquivo**: Criar `UEstatisticas.pas`
**Problema**: Sem dados sobre qual migrador é mais usado
**Impacto**: Não sabe prioridades de desenvolvimento
**Solução Proposta**:
```
- Contar quantas vezes cada exe foi aberto
- Guardar estatísticas diárias
- Dashboard com gráficos
```

---

### **23. Suporte a Proxy**
**Arquivo**: `UAtualizador.pas`, `UReportarProblema.pas`
**Problema**: Sem suporte a proxy corporativo
**Impacto**: Não funciona em rede corporativa
**Solução Proposta**:
```
- Detectar proxy automático
- Permitir configuração manual
- Usar Windows WinHTTP config
```

---

### **24. Verificação de Atualizações em Background**
**Arquivo**: `UAtualizador.pas`
**Problema**: Só verifica na inicialização
**Impacto**: Perde atualização se ficar aberto muito tempo
**Solução Proposta**:
```
- Timer que verifica a cada 12 horas
- Mesmo estando aberto
- Notifica silenciosamente
```

---

---

## 📊 Tabela de Priorização

| # | Melhoria | Prioridade | Esforço | Impacto | Score | Status |
|---|----------|-----------|--------|--------|-------|--------|
| 1 | Cache de Versão | ALTA | Baixo | Alto | 9/10 | ✅ Feito |
| 2 | Validação de Download | ALTA | Médio | Alto | 8/10 | ✅ Feito |
| 3 | Múltiplas Instâncias | ALTA | Médio | Médio | 7/10 | Pendente |
| 4 | Sistema de Crash | ALTA | Alto | Alto | 8/10 | ✅ Feito |
| 5 | Espaço em Disco | ALTA | Baixo | Médio | 7/10 | Pendente |
| 6 | Limpeza de Logs | MÉDIA | Baixo | Médio | 6/10 |
| 7 | Compressão de Logs | MÉDIA | Médio | Baixo | 5/10 |
| 8 | Ícone Notifications | MÉDIA | Baixo | Baixo | 4/10 |
| 9 | Detectar Rede | MÉDIA | Médio | Médio | 7/10 |
| 10 | Otimização de Temas | MÉDIA | Baixo | Baixo | 4/10 |
| 11 | Preferências | MÉDIA | Médio | Médio | 6/10 |
| 12 | Timeout na UI | MÉDIA | Médio | Médio | 6/10 |
| 13 | Histórico de Reportes | MÉDIA-BAIXA | Baixo | Baixo | 4/10 |
| 14 | Validação Visual | MÉDIA-BAIXA | Médio | Médio | 5/10 |
| 15 | Expandir Filtro | MÉDIA-BAIXA | Baixo | Baixo | 3/10 |
| 16 | Modo Silencioso | MÉDIA-BAIXA | Médio | Médio | 5/10 |
| 17 | Temas Customizáveis | MÉDIA-BAIXA | Alto | Baixo | 4/10 |
| 18 | Log Estruturado | MÉDIA-BAIXA | Médio | Médio | 5/10 |
| 19 | Agendador de Tarefas | BAIXA | Médio | Baixo | 3/10 |
| 20 | Internacionalização | BAIXA | Alto | Médio | 4/10 |
| 21 | Exportar Log ZIP | BAIXA | Baixo | Baixo | 2/10 |
| 22 | Estatísticas de Uso | BAIXA | Médio | Baixo | 3/10 |
| 23 | Suporte a Proxy | BAIXA | Alto | Médio | 4/10 |
| 24 | Background Check Updates | BAIXA | Médio | Baixo | 3/10 |

---

## 🎯 Recomendações de Implementação

### **Fase 1 (Próximas Sprints)** - ALTA Prioridade
1. ✅ Cache de Versão — feito (rápido, grande impacto)
2. ✅ Validação de Download — feito (segurança crítica)
3. ✅ Sistema de Crash — feito (fundamental para suporte)
4. ⬜ Espaço em Disco (previne falhas)
5. ⬜ Múltiplas Instâncias (UX)

### **Fase 2 (Sprint Seguinte)** - MÉDIA Prioridade
6. Limpeza de Logs (manutenção)
7. Detectar Rede (melhor feedback)
8. Preferências (persistência)
9. Timeout com feedback (UX)

### **Fase 3 (Backlog)** - MÉDIA-BAIXA e BAIXA
- Resto das melhorias conforme necessidade

---

## 📝 Conclusão

O Multi Migrador já está bem estruturado com as 11 melhorias implementadas.
Das 24 melhorias adicionais listadas aqui, **3 das 5 de ALTA prioridade já
foram implementadas** (Cache de Versão, Validação SHA256 e Sistema de Crash),
restando Múltiplas Instâncias e Espaço em Disco para fechar a Fase 1.

**Tempo estimado para Fase 1 (restante)**: 1-2 dias de desenvolvimento
**Tempo estimado para Fase 2**: 2-3 dias de desenvolvimento
**Tempo estimado para Fase 3**: 1-2 semanas conforme necessidade

---

## 📐 Processo Padrão de Release e Novo Migrador

Documentado aqui porque hoje esse conhecimento só existe espalhado em
comentários de código e nas mensagens de commit — não há uma lista única a
seguir. Convertido em checklist para reduzir o risco de esquecer um passo
(já aconteceu: 4 migradores ficaram fora do pacote por várias releases
porque a lista de pastas era mantida manualmente — resolvido depois trocando
para descoberta automática via `git ls-tree` no `gerar_recursos.bat`).

### Checklist de release (bump de versão)

A versão vive em **3 lugares** que precisam ficar sincronizados — divergência
entre eles não quebra a build, mas o auto-updater (`UAtualizador.pas`) e o
version info do exe passam a reportar números diferentes:

1. `MultiMigrador.dproj` → `VerInfo_Release` (e `VerInfo_Build` se aplicável)
2. `MultiMigrador.dproj` → `VerInfo_Keys` → `FileVersion=` e `ProductVersion=`
3. `UAtualizador.pas` → constante `APP_VERSAO` (comentário no próprio código:
   *"bump a cada release"*)

Ordem de operações, na sequência que os commits recentes seguiram:

1. Commitar as mudanças de código/migrador (o `gerar_recursos.bat` empacota a
   partir de `git archive HEAD` — **arquivo não commitado não entra no
   pacote embutido**, mesmo estando na pasta).
2. Bumpar a versão nos 3 lugares acima.
3. Rodar `gerar_recursos.bat` (regenera `migradores.zip` e
   `DllsEmbutidas.res` a partir do HEAD já commitado).
4. Recompilar (F9 na IDE ou `msbuild`).
5. Publicar um **Release no GitHub** com tag `vX.Y.Z` e o
   `MultiMigrador.exe` compilado como asset — é a única forma de distribuir o
   exe (não é versionado no repo; ver `.gitignore`) e é o que o
   auto-updater consulta em `releases/latest`.
6. Commitar o bump de versão e dar push.

### Estrutura padrão de uma pasta de migrador

Ao adicionar um sistema novo (ex.: commit `66e11ac`, XD SISTEMAS), a pasta
`<NOME DO SISTEMA>/` deve trazer:

| Arquivo | Obrigatório | Observação |
|---|---|---|
| `<Nome>.exe` | Sim | Nome livre — o launcher lista qualquer `*.exe` da pasta (exceto `unins000.exe`); só precisa bater com o `.dproj` se um existir na pasta. |
| `*.png` | Sim | Ícone do card. **Só `.png` é lido** (`UPrincipal.pas`, busca por `*.png`) — logo em `.jpg` fica sem ícone no card. Não commitar `.jpg` "de apoio": é peso morto no pacote. |
| `config.ini` | Se o migrador usa conexão a banco | Preservado na atualização se já existir na máquina do cliente (dado de conexão local não é sobrescrito). |
| DLLs de runtime (`fbclient.dll`, driver do banco de origem, etc.) | Se o exe depende delas | Ficam ao lado do exe, mesmo padrão dos demais migradores. |
| `orientacoes.txt` | Não | Convenção legada — não é mais lida pela UI (`UPrincipal.pas`: *"As orientações deixaram de ser exibidas aqui"*). Não é erro deixar de fora. |

Nomenclatura do `.exe` **não é estritamente padronizada** hoje (mistura
`Migrador<Nome>.exe` e `<Nome>.exe` entre as pastas existentes) — a única
renomeação feita até agora foi pontual (RENSOFTWARE, commit `1aacac1`) para
evitar conflito com o `gerar_recursos.bat`, não uma padronização geral. Não
tratar isso como pendência a menos que cause um conflito real.

### Ajuste aplicado nesta revisão

- Removido `XD SISTEMAS/logo.jpg`: arquivo órfão, sem uso (a UI só lê
  `.png`), deixado no commit `66e11ac` junto com o `.png` equivalente.
