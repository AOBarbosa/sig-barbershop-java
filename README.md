# sig-barbershop-java

Backend do **sig-barbershop** (sistema de gestão de barbearia) reescrito em **Java 17 puro** — sem Spring ou qualquer framework — com regras de negócio especificadas em **JML** e verificadas com **OpenJML** (ESC estático e RAC em runtime).

Projeto da disciplina *Lógica Aplicada à Engenharia de Software* (UFRN). Versão original (Python/FastAPI + MySQL) desenvolvida na disciplina de Banco de Dados; o frontend Next.js original continua consumindo a mesma API REST.

> **Status:** esqueleto criado. Nenhuma funcionalidade implementada ainda. Veja o andamento em [`docs/MIGRATION_PLAN.md`](docs/MIGRATION_PLAN.md) e o planejamento das issues em [`PLAN.md`](PLAN.md).

## Stack
| Função | Escolha |
|---|---|
| Linguagem | Java 17 (compilado com `--release 17`) |
| Build | Maven |
| HTTP | `com.sun.net.httpserver.HttpServer` + `ExecutorService` |
| Banco | MySQL 8 via JDBC puro (MySQL Connector/J) + pool próprio |
| JSON / JWT / senha | implementação própria (`javax.crypto`: HMAC-SHA256 e PBKDF2) |
| Testes | JUnit 5 + JaCoCo |
| Especificação/verificação | JML + OpenJML |

Dependências permitidas: **somente** MySQL Connector/J e JUnit 5 (mais plugins de build).

## Estrutura
```
src/main/java/br/ufrn/sigbarbershop/
├── domain/              regras de negócio puras (alvo principal do ESC)
├── repository/          interfaces com contratos JML
│   ├── memory/          implementação em memória
│   └── jdbc/            implementação MySQL + pool de conexões
├── service/             casos de uso, transações, exceções de domínio
├── http/                servidor, roteador, handlers, DTOs, JWT, CORS
│   └── json/            parser/serializador JSON próprio
└── app/                 configuração e injeção de dependência (AppFactory, Main)
db/                      schema.sql e seed.sql (copiados do projeto original)
scripts/                 scripts de verificação/empacotamento
verification/            lista de classes verificadas pelo ESC
docs/                    documentação (em português)
```

## Pré-requisitos
- JDK 17 ou superior (o build usa `--release 17`).
- Maven 3.9+.
- OpenJML (instruções serão adicionadas na Etapa 6). Roda em macOS e Linux; no Windows, somente via WSL.

## Comandos
```bash
mvn -q compile        # compila
mvn -q test           # testes unitários
mvn verify            # testes + relatório de cobertura (target/site/jacoco)
scripts/openjml-check.sh   # placeholder da verificação JML
```

## Documentação
- [`PLAN.md`](PLAN.md) — planejamento e issues.
- [`docs/MIGRATION_PLAN.md`](docs/MIGRATION_PLAN.md) — análise do sistema original, inventário de endpoints, decisões.
- [`docs/jml-guidelines.md`](docs/jml-guidelines.md) — diretrizes de especificação JML do projeto.

## Equipe
André Barbosa e Fernando.
