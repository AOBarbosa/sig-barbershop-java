# Plano de Migração — sig-barbershop (Python/FastAPI → Java 17 puro + JML)

> Etapa 0 (análise). Fonte analisada: `/Users/andrebarbosa/Documents/bd/sig-babershop` (commit `6f800da`, somente leitura).
> Converte-se apenas `api/`. O `frontend/` (Next.js) permanece **inalterado** e é a referência de contrato.

## Status das etapas

| Etapa | Descrição | Status |
|---|---|---|
| 0 | Análise (este documento) | ✅ concluída (aguardando aprovação) |
| 1 | Esqueleto (pom, pacotes, config, `TransactionRunner`) | 🟡 estrutura criada (pom, pacotes, README, db/, placeholder OpenJML, `docs/jml-guidelines.md`); falta `Config` e `TransactionRunner` |
| 2 | Núcleo de domínio puro com JML | ⏳ |
| 3 | Repositórios em memória + suíte abstrata de contratos | ⏳ |
| 4 | Serviços (4a…4f, por módulo) | ⏳ |
| 5 | HTTP + autenticação (rodando em memória) | ⏳ |
| 6 | Verificação JML (OpenJML ESC + RAC) | ⏳ |
| 7 | Pacote de entrega acadêmica | ⏳ |
| 8 | Adaptador MySQL (pool próprio + JDBC) + docker-compose | ⏳ |
| 9 | Paridade final | ⏳ |

---

## 1. Verificação da análise prévia

| # | Afirmação da análise prévia | Veredito | Evidência / correção |
|---|---|---|---|
| 1 | API REST com **49 endpoints** | ❌ **Refutado em parte** | O backend declara **72 rotas de negócio + `GET /health` = 73**. O número **49** corresponde exatamente às rotas **chamadas pelos services do frontend** (`frontend/src/services/*.ts`). O checklist de paridade (§4) cobre as 73; a coluna "FE" marca as 49 consumidas. |
| 2 | docker-compose: MySQL 8 (schema → seed), API :8000, frontend :3000 | ✅ | `docker-compose.yml` monta `schema.sql` como `01_` e `seed.sql` como `02_` em `/docker-entrypoint-initdb.d`. |
| 3 | 16 tabelas | ✅ | PESSOA, TELEFONE, CLIENTE, CAIXA, BARBEIRO, DISPONIBILIDADE, SERVICO, HISTORICO_SERVICO, ATENDIMENTO, ATENDIMENTO_SERVICO, PRODUTO, HISTORICO_PRODUTO, VENDA, VENDA_PRODUTO, FIDELIDADE, HISTORICO_PONTOS. |
| 4 | Camadas Router → Service → Repository | ✅ com ressalva | Routers contêm lógica de permissão/filtragem (`_validar_dono_do_atendimento`, `_ocultar_comissao`, `_ocultar_preco_custo`, filtro por cliente em `GET /atendimentos`, `_validar_acesso` dos pontos). |
| 5 | Pool de 5 conexões, autocommit ligado, rollback de transação aberta ao fim da requisição | ✅ | `database.py` (`pool_size=5`, `autocommit=True`, criação preguiçosa); `dependencies.get_db` faz `rollback()` se `conn.in_transaction`. |
| 6 | Login gera JWT em cookie httponly `access_token` | ✅ | `auth_router._set_cookie_auth`: `httponly=True, samesite="lax", path="/"`, sem `Max-Age` (cookie de sessão). |
| 7 | Papel derivado a cada requisição (admin → barbeiro/caixa → cliente) | ✅ | `auth_service._derivar_role`: `PESSOA.admin` → `admin`; BARBEIRO **ou** CAIXA → `funcionario`; CLIENTE → `cliente`; nenhum → **403** "Pessoa sem papel de acesso definido". O claim `role` do JWT **não** é usado pela API (só pelo `middleware.ts`). |
| 8 | Admin "gerencia tudo, inclusive caixas"; funcionário "clientes, atendimentos, vendas, fidelidade" | ⚠️ Corrigido | **Fidelidade é `require_funcionario`**, não só admin (a análise dizia "admin define regras"). Barbeiros (escrita) e caixas são **somente admin**. Ver matriz §4.2. |
| 9 | Cliente "consulta seus dados e marca horários" | ✅ | Cliente vê/agenda só os próprios atendimentos e pontos. Não acessa `/clientes`, `/vendas`. |
| 10 | Disponibilidade: fora → 422; ocupado → 409 | ✅ | `atendimento_service._validar_horario_barbeiro`. Mensagens: "Horario fora da disponibilidade do barbeiro" (422) e "Horario indisponivel para este barbeiro" (409). |
| 11 | Atendimento com 1+ serviços; `valor_total` recalculado | ⚠️ | Recalculado a cada inclusão/remoção. **Não** há exigência de "1 ou mais": o atendimento é criado **sem** serviços e o frontend adiciona depois, um POST por serviço. |
| 12 | Estados do atendimento | ✅ | `ENUM('AGENDADO','EM_EXECUCAO','CONCLUIDO','CANCELADO')`. |
| 13 | Ao concluir credita pontos | ✅ | Só via `PATCH /atendimentos/{id}/status`. **`PUT /atendimentos/{id}` também muda `status` e NÃO credita** (contorna a regra). |
| 14 | Histórico de preços com vigência; preço copiado | ✅ | `encerrar_vigente` (`data_fim=CURRENT_DATE, ativo=FALSE`) + nova linha (`data_inicio=date.today()`). Vigente = `ativo=TRUE AND data_fim IS NULL`. Preço copiado para `preco_cobrado` / `preco_unitario`. |
| 15 | Formas de pagamento: dinheiro, PIX, crédito, débito | ⚠️ Corrigido | Há também **`OUTRO`** (`ENUM('DINHEIRO','PIX','CARTAO_CREDITO','CARTAO_DEBITO','OUTRO')`). |
| 16 | Estados da venda: aberta, paga, cancelada, estornada | ✅ | `ENUM('ABERTA','PAGA','CANCELADA','ESTORNADA')`. Criação força `ABERTA`. |
| 17 | Pagamento dispara acúmulo de pontos | ✅ | `PATCH /vendas/{id}/status` → `PAGA`: pontos = `FIDELIDADE.pontos_acumulados × quantidade` por produto com regra ativa. |
| 18 | Fidelidade: exatamente um serviço OU um produto | ✅ | `fidelidade_service._validar_xor` (422 "Fidelidade deve referenciar exatamente um de SERVICO ou PRODUTO"). |
| 19 | Extrato: acúmulo ou uso | ✅ | `ENUM('ACUMULA','USA')`. Saldo = Σ ACUMULA − Σ USA. |
| 20 | Comissão só para admin | ✅ + extra | Idem para **`preco_custo` de produtos** (`GET /produtos*`, campo `null` para não-admin). |
| 21 | `schema.sql` é a fonte de verdade dos enums | ✅ | O `CLAUDE.md` do original lista enums desatualizados (`agendado|em_andamento…`, `pendente|concluida…`, `acumulo|resgate`). |
| P1 | `/pessoas` sem autenticação | ✅ Confirmado | Nenhuma dependência de auth em `pessoa_router.py`. Causa: `getPessoas()` é chamado pelo **agendamento público** (`agendamentoPublicoService.getCatalogoAgendamento`) para obter o nome dos barbeiros, antes do login. |
| P2 | Nenhuma troca de status é bloqueada | ✅ Confirmado | Além disso: `POST /atendimentos` aceita `status` arbitrário e `PUT /atendimentos/{id}` muda status sem regra e sem pontos. |
| P3 | Conflito compara só o início exato | ✅ Confirmado | `agenda_repository.barbeiro_ocupado_no_horario`: `data_hora_inicio = %s AND status <> 'CANCELADO'`. |
| P4 | Venda fictícia para os pontos de atendimento | ✅ Confirmado | `historico_pontos_service._criar_venda_do_atendimento`: status `PAGA`, forma `OUTRO`, `valor_total` do atendimento, primeiro caixa por id; 422 "Nenhum caixa cadastrado para registrar pontos". Só cria a venda se houver ao menos 1 ponto. |
| P5 | Nenhum TRIGGER | ✅ Confirmado | `schema.sql` não contém `TRIGGER` nem `CHECK`. |
| P6 | USA nunca registrado | ✅ Confirmado | Só aparece no cálculo de saldo. `FIDELIDADE.pontos_uso` é armazenado e nunca usado (no seed vale 10× `pontos_acumulados`, sugerindo "custo de resgate"). |
| P7 | Problemas menores | ✅ Confirmados | Ver §9 (novos achados). |

