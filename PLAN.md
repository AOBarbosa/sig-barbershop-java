# PLAN — sig-barbershop-java

Planejamento para virar **issues no GitHub**. Cada item `### [ID]` abaixo é uma issue.
Detalhes técnicos (inventário de endpoints, regras, formatos, decisões) estão em [`docs/MIGRATION_PLAN.md`](docs/MIGRATION_PLAN.md); as issues referenciam suas seções (ex.: "MP §4").

## Contexto em 5 linhas
- Migração do backend `api/` do sig-barbershop (FastAPI + MySQL) para **Java 17 puro** (sem frameworks), para a disciplina *Lógica Aplicada à Engenharia de Software*.
- Regras de negócio especificadas com **JML** e verificadas com **OpenJML** (ESC estático + RAC em runtime).
- Prioridade **A**: entrega acadêmica (código anotado + planilha + slides + demo ao vivo da verificação) — apresentação em **07 ou 09/12/2026**.
- Prioridade **B**: paridade com a API original (73 rotas, frontend Next.js original **sem alterações**) com MySQL real.
- A entrega A não depende de B: o pacote é produzido antes do adaptador MySQL.

## Equipe e divisão sugerida
| Pessoa | Foco principal |
|---|---|
| **André** | infraestrutura, HTTP/JSON/JWT, autenticação/pessoas, agenda/atendimentos, pool + JDBC, docker |
| **Fernando** | domínio de catálogo/vendas/fidelidade, repositórios em memória, verificação OpenJML, pacote de entrega |

A divisão é uma sugestão; issues marcadas **(par)** devem ser feitas/revisadas em dupla.

## Convenções
- Branch por issue a partir da `main`: `feature/<n>-<slug>`; PR com `Closes #<n>`; merge só com `mvn -q test` verde (CI).
- Código, nomes e comentários em **inglês**; documentação em `docs/` em **português**.
- Dependências permitidas: **MySQL Connector/J** e **JUnit 5** (+ plugins Maven: compiler, surefire, jacoco). Qualquer outra → discutir antes.
- Classes de domínio/serviço: contratos JML em todo método público, sem streams/lambdas complexos, sem reflexão, dinheiro em centavos (`long`).
- Toda divergência intencional em relação ao Python → `docs/DIVERGENCES.md`.

## Labels sugeridas
`etapa-1` … `etapa-9`, `domain`, `service`, `repository`, `http`, `jml`, `infra`, `docs`, `bug-original` (correção de bug do Python), `decisao-pendente` (bloqueada aguardando decisão).

## Marcos (milestones)
| Marco | Etapas | Data-alvo sugerida |
|---|---|---|
| M0 — Análise | 0 | ✅ 23/11 |
| M1 — Núcleo verificável | 1, 2, 3 | 28/11 |
| M2 — Serviços + API em memória | 4, 5 | 02/12 |
| M3 — Entrega acadêmica | 6, 7 | 05/12 (folga até a apresentação) |
| M4 — Paridade MySQL | 8, 9 | após a apresentação (ou em paralelo se sobrar tempo) |

## Decisões pendentes (bloqueiam issues marcadas `decisao-pendente`)
Ver MP §9 e §10. Resumo:
- **D1 (item 4)** venda fictícia dos pontos de atendimento → recomendada: HISTORICO_PONTOS com origem venda **ou** atendimento.
- **D2 (item 5)** garantia XOR no banco → recomendada: `CHECK`.
- **D3 (item 6)** resgate de pontos → recomendada: domínio + serviço + endpoint aditivo; e o que fazer no estorno.
- **D4 (P3)** sub-decisões de sobreposição (duração mínima 30 min, fim dentro da disponibilidade, 409 ao estender).
- **D5 (N1–N9)** novos achados: `GET /caixas` para funcionário, extrato de pontos (`id_historico`), 500 em exclusões, `preferencias` descartadas, desconto, venda fechada editável, regra de fidelidade duplicada, `ativo` ignorado.

---

## Etapa 1 — Esqueleto (M1)

### [E1-1] Projeto Maven e estrutura de pacotes — André
- `pom.xml` com `maven.compiler.release=17`, Connector/J, JUnit 5, Surefire, JaCoCo (relatório em `mvn verify`).
- Pacotes: `domain`, `repository`, `repository.memory`, `repository.jdbc`, `service`, `http`, `http.json`, `app`.
- `.gitignore`, `README.md` inicial (como compilar/testar), `db/schema.sql` e `db/seed.sql` copiados do original.
- **Aceite:** `mvn -q compile` e `mvn -q test` passam; árvore de pacotes criada.

