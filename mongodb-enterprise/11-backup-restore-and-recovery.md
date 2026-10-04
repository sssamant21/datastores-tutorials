# 11 — Backup, Restore, and Recovery

**Status:** Draft; live lab not run.

**Objective:** Create a small backup, restore it to an isolated test deployment, and verify recovered data.

## Recovery fundamentals

| Term | Meaning | Example target |
|---|---|---|
| RPO | Maximum acceptable data loss | 15 minutes |
| RTO | Maximum acceptable recovery time | 1 hour |
| Retention | How long recovery points remain available | 30 days |
| Restore drill | Practice recovery and measure results | Monthly |

Replication supports availability. Accidental deletion can replicate to every member, so replicas do not replace backups.

## Choose a backup method

| Method | Typical use |
|---|---|
| mongodump / mongorestore | Small logical backups, migrations, selective recovery |
| Ops Manager Backup | Managed snapshots and point-in-time recovery when configured |
| Coordinated storage snapshots | Large deployments with a supported consistency procedure |

Ops Manager recovery requires enabled backup, retained snapshots and available oplog coverage. Verify the recoverable time window.

## Prepare the lab

Use a test source and a separate test restore deployment. Replace example hosts, users and certificate paths. Install compatible MongoDB Database Tools; verify source/target server and FCV compatibility. Use approved backup/restore identities. The target namespace must be unused.

In Windows CMD:
```bat
mongodump --version
mongorestore --version
mkdir C:\mongodb-backups
```

In mongosh connected to the test source:
```javascript
use mongodb_tutorials
db.tutorial_backup.insertOne({
  _id: "tutorial-backup-check",
  message: "Restore verification",
  createdAt: new Date()
})
db.tutorial_backup.findOne({ _id: "tutorial-backup-check" })
```

Use a dedicated one-document collection. Pause its writers until the dump finishes.

## Create the backup

Run in CMD, outside mongosh:
```bat
mongodump --uri="mongodb://mongo1.example.com:27017,mongo2.example.com:27017/?replicaSet=rs0" --username=backup_user --authenticationDatabase=admin --ssl --sslCAFile="C:\certs\mongodb-ca.pem" --db=mongodb_tutorials --collection=tutorial_backup --archive="C:\mongodb-backups\tutorial-backup.archive.gz" --gzip
```

Enter the password when prompted. Check successful completion and archive existence. Dump exports documents, collection metadata/options and index definitions. Compression does not encrypt the backup; protect storage and access.

This single-collection exercise does not demonstrate a consistent backup of an active application. A whole-replica-set oplog dump has different constraints; it cannot be combined with this restricted collection recipe. Sharded backups need topology-specific coordination.

## Restore to the test deployment

Run in CMD:
```bat
mongorestore --uri="mongodb://restore1.example.com:27017,restore2.example.com:27017/?replicaSet=restoreRs" --username=restore_user --authenticationDatabase=admin --ssl --sslCAFile="C:\certs\restore-ca.pem" --archive="C:\mongodb-backups\tutorial-backup.archive.gz" --gzip --nsInclude="mongodb_tutorials.tutorial_backup" --nsFrom="mongodb_tutorials.tutorial_backup" --nsTo="mongodb_restore_lab.tutorial_backup" --stopOnError
```

Require an empty destination. Check the summary for failures and partial results. Namespace mapping restores under a different database name.

## Verify recovery

Connect mongosh to the restore deployment:
```javascript
use mongodb_restore_lab
db.tutorial_backup.countDocuments({})
db.tutorial_backup.findOne({ _id: "tutorial-backup-check" })
db.tutorial_backup.getIndexes()
```

Expect one document, matching marker/message/timestamp, the _id index and zero failed documents. Production verification also compares options, representative records, business totals and application behavior. Record elapsed recovery time against RTO.

## Accidental deletion recovery

1. Stop the faulty job or operation.
2. Identify affected records and incident time.
3. Select a backup or supported recovery point before deletion.
4. Restore into an isolated deployment and validate.
5. Apply a reviewed repair preserving legitimate later changes.

A logical archive recovers its captured contents. Later timestamp recovery requires an appropriate retained recovery history.

## Common problems

| Problem | Check or solution |
|---|---|
| Command not found | Install Database Tools and update PATH |
| Authentication failure | User, authentication database and permissions |
| TLS failure | CA, hostname, expiry and client-certificate requirements |
| No restored documents | Archive and original nsInclude namespace |
| Duplicate keys | Fresh destination; inspect partial results |
| Recovery fails | Verify compatibility and run restore drills |

Clean up only the marker on each respective deployment after verification:
```javascript
db.getSiblingDB("mongodb_tutorials").tutorial_backup.deleteOne({ _id: "tutorial-backup-check" })
```
```javascript
db.getSiblingDB("mongodb_restore_lab").tutorial_backup.deleteOne({ _id: "tutorial-backup-check" })
```

## References

- [mongodump](https://www.mongodb.com/docs/database-tools/mongodump/)
- [mongorestore](https://www.mongodb.com/docs/database-tools/mongorestore/)
- [Ops Manager backup](https://www.mongodb.com/docs/ops-manager/current/core/backup-overview/)

**Next:** [12 — Ops Manager and Enterprise Management](12-ops-manager-and-enterprise-management.md).