---

## 2. Inventário do banco (schema.sql)

Banco `sig_barbershop`, `utf8mb4_unicode_ci`. Nenhum CHECK, TRIGGER, VIEW ou PROCEDURE. Todos os FKs sem ação explícita são **RESTRICT** (padrão do InnoDB).

| Tabela | PK | Colunas (tipo, nulidade, default) | UNIQUE / FK |
|---|---|---|---|
| PESSOA | `id_pessoa` AI | `nome VARCHAR(100) NN`, `cpf VARCHAR(14)`, `email VARCHAR(100)`, `data_nascimento DATE`, `admin TINYINT NN DEF 0`, `senha_hash VARCHAR(255)` | UNIQUE(cpf), UNIQUE(email) (aceitam vários NULL) |
| TELEFONE | (`PESSOA_id_pessoa`, `telefone`) | `telefone VARCHAR(20) NN` | FK→PESSOA **ON DELETE CASCADE** |
| CLIENTE | `PESSOA_id_pessoa` | `preferencias TEXT`, `observacoes TEXT` | FK→PESSOA CASCADE |
| CAIXA | `PESSOA_id_pessoa` | — | FK→PESSOA CASCADE |
| BARBEIRO | `PESSOA_id_pessoa` | `apelido VARCHAR(60)`, `comissao_percentual DECIMAL(5,2)` | FK→PESSOA CASCADE |
| DISPONIBILIDADE | `id_disponibilidade` AI | `BARBEIRO_PESSOA_id_pessoa NN`, `dia_semana ENUM(SEGUNDA..DOMINGO) NN`, `hora_inicio TIME NN`, `hora_fim TIME NN`, `ativo TINYINT NN DEF 1` | FK→BARBEIRO CASCADE |
| SERVICO | `id_servico` AI | `nome VARCHAR(80) NN`, `ativo TINYINT NN DEF 1` | — |
| HISTORICO_SERVICO | `id_historico` AI | `SERVICO_id_servico NN`, `preco DECIMAL(10,2) NN`, `duracao_em_minutos INT NN`, `pontos_gerados INT NN DEF 0`, `data_inicio DATE NN`, `data_fim DATE`, `ativo TINYINT NN DEF 1` | FK→SERVICO **RESTRICT** |
| ATENDIMENTO | `id_atendimento` AI | `CLIENTE_PESSOA_id_pessoa NN`, `BARBEIRO_PESSOA_id_pessoa NN`, `data_hora_inicio DATETIME NN`, `data_hora_fim DATETIME`, `valor_total DECIMAL(10,2) NN DEF 0`, `status ENUM(AGENDADO,EM_EXECUCAO,CONCLUIDO,CANCELADO) NN DEF AGENDADO`, `observacoes TEXT` | FK→CLIENTE, FK→BARBEIRO (RESTRICT) |
| ATENDIMENTO_SERVICO | (`ATENDIMENTO_id_atendimento`, `SERVICO_id_servico`) | `preco_cobrado DECIMAL(10,2) NN` | FK→ATENDIMENTO CASCADE, FK→SERVICO RESTRICT |
| PRODUTO | `id_produto` AI | `nome VARCHAR(80) NN`, `categoria VARCHAR(60)`, `ativo TINYINT NN DEF 1` | — |
| HISTORICO_PRODUTO | `id_historico` AI | `PRODUTO_id_produto NN`, `preco_venda DECIMAL(10,2) NN`, `preco_custo DECIMAL(10,2) NN`, `pontos_gerados INT NN DEF 0`, `data_inicio DATE NN`, `data_fim DATE`, `ativo TINYINT NN DEF 1` | FK→PRODUTO RESTRICT |
| VENDA | `id_venda` AI | `CLIENTE_PESSOA_id_pessoa NN`, `CAIXA_PESSOA_id_pessoa NN`, `data_hora DATETIME NN`, `valor_total DECIMAL(10,2) NN DEF 0`, `status ENUM(ABERTA,PAGA,CANCELADA,ESTORNADA) NN DEF ABERTA`, `forma_pagamento ENUM(DINHEIRO,PIX,CARTAO_CREDITO,CARTAO_DEBITO,OUTRO) NN`, `desconto DECIMAL(10,2) NN DEF 0` | FK→CLIENTE, FK→CAIXA |
| VENDA_PRODUTO | (`VENDA_id_venda`, `PRODUTO_id_produto`) | `quantidade INT NN`, `preco_unitario DECIMAL(10,2) NN DEF 0` | FK→VENDA CASCADE, FK→PRODUTO RESTRICT |
| FIDELIDADE | `id_fidelidade` AI | `PRODUTO_id_produto INT NULL`, `SERVICO_id_servico INT NULL`, `pontos_acumulados INT NN DEF 0`, `pontos_uso INT NN DEF 0`, `ativo TINYINT NN DEF 1` | FK→PRODUTO, FK→SERVICO (RESTRICT) |
| HISTORICO_PONTOS | `id_movimentacao` AI | `CLIENTE_PESSOA_id_pessoa NN`, `VENDA_id_venda NN`, `FIDELIDADE_id_fidelidade NN`, `pontos INT NN`, `tipo_movimentacao ENUM(ACUMULA,USA) NN`, `data_movimentacao DATETIME NN` | FK→CLIENTE, FK→VENDA, FK→FIDELIDADE (RESTRICT) |

**Relacionamentos (especialização de PESSOA):** CLIENTE, CAIXA e BARBEIRO compartilham a PK de PESSOA (especialização sobreposta: uma pessoa pode ter vários papéis; no seed, Roberto é admin **e** caixa). TELEFONE é multivalorado de PESSOA. ATENDIMENTO N:M SERVICO via ATENDIMENTO_SERVICO; VENDA N:M PRODUTO via VENDA_PRODUTO. FIDELIDADE é uma "categoria" (união) de SERVICO ou PRODUTO.

**Consequências dos FKs RESTRICT (achados):**
- `DELETE /servicos/{id}` e `DELETE /produtos/{id}` **sempre falham com 500** para itens criados pela API, porque sempre existe linha em HISTORICO_* (e às vezes em FIDELIDADE). Os services só checam ATENDIMENTO_SERVICO / VENDA_PRODUTO.
- `DELETE /vendas/{id}` dá 500 se a venda tiver HISTORICO_PONTOS; `DELETE /fidelidades/{id}` dá 500 se a regra já tiver sido usada.
- `DELETE /barbeiros/{id}` apaga as disponibilidades em cascata; `DELETE /pessoas/{id}` apaga os telefones em cascata.

**Dados de exemplo (seed.sql):** 8 pessoas (ids 1–8), 8 telefones, clientes 1–4, caixa 5 (Roberto, também admin), barbeiros 6, 7 e 8 com comissões 40, 45 e 35, 6 disponibilidades, 6 serviços com histórico desde 2026-01-01, 4 produtos com histórico, 5 atendimentos (3 CONCLUIDO, 1 CANCELADO, 1 AGENDADO), 4 vendas (3 PAGA, 1 ABERTA `OUTRO`), 7 regras de fidelidade (4 de serviço, 3 de produto) e 4 movimentações ACUMULA. Inconsistências no seed: a venda 3 vende o produto 4 (Cera), mas o ponto lançado usa a regra 7 (Óleo, produto 3); os atendimentos concluídos não têm pontos. **Manter como está** (são dados de exemplo; a paridade exige os mesmos dados).

---

## 3. Entidades de domínio em Java (proposta de nomes; código em inglês)

