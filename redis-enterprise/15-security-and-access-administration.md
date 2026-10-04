# 15 — Security and Access Administration

**Status:** Draft

**Audience:** Redis Enterprise administrators, SREs, and DBREs.

## Separate access planes

Management users administer the cluster. Database users authenticate application commands. Give each application its own least-privilege access where supported; avoid sharing administrator credentials.

## Access workflow

1. Identify required commands and key prefixes.
2. Configure database roles/users through supported Enterprise controls.
3. Require verified TLS and approved network paths.
4. Store credentials in a secret manager.
5. Test allowed and denied operations with that application's identity.

Use release-specific ACL features. Avoid assuming standalone ACL SETUSER changes are the appropriate durable Enterprise management method.

## Lab

With a test application's credentials:
```redis
SET tutorial:access:allowed "demo" EX 60
GET tutorial:access:allowed
DEL tutorial:access:allowed
```

Configure this identity for the tutorial:access:* prefix. Attempt GET on a deliberately disallowed prefix and verify NOPERM. Do not grant destructive commands just to demonstrate them.

## Rotation and certificates

Record certificate expiry and renewal ownership. Use supported credential overlap or a second identity where appropriate: deploy new credentials, verify applications reconnect, then revoke old access. Test the exact rotation behavior in staging.

Monitor authentication failures and permission errors. Do not log secrets or include sensitive key values in incident evidence.

## Acceptance and references

Acceptance: required operations succeed, forbidden scope is denied, certificate validation works, and rotation is demonstrated.

- [Enterprise security](https://redis.io/docs/latest/operate/rs/security/)
- [TLS connection examples](https://redis.io/docs/latest/develop/tools/cli/)

**Next:** [16 — Capacity and Shard Administration](16-capacity-and-shard-administration.md)