### [E1-2] Configuração por variáveis de ambiente — André
- Classe `Config` lendo `REPOSITORY` (`memory|mysql`), `API_PORT`, `DB_*`, `JWT_SECRET` (obrigatório, sem default no código), `JWT_EXPIRE_MINUTES` (60), `FRONTEND_URL`, `APP_TIMEZONE`, `PBKDF2_ITERATIONS`.
- **Aceite:** testes de leitura/erro para variável obrigatória ausente.

### [E1-3] `TransactionRunner` (interface + memória) — André **(par)**
- Interface com propagação REQUIRED; `InMemoryTransactionRunner` com lock global + snapshot/restore de repositórios `Snapshotable` (MP §8.1).
- **Aceite:** teste prova "tudo ou nada" (exceção no meio desfaz todas as escritas) e aninhamento.

### [E1-4] Placeholder do OpenJML — Fernando
- `scripts/openjml-check.sh` documentado (variável `OPENJML_HOME`, uso previsto); seção no README.
- **Aceite:** script executa e explica o que falta configurar.

---

## Etapa 2 — Núcleo de domínio puro com JML (M1)

> Toda issue desta etapa: contratos completos (`requires/ensures/assignable/invariant`, `pure` nos getters), testes JUnit, sem I/O.

### [E2-1] Value objects `Money` e `Percentage` — Fernando
- Centavos `long`, soma/multiplicação por quantidade sem overflow (contrato), formatação `"35.00"` e float-Python para percentual.
- **Aceite:** invariantes `cents >= 0` (onde aplicável); testes de borda.

### [E2-2] Intervalos: `TimeRange` e `DateTimeInterval` — André
- Intervalos semiabertos `[início, fim)`, `overlaps`, `contains`; `DayOfWeekPt` (SEGUNDA..DOMINGO ↔ `java.time.DayOfWeek`).
- **Aceite:** contrato de simetria de `overlaps`; testes das bordas (fim == início não sobrepõe).

### [E2-3] Máquinas de estado `AppointmentStatus` e `SaleStatus` — André
- `canTransitionTo` puro conforme MP §5.3 (alinhado com `StatusActions.tsx`); `PaymentMethod`.
- **Aceite:** contrato enumerando as transições válidas; teste da tabela completa estado×estado.

### [E2-4] `Appointment` / `AppointmentItem` — André
- Total = Σ `preco_cobrado` (laço com `loop_invariant`/`decreases`), sem itens duplicados, itens só em estados abertos (P7a), duração efetiva (mín. 30 min — **D4**).
- **Aceite:** invariantes mantidas por todos os métodos; testes.

### [E2-5] `Sale` / `SaleItem` — Fernando
- Total = Σ `quantidade × preco_unitario` (`loop_invariant`); regra de desconto conforme **D5/N5**; itens só em venda ABERTA (**D5/N6**).
- **Aceite:** idem E2-4.

### [E2-6] `PriceHistory` (serviço e produto) — Fernando
- Invariante: no máximo **uma** linha vigente; `data_fim == null ⇔ vigente`; `data_fim ≥ data_inicio`; operação `changePrice(today, values)` encerra a vigente e abre nova.
- **Aceite:** contrato de `changePrice` com `\old`; testes de alterações no mesmo dia (N10).

### [E2-7] Fidelidade: `LoyaltyRule`, `LoyaltyCalculator`, `PointsLedger` — Fernando `decisao-pendente (D1, D3)`
- Invariante XOR serviço/produto; cálculo de pontos de atendimento (1× por serviço) e de venda (× quantidade); saldo = Σ ACUMULA − Σ USA; resgate (se D3=A/B) com `saldo ≥ custo`.
- **Aceite:** contratos com `\sum`/laços anotados; testes.

### [E2-8] Agenda: `AvailabilityPolicy` — André `decisao-pendente (D4)`
- `covers(LocalDateTime)` (dia da semana + `hora_inicio ≤ t < hora_fim`, só ativas); sobreposição entre disponibilidades do mesmo dia; conflito de atendimentos por intervalo (P3).
- **Aceite:** contratos; testes reproduzindo os casos do Python + casos de duração.

### [E2-9] Políticas de acesso: `Role`, `RoleResolver`, `AccessPolicy`, `ResponseMasking` — André
- Papel derivado (admin > barbeiro/caixa > cliente > nenhum); regras "dono ou funcionário"; máscara de comissão/preço de custo/pessoas (P1).
- **Aceite:** tabela de permissões da MP §4.2 coberta por testes.

### [E2-10] Exceções de domínio — Fernando
- `DomainException` + `NotFound(404)`, `Conflict(409)`, `BusinessRule(422)`, `Forbidden(403)`, `Unauthorized(401)` com `detail` idêntico ao Python.
- **Aceite:** catálogo de mensagens centralizado e testado.

---