| Tabela | Classe de domínio | Observações |
|---|---|---|
| PESSOA | `Person` | `admin` boolean; `passwordHash` fica **fora** do objeto exposto (repositório tem método próprio) |
| TELEFONE | `Phone` (value object) | chave composta (personId, number) |
| CLIENTE | `Customer` | `pointsBalance` é derivado (não é campo persistido) |
| CAIXA | `Cashier` | |
| BARBEIRO | `Barber` | `commission` como `Percentage` (centésimos em `long`) |
| DISPONIBILIDADE | `Availability` | `DayOfWeekPt` + `TimeRange` |
| SERVICO / HISTORICO_SERVICO | `ServiceOffering` / `ServicePriceHistory` | evita colisão com o pacote `service` |
| PRODUTO / HISTORICO_PRODUTO | `Product` / `ProductPriceHistory` | |
| ATENDIMENTO / ATENDIMENTO_SERVICO | `Appointment` / `AppointmentItem` | `AppointmentStatus` com `canTransitionTo` |
| VENDA / VENDA_PRODUTO | `Sale` / `SaleItem` | `SaleStatus`, `PaymentMethod` |
| FIDELIDADE | `LoyaltyRule` | invariante XOR serviço/produto |
| HISTORICO_PONTOS | `PointsMovement` | `MovementType {ACUMULA, USA}` |
| — | `Money` | centavos em `long`, nunca `double` |
| — | `TimeRange`, `DateTimeInterval` | sobreposição de intervalos semiabertos `[início, fim)` |

Pacote base proposto: `br.ufrn.sigbarbershop` (subpacotes `domain`, `repository`, `repository.memory`, `repository.jdbc`, `service`, `http`, `http.json`, `app`). Pode ser ajustado na Etapa 1.

---

## 4. Inventário de endpoints (checklist de paridade)

Legenda de papel: **pub** = sem login; **opt** = login opcional (muda o conteúdo); **auth** = qualquer usuário logado; **func** = admin ou funcionário; **adm** = só admin. FE ✓ = chamado pelo frontend (49 rotas).
Erros comuns a todas as rotas: **401** "Nao autenticado" / "Token invalido ou expirado" / "Usuario nao encontrado" e **403** "Pessoa sem papel de acesso definido" (rotas com login); **403** "Acesso restrito a administradores" / "Acesso restrito a funcionarios"; **422** de validação Pydantic (corpo, parâmetro de caminho não inteiro, query ausente).

### 4.1 Tabela

