# Diretrizes JML do projeto

Baseadas no material da disciplina (*Aula 18 — JML / OpenJML*, Lógica Aplicada à Engenharia de Software) e nas regras do `PLAN.md`. Valem para todo código em `domain`, `service` e nas interfaces de `repository`.

## 1. Sintaxe
- Contratos **antes** do método/campo, em `//@ ...` ou `/*@ ... @*/`, **sem espaço** entre `//` ou `/*` e `@` (`// @` vira comentário comum e o contrato é ignorado silenciosamente).
- Não usar anotações Java dentro de comentário JML (`//@Override` é erro).
- Ordem recomendada das cláusulas: `requires` → `assignable` → `ensures` → `signals`/`signals_only`.
- Preferir **várias cláusulas** curtas a uma grande com `&&` (mensagens de erro melhores).
- Dentro de `requires`/`ensures`, cláusulas anteriores podem garantir a boa definição das posteriores (ex.: `requires a != null;` antes de `requires 0 <= i < a.length;`).

## 2. O que todo método público deve ter
| Tipo de método | Especificação mínima |
|---|---|
| Getter / consulta sem efeito | `//@ pure` + `ensures \result == ...` |
| Consulta usada em outros contratos | `pure` (retorno primitivo) ou `spec_pure` (retorno objeto) |
| Comando (altera estado) | `requires`, **uma** cláusula `assignable` (interseção se houver várias), `ensures` com `\old(...)` |
| Pode falhar por regra de negócio | `public normal_behavior` **also** `public exceptional_behavior` com `signals_only` (pré-condições **disjuntas**; sobreposição é erro) |
| Construtor | `public normal_behavior`, `ensures` nos campos, `pure` se só inicializa o próprio objeto |
| Auxiliar privado que não preserva invariantes | `helper` (não assume nem garante invariantes) — usar com parcimônia |

## 3. Invariantes, `initially` e `constraint`
- Invariantes de classe `public invariant` sobre campos `private /*@ spec_public @*/` (ou atributos de modelo — §6).
- Todo construtor deve estabelecer e todo método público preservar os invariantes (ex.: `PriceHistory`: no máximo uma linha vigente).
- `constraint` para restrições de história (ex.: `id` nunca muda; total de pontos acumulados nunca diminui).
- Cuidado com chamadas que saem do objeto no meio de uma atualização (o invariante é exigido na chamada).

## 4. Nulidade
- O padrão do JML é **`non_null`**. Tudo que puder ser `null` deve ser marcado `/*@ nullable @*/` (campos opcionais de entidades, retorno de `findById`).
- Arrays: `/*@ nullable @*/ T /*@ non_null @*/ []` quando o array existe mas os elementos podem faltar.
- Não usar `nullable_by_default` nas classes verificadas (perde-se a garantia gratuita).

## 5. Aritmética
- Código Java roda em modo **safe**: o ESC aponta qualquer overflow possível. Especificações usam **bigint** (matemática).
- Dinheiro em centavos (`long`): toda soma/multiplicação precisa de `requires` limitando operandos (ex.: `requires 0 <= qty <= 10_000 && 0 <= unitCents <= 100_000_000;`).
- Não desativar avisos com `code_java_math` — overflow aqui é bug, não intenção.

## 6. Interfaces de repositório: atributos de modelo
- Especificar interfaces com `//@ public model instance ...` e `represents` nas implementações (memória e JDBC), para o contrato ser **o mesmo** nas duas.
- Usar `\datagroup` para condições de quadro abstratas (`assignable contents;`).
- Implementações **herdam** a especificação; refinamentos só com `also` (pré-condição mais fraca, pós-condição mais forte). Nunca fortalecer pré-condição em subtipo.

## 7. Laços
- Todo laço em classe verificada tem:
  - `maintaining` (ou `loop_invariant`) com o **intervalo do índice** (`0 <= i <= n`) **e** o predicado indutivo do que já foi feito;
  - `loop_writes` com o que o corpo altera;
  - `decreases` com expressão natural que diminui (ex.: `n - i`).
- Em `for-each`/`while`, usar `\count`.
- **`\sum`, `\product` e `\numof` não são suportados pelo ESC**: para totais (valor do atendimento/venda, saldo de pontos) usar acumulador + invariante de laço, ou variável fantasma (`ghost` + `set`), ou função `pure` recursiva especificada. `\sum` pode aparecer só onde basta RAC.

## 8. Aliasing e exposição de representação
- Construtores/setters que recebem arrays ou listas fazem **cópia defensiva** e declaram `ensures \fresh(campo)`.
- Getters de coleções devolvem cópia ou estrutura imutável.
- Métodos com dois parâmetros do mesmo tipo mutável devem considerar `requires this != outro` quando relevante.

## 9. `assert` e `assume`
- `assert` (JML ou Java — o OpenJML interpreta o `assert` do Java) é bem-vindo como lema intermediário.
- `assume` **só** como andaime temporário. Verificação só é considerada concluída sem nenhum `assume` (ou com todos trocados por `assert`). Os que sobrarem vão para `docs/jml-notes.md` com justificativa.

## 10. Estilo de código para classes alvo do ESC
- Classes (não records) no domínio; imutáveis quando possível (`final`, sem setters).
- Laços `for` simples; sem streams, lambdas complexos, reflexão ou anotações mágicas.
- Métodos curtos; uma responsabilidade por método.
- Enums para estados, com transições num método `pure` (`canTransitionTo`) totalmente especificado.
- Datas com `java.time` (`LocalDate`, `LocalTime`, `LocalDateTime`), relógio injetado (`Clock`) — nada de `now()` direto no domínio.
- Infraestrutura (JDBC, JSON, HTTP, JWT, hash) fora do ESC: contratos nas interfaces + RAC/testes.

## 11. Execução do OpenJML (referência)
- `openjml --esc <arquivos>` (estático) e `openjml --rac <arquivos>` (dinâmico, depois executar com o runtime do OpenJML no classpath).
- Opções úteis: `--progress`, `--class-path`, `--source-path`, `--specs-path`, `--quiet`; `--nullable-by-default` **não** será usado.
- Sistemas suportados: macOS e Linux. **Windows apenas via WSL ou VM** → os scripts do projeto são `.sh`.
- Depuração: `//@ show expr;` dentro do método exibe valores do contraexemplo.

## 12. Checklist de revisão de PR (JML)
- [ ] Todo método público de `domain`/`service`/interfaces de `repository` tem contrato.
- [ ] Contratos descrevem a regra de negócio **correta** (não o comportamento bugado do Python).
- [ ] Nenhum `// @` com espaço; nenhum `assume` sem registro em `docs/jml-notes.md`.
- [ ] `nullable` explícito onde há `null`.
- [ ] Limites de overflow nas operações com `long`/`int`.
- [ ] Laços com invariante, `loop_writes` e `decreases`.
- [ ] `normal_behavior`/`exceptional_behavior` com pré-condições disjuntas.
- [ ] Testes JUnit cobrindo os casos normal e excepcional.