## Etapa 3 — Repositórios em memória (M1)

### [E3-1] Interfaces de repositório com contratos — Fernando **(par)**
- Uma interface por agregado (Person, Phone, Customer, Cashier, Barber, Availability, ServiceOffering+history, Product+history, Appointment+items, Sale+items, LoyaltyRule, PointsMovement).
- Contratos válidos para memória **e** JDBC (ex.: `findById` retorna `null` ou entidade com o id; `save` atribui id > 0 único).
- **Aceite:** interfaces compilam com JML; revisão em dupla.

### [E3-2] Implementações em memória (`Snapshotable`) — Fernando
- Estruturas simples, ordenações idênticas às consultas SQL (MP §4.1: "ordem").
- **Aceite:** integra com `InMemoryTransactionRunner` (rollback restaura).

### [E3-3] Suíte abstrata de contratos — Fernando
- `Abstract<X>RepositoryContractTest` parametrizada pela fábrica do repositório; rodará contra memória agora e MySQL na Etapa 8.
- **Aceite:** suíte verde em memória.

### [E3-4] `SeedLoader` + `PasswordHasher` PBKDF2 — André
- Seed equivalente ao `seed.sql` (mesmos ids/valores), senhas `admin123`/`func123`/`cliente123` em PBKDF2; `Pbkdf2PasswordHasher` (`javax.crypto`, salt aleatório, comparação em tempo constante) com contrato `verify(hash(p), p)`.
- **Aceite:** testes do hasher; contagem de registros igual ao seed.

---

## Etapa 4 — Serviços (M2) — uma subetapa por vez, com pausa para revisão