| # | Método | Rota | Papel | Entrada | Saída (status) | Erros de negócio | FE |
|---|---|---|---|---|---|---|---|
| 1 | GET | `/health` | pub | — | `{"status":"ok"}` 200 | — | |
| **Auth** |
| 2 | POST | `/auth/login` | pub | `LoginRequest{email 1..100, senha 1..72}` | `UsuarioAtual` 200 + Set-Cookie | 401 "Email ou senha invalidos"; 403 sem papel | ✓ |
| 3 | POST | `/auth/registrar-cliente` | pub | `RegistroClienteRequest{nome 1..100, cpf ≤14?, email 1..100, data_nascimento?, senha 6..72, preferencias?, observacoes?}` | `UsuarioAtual` 201 + Set-Cookie | 409 "CPF ja cadastrado" / "Email ja cadastrado" | ✓ |
| 4 | POST | `/auth/logout` | pub | — | 204, apaga o cookie | — | ✓ |
| 5 | GET | `/auth/me` | auth (cookie) | — | `UsuarioAtual` 200 | 401/403 | ✓ |
| **Pessoas** (hoje **pub** — bug P1) |
| 6 | GET | `/pessoas` | pub | — | `PessoaResponse[]` (ordem: nome) | — | ✓ |
| 7 | GET | `/pessoas/{id}` | pub | — | `PessoaResponse` | 404 "Pessoa nao encontrada" | ✓ |
| 8 | GET | `/pessoas/{id}/telefones` | pub | — | `TelefoneResponse[]` (ordem: telefone) | 404 Pessoa | |
| 9 | POST | `/pessoas` | pub | `PessoaCreate` | `PessoaResponse` 201 | 409 CPF / Email | ✓ |
| 10 | PUT | `/pessoas/{id}` | pub | `PessoaUpdate` (parcial) | `PessoaResponse` | 404; 409 CPF / Email | ✓ |
| 11 | DELETE | `/pessoas/{id}` | pub | — | 204 | 404; 409 "Pessoa possui vinculos (cliente, barbeiro ou caixa)" | |
| **Telefones** |
| 12 | GET | `/telefones/{pessoa_id}/{telefone}` | func | — | `TelefoneResponse` | 404 "Telefone nao encontrado" | |
| 13 | POST | `/telefones` | func | `TelefoneCreate{PESSOA_id_pessoa>0, telefone 1..20}` | 201 | 404 Pessoa; duplicado → **500** | |
| 14 | PUT | `/telefones/{pessoa_id}/{telefone}` | func | `TelefoneUpdate{telefone? 1..20}` | 200 | 404 Telefone | |
| 15 | DELETE | `/telefones/{pessoa_id}/{telefone}` | func | — | 204 | 404 Telefone | |
| **Clientes** |
| 16 | GET | `/clientes` | func | — | `ClienteResponse[]` (ordem: id; inclui `saldo_pontos`) | — | ✓ |
| 17 | GET | `/clientes/{id}` | func | — | `ClienteResponse` | 404 "Cliente nao encontrado" | ✓ |
| 18 | POST | `/clientes` | func | `ClienteCreate{PESSOA_id_pessoa>0, preferencias?, observacoes?}` | 201 | 404 Pessoa; 409 "Pessoa ja esta cadastrada como cliente" | ✓ |
| 19 | POST | `/clientes/completo` | func | `ClienteCompletoCreate` (Pessoa + preferencias, observacoes) | `{cliente, pessoa}` 201 | 409 CPF / Email (**preferências e observações são descartadas** — achado N4) | ✓ |
| 20 | DELETE | `/clientes/{id}` | func | — | 204 | 404; 409 "Cliente possui atendimentos, vendas ou historico de pontos" | |
| **Pontos** |
| 21 | GET | `/clientes/{id}/pontos` | auth (cliente só o próprio) | — | `{CLIENTE_PESSOA_id_pessoa, saldo}` | 403 "Acesso restrito ao proprio cliente ou a funcionarios"; 404 Cliente | ✓ |
| 22 | GET | `/clientes/{id}/pontos/historico` | idem | — | `HistoricoPontosResponse[]` (data desc, id desc) | idem | ✓ (contrato divergente, achado N2) |
| **Caixas** |
| 23 | GET | `/caixas` | adm | — | `[{PESSOA_id_pessoa}]` | — | ✓ (o formulário de venda do **funcionário** chama esta rota e recebe 403 — achado N1) |
| 24 | GET | `/caixas/{id}` | adm | — | `CaixaResponse` | 404 "Caixa nao encontrado" | |
| 25 | POST | `/caixas` | adm | `CaixaCreate{PESSOA_id_pessoa>0}` | 201 | 404 Pessoa; 409 "Pessoa ja esta cadastrada como caixa" | |
| 26 | DELETE | `/caixas/{id}` | adm | — | 204 | 404; 409 "Caixa possui vendas vinculadas" | |
| **Barbeiros** |
| 27 | GET | `/barbeiros` | opt | — | `BarbeiroResponse[]` (ordem: id), `comissao_percentual=null` se não admin | — | ✓ |
| 28 | GET | `/barbeiros/{id}` | opt | — | idem | 404 "Barbeiro nao encontrado" | ✓ |
| 29 | GET | `/barbeiros/{id}/disponibilidades` | pub | — | `DisponibilidadeResponse[]` (ordem: SEGUNDA..DOMINGO, hora_inicio) | 404 Barbeiro | ✓ |
| 30 | GET | `/barbeiros/{id}/horarios-ocupados?inicio=&fim=` | pub | query datetime obrigatórias | `[{"data_hora_inicio": dt}]` (não cancelados, `inicio ≤ x ≤ fim`) — **sem response_model** e **sem 404** | 422 query | ✓ |
| 31 | POST | `/barbeiros` | adm | `BarbeiroCreate{PESSOA_id_pessoa>0, apelido? ≤60, comissao_percentual? float}` | 201 | 404 Pessoa; 409 "Pessoa ja esta cadastrada como barbeiro" | ✓ |
| 32 | POST | `/barbeiros/completo` | adm | `BarbeiroCompletoCreate` (Pessoa + apelido, comissão) | `{barbeiro, pessoa}` 201 | 409 CPF / Email | ✓ |
| 33 | PUT | `/barbeiros/{id}/completo` | adm | `BarbeiroCompletoUpdate` (parcial) | `{barbeiro, pessoa}` | 404 Barbeiro / Pessoa; 409 CPF / Email | ✓ |
| 34 | PUT | `/barbeiros/{id}` | adm | `BarbeiroUpdate` (parcial) | `BarbeiroResponse` | 404 | ✓ |
| 35 | DELETE | `/barbeiros/{id}` | adm | — | 204 | 404; 409 "Barbeiro possui atendimentos vinculados" | |
| **Disponibilidades** |
| 36 | GET | `/disponibilidades/{id}` | pub | — | `DisponibilidadeResponse` | 404 "Disponibilidade nao encontrada" | |
| 37 | POST | `/disponibilidades` | func | `DisponibilidadeCreate{BARBEIRO>0, dia_semana, hora_inicio, hora_fim > inicio, ativo=true}` | 201 (`ativo` enviado é **ignorado**, achado N8) | 404 Barbeiro; 409 "Barbeiro ja possui disponibilidade sobreposta neste dia"; 422 (validador Pydantic) | ✓ |
| 38 | PUT | `/disponibilidades/{id}` | func | `DisponibilidadeUpdate` (parcial) | 200 | 404; 422 "hora_fim deve ser posterior a hora_inicio"; 409 sobreposição | |
| 39 | DELETE | `/disponibilidades/{id}` | func | — | 204 | 404 | ✓ |
| **Serviços** |
| 40 | GET | `/servicos` | pub | — | `ServicoResponse[]` (ordem: nome; preço, duração e pontos do histórico vigente) | — | ✓ |
| 41 | GET | `/servicos/{id}` | pub | — | `ServicoResponse` | 404 "Servico nao encontrado" | ✓ |
| 42 | GET | `/servicos/{id}/historico` | pub | — | `HistoricoServicoResponse[]` (data_inicio desc) | 404 | |
| 43 | POST | `/servicos` | func | `ServicoCreate{nome 1..80, ativo=true, preco≥0, duracao>0, pontos≥0=0}` | 201 | — | ✓ |
| 44 | PUT | `/servicos/{id}` | func | `ServicoUpdate` (parcial) | 200 | 404 | ✓ |
| 45 | DELETE | `/servicos/{id}` | func | — | 204 | 404; 409 "Servico possui atendimentos vinculados"; na prática **500** (FK do histórico, achado N3) | |
| **Produtos** |
| 46 | GET | `/produtos` | opt | — | `ProdutoResponse[]` (ordem: nome; `preco_custo=null` se não admin) | — | ✓ |
| 47 | GET | `/produtos/{id}` | opt | — | idem | 404 "Produto nao encontrado" | ✓ |
| 48 | GET | `/produtos/{id}/historico` | opt | — | `HistoricoProdutoResponse[]` (custo mascarado) | 404 | |
| 49 | POST | `/produtos` | func | `ProdutoCreate{nome 1..80, categoria? ≤60, ativo, preco_venda≥0, preco_custo≥0, pontos≥0}` | 201 (custo **não** mascarado) | — | ✓ |
| 50 | PUT | `/produtos/{id}` | func | `ProdutoUpdate` (parcial) | 200 | 404 | ✓ |
| 51 | DELETE | `/produtos/{id}` | func | — | 204 | 404; 409 "Produto possui movimentacoes vinculadas"; na prática **500** (N3) | |
| **Atendimentos** |
| 52 | GET | `/atendimentos` | auth (cliente: só os próprios) | — | `AtendimentoResponse[]` (data_hora_inicio desc, id desc) | — | ✓ |
| 53 | GET | `/atendimentos/{id}` | auth (dono ou func) | — | `AtendimentoResponse` | 404 "Atendimento nao encontrado"; 403 "Acesso restrito ao proprio cliente ou a funcionarios" | ✓ |
| 54 | GET | `/atendimentos/{id}/servicos` | auth (dono ou func) | — | `AtendimentoServicoResponse[]` (ordem: servico_id) | 404; 403 | ✓ |
| 55 | POST | `/atendimentos/{id}/servicos` | auth (dono ou func) | `{SERVICO_id_servico>0}` (extra=forbid) | 201 | 404 Atendimento / Servico; 409 "Servico ja vinculado ao atendimento"; 422 "Servico sem preco vigente" | ✓ |
| 56 | DELETE | `/atendimentos/{id}/servicos/{sid}` | func | — | 204 | 404 Atendimento; 404 "Servico nao vinculado ao atendimento" | |
| 57 | POST | `/atendimentos` | auth (cliente: só para si) | `AtendimentoCreate{CLIENTE>0, BARBEIRO>0, data_hora_inicio, data_hora_fim?, status=AGENDADO, observacoes?}` (extra=forbid) | 201 | 403 "Cliente so pode agendar atendimento para si mesmo"; 404 Cliente / Barbeiro; 422 disponibilidade; 409 ocupado | ✓ |
| 58 | PUT | `/atendimentos/{id}` | func | `AtendimentoUpdate` (parcial, extra=forbid) | 200 | 404; 404 Cliente / Barbeiro; 422 / 409 se mudar barbeiro ou horário | |
| 59 | PATCH | `/atendimentos/{id}/status` | func | `{status}` | 200 | 404; 422 "Nenhum caixa cadastrado para registrar pontos" | ✓ |
| 60 | DELETE | `/atendimentos/{id}` | func | — | 204 | 404 | |
| **Vendas** (todas func) |
| 61 | GET | `/vendas` | func | — | `VendaResponse[]` (data_hora desc, id desc) | — | ✓ |
| 62 | GET | `/vendas/{id}` | func | — | `VendaResponse` | 404 "Venda nao encontrada" | ✓ |
| 63 | POST | `/vendas` | func | `VendaCreate{CLIENTE>0, CAIXA>0, data_hora, forma_pagamento, desconto≥0 (10,2)}` (extra=forbid) | 201 (`status=ABERTA`, `valor_total=0`) | 404 Cliente / "Caixa nao encontrado" | ✓ |
| 64 | PATCH | `/vendas/{id}/status` | func | `{status}` | 200 | 404 | ✓ |
| 65 | DELETE | `/vendas/{id}` | func | — | 204 | 404; 500 se houver pontos (N3) | |
| 66 | GET | `/vendas/{id}/produtos` | func | — | `VendaProdutoResponse[]` (ordem: produto_id) | 404 | ✓ |
| 67 | POST | `/vendas/{id}/produtos` | func | `{PRODUTO_id_produto>0, quantidade>0}` (extra=forbid) | 201 | 404 Venda / Produto; 409 "Produto ja vinculado a venda"; 422 "Produto sem preco vigente" | ✓ |
| 68 | DELETE | `/vendas/{id}/produtos/{pid}` | func | — | 204 | 404 Venda; 404 "Produto nao vinculado a venda"; 404 Produto | |
| **Fidelidade** (todas func) |
| 69 | GET | `/fidelidades` | func | — | `FidelidadeResponse[]` (ordem: id) | — | ✓ |
| 70 | GET | `/fidelidades/{id}` | func | — | `FidelidadeResponse` | 404 "Fidelidade nao encontrada" | ✓ |
| 71 | POST | `/fidelidades` | func | `FidelidadeCreate{SERVICO?, PRODUTO?, pontos_acumulados≥0=0, pontos_uso≥0=0, ativo=true}` | 201 | 422 XOR; FK inexistente → **500** (N10) | ✓ |
| 72 | PUT | `/fidelidades/{id}` | func | `FidelidadeUpdate` (parcial) | 200 | 404; 422 XOR | ✓ |
| 73 | DELETE | `/fidelidades/{id}` | func | — | 204 | 404; 500 se a regra já foi usada (N3) | |

### 4.2 Matriz de permissões (original → Java)

