# Databricks Cloud-Aware Tutorial Matrix

## Purpose

The Databricks tutorial track uses a **common-core + cloud-specific implementation** model.

- Teach Databricks concepts once in the main tutorial series.
- Add AWS, Azure, or GCP guidance only when architecture, identity, networking, storage, security, deployment, or operations materially differ.
- Do not duplicate an entire tutorial simply to change cloud-provider terminology.
- Validate cloud-specific implementation guidance against current official Databricks documentation before marking a tutorial canonical.

## Cloud-aware rule

| Classification | Meaning | Repository location |
|---|---|---|
| Common | Concept and workflow are materially cloud-independent | `databricks/part-*` |
| Common + Cloud Notes | Core tutorial is common, with short AWS/Azure/GCP differences | Main tutorial + links to `databricks/cloud/` where needed |
| Cloud Implementation | Implementation materially differs by cloud | `databricks/cloud/aws`, `azure`, or `gcp` |

## Provider mapping

| Concern | AWS | Azure | GCP |
|---|---|---|---|
| Primary object storage | Amazon S3 | Azure Data Lake Storage Gen2 / Azure Storage | Google Cloud Storage |
| Cloud identity foundation | AWS IAM | Microsoft Entra ID + Azure identity mechanisms | Google Cloud IAM / service accounts |
| Network construct | VPC | VNet | VPC |
| Private-connectivity concepts | AWS PrivateLink and provider-specific private networking | Azure Private Link / private endpoints and provider-specific networking | Private Service Connect and provider-specific private networking |
| Unity Catalog external-storage access | Storage credentials + external locations using AWS-specific authentication | Storage credentials + external locations using Azure-specific authentication | Storage credentials + external locations using GCP-specific authentication |

The table is a learning map, not a complete deployment specification. Exact supported features, authentication methods, networking patterns, and serverless/classic behavior must be validated for the target cloud and region.

## Tutorial matrix

| Tutorial | Classification | AWS | Azure | GCP | Notes |
|---|---|---:|---:|---:|---|
| 1.1 What Is Databricks? | Common | — | — | — | Platform introduction |
| 1.2 Lakehouse Architecture Fundamentals | Common + Cloud Notes | ✓ | ✓ | ✓ | Object-storage and identity examples differ |
| 1.3 Databricks Platform Architecture | Common + Cloud Notes | ✓ | ✓ | ✓ | Control/compute planes, classic/serverless and workspace storage require cloud-aware treatment |
| 1.4 Workspace Fundamentals | Common + Cloud Notes | ✓ | ✓ | ✓ | Workspace provisioning and administration differ |
| 1.5 Compute Fundamentals | Common + Cloud Notes | ✓ | ✓ | ✓ | Compute concepts are common; infrastructure/networking details differ |
| 1.6 Notebook Fundamentals | Common | — | — | — | Authoring concepts are largely common |
| 2.x Delta Lake & Data Fundamentals | Common + Cloud Notes | ✓ | ✓ | ✓ | Storage paths/integration differ; Delta concepts remain common |
| 3.x Unity Catalog & Governance | Common + Cloud Implementation | ✓ | ✓ | ✓ | Storage credentials, external locations and IAM integration differ |
| 4.x Data Engineering | Common + Cloud Notes | ✓ | ✓ | ✓ | Source integrations and cloud ingestion services can differ |
| 5.x Databricks SQL | Common + Cloud Notes | ✓ | ✓ | ✓ | Core SQL concepts common; networking/integration can differ |
| 6.x Performance & Cost | Common + Cloud Implementation | ✓ | ✓ | ✓ | Pricing, VM families, egress and storage economics differ |
| 7.x Production Operations | Common + Cloud Implementation | ✓ | ✓ | ✓ | Monitoring, networking and infrastructure troubleshooting differ |
| 8.x Security & Administration | Common + Cloud Implementation | ✓ | ✓ | ✓ | Identity, network isolation, encryption and storage security differ materially |
| 9.x CI/CD & Automation | Common + Cloud Implementation | ✓ | ✓ | ✓ | Terraform/provider/account bootstrap details differ |
| 10.x Real-World Project | Common + Cloud Implementation | ✓ | ✓ | ✓ | Provide one common design plus cloud implementation variants |

## Repository structure

```text
databricks/
├── README.md
├── STATUS.md
├── CLOUD-MATRIX.md
├── part-01-fundamentals/
├── part-02-delta-lake-data-fundamentals/
├── part-03-unity-catalog-governance/
├── part-04-data-engineering/
├── part-05-databricks-sql/
├── part-06-performance-cost/
├── part-07-production-operations/
├── part-08-security-administration/
├── part-09-cicd-automation/
├── part-10-real-world-project/
└── cloud/
    ├── README.md
    ├── aws/
    │   └── README.md
    ├── azure/
    │   └── README.md
    └── gcp/
        └── README.md
```

## Canonical review requirement

A cloud-aware tutorial cannot be marked canonical until:

1. The common Databricks behavior has been validated.
2. Cloud-specific statements have been checked for AWS, Azure, and GCP where applicable.
3. Serverless and classic compute differences are not incorrectly generalized.
4. Identity, networking, and storage terminology is provider-correct.
5. Region/feature availability is not presented as universal when it is provider- or region-dependent.
6. Labs remain safe for the stated environment and do not embed credentials or production identifiers.

## Existing tutorial classification

### Part 1.1 — What Is Databricks?

**Classification:** Common

No structural change required.

### Part 1.2 — Lakehouse Architecture Fundamentals

**Classification:** Common + Cloud Notes

The canonical tutorial remains valid. Future revisions can link to cloud-specific storage, identity, and networking implementation guidance without duplicating the tutorial.

## Next tutorial

Part 1.3 — Databricks Platform Architecture should be authored as **Common + Cloud Notes** from its first draft.