### [E4a] Auth, pessoas, telefones, clientes, caixas — André `bug-original`
- Login, registro, usuário atual; CRUDs com unicidade de CPF/email; **P1** (pessoas protegido + mascarado); **N1** e **N4** conforme D5.
- **Aceite:** testes de serviço com repositórios em memória para cada regra/erro da MP §4.1 (#2–#26).

### [E4b] Catálogo: serviços, produtos, histórico de preços — Fernando
- Criação com histórico inicial, atualização parcial (encerra vigente + nova linha), exclusão com 409 (N3 conforme D5).
- **Aceite:** rotas #40–#51 cobertas em nível de serviço.

### [E4c] Barbeiros e disponibilidades — André
- CRUD simples/completo, disponibilidades com sobreposição (409) e `ativo` (N8 conforme D5), horários ocupados (P3: inícios cobertos).
- **Aceite:** rotas #27–#39.

### [E4d] Atendimentos e agenda — André `bug-original` `decisao-pendente (D4)`
- Criação (só AGENDADO), conflito por intervalo (P3), status com máquina de estados (P2) inclusive via PUT, serviços só em atendimento aberto (P7a), crédito de pontos na conclusão (D1).
- **Aceite:** rotas #52–#60; testes de pontos não duplicados.

### [E4e] Vendas — Fernando `bug-original` `decisao-pendente (D5)`
- Criação ABERTA, itens com preço vigente, máquina de estados (P2), desconto/itens em venda fechada (N5/N6), estorno (D3).
- **Aceite:** rotas #61–#68.

### [E4f] Fidelidade e pontos — Fernando `decisao-pendente (D1, D2, D3)`
- CRUD de regras (XOR, unicidade N7), saldo/extrato (N2), resgate (D3).
- **Aceite:** rotas #21–#22, #69–#73.

---

## Etapa 5 — HTTP e autenticação, rodando em memória (M2)

### [E5-1] JSON próprio (`http.json`) — André
- Parser + serializador: objetos, arrays, strings (escapes, `\uXXXX`, pares substitutos), números, booleanos, null; mapa ordenado; formatos da MP §6.
- **Aceite:** testes de ida e volta + casos inválidos (erro com posição).

### [E5-2] Servidor, roteador e erros — André
- `HttpServer` + `ExecutorService` fixo; roteador com `{param}`; 404/405; mapeamento `DomainException`→`{"detail": ...}`; 422 estilo Pydantic; CORS com credenciais (preflight); barra final.
- **Aceite:** testes HTTP em porta efêmera.

### [E5-3] JWT HS256 + cookie — André
- `JwtCodec` com `javax.crypto.Mac` (header/payload idênticos ao PyJWT, MP §7.3), cookie `access_token` HttpOnly/Lax; login/registro/logout/me.
- **Aceite:** token gerado é aceito pelo `jose` (teste com token fixo conhecido) e expira.

### [E5-4] DTOs e validação estilo Pydantic — Fernando
- Records por payload (MP §5.1): tamanhos, `>0`, `≥0`, enums, `extra=forbid` onde houver, tri-state para PATCH/PUT parcial, coerção lax.
- **Aceite:** testes de validação por DTO.

### [E5-5] Handlers dos módulos + `AppFactory`/`Main` — André e Fernando **(par)**
- Handlers finos (sem regra): André = auth/pessoas/telefones/clientes/caixas/barbeiros/disponibilidades/atendimentos; Fernando = serviços/produtos/vendas/fidelidades/pontos.
- `AppFactory` monta tudo por construtor; `REPOSITORY=memory`.
- **Aceite:** API sobe em memória e o frontend original faz login e lista dados.

---

## Etapa 6 — Verificação JML (M3)

### [E6-1] Prova de compatibilidade OpenJML × Java 17 — Fernando
- Instalar OpenJML, verificar uma classe pequena (ESC e RAC); registrar versão e restrições (records/switch/lambdas) em `docs/jml-notes.md`.
- **Aceite:** comando reproduzível documentado no README.

### [E6-2] Conjunto alvo e scripts — Fernando
- `verification/targets.txt` (domínio + serviços principais, ESC em poucos minutos); `scripts/verify-rac.sh`, `verify-esc.sh`, `verify-all.sh` (caminhos relativos, código de saída, logs em `docs/verification/logs/`). `.bat` se a máquina da apresentação for Windows.
- **Aceite:** `scripts/verify-all.sh` roda do zero num clone limpo.

### [E6-3] Fechar provas do núcleo — André e Fernando **(par)**
- Corrigir código/contratos até o ESC passar no conjunto alvo; o que não provar → `docs/jml-notes.md` com motivo; `docs/verification/RESULTS.md` (tabela por classe).
- **Aceite:** verde no conjunto alvo.

---

## Etapa 7 — Pacote de entrega (M3) — `docs/entrega/`

### [E7-1] Descrição do problema e diagramas — André
- `01-descricao-problema.md`; `02-diagrama-classes.puml` completo + versão simplificada (núcleo verificado) e PNG se possível.

### [E7-2] Trechos anotados e estratégia de verificação — Fernando
- `03-trechos-anotados.md` (6–8 trechos); `04-estrategia-verificacao.md` com **roteiro da demo ao vivo** (comandos, ordem, tempo, saída esperada, mutação controlada que falha).

### [E7-3] Métricas e empacotamento — Fernando
- `05-metricas.md` + `scripts/metrics.sh` (campos da planilha — **aguardando a planilha**); `scripts/package.sh` gera o zip e é testado extraindo em outro diretório (`mvn clean test` + `verify-all.sh`).

### [E7-4] Ensaio da demonstração — André e Fernando **(par)**
- Rodar o roteiro no computador da apresentação, cronometrar, ajustar.

---

## Etapa 8 — Adaptador MySQL (M4)

### [E8-1] Pool de conexões próprio — André
- `SimpleConnectionPool` tamanho 5 com contratos (`borrowed + free == size`), validação/recriação, timeout, rollback na devolução (MP §8.2).
- **Aceite:** testes de concorrência (N threads > 5) e de esgotamento.

### [E8-2] `JdbcTransactionRunner` + repositórios JDBC — André e Fernando **(par)**
- Mesmas interfaces; SQL equivalente ao original (ordenações, `CAST(... AS CHAR)`, vigência).
- **Aceite:** suíte abstrata de contratos verde contra MySQL (container).

### [E8-3] Schema/seed ajustados — Fernando `decisao-pendente (D1, D2)`
- Mudanças aprovadas no schema (origem dos pontos, CHECK/TRIGGER), seed com PBKDF2 (`SeedPasswordTool`).

### [E8-4] Docker — André
- `Dockerfile` da API (build multi-stage Maven → JRE 17); `docker-compose.yml` MySQL + API Java + frontend **original**, mesmo `JWT_SECRET` na API e no frontend; `REPOSITORY=mysql`.
- **Aceite:** `docker compose up` e login pelo frontend.

---

## Etapa 9 — Paridade final (M4)

### [E9-1] Testes HTTP de todas as rotas — André e Fernando (dividir por módulo como na Etapa 4)
- Portar a intenção dos 172 testes de router + 225 de serviço do pytest; uma bateria por rota × papel × erro (73 rotas).

### [E9-2] Comparação lado a lado com a API Python — André
- Script que executa as mesmas requisições nas duas APIs (mesmo seed) e compara status/JSON, ignorando divergências documentadas.

### [E9-3] Fluxos do frontend original — Fernando
- Roteiro manual: login nos 3 papéis, agendamento público, CRUDs, venda, status, pontos; registrar evidências.

### [E9-4] Fechamento — André e Fernando **(par)**
- README completo, relatório JaCoCo, `docs/DIVERGENCES.md` final, zip regenerado e verificações reconfirmadas.
