# 09 — Users, Roles, Authentication, and TLS

**Status:** Draft

**Objective:** Create scoped users and verify allowed and denied access.

**Prerequisite:** Self-managed test deployment with authorization and TLS already enabled; administrator privileges for user management.

## Security controls

Authentication verifies identity; authorization controls permitted actions; TLS protects transport. Creating a user does not enable server access control. Use the supported deployment process for server configuration.

| Role | Purpose |
|---|---|
| read | Database reads |
| readWrite | Reads/writes and additional database privileges |
| dbAdmin | Database administration |
| clusterMonitor | Health monitoring |
| userAdmin | User/role management |
| root | Broad administration |

Prefer least privilege; custom roles can be narrower than readWrite. Keep application and user-management identities separate.

## Create a user over TLS

```javascript
use mongodb_tutorials
db.createUser({
  user: "tutorial_app",
  pwd: passwordPrompt(),
  roles: [{ role: "readWrite", db: "mongodb_tutorials" }],
  mechanisms: ["SCRAM-SHA-256"]
})
```

The authentication database is mongodb_tutorials. Prompting does not encrypt transport. Atlas uses its own user-management interfaces. If Ops Manager manages users, use its configured workflow to avoid drift.

## Connect

Single-line Windows example; replace hosts, set name and certificate path:
```cmd
mongosh "mongodb://mongo1.example.com:27017,mongo2.example.com:27017,mongo3.example.com:27017/mongodb_tutorials?replicaSet=rs0&authSource=mongodb_tutorials" --username tutorial_app --authenticationMechanism SCRAM-SHA-256 --tls --tlsCAFile "C:\certs\mongodb-ca.pem"
```

## Access tests

As the new application user:
```javascript
db.tutorial_access.insertOne({ _id: "tutorial-access-check", status: "allowed" })
db.tutorial_access.findOne({ _id: "tutorial-access-check" })
db.tutorial_access.deleteOne({ _id: "tutorial-access-check" })
db.runCommand({ connectionStatus: 1, showPrivileges: false })

db.getSiblingDB("tutorial_restricted")
  .getCollection("access_probe").findOne({})
```

Expect allowed CRUD, recorded authenticated identity/roles, and Unauthorized on restricted database if no additional roles exist. Successful CRUD alone does not prove restricted permissions.

## TLS and rotation

Verify hostname-matching certificates, CA trust, optional client certificates, expiry alerts and staging renewal. TLS, encryption at rest, and external authentication are distinct controls.

As administrator:
```javascript
use mongodb_tutorials
db.changeUserPassword("tutorial_app", passwordPrompt())
```

Update secrets and verify fresh connections. A password change does not necessarily terminate existing authenticated connections.

Remove only the test identity after the exercise:
```javascript
db.dropUser("tutorial_app")
```

## Troubleshooting and completion

Authentication failure: check identity, secret, authSource and mechanism. Unauthorized: check roles/scope. TLS errors: check CA, hostname, expiry and client cert. Rotation failures: check secret rollout/fresh connection. Broad access: inspect inherited roles.

Completion: demonstrate allowed and denied access with verified TLS.

## References

- [createUser](https://www.mongodb.com/docs/manual/reference/method/db.createUser/)
- [Built-in roles](https://www.mongodb.com/docs/manual/reference/built-in-roles/)
- [Transport encryption](https://www.mongodb.com/docs/manual/core/security-transport-encryption/)

**Next:** [10 — Storage and Capacity](10-storage-wiredtiger-capacity-planning.md)
