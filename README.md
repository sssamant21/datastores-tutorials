# Datastores Tutorials

Production-oriented tutorials, hands-on labs, runbooks, and practical use cases for datastore administrators, DBREs, SREs, developers, and application/data engineering teams.

## Datastores

- **Elasticsearch** — administration, DBRE/SRE operations, mapping governance, query performance, troubleshooting, hands-on labs, runbooks, and production use cases.
- **MongoDB** — administration, operations, troubleshooting, labs, runbooks, and use cases.
- **Snowflake** — administration, security, performance, troubleshooting, labs, runbooks, and data-platform use cases.
- **PostgreSQL** — administration, DBRE/SRE operations, performance, troubleshooting, labs, runbooks, and use cases.
- **Kafka** — administration, reliability, performance, troubleshooting, labs, runbooks, and streaming use cases.
- **Redis** — focused initially on caching architecture, operations, troubleshooting, labs, and caching use cases.

## Repository Philosophy

This repository is intentionally practice-first rather than book-first. Content should help engineers understand a concept, reproduce it in a lab, operate it safely, troubleshoot failures, and apply it to realistic production scenarios.

Each datastore area is organized around four primary content types:

1. **Tutorials** — concepts explained through practical examples.
2. **Hands-on Labs** — reproducible exercises and experiments.
3. **Runbooks** — production operational and troubleshooting procedures.
4. **Use Cases** — end-to-end implementation patterns and realistic scenarios.

## Initial Focus

The first learning track is **Elasticsearch for Administrator / DBRE / SRE**. Mapping and query performance are treated as core operational responsibilities because both directly affect cluster stability, resource consumption, scalability, and production reliability.

## Structure

```text
datastores-tutorials/
├── elasticsearch/
├── mongodb/
├── snowflake/
├── postgresql/
├── kafka/
├── redis/
└── README.md
```

Each datastore directory will grow independently while following the same practical learning model.
