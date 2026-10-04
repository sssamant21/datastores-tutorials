# 30 — Network Policies & Connectivity Security

## Overview

Authentication and RBAC answer who you are and what you are allowed to do. Network security adds another question: where are you allowed to connect from?

A production Snowflake security model includes identity, authentication, network boundaries, authorization/RBAC, and object privileges.

This chapter covers network policies, allowed and blocked network locations, network rules, account/user-level controls, private connectivity concepts, cloud-provider connectivity, service-account connectivity, rollout safety, troubleshooting, incident response, and production runbooks.

---

# Part 1 — Defense in Depth

## 1. Authentication Is Not Enough

If an attacker obtains valid credentials, network restrictions provide an additional boundary by requiring the connection to originate from an approved network location.

## 2. RBAC Is Not a Network Firewall

RBAC controls privileges after authentication. It does not replace network controls, and network controls do not replace RBAC.

## 3. Layered Security Model

A mature architecture may combine network restrictions, SSO/MFA/key pair/OAuth, authentication policies, RBAC, data governance policies, and monitoring.

---

# Part 2 — Snowflake Network Policies

## 4. What Is a Network Policy?

A Snowflake network policy defines network locations that are allowed or blocked for applicable authentication traffic.

## 5. Basic IP Restriction Concept

If corporate traffic exits through a stable approved address, policy can restrict access to that location. Use documentation/test addresses only in examples and never copy tutorial IPs into production.

## 6. Why Network Policies Matter

Network policies help reduce risks associated with stolen credentials, unrestricted internet access, unexpected service locations, unmanaged workstations, misconfigured integrations, and unauthorized automation.

---

# Part 3 — Network Policy Architecture

## 7. Account-Level Policy

An account-level policy can provide a broad account security boundary. Use account-wide controls carefully because mistakes can affect many users and workloads.

## 8. User-Level Policy

Different identities may require different network boundaries. Human users may use a corporate policy while AIRFLOW_SVC uses an AWS workload policy.

## 9. Why Per-User Policies Can Help

Human users and production applications often connect from different locations. One giant allowlist can create unnecessary exposure.

---

# Part 4 — Network Rules

## 10. What Is a Network Rule?

Snowflake network rules provide reusable definitions of network identifiers used by supported security and integration features.

## 11. Why Network Rules Help

Reusable rules reduce repeated network definitions and can make policies easier to understand and maintain.

---

# Part 5 — Create a Network Rule

## 12. IPv4 Network Rule

```sql
CREATE NETWORK RULE corporate_ipv4_rule
    MODE = INGRESS
    TYPE = IPV4
    VALUE_LIST = (
        '203.0.113.10/32',
        '198.51.100.0/24'
    );
```

These are documentation addresses. Replace them only with approved organizational ranges.

## 13. CIDR Ranges

A /32 represents one IPv4 address, while broader prefixes represent larger ranges. Use the narrowest practical range.

## 14. Avoid Overly Broad Ranges

Avoid broad ranges such as 0.0.0.0/0 merely to make connectivity work. Troubleshoot the real source instead.

---

# Part 6 — Network Policy Using Rules

## 15. Create Network Policy

```sql
CREATE NETWORK POLICY corporate_policy
    ALLOWED_NETWORK_RULE_LIST = (
        'corporate_ipv4_rule'
    );
```

Validate current syntax and supported rule types against current Snowflake documentation before production use.

## 16. Policy Architecture

Separating reusable network definitions from enforcement policy improves maintainability.

---

# Part 7 — Allowed and Blocked Sources

## 17. Allowlisting

An allowlist defines locations that are permitted to proceed to authentication.

## 18. Blocked Sources

Policies can also incorporate blocked network locations where supported.

## 19. Allow and Block Interaction

Understand Snowflake's current evaluation behavior before using both allowed and blocked sources. Never assume precedence.

---

# Part 8 — Account-Level Enforcement

## 20. Account-Wide Network Policy

An account-level network policy can affect a large portion of Snowflake connectivity. Treat activation as a production change.

## 21. Account-Level Risk

Incorrect policy can block users, services, ETL, BI tools, and automation.

## 22. Before Account Activation

Inventory human login sources, ETL, BI, dbt, Airflow, applications, Terraform, monitoring, CLI/connectors, cloud workloads, and break-glass administration paths.

---

# Part 9 — User-Level Enforcement