| Recurso | pub | cliente | funcionário | admin | Mudança em Java |
|---|---|---|---|---|---|
| `/health`, `/auth/login`, `/auth/registrar-cliente`, `/auth/logout` | ✓ | ✓ | ✓ | ✓ | — |
| `/auth/me` | — | ✓ | ✓ | ✓ | — |
| GET `/pessoas`, GET `/pessoas/{id}` | ✓ (tudo) | ✓ (tudo) | ✓ | ✓ | **P1:** pub/cliente veem **só barbeiros**, com `cpf`, `email` e `data_nascimento` nulos e `admin=false` (mesmo formato). func/adm veem tudo. |
| POST/PUT/DELETE `/pessoas`, GET `/pessoas/{id}/telefones` | ✓ | ✓ | ✓ | ✓ | **P1:** exige func; criar/alterar com `admin=true` (ou alterar o campo `admin`) exige **adm** (403). |
| `/telefones/*` | — | — | ✓ | ✓ | — |
| `/clientes` (CRUD) | — | — | ✓ | ✓ | — |
| `/clientes/{id}/pontos*` | — | só o próprio | ✓ | ✓ | lógica sai do router para o `AccessPolicy` |
| `/caixas` | — | — | — | ✓ | N1 (decisão): liberar **GET** para func? |
| GET `/barbeiros*`, `/disponibilidades/{id}`, GET `/servicos*` | ✓ | ✓ | ✓ | ✓ | comissão visível só para adm |
| GET `/produtos*` | ✓ | ✓ | ✓ | ✓ | `preco_custo` visível só para adm |
| escrita `/barbeiros*` | — | — | — | ✓ | — |
| escrita `/disponibilidades`, `/servicos`, `/produtos` | — | — | ✓ | ✓ | — |
| GET `/atendimentos*`, POST `/atendimentos`, POST `/atendimentos/{id}/servicos` | — | só os próprios | ✓ | ✓ | — |
| PUT / PATCH / DELETE `/atendimentos*` | — | — | ✓ | ✓ | — |
| `/vendas*`, `/fidelidades*` | — | — | ✓ | ✓ | — |

Por que não basta "a listagem pública de barbeiros já devolver o nome": o frontend **inalterado** continua chamando `GET /pessoas` no catálogo público (`getCatalogoAgendamento`) e cruza `barbeiro.PESSOA_id_pessoa` com `pessoa.id_pessoa`. A solução que **não muda o contrato** é filtrar e mascarar o conteúdo de `GET /pessoas` por papel, como o original já faz com a comissão. O formato é preservado: o frontend só exige as chaves `id_pessoa`, `nome` e `cpf`, e `cpf` pode ser `null`. Assim, não é preciso parar por mudança de contrato.

---

## 5. Regras de negócio e validações (onde vivem em Java)

Legenda de destino: **D** = `domain` (puro, alvo de ESC); **S** = `service` (com contratos, RAC/ESC); **H** = `http` (DTO / validação de formato); **R** = contrato da interface de repositório; **DB** = schema.

### 5.1 Validação de formato (Pydantic → records `http` com validação manual) — H
- Tamanhos de string: nome 1..100 (Pessoa) / 1..80 (Serviço, Produto); cpf ≤14; email ≤100 (sem validação de formato de e-mail!); apelido ≤60; categoria ≤60; telefone 1..20; senha 1..72 (login) e 6..72 (registro).
- Inteiros `>0` em todos os ids de payload; `quantidade>0`; `duracao_em_minutos>0`; `pontos*≥0`; `preco*≥0`; `desconto≥0` com no máximo 10 dígitos e 2 casas.
- `extra="forbid"` **só** em AtendimentoCreate/Update/StatusUpdate/ServicoCreate e VendaCreate/StatusUpdate/ProdutoCreate → campo desconhecido gera 422. Os demais payloads **ignoram** campos extras (ex.: o frontend envia `disponibilidades` dentro de `/barbeiros/completo`? Não: ele separa antes; mas a regra de ignorar continua valendo).
- Enums literais (status, forma de pagamento, dia da semana) em MAIÚSCULAS.
- Disponibilidade: `hora_fim > hora_inicio` no validador do modelo (422 no formato Pydantic) e de novo no service do PUT (422 com `detail` string).
- Coerção "lax" do Pydantic v2 que precisa ser reproduzida: `int` aceita `"5"` e `5.0`; `bool` aceita `true`, `1`, `"true"`, `"1"`, `"yes"` etc.; `Decimal` aceita número ou string; `datetime` aceita `YYYY-MM-DDTHH:MM[:SS[.ffffff]][Z|±HH:MM]` (o frontend envia `YYYY-MM-DDTHH:MM`); `date` aceita `YYYY-MM-DD`; `time` aceita `HH:MM[:SS]`.
- Atualizações parciais (`model_dump(exclude_unset=True)`): é preciso distinguir **campo ausente** de **campo `null`** (ex.: `PUT /pessoas` com `"email": null` grava NULL). Em Java: DTO de patch com um wrapper tri-state (`Absent | Null | Value`) na camada `http`, convertido para um comando de serviço com flags `hasX`.

### 5.2 Regras de negócio
| Regra | Original | Destino |
|---|---|---|
| CPF e e-mail únicos (409) em criar/atualizar pessoa, cliente completo, barbeiro completo, registro | service | S (+R `findByCpf` / `findByEmail`) |
| Pessoa com vínculo não pode ser excluída (409) | service | S |
| Papel derivado (admin > barbeiro/caixa > cliente) | auth_service | S (`RoleResolver`, puro) + contrato |
| Comissão e `preco_custo` ocultos para não-admin | router | S/H (`ResponseMasking` puro, testado) |
| Disponibilidade: intervalo válido; sem sobreposição no mesmo dia (inclui inativas; `[a,b)`) | service (comparando strings) | **D** `TimeRange.overlaps` |
| Horário do atendimento dentro de uma disponibilidade **ativa** do dia (`DAYOFWEEK`, `hora_inicio ≤ t < hora_fim`) | SQL | **D** `AvailabilityPolicy.covers(LocalDateTime)` + mapeamento `DayOfWeek`→enum PT |
| Conflito de agenda (hoje: mesmo início, exceto CANCELADO) | SQL | **D** `DateTimeInterval.overlaps` com duração (correção P3) |
| `valor_total` do atendimento = Σ `preco_cobrado` | SQL SUM | **D** `Appointment.total()` com `loop_invariant` |
| `valor_total` da venda = Σ `quantidade × preco_unitario` (desconto **ignorado**, N5) | SQL SUM | **D** `Sale.total()` |
| Preço vigente copiado no lançamento; 422 se não houver | service | S + **D** `PriceHistory.current()` |
| Histórico: no máximo **uma** linha vigente por item; ao alterar preço, encerra a vigente (`data_fim = hoje`, `ativo = 0`) e cria nova (`data_inicio = hoje`) | service + SQL | **D** `PriceHistory` (invariante: ≤1 vigente; `data_fim ≥ data_inicio`) |
| Serviço ou produto não pode ser vinculado duas vezes (409) | service | S/D |
| Fidelidade XOR serviço/produto (422) | service | **D** invariante de `LoyaltyRule` (+ DB, decisão P5) |
| Pontos de atendimento = Σ `pontos_acumulados` das regras **ativas** dos serviços (1× por serviço); de venda = Σ `pontos_acumulados × quantidade`. **Observação:** `HISTORICO_*.pontos_gerados` **não** é usado no cálculo | service | **D** `LoyaltyCalculator` |
| Acúmulo só na **transição** para CONCLUIDO / PAGA | service | **D** máquina de estados (correção P2) |
| Saldo = Σ ACUMULA − Σ USA | SQL | **D** `PointsLedger.balance()` (invariante `≥0` se houver resgate) |
| Exclusões bloqueadas por vínculo (409): barbeiro (atendimentos), caixa (vendas), cliente (atendimentos, vendas, pontos), serviço (atendimento), produto (venda) | service | S |
| Cliente só acessa os próprios atendimentos e pontos | router | S (`AccessPolicy`) |
| Criar venda: `status = ABERTA`, `valor_total = 0` | service | S |

### 5.3 Correções a aplicar sem perguntar (política)
- **P1** (§4.2).
- **P2:** máquinas de estado alinhadas com o que o **frontend já oferece** (`StatusActions.tsx`):
  - Atendimento: `AGENDADO → {EM_EXECUCAO, CANCELADO}`, `EM_EXECUCAO → {CONCLUIDO, CANCELADO}`; CONCLUIDO e CANCELADO são terminais. Transição inválida → **409** (proposta; o original não tem código para isso).
  - Venda: `ABERTA → {PAGA, CANCELADA}`, `PAGA → {ESTORNADA}`; CANCELADA e ESTORNADA são terminais.
  - `POST /atendimentos` aceitará só `status = AGENDADO` (outro valor → 422) e `PUT /atendimentos/{id}` com `status` passará pela mesma máquina e pelo crédito de pontos.
  - Transição para o mesmo estado (ex.: PAGA → PAGA) → 409.
