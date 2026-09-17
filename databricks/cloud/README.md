# Databricks Cloud-Specific Implementation Guides

This directory contains implementation guidance that materially differs across AWS, Azure, and Google Cloud.

## Design principle

The main `databricks/part-*` tutorials remain the source of truth for common Databricks concepts. Content belongs here only when cloud-provider implementation details are substantial enough that putting all variants inline would reduce clarity or safety.

## Cloud directories

- `aws/` — AWS-specific identity, storage, networking, security, deployment, cost, and operational guidance.
- `azure/` — Azure-specific identity, storage, networking, security, deployment, cost, and operational guidance.
- `gcp/` — GCP-specific identity, storage, networking, security, deployment, cost, and operational guidance.

## What belongs here

Examples include:

- Unity Catalog storage-credential implementation
- External-location authentication
- Customer-managed storage
- Classic compute networking
- Serverless network connectivity
- Private connectivity
- Cloud IAM integration
- Encryption/key-management implementation
- Terraform/bootstrap differences
- Cloud-specific monitoring and troubleshooting
- Cost and egress considerations

## What does not belong here

Do not duplicate common tutorials for:

- Delta Lake concepts
- Bronze/Silver/Gold semantics
- SQL fundamentals
- Notebook fundamentals
- General data-quality concepts
- General governance principles

## Validation rule

Cloud implementation guides must be revalidated against current official Databricks documentation before being marked canonical. Feature availability and architecture can differ by cloud, region, workspace type, and compute model.