## 23. User-Specific Network Policy

Where supported and appropriate, a network policy can be associated with an individual user.

## 24. Example Design

Use corporate policy for analysts and service-specific policies for AIRFLOW_SVC and DBT_SVC.

## 25. Service Accounts

Service accounts are strong candidates for narrow network restrictions because workloads often originate from known infrastructure.

---

# Part 10 — Determining Source IP

## 26. Why Source IP Is Often Misunderstood

Traffic may traverse VPN, proxy, NAT gateway, firewall, or other egress infrastructure. Snowflake may see the egress address rather than the workstation's local address.

## 27. Kubernetes Workloads

Pod private addresses are often not the source evaluated externally. Determine the actual NAT or egress path.

## 28. Cloud Workloads

For AWS, Azure, or GCP workloads, determine the real egress path, such as NAT, firewall, proxy, or private endpoint.

---

# Part 11 — Dynamic IP Problems

## 29. Dynamic Client IPs

Home, mobile, and some VPN networks use changing public addresses, making strict individual IP allowlisting operationally difficult.

## 30. Better Human Access Architecture

Where appropriate, route users through controlled corporate VPN infrastructure with stable egress.

## 31. Avoid Constant Policy Changes

Prefer stable network architecture over daily manual policy modifications.

---

# Part 12 — Private Connectivity

## 32. Why Private Connectivity?

Private connectivity can provide a more controlled path between customer cloud environments and Snowflake where public internet access does not meet requirements.

## 33. Conceptual Architecture

Application VPC/VNet → private connectivity → Snowflake.

## 34. Cloud Provider Technologies

Depending on deployment, private connectivity may use AWS PrivateLink, Azure Private Link, or supported Google Cloud private connectivity capabilities. Availability depends on provider, region, account configuration, edition/features, and current platform support.

---

# Part 13 — AWS Connectivity

## 35. Public Connectivity Pattern

EKS/EC2/application traffic may traverse a NAT gateway before reaching Snowflake. The NAT public address may need to be considered by network policy.

## 36. Private Connectivity Pattern

AWS VPC → private endpoint → PrivateLink → Snowflake. Private DNS and endpoint configuration are important.

---

# Part 14 — Azure Connectivity

## 37. Public Azure Pattern

AKS/VM/application → NAT/firewall → internet → Snowflake. Determine the actual outbound public IP.

## 38. Private Azure Pattern

Azure VNet → private endpoint → Private Link → Snowflake. DNS must align with the private connectivity design.

---

# Part 15 — GCP Connectivity

## 39. Public GCP Pattern

GKE/Compute/application → Cloud NAT/egress → internet → Snowflake. Identify actual egress.

## 40. Private GCP Architecture

Validate supported Snowflake and Google Cloud private-connectivity architecture against current vendor documentation.

---

# Part 16 — DNS

## 41. DNS Is Critical

Private connectivity frequently depends on correct DNS resolution.

## 42. Troubleshooting DNS

```bash
nslookup <snowflake-hostname>
```

or:

```bash
dig <snowflake-hostname>
```

Validate resolved address, DNS server, private DNS, search domains, and split-horizon configuration.

## 43. Do Not Assume Connectivity Is Private

A private endpoint existing does not prove an application uses it. Verify DNS, routing, endpoint configuration, and connection path.

---

# Part 17 — Proxies and Firewalls

## 44. Corporate Proxy

A proxy can affect source network identity and connectivity behavior.

## 45. Firewall Rules

Troubleshoot the entire path: client firewall, corporate firewall, cloud controls, routes, NAT, proxy, DNS, private endpoint, and Snowflake policy.

---

# Part 18 — Drivers and Applications

## 46. Connectivity Applies Beyond Snowsight

Restrictions can affect Snowflake CLI/SnowSQL, Python connector, JDBC, ODBC, BI tools, dbt, Airflow, ETL platforms, applications, Terraform, and monitoring.

## 47. Test the Real Workload

Test from the actual workload infrastructure, not only from a laptop.

---

# Part 19 — Rollout Strategy

## 48. Never Start with a Blind Account-Wide Restriction

Inventory → create rules → create policy → controlled identity test → application test → break-glass validation → expand scope → account-wide enforcement if required.

## 49. Pilot User

Verify allowed network succeeds and blocked network fails.

## 50. Pilot Service

Test a representative service path before broad rollout.

---

# Part 20 — Preventing Lockout