- **P3:** intervalo efetivo do atendimento = `[início, início + duração)`, com duração = Σ `duracao_em_minutos` vigentes dos serviços vinculados, mínimo **30 min** (a grade do frontend). Valida na criação, na alteração de horário ou barbeiro e **ao adicionar serviço** (409). `GET /barbeiros/{id}/horarios-ocupados` passa a devolver também os inícios de grade cobertos por atendimentos longos, para o frontend esconder esses horários (mesmo formato). Sub-decisões no §10.
- **P7a:** adicionar ou remover serviço de atendimento CONCLUIDO ou CANCELADO → 409.
- **P7b:** `JWT_SECRET` obrigatório por variável de ambiente (falha ao iniciar sem ele); valor só no `docker-compose` de desenvolvimento, **igual para a API e para o container do frontend** (ver §7).

---

## 6. Formatos de serialização JSON (FastAPI + Pydantic v2)

| Tipo Python | Exemplo de saída | Regra para o serializador Java |
|---|---|---|
| `Decimal` (DECIMAL(10,2)) | `"35.00"` (**string**) | `Money` → string com exatamente 2 casas (`valor_total`, `preco*`, `desconto`, `preco_cobrado`, `preco_unitario`). Os tipos do frontend declaram `string`; ele usa `Number(...)`. |
| `float` (`comissao_percentual`) | `40.0`, `12.5`, `33.33` (**número**) | repr do Python: parte inteira + `.` + casas sem zeros à direita, mínimo de 1 casa. |
| `int` (ids, pontos, quantidade, `saldo`, `saldo_pontos`) | `5` | o SUM do MySQL devolve Decimal, mas o Pydantic converte para int. |
| `bool` (`admin`, `ativo`) | `true` / `false` | TINYINT → bool. |
| `date` | `"1990-03-15"` | ISO. |
| `time` (`hora_inicio`, `hora_fim`) | `"08:00:00"` | sempre com segundos. |
| `datetime` naive | `"2026-06-10T09:00:00"` | ISO sem fuso; microssegundos só se ≠ 0 (DATETIME não tem). |
| enums `Literal` / `Enum` | `"AGENDADO"`, `"SEGUNDA"` | `name()` do enum Java. |
| `None` | `null` | campos opcionais sempre presentes com `null` (não omitir). |
| Ordem das chaves | ordem de declaração no modelo Pydantic (classe base primeiro) | Serializador com mapa ordenado (`LinkedHashMap`-like). Ex.: `PessoaResponse` = `nome, cpf, email, data_nascimento, admin, id_pessoa`. |
| Erro de negócio | `{"detail": "Cliente nao encontrado"}` | mensagens idênticas (ASCII, sem acento). |
| Erro de validação 422 | `{"detail":[{"type":"missing","loc":["body","nome"],"msg":"Field required","input":{...}}]}` | reproduzir a estrutura (`type`, `loc`, `msg`, `input`); o frontend só converte para `Error` (mensagem `[object Object]`), então mensagens aproximadas bastam. |
| Rota inexistente / método inválido | 404 `{"detail":"Not Found"}` / 405 `{"detail":"Method Not Allowed"}` | idem. |
| Exceção não tratada | 500 `Internal Server Error` (texto puro, sem CORS) | Java: 500 `{"detail":"Internal Server Error"}` (divergência cosmética, documentar). |
| 204 | corpo vazio | idem. |
| Barra final (`/atendimentos/`) | 307 redirecionando para sem barra | reproduzir ou aceitar as duas formas (documentar). |

**Cookies:** login e registro enviam `Set-Cookie: access_token=<jwt>; HttpOnly; Path=/; SameSite=lax` (sem `Max-Age` nem `Secure`). O logout envia `access_token=""; expires=Thu, 01 Jan 1970 00:00:00 GMT; Max-Age=0; Path=/; SameSite=lax`.

**CORS (Starlette `CORSMiddleware`):** origem permitida = `FRONTEND_URL` (padrão `http://localhost:3000`); `Access-Control-Allow-Credentials: true`; o preflight `OPTIONS` responde 200 com `Allow-Methods: DELETE, GET, HEAD, OPTIONS, PATCH, POST, PUT`, `Allow-Headers` ecoando o que foi solicitado e `Max-Age: 600`; respostas simples incluem `Access-Control-Allow-Origin: <origem>` e `Vary: Origin`.

**Fuso horário:** tudo é *naive*. `date.today()` (histórico de preços), `datetime.now()` (venda fictícia) e `NOW()` do MySQL (movimentação de pontos) usam o relógio do container, que é **UTC** no Docker. Em Java: `java.time.Clock` injetado e configurável (`APP_TIMEZONE`), com padrão igual ao do original (fuso do sistema). O deslocamento de 3h no `toISOString()` do frontend fica **só documentado**.

---

## 7. Autenticação: senhas e JWT

### 7.1 Hash de senha hoje
- `bcrypt.hashpw(..., gensalt())` (custo 12, formato `$2b$12$…`, 60 caracteres). Verificação com `bcrypt.checkpw`. Limite de 72 bytes, daí `max_length=72`.
- Hashes de teste: em `seed.sql`, só 3 pessoas têm senha. As credenciais também estão no `README.md`:
  - `roberto@email.com` / `admin123` (admin; também é caixa)
  - `marcos@email.com` / `func123` (barbeiro → funcionário)
  - `carlos@email.com` / `cliente123` (cliente)
- Os testes pytest usam senhas próprias (`test_security.py`, `test_auth_service.py`), com hash gerado na hora.

### 7.2 PBKDF2 em Java
- Formato armazenado: `pbkdf2_sha256$<iterações>$<salt_base64>$<hash_base64>`, com 16 bytes de salt e 32 de hash. São cerca de 95 caracteres, **cabe em `VARCHAR(255)`**: não é preciso mudar o schema.
- 600.000 iterações (recomendação OWASP para PBKDF2-HMAC-SHA256) em produção e no seed; configurável e com valor baixo nos testes.
- Comparação em tempo constante (`MessageDigest.isEqual`). Contrato da interface: `verify(hash(p), p) == true`; `verify(h, p) == false` se `h` não estiver no formato.
- Regeneração do seed: um utilitário (`app.SeedPasswordTool`) gera os 3 hashes; o `db/seed.sql` do projeto Java recebe os novos valores (as mesmas senhas em texto). Um banco MySQL com volume antigo (bcrypt) **não** fará login: documentar `docker compose down -v`. Os repositórios em memória carregam o mesmo seed já em PBKDF2.

### 7.3 JWT
- PyJWT HS256. Header `{"alg":"HS256","typ":"JWT"}`; payload `{"sub":"<id_pessoa como string>","role":"admin|funcionario|cliente","exp":<epoch em segundos>}`; `exp = agora + JWT_EXPIRE_MINUTES` (padrão 60). Base64url sem padding.
- `middleware.ts` (jose `jwtVerify`): valida a assinatura com `process.env.JWT_SECRET` (ou o padrão escrito no código `dev-secret-troque-em-producao-32-bytes+`), valida `exp` e lê `payload.role`. Rotas staff exigem `admin|funcionario`; `/barbeiros/novo` e `/barbeiros/{id}/editar` exigem admin.
- **Achado:** o `docker-compose.yml` original **não** passa `JWT_SECRET` ao container do frontend. Se a API usar o `.env` (do `.env.example`), os segredos divergem e o middleware rejeita todo token. Em Java, o compose passará **o mesmo** `JWT_SECRET` aos dois serviços (mudança só no compose, não no código do frontend).
- Na API, o papel é **re-derivado do banco** a cada requisição (o claim `role` é ignorado), e `sub` inexistente → 401 "Usuario nao encontrado". Manter.

---

## 8. Mapa Python → Java

