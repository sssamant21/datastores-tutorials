#!/usr/bin/env python3
"""Fail-closed, offline assertions over Scenario 02's saved API/log evidence."""
import base64
from datetime import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import sys

INDEX = "installation-validation-v1"
KEY = "cluster.routing.allocation.enable"
NODES = {f"elasticsearch-{i}" for i in range(3)}
TLS_ERROR = re.compile(
    r"SSLHandshakeException|certificate_unknown|bad_certificate|unknown_ca|"
    r"unable to find valid certification path|CertPathValidatorException|"
    r"failed to establish trust with (?:server|client)|"
    r"No subject alternative (?:DNS )?names? matching", re.I)
TRANSPORT = re.compile(r"xpack\.security\.transport\.ssl|SecurityNetty4Transport|"
                       r"\bo\.e\.x\.s\.t\.n\.SecurityNetty4Transport\b|:9300\b")


def require(condition, message):
    if not condition:
        raise ValueError(message)


class Evidence:
    def __init__(self, directory):
        self.directory = Path(directory)

    def text(self, name):
        return (self.directory / name).read_text(encoding="utf-8")

    def data(self, name):
        return json.loads(self.text(name))

    def bootstrap(self, phase):
        for name in ["configmap", *sorted(NODES)]:
            suffix = "" if name == "configmap" else "-config"
            content = self.text(f"{phase}-{name}{suffix}.yml")
            require("cluster.name:" in content and "discovery.seed_hosts:" in content,
                    f"{phase}/{name}: missing/unreadable runtime config")
            require("cluster.initial_master_nodes" not in content,
                    f"{phase}/{name}: bootstrap setting present")

    def documents(self, phase):
        data = self.data(f"{phase}-documents.json")
        require(data.get("timed_out") is False and data["_shards"]["failed"] == 0,
                f"{phase}: incomplete search")
        require(data["hits"]["total"] == {"value": 4, "relation": "eq"},
                f"{phase}: count is not exactly four")
        hits = data["hits"]["hits"]
        require(len(hits) == 4 and {h["_id"] for h in hits} == {"1", "2", "3", "4"},
                f"{phase}: missing/duplicate document IDs")
        return {h["_id"]: h["_source"] for h in hits}

    def shards(self, filename, yellow=False):
        shards = self.data(filename)
        require(len(shards) == 6, f"{filename}: expected six shard copies")
        for shard in "012":
            copies = [s for s in shards if s["shard"] == shard]
            require(len(copies) == 2 and sorted(s["prirep"] for s in copies) == ["p", "r"],
                    f"{filename}: wrong shard/replica layout")
        require(all(s["index"] == INDEX and s["state"] == "STARTED"
                    for s in shards if s["prirep"] == "p"), f"{filename}: primary not active")
        if yellow:
            require(any(s["prirep"] == "r" and s["state"] == "UNASSIGNED" for s in shards),
                    f"{filename}: no unassigned replica")
        else:
            require(all(s["state"] == "STARTED" for s in shards), f"{filename}: incomplete shards")
        return shards

    def phase(self, phase, nodes, status):
        identity = self.data(f"{phase}-identity.json")
        uuid = self.data("01-baseline-cluster-identity.json")["cluster_uuid"]
        require(isinstance(uuid, str) and uuid not in ("", "_na_", "null"), "invalid baseline UUID")
        require(identity["cluster_uuid"] == uuid and identity["version"]["number"] == "9.5.3",
                f"{phase}: UUID/version changed")
        names = [n["name"] for n in self.data(f"{phase}-nodes.json")]
        expected = NODES if nodes == 3 else NODES - {"elasticsearch-2"}
        require(len(names) == nodes and set(names) == expected, f"{phase}: wrong cluster members")
        health = self.data(f"{phase}-cluster-health.json")
        require(health["number_of_nodes"] == nodes and health["status"] == status
                and health.get("timed_out") is False, f"{phase}: wrong cluster health")
        require(health["unassigned_shards"] > 0 if status == "yellow" else health["unassigned_shards"] == 0,
                f"{phase}: wrong unassigned count")
        if status == "green":
            require(health["initializing_shards"] == 0 and health["relocating_shards"] == 0,
                    f"{phase}: cluster not settled")
        settings = self.data(f"{phase}-index-settings.json")[INDEX]["settings"]
        require(settings["index.number_of_shards"] == "3" and settings["index.number_of_replicas"] == "1",
                f"{phase}: index topology changed")
        require(settings["index.uuid"] == self.data("baseline-index-settings.json")[INDEX]["settings"]["index.uuid"],
                f"{phase}: index recreated")
        require(self.data(f"{phase}-mapping.json") == self.data("baseline-mapping.json"),
                f"{phase}: mapping changed")
        require(self.documents(phase) == self.documents("baseline"), f"{phase}: document content changed")
        self.bootstrap(phase)

    def storage(self, pvc_file, pv_file):
        pvcs = self.data(pvc_file)["items"]
        pvcs = [p for p in pvcs if p["metadata"]["name"] in {f"data-{n}" for n in NODES}]
        require(len(pvcs) == 3, "expected three Elasticsearch PVCs")
        pvs = {p["metadata"]["name"]: p for p in self.data(pv_file)["items"]}
        result = {}
        for pvc in pvcs:
            meta, spec = pvc["metadata"], pvc["spec"]
            pv = pvs[spec["volumeName"]]
            require(pvc["status"]["phase"] == "Bound" and pv["status"]["phase"] == "Bound",
                    "storage not Bound")
            ref = pv["spec"]["claimRef"]
            require(ref["uid"] == meta["uid"] and ref["name"] == meta["name"]
                    and ref["namespace"] == meta["namespace"], "PV claim binding changed")
            # Compare the full storage source/spec too, not merely a reusable PV name.
            result[meta["name"]] = [meta["uid"], spec["volumeName"], pv["metadata"]["uid"], pv["spec"]]
        return result

    def baseline(self):
        self.phase("baseline", 3, "green")
        shards = self.shards("04-baseline-shards.json")
        require(any(s["node"] == "elasticsearch-2" for s in shards),
                "node 2 has no validation shard to unassign; do not inject")
        self.storage("07-baseline-pvcs.json", "08-baseline-pvs.json")
        mapping = self.data("baseline-mapping.json")[INDEX]["mappings"]["properties"]
        for field, kind in {"patient_id": "keyword", "facility": "keyword", "event_time": "date", "description": "text"}.items():
            require(mapping[field]["type"] == kind, f"wrong mapping: {field}")

    def tls(self):
        pod = self.data("failure-pod.json")
        since = pod["metadata"]["creationTimestamp"]
        require(pod["metadata"]["uid"] != self.text("baseline-node2-uid.txt").strip(), "injected pod was not recreated")
        require(self.text("failure-loaded-certificate.txt") == self.text("injected-certificate.txt")
                and self.text("injected-certificate.txt") != self.text("baseline-certificate.txt"),
                "injected certificate not loaded")
        matches = []
        for node in sorted(NODES):
            for line in self.text(f"{node}-transport.log").splitlines():
                timestamp, _, record = line.partition(" ")
                # RFC3339 timestamps, with fractional seconds normalized for comparison.
                try:
                    fresh = datetime.fromisoformat(timestamp.replace("Z", "+00:00")) >= datetime.fromisoformat(since.replace("Z", "+00:00"))
                except ValueError:
                    continue
                try:
                    event = json.loads(record)
                    if event.get("log.level") not in ("WARN", "ERROR"):
                        continue
                    record = " ".join(str(event.get(k, "")) for k in ("log.logger", "message", "error.type", "error.stack_trace"))
                except json.JSONDecodeError:
                    if not re.search(r"\[(?:WARN\s*|ERROR)\]", record):
                        continue
                # Peers must identify the injected node by IP/name/issuer. Node 2's
                # own transport errors are inherently scoped to that node.
                related = node == "elasticsearch-2" or any(v in record for v in
                    (pod["status"]["podIP"], "elasticsearch-2", "Scenario-002-Untrusted-CA"))
                if fresh and related and TRANSPORT.search(record) and TLS_ERROR.search(record):
                    matches.append(f"{node}: {line}")
        require(matches, "no fresh, node-2-related transport TLS failure record")
        return "\n".join(matches) + "\n"

    def explain(self, filename, shards_file):
        data = self.data(filename)
        shards = self.shards(shards_file, yellow=True)
        require(data["index"] == INDEX and data["primary"] is False and data["current_state"] == "unassigned"
                and data["can_allocate"] == "no", f"{filename}: wrong explain target/state")
        require(any(s["shard"] == str(data["shard"]) and s["prirep"] == "r" and s["state"] == "UNASSIGNED" for s in shards),
                f"{filename}: target is not an unassigned replica")
        require(any(d["decider"] == "enable" and d["decision"] == "NO"
                    and KEY in d["explanation"] and "primaries" in d["explanation"]
                    for n in data["node_allocation_decisions"] for d in n["deciders"]),
                f"{filename}: allocation.enable=primaries not proven")

    def failure(self):
        self.phase("failure", 2, "yellow")
        require(self.text("transport-tls-failure-evidence.txt") == self.tls(), "TLS excerpt differs from source logs")
        self.restricted("failure")
        self.explain("20-allocation-explain.json", "17-failure-shards.json")

    def restricted(self, phase):
        settings = self.data(f"{phase}-settings.json")
        require(settings["persistent"].get(KEY) == "primaries" and KEY not in settings["transient"],
                f"{phase}: allocation restriction overridden")

    def rejoined(self):
        self.phase("rejoined", 3, "yellow")
        self.restricted("rejoined")
        self.explain("rejoined-allocation-explain.json", "rejoined-shards.json")
        require(self.text("repaired-loaded-certificate.txt") == self.text("baseline-certificate.txt"),
                "original TLS certificate not restored")
        require(self.data("repaired-pod.json")["metadata"]["uid"] != self.data("failure-pod.json")["metadata"]["uid"],
                "repaired pod not recreated")

    def all(self):
        self.baseline()
        self.failure()
        self.rejoined()
        self.phase("final", 3, "green")
        self.shards("final-shards.json")
        require(self.storage("07-baseline-pvcs.json", "08-baseline-pvs.json") == self.storage("28-final-pvcs.json", "29-final-pvs.json"),
                "PVC/PV identity or storage source changed")
        before, after = self.data("original-allocation-state.json"), self.data("final-settings.json")
        for scope in ("persistent", "transient"):
            require(before[scope] == after[scope], f"{scope} settings not restored exactly")
        require(self.text("negative-auth-status.txt").strip() == "401"
                and self.data("31-negative-auth.json")["status"] == 401, "negative authentication did not return 401")
        require(self.data("27-final-index-count.json")["count"] == 4, "wrong final count")
        processes = self.data("final-process.json")["nodes"]
        require(len(processes) == 3 and all(n["process"]["max_file_descriptors"] >= 65535 for n in processes.values()),
                "missing/insufficient file descriptor evidence")
        print("PASS: saved evidence proves baseline, injected TLS failure, allocation block, TLS-only rejoin, exact restoration, identity/storage/data continuity, and final recovery")

    def sanitize(self):
        password = os.environ.get("ES_PASSWORD", "")
        secrets = [password, base64.b64encode(f"{os.environ.get('ES_USER', 'elastic')}:{password}".encode()).decode()] if password else []
        forbidden = re.compile(r"BEGIN (?:[A-Z0-9]+ )*PRIVATE KEY|Authorization\s*:\s*(?:Basic|Bearer)\s+(?!\[REDACTED\])\S+|ELASTIC_PASSWORD\s*[=:]", re.I)
        for path in self.directory.rglob("*"):
            require(not path.is_symlink(), "symlink in evidence")
            if not path.is_file():
                continue
            content = path.read_text(encoding="utf-8")
            require(not forbidden.search(content) and not any(s in content for s in secrets),
                    f"unsanitized evidence: {path.name}")
        print("PASS: evidence sanitation")

    def artifact(self, expected_head):
        require(re.fullmatch(r"[a-f0-9]{40}", expected_head), "expected head must be a full commit SHA")
        require(self.data("source.json")["head_sha"] == expected_head, "artifact belongs to another commit")
        listed = set()
        for line in self.text("SHA256SUMS").splitlines():
            digest, name = line.split("  ", 1)
            name = name.removeprefix("./")
            path = self.directory / name
            require(path.resolve().is_relative_to(self.directory.resolve()) and not path.is_symlink(), "unsafe manifest path")
            require(name not in listed and hashlib.sha256(path.read_bytes()).hexdigest() == digest, f"hash mismatch: {name}")
            listed.add(name)
        require(listed == {p.relative_to(self.directory).as_posix() for p in self.directory.rglob("*") if p.is_file() and p.name != "SHA256SUMS"},
                "manifest does not cover every evidence file")
        require(self.text("cleanup-status.txt").strip() == "0" and "es-scenario-002" not in self.text("remaining-kind-clusters.txt"), "job cluster cleanup not proven")
        require(self.text("32-validation-result.txt").strip() == "SCENARIO 002 IMPLEMENTATION VALIDATION PASS", "missing completion marker")
        self.all()
        self.sanitize()
        print(f"PASS: independently verified artifact for {expected_head}")


if __name__ == "__main__":
    try:
        evidence = Evidence(sys.argv[2])
        result = getattr(evidence, sys.argv[1])(*sys.argv[3:])
        if sys.argv[1] == "tls":
            (evidence.directory / "transport-tls-failure-evidence.txt").write_text(result, encoding="utf-8", newline="\n")
    except (ValueError, KeyError, TypeError, OSError, IndexError) as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        sys.exit(1)