## 51. Network Policy Lockout Risk

Incorrect policy can block administrators. Plan recovery before enforcement.

## 52. Break-Glass Planning

Define who can invoke recovery, identity verification, restoration steps, auditing, and removal of temporary access.

## 53. Validate Administrative Paths

Confirm administrative and recovery paths before activating restrictive policies.

---

# Part 21 — Monitoring

## 54. Monitor Login Activity

Authentication failures can reveal network policy errors, invalid credentials, unexpected origins, service misconfiguration, and attacks.

## 55. Baseline Normal Sources

Understand expected networks for humans, applications, ETL, BI, automation, and administration.

## 56. Service Source Drift

Unexpected source changes can indicate NAT replacement, migration, failover, routing/proxy change, misconfiguration, or unauthorized execution. Investigate before expanding allowlists.

---

# Part 22 — Troubleshooting

## 57. User Cannot Connect

Check reachability, DNS, routing, expected source, network policy, and authentication separately.

## 58. Works from Laptop but Not Application

Compare source IP, DNS, proxy, private endpoint, authentication, and account URL.

## 59. Works from One Pod but Not Another

Check node placement, subnet, NAT gateway, network policy, service mesh, proxy, DNS, and firewall/security controls.

## 60. Works in Staging but Not Production

Compare account, policy, rule, NAT, private endpoint, DNS, firewall, proxy, URL, and region.

## 61. Connection Suddenly Fails

Correlate failure time with policy, network-rule, NAT, firewall, DNS, endpoint, VPN, proxy, migration, or authentication changes.

---

# Part 23 — Network Incident Runbook

## 62. Production Connectivity Incident

1. Capture timestamp.
2. Identify affected user/service.
3. Identify environment.
4. Capture exact error.
5. Identify Snowflake account/region.
6. Determine scope.
7. Compare browser/application behavior.
8. Resolve hostname.
9. Test network reachability.
10. Determine actual source/egress.
11. Verify NAT/proxy/firewall.
12. Inspect network policy.
13. Inspect network rules.
14. Verify policy assignment.
15. Check recent policy changes.
16. Check recent cloud-network changes.
17. Check private endpoint.
18. Check DNS.
19. Check authentication separately.
20. Compare with known-good workload.
21. Apply minimum correction.
22. Validate application connectivity.
23. Validate unauthorized sources remain blocked.
24. Monitor recovery.
25. Document root cause.

---

# Part 24 — Security Investigation

## 63. Unexpected Source Address

Identify identity, determine whether login succeeded, validate infrastructure, check credential exposure, and contain if required.

## 64. Do Not Simply Add the Address

If a service starts connecting from an unknown address, determine why before allowlisting it.

---

# Part 25 — Change Management

## 65. Network Policy Changes Are Production Changes

Use change tickets, peer review, impact analysis, testing, rollback, validation, and monitoring.

## 66. Pre-Change Checklist

- Current policy captured
- Current rules captured
- New source validated
- CIDR validated
- Workloads identified
- Admin access considered
- Service paths validated
- Rollback prepared
- Test plan prepared
- Monitoring ready

## 67. Post-Change Checklist

- Human login works
- Required applications connect
- ETL works
- BI works
- Automation works
- Unauthorized source blocked
- Login failures monitored
- No unexpected source expansion

---

# Part 26 — Infrastructure as Code

## 68. Network Security as Code

Manage network rules and policies through controlled IaC where practical for review, version history, repeatability, drift detection, rollback, and environment consistency.

## 69. Avoid Console Drift

Reconcile emergency manual changes with the authoritative configuration.

## 70. Protect Critical Changes

Require peer review for broad CIDR additions, policy removal, account-level changes, private-connectivity changes, and security-boundary changes.

---

# Part 27 — Production Design Example

## 71. Human Users

Employees → corporate VPN → stable egress → corporate network policy → Snowflake, combined with SSO/MFA and RBAC.

## 72. Production Application

Application → controlled cloud network → NAT/private connectivity → service-specific network policy → Snowflake, combined with non-interactive authentication and least-privilege role.

## 73. Combined Security Model

Network boundary → authentication → role → privileges → data.

Every layer should be independently defensible.

---

# Part 28 — Hands-On Lab

## 74. Lab Objective

Practice creating network rules, creating a policy, reviewing configuration, positive/negative testing, and safe troubleshooting in non-production.

## 75. Determine Approved Test Source

Identify the actual public egress of the test environment. Do not guess. Record test client, public egress, CIDR, environment, and owner.

## 76. Create Lab Database and Schema

```sql
CREATE OR REPLACE DATABASE network_security_lab;
CREATE OR REPLACE SCHEMA network_security_lab.security;
```

## 77. Create Test Network Rule

```sql
CREATE NETWORK RULE network_security_lab.security.lab_ipv4_rule
    MODE = INGRESS
    TYPE = IPV4
    VALUE_LIST = (
        '203.0.113.10/32'
    );
```

Replace the documentation address with the approved test CIDR. Do not activate the example unchanged.

## 78. Inspect Network Rule

Use appropriate Snowflake metadata/SHOW commands and confirm name, mode, type, value list, and owner.

## 79. Create Lab Network Policy

```sql
CREATE NETWORK POLICY lab_network_policy
    ALLOWED_NETWORK_RULE_LIST = (
        'network_security_lab.security.lab_ipv4_rule'
    );
```

Do not attach it account-wide.

## 80. Create Dedicated Lab User

```sql
CREATE USER network_policy_test_user;
```

Configure secure authentication according to organizational policy.

## 81. Assign Minimum Lab Access

Use a dedicated lab role rather than broad administrative access.

## 82. Associate Policy with Test User

Associate the policy only with the dedicated test identity using currently supported Snowflake syntax. Do not experiment using the only administrative account.

## 83. Positive Test

Connect from the approved network and confirm valid authentication succeeds.

## 84. Negative Test

Attempt from a controlled source outside the allowlist and confirm policy denial.

## 85. Troubleshooting Exercise

If approved client is blocked, confirm public source, VPN, proxy, NAT, CIDR, rule, policy, assignment, and account before broadening policy.

## 86. Cleanup

Remove the test policy association before dropping dependent objects, then clean up policy, database, user, roles, and credentials in supported dependency order.

---

# Part 29 — Production Checklist

## 87. Network Policy Checklist

- Purpose documented
- Owner identified
- Allowed sources documented
- Blocked sources documented
- CIDRs validated
- Account/user scope understood
- Services inventoried
- Admin access considered
- Negative test completed
- Rollback documented

## 88. Network Rule Checklist

- Rule name meaningful
- MODE correct
- TYPE correct
- VALUE_LIST validated
- CIDR narrow enough
- Owner controlled
- IaC managed
- Dependencies documented

## 89. Private Connectivity Checklist

- Cloud/provider support validated
- Region validated
- Snowflake configuration complete
- Private endpoint healthy
- DNS correct
- Routing correct
- Firewall correct
- Application uses private path
- Failover considered
- Monitoring configured

## 90. Service Connectivity Checklist

- Dedicated service identity
- Dedicated role
- Authentication approved
- Source network known
- NAT/private path known
- Network policy correct
- DNS verified
- Production test completed
- Monitoring enabled

---

# Acceptance Criteria

The chapter is complete when you can:

- explain network security as defense in depth
- distinguish authentication, authorization, and network restrictions
- explain network policies and network rules
- design account-level and user-level controls
- restrict service identities
- understand allowed/blocked sources and CIDR
- determine actual client/cloud/Kubernetes egress
- handle dynamic human IPs
- explain private connectivity across major cloud providers
- troubleshoot DNS, proxies, and firewalls
- validate application-specific connectivity
- roll out policies safely
- prevent administrative lockout
- design break-glass recovery
- monitor source changes
- troubleshoot connectivity incidents
- investigate unexpected sources
- manage changes through change control and IaC
- perform positive and negative network tests
- execute the production connectivity runbook

---

## Key Takeaways

Snowflake security should not rely on credentials alone.

Use layered controls: network boundary + authentication + RBAC + governance + monitoring.

Network policies restrict where connections are allowed to originate. Network rules make network definitions reusable and easier to manage.

For services, combine a dedicated identity, known network source, strong authentication, and least-privilege role.

When troubleshooting connectivity, trace application → DNS → proxy/firewall → NAT/private endpoint → Snowflake network policy → authentication.

Do not solve an unexplained connectivity problem by continually expanding the allowlist. Determine the actual source and network path first.

A network policy is a security boundary. Treat every change to that boundary as a production security change.

The next chapter is **Chapter 31 — MFA, SSO & Key-Pair Authentication**.