| Python | Java |
|---|---|
| `int` (ids) | `int`; ids gerados pelo repositório (AUTO_INCREMENT / contador em memória) |
| `Decimal` dinheiro | `Money` (centavos `long`, imutável) |
| `float` comissão | `Percentage` (centésimos `long`; serializado como float do Python) |
| `str \| None` | `String` com `/*@ nullable @*/` |
| `X \| None` de busca no repositório | retorno `null` + contrato (`ensures \result == null \|\| \result.id() == id`); evitar `Optional` nas classes verificadas (melhor suporte do OpenJML) |
| `date` / `time` / `datetime` naive | `LocalDate` / `LocalTime` / `LocalDateTime` + `Clock` injetado |
| `Literal[...]` / `Enum` | `enum` Java com os mesmos nomes |
| `dict` de linha | classe de domínio imutável ou com métodos de alteração |
| `HTTPException(status, detail)` | hierarquia `DomainException` em `service` (`NotFound` 404, `Conflict` 409, `BusinessRule` 422, `Forbidden` 403, `Unauthorized` 401), cada uma com o `detail` original; o `http` mapeia para status e JSON |
| `RequestValidationError` | `ValidationException` (só no `http`) → 422 com lista de erros |
| `Depends(get_db)` / transação | `TransactionRunner` (§8.1) |
| `Depends(require_*)` | `AuthContext` resolvido no roteador + `AccessPolicy` (puro) chamado pelo handler |
| `model_dump(exclude_unset=True)` | wrapper tri-state no DTO → comando com flags |
| `conn.cursor(dictionary=True)` | `PreparedStatement` + `ResultSet` mapeado à mão (`repository.jdbc`) |

### 8.1 Desenho do `TransactionRunner`

```java
public interface TransactionRunner {
    //@ requires work != null;
    //@ ensures (* se work lançar, nenhum efeito persiste *);
    <T> T inTransaction(TransactionalWork<T> work);
}
@FunctionalInterface
public interface TransactionalWork<T> { T run(); }
```
- **Propagação REQUIRED:** chamada aninhada participa da transação externa (necessário porque `atendimento_service` chama `historico_pontos_service`).
- **Memória** (`InMemoryTransactionRunner`): um `ReentrantLock` global serializa as transações. Ao entrar no nível mais externo, cada repositório `Snapshotable` registrado tira um snapshot (cópia das estruturas); em exceção, `restore()`. Leituras fora de transação também tomam o lock (consistência simples, volume pequeno).
- **JDBC** (`JdbcTransactionRunner`): pega uma conexão do pool, `setAutoCommit(false)`, publica no `ConnectionContext` (ThreadLocal) e, ao terminar, `commit()` ou `rollback()`. No `finally`, restaura `autoCommit=true` e devolve ao pool. Os repositórios JDBC usam a conexão do contexto, se houver; senão, pegam uma emprestada para a operação (autocommit), espelhando o original.
- Exceções de negócio (`DomainException`) e qualquer `RuntimeException` causam rollback e são propagadas.

### 8.2 Desenho do pool próprio (`SimpleConnectionPool`)
- Tamanho fixo **5**, criação preguiçosa como no original (ou na primeira chamada de `borrow`).
- Estado: `Connection[] all`, `boolean[] borrowed`, `int borrowedCount`. Sincronização com `synchronized` + `wait/notifyAll` (sem `java.util.concurrent` nas partes especificadas).
- `borrow(timeoutMillis)`: espera uma conexão livre; valida com `isValid(2)` e recria se estiver quebrada; timeout → `PoolExhaustedException`.
- `release(c)`: se `!getAutoCommit()`, faz `rollback()` e restaura `autoCommit=true` (equivale ao rollback do `get_db`); marca a conexão como livre e notifica.
- Contratos: `invariant borrowedCount + freeCount() == size && 0 <= borrowedCount <= size`; `borrow` garante `borrowedCount == \old(borrowedCount)+1`; `release` de conexão não emprestada → `IllegalArgumentException`.
- `close()` fecha todas as conexões (shutdown hook no `Main`).
- **Sem proxy dinâmico** (reflexão): o repositório devolve a conexão explicitamente via `ConnectionContext` ou `try-finally`.

---

## 9. Novos achados (não listados na análise prévia)

| # | Achado | Impacto | Política proposta |
|---|---|---|---|
| N1 | `GET /caixas` é só admin, mas `useVendaLookups` (formulário de venda) chama a rota. **O funcionário não consegue abrir o formulário de nova venda.** | Fluxo do frontend quebrado para funcionário | **Decisão**: liberar `GET /caixas` e `GET /caixas/{id}` para func (escrita continua adm) |
| N2 | O extrato de pontos do frontend espera `id_historico`, `tipo_movimentacao` `"acumulo"\|"resgate"` e `descricao`; a API devolve `id_movimentacao` e `"ACUMULA"\|"USA"`. **A tela de pontos falha** ("Resposta inválida…") sempre que há movimentações. | Fluxo quebrado no original | **Decisão**: (a) paridade estrita (quebrado); (b) acrescentar `id_historico` (= id) e `descricao` (`null`) mantendo os campos atuais; (c) além de (b), mudar `tipo_movimentacao` para minúsculo, o que quebra paridade com a API Python |
| N3 | Exclusões que esbarram em FK RESTRICT viram **500**: serviço/produto (sempre, por causa do histórico), venda com pontos, regra usada | Erros 500 | **Decisão**: devolver 409 com mensagem clara (sem mudar o schema) **ou** excluir o histórico junto |
| N4 | `POST /clientes/completo` descarta `preferencias` e `observacoes` | Perda silenciosa de dados | **Decisão** (recomendo corrigir: gravar os campos) |
| N5 | `desconto` da venda nunca é abatido do `valor_total` | Total incorreto | **Decisão**: `valor_total = max(0, Σ itens − desconto)` ou manter |
| N6 | Adicionar ou remover produto em venda PAGA, CANCELADA ou ESTORNADA é permitido | Total de venda paga alterado | **Decisão** (análogo ao P7a; recomendo bloquear com 409) |
| N7 | Várias regras de fidelidade **ativas** para o mesmo item são permitidas; o cálculo pega uma arbitrária (`fetchone`) | Pontuação não determinística | **Decisão**: no máximo 1 regra ativa por item (409) |
| N8 | `POST /disponibilidades` ignora o campo `ativo` (sempre grava 1) | Menor | **Decisão** (recomendo respeitar o campo) |
| N9 | Regra de fidelidade ou telefone duplicado com FK inexistente → 500 | Menor | Recomendo 404 / 409 (decisão em bloco com N3) |
| N10 | `PUT /servicos` e `PUT /produtos` criam nova linha de histórico mesmo sem mudança de valores; duas alterações no mesmo dia geram linhas com o mesmo `data_inicio` | Histórico poluído, mas o invariante de 1 vigente se mantém | Manter (paridade) e documentar; o contrato JML exige só "≤1 vigente" e `data_fim ≥ data_inicio` |
| N11 | Qualquer funcionário edita a disponibilidade de qualquer barbeiro; a verificação de sobreposição considera disponibilidades inativas | Menor | Manter (paridade) |
| N12 | Os testes pytest **nunca** acessam o MySQL (a fixture `db_conn` não é usada; tudo é fake ou monkeypatch) | Não há teste de integração real | A suíte abstrata de contratos (memória + MySQL) cobre essa lacuna |

---

## 10. Pontos de decisão de modelagem (aguardando sua escolha)

### Item 4 — Venda fictícia ao concluir atendimento
| Opção | Descrição | Prós | Contras |
|---|---|---|---|
| **A** (recomendada) | `HISTORICO_PONTOS.VENDA_id_venda` passa a aceitar NULL e ganha a coluna `ATENDIMENTO_id_atendimento` (FK, NULL), com a regra "exatamente uma origem" (CHECK + contrato JML) | Modelo correto; sem venda fantasma; não depende de caixa; ótimo alvo de invariante XOR | Muda o schema (continuam 16 tabelas); `VENDA_id_venda` pode vir `null` (o frontend não usa esse campo) |
| B | Manter a venda fictícia, mas escondê-la de `GET /vendas` e do faturamento | Sem mudar o schema | Continua dependendo de caixa (422); a regra fica artificial e difícil de especificar |
| C | Não creditar pontos por atendimento | Simples | Perde funcionalidade; as regras de fidelidade de serviço ficam inúteis |
| D | Paridade estrita (como no original) | Zero divergência | Mantém o bug; o contrato JML teria de descrever um comportamento incorreto |

