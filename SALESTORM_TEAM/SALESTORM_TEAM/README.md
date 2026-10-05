# SALESTORM - Flash-Sale System Design Submission

**Problem:** 10,000 concurrent buyers, 100 units; no overselling, no duplicate payments/orders, safe recovery.
**Core idea:** a funnel (CDN/waiting room -> gateway -> Redis atomic stock gate -> Postgres conditional update -> idempotent payment -> outbox/Kafka -> idempotent order) so contention is resolved in one place and every step is retry-safe.

| Folder | Contents |
|---|---|
| 01_Requirements | Functional/non-functional requirements, assumptions, capacity |
| 02_HLD | Context, container, component, deployment diagrams, bottlenecks |
| 03_LLD | Class, 3 sequence diagrams, state diagrams |
| 04_Database | ER diagram, DDL (`schema.sql`) |
| 05_API | `openapi.yaml`, events and ownership |
| 06_SOLID | SOLID mapping |
| 07_Design_Patterns | Pattern mapping and trade-offs |
| 08_Scalability_Reliability | 10k/100 walkthrough, 50x, failure handling |
| 09_Security_Observability | Security controls, metrics, logs, tracing |
| 10_ADR | Architecture decisions |
| 12_Presentation | 5-minute pitch deck |

Diagrams are Mermaid (render in GitHub/VS Code or mermaid.live).