### Item 5 — Garantia no banco da regra XOR de fidelidade
| Opção | Descrição | Prós | Contras |
|---|---|---|---|
| **A** (recomendada) | `CHECK ((PRODUTO_id_produto IS NULL) <> (SERVICO_id_servico IS NULL))` em FIDELIDADE (MySQL ≥ 8.0.16 aplica CHECK) | Declarativo, curto, fácil de testar; casa com o invariante JML | Não é TRIGGER (se a disciplina de BD exigir trigger, ver B) |
| B | TRIGGER `BEFORE INSERT` / `BEFORE UPDATE` com `SIGNAL SQLSTATE '45000'` | Bate com o que o CLAUDE.md original prometia | Mais código SQL; `DELIMITER` no script de init; mais difícil de manter |
| C | Só service + JML (como hoje) | Sem mudar o schema | Sem defesa em profundidade |

### Item 6 — Resgate de pontos (USA)
| Opção | Descrição | Prós | Contras |
|---|---|---|---|
| **A** (recomendada) | Implementar no domínio e no serviço: resgatar a regra R custa `R.pontos_uso`; exige saldo ≥ custo; registra USA. Expor um endpoint **novo e aditivo** (`POST /clientes/{id}/pontos/resgates`), documentado como divergência | Excelente alvo de verificação (`invariant saldo ≥ 0`, `ensures saldo == \old(saldo) - custo`); não quebra o frontend | Endpoint que o frontend não usa; a origem do resgate depende do item 4 (com 4A, o resgate pode apontar para atendimento ou venda) |
| B | Só domínio e serviço, sem endpoint HTTP | Contratos e testes sem nova superfície de API | Código sem uso em runtime |
| C | Não implementar; só documentar | Menor esforço | Perde o melhor exemplo de invariante de saldo |
| Sub-decisão | Estorno (`PAGA → ESTORNADA`): estornar os pontos acumulados? | Opções: (i) registrar USA compensatório (exige saldo suficiente); (ii) bloquear o estorno se os pontos já foram usados; (iii) não mexer nos pontos | — |

### Sub-decisões do P3 (correção já autorizada; detalhes a confirmar)
1. Duração mínima de um atendimento sem serviços: **30 min** (a grade do frontend)?
2. Exigir que o **fim** do atendimento também caia dentro da disponibilidade (ex.: 16:30 + 60 min com a agenda até 17:00 → 422)? O original só verifica o início.
3. Ao adicionar um serviço que estende o atendimento sobre outro → **409** (o atendimento já criado permanece, sem o serviço). OK?
4. Código para transição de status inválida (P2): **409** (proposto) ou 422?

---

## 11. Testes pytest e plano de portabilidade

| Pasta | Testes | Como acessam | Plano em Java |
|---|---|---|---|
| `tests/routers` | 172 | `TestClient` + `dependency_overrides` (usuário e conexão falsos) + `monkeypatch` do service | **Etapa 9:** testes HTTP JUnit contra o servidor real em memória (porta efêmera) com o seed; um teste por rota × papel × erro. Cobrem status, formato JSON e permissões. |
| `tests/services` | 225 | `FakeConn` + monkeypatch dos repositórios | **Etapa 4:** testes de serviço com repositórios em memória (sem mocks), um por regra; as divergências (P1, P2, P3…) ganham testes novos. |
| `tests/repositories` | 143 | `FakeCursor` verificando **o texto do SQL** e os parâmetros | Não portáveis 1:1 (testam a implementação). Substituídos pela **suíte abstrata de contratos** (Etapa 3), executada contra memória e MySQL (Etapa 8). |
| raiz (`test_security`, `test_dependencies`, `test_database`, `test_main`, `test_schema_relacional_aprovado`, `*coverage_gaps`) | 31 | unitários | `PasswordHasher`, `JwtCodec`, `AccessPolicy`, pool, `/health` e um teste que confere colunas e enums do `db/schema.sql`. |
| **Total** | **571** | — | Meta: JaCoCo ≥ 90% nos pacotes `domain` e `service` (o original exige 100%; aqui a meta é alta, não obrigatória). |

Os testes Cypress do frontend (13 specs) mockam a API com `cy.intercept()`. Servem para a UI, não para a paridade da API. A validação dos fluxos na Etapa 9 será manual e roteirizada (login nos 3 papéis, agendamento público, CRUDs, venda, pontos), com o frontend original apontando para a API Java.

---

## 12. Divisão das etapas seguintes (ajustada)

- **Etapa 1 — Esqueleto.** `pom.xml` (Connector/J, JUnit 5, Surefire, JaCoCo, `maven.compiler.release=17`). A máquina tem JDK 23 instalado; compilar com `--release 17`. Estrutura de pacotes, `Config` (variáveis de ambiente), `db/schema.sql` e `db/seed.sql` copiados do original, `TransactionRunner` com a interface e a versão em memória, `scripts/openjml-check.sh` (placeholder) e `README.md`.
- **Etapa 2 — Domínio.** `Money`, `Percentage`, `TimeRange`, `DateTimeInterval`, `DayOfWeekPt`, enums de status com `canTransitionTo`, `Appointment`/`AppointmentItem`, `Sale`/`SaleItem`, `PriceHistory` (serviço e produto), `LoyaltyRule`, `LoyaltyCalculator`, `PointsLedger`, `AvailabilityPolicy`, `RoleResolver`, `AccessPolicy`, `ResponseMasking` + exceções. Tudo com JML e JUnit.
- **Etapa 3 — Repositórios.** Interfaces com contratos para os 16 agregados e tabelas, implementações em memória `Snapshotable`, `SeedLoader` (seed equivalente, senhas PBKDF2) e `AbstractXRepositoryContractTest`.
- **Etapa 4 — Serviços** (uma subetapa por vez, com pausa):
  - 4a auth / pessoas / telefones / clientes / caixas (P1, N1, N4);
  - 4b catálogo: serviços, produtos, histórico (N3, N10);
  - 4c barbeiros e disponibilidades (N8);
  - 4d atendimentos e agenda (P2, P3, P7a);
  - 4e vendas (P2, N5, N6);
  - 4f fidelidade e pontos (itens 4, 5 e 6, N2, N7).
- **Etapa 5 — HTTP.** `HttpServer` + `ExecutorService` fixo, roteador com parâmetros de caminho, `http.json` (parser e serializador), DTOs record com validação estilo Pydantic, `JwtCodec` (HS256 com `Mac`), `Pbkdf2PasswordHasher`, CORS, mapeamento de erros e `AppFactory` (`REPOSITORY=memory|mysql`).
- **Etapa 6 — Verificação JML.** Primeiro testar a compatibilidade do OpenJML com o Java 17 numa classe pequena: as versões recentes do OpenJML trazem JDK próprio e podem exigir que as classes verificadas evitem records, `switch` expressions e lambdas. Depois, `verification/targets.txt`, scripts e `docs/verification/RESULTS.md`.
- **Etapa 7 — Entrega.** `docs/entrega/` (01–05), PlantUML, métricas, `scripts/package.sh` e teste do zip.
- **Etapa 8 — MySQL.** `SimpleConnectionPool`, repositórios JDBC, `JdbcTransactionRunner`, suíte de contratos contra o MySQL (container do docker-compose), schema ajustado (itens 4 e 5, se aprovados), seed PBKDF2, `Dockerfile` e `docker-compose.yml` (MySQL + API Java + frontend original, com o mesmo `JWT_SECRET` nos dois).
- **Etapa 9 — Paridade.** Testes HTTP das 73 rotas, comparação lado a lado com a API Python (script que faz as mesmas requisições nas duas e compara status e JSON), roteiro de fluxos do frontend, `docs/DIVERGENCES.md` final, cobertura e zip regenerado.

## 13. Pendências desta etapa
- O diretório `sig-babershop-java` **não é repositório git**: não houve commit. Confirmar se deve ser criado (`git init` + remoto no GitHub para as issues do `PLAN.md`).
- Respostas às decisões do §10 (itens 4, 5, 6 e sub-decisões do P3) e aos achados N1–N9 do §9.
- Planilha de quantitativos (placeholder do prompt).
- ~~Orientações JML da disciplina~~ → recebidas (Aula 18) e consolidadas em [`docs/jml-guidelines.md`](jml-guidelines.md). Impactos no plano: `\sum`/`\numof` **não** são suportados pelo ESC (totais via acumulador + `maintaining` ou `ghost`); interfaces de repositório especificadas com **model fields** + `represents`; padrão `non_null`; aritmética *safe* exige limites de overflow nos `long` de dinheiro.
- ~~Scripts `.bat`~~ → desnecessários: o OpenJML só roda em macOS/Linux (Windows apenas via WSL), então a demonstração usa os scripts `.sh`.
