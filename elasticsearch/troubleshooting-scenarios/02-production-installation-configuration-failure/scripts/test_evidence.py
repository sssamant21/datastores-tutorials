"""Regression cases for acceptance gates that previously admitted false PASS."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("verifier", Path(__file__).with_name("verify-evidence.py"))
verifier = importlib.util.module_from_spec(spec)
spec.loader.exec_module(verifier)


class Gates(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.e = verifier.Evidence(self.root)

    def put(self, name, value):
        (self.root / name).write_text(value if isinstance(value, str) else json.dumps(value), encoding="utf-8")

    def tls_fixture(self, message, timestamp="2026-09-16T00:44:47Z", node="elasticsearch-2"):
        message.setdefault("log.level", "WARN")
        self.put("failure-pod.json", {"metadata": {"uid": "new", "creationTimestamp": "2026-09-16T00:44:00Z"}, "status": {"podIP": "10.0.0.2"}})
        self.put("baseline-node2-uid.txt", "old")
        self.put("failure-loaded-certificate.txt", "bad certificate")
        self.put("injected-certificate.txt", "bad certificate")
        self.put("baseline-certificate.txt", "good certificate")
        for n in verifier.NODES:
            self.put(f"{n}-transport.log", f"{timestamp} {json.dumps(message)}\n" if n == node else "")

    def test_real_transport_handshake(self):
        self.tls_fixture({"message": "exception caught on transport layer remoteAddress=10.0.0.1:9300", "error.stack_trace": "javax.net.ssl.SSLHandshakeException: (certificate_required) Received fatal alert"})
        self.e.tls()

    def test_generic_feature_strings_fail(self):
        self.tls_fixture({"message": "loaded features x509 certificate verification transport :9300"})
        with self.assertRaises(ValueError): self.e.tls()

    def test_http_tls_failure_fails(self):
        self.tls_fixture({"log.logger": "SecurityNetty4HttpServerTransport", "message": "SSLHandshakeException at 10.0.0.2:9200"})
        with self.assertRaises(ValueError): self.e.tls()

    def test_old_tls_failure_fails(self):
        self.tls_fixture({"message": "SSLHandshakeException at 10.0.0.1:9300"}, timestamp="2026-09-16T00:43:59Z")
        with self.assertRaises(ValueError): self.e.tls()

    def test_unrelated_peer_failure_fails(self):
        self.tls_fixture({"message": "SSLHandshakeException at 10.0.0.99:9300"}, node="elasticsearch-0")
        with self.assertRaises(ValueError): self.e.tls()

    def test_separate_records_cannot_supply_context(self):
        self.tls_fixture({"message": "ordinary transport at :9300"})
        with (self.root / "elasticsearch-2-transport.log").open("a") as f:
            f.write('2026-09-16T00:44:48Z {"log.level":"WARN","message":"SSLHandshakeException at :9200"}\n')
        with self.assertRaises(ValueError): self.e.tls()

    def test_certificate_not_loaded_fails(self):
        self.tls_fixture({"message": "SSLHandshakeException at :9300"})
        self.put("failure-loaded-certificate.txt", "good certificate")
        with self.assertRaises(ValueError): self.e.tls()

    def explain_fixture(self, decider):
        shards = [{"index": verifier.INDEX, "shard": str(i), "prirep": role, "state": "STARTED" if role == "p" else "UNASSIGNED"} for i in range(3) for role in ("p", "r")]
        self.put("shards.json", shards)
        self.put("explain.json", {"index": verifier.INDEX, "shard": 0, "primary": False, "current_state": "unassigned", "can_allocate": "no", "node_allocation_decisions": [{"deciders": [decider]}]})

    def test_enable_primaries_explain_passes(self):
        self.explain_fixture({"decider": "enable", "decision": "NO", "explanation": "replica allocations are forbidden due to cluster setting [cluster.routing.allocation.enable=primaries]"})
        self.e.explain("explain.json", "shards.json")

    def test_unrelated_no_decider_fails(self):
        self.explain_fixture({"decider": "same_shard", "decision": "NO", "explanation": "already allocated"})
        with self.assertRaises(ValueError): self.e.explain("explain.json", "shards.json")

    def test_wrong_enable_setting_fails(self):
        self.explain_fixture({"decider": "enable", "decision": "NO", "explanation": "index.routing.allocation.enable=none"})
        with self.assertRaises(ValueError): self.e.explain("explain.json", "shards.json")

    def test_missing_config_fails(self):
        for n in ["configmap", *verifier.NODES]:
            self.put(f"baseline-{n}{'' if n == 'configmap' else '-config'}.yml", "")
        with self.assertRaises(ValueError): self.e.bootstrap("baseline")

    def test_password_and_private_keys_fail_sanitation(self):
        with patch.dict("os.environ", {"ES_PASSWORD": "test-secret-123"}):
            for secret in ("test-secret-123", "-----BEGIN EC PRIVATE KEY-----", "Authorization: Bearer token", "ELASTIC_PASSWORD=value"):
                with self.subTest(secret=secret):
                    self.put("leak.txt", secret)
                    with self.assertRaises(ValueError): self.e.sanitize()

    def test_missing_members_fail(self):
        self.put("final-settings.json", {"persistent": {verifier.KEY: "primaries"}, "transient": {verifier.KEY: "all"}})
        with self.assertRaises(ValueError): self.e.restricted("final")

    def test_same_count_changed_content_detectable(self):
        hits = [{"_id": str(i), "_source": {"value": i}} for i in range(1, 5)]
        data = {"timed_out": False, "_shards": {"failed": 0}, "hits": {"total": {"value": 4, "relation": "eq"}, "hits": hits}}
        self.put("baseline-documents.json", data)
        hits[0]["_source"]["value"] = "corrupted"
        self.put("final-documents.json", data)
        self.assertNotEqual(self.e.documents("baseline"), self.e.documents("final"))

    def test_partial_search_fails(self):
        self.put("final-documents.json", {"timed_out": False, "_shards": {"failed": 1}})
        with self.assertRaises(ValueError): self.e.documents("final")

    def test_pv_recreation_with_same_name_detectable(self):
        pvcs, pvs = [], []
        for i in range(3):
            meta = {"name": f"data-elasticsearch-{i}", "uid": f"pvc-{i}", "namespace": "lab"}
            pvcs.append({"metadata": meta, "spec": {"volumeName": f"pv-{i}"}, "status": {"phase": "Bound"}})
            pvs.append({"metadata": {"name": f"pv-{i}", "uid": f"pv-uid-{i}"}, "spec": {"claimRef": meta}, "status": {"phase": "Bound"}})
        self.put("pvc.json", {"items": pvcs})
        self.put("pv.json", {"items": pvs})
        before = self.e.storage("pvc.json", "pv.json")
        pvs[0]["metadata"]["uid"] = "recreated"
        self.put("pv.json", {"items": pvs})
        self.assertNotEqual(before, self.e.storage("pvc.json", "pv.json"))

    def test_empty_pvc_inventory_fails(self):
        self.put("pvc.json", {"items": []})
        with self.assertRaises(ValueError): self.e.storage("pvc.json", "pv.json")


if __name__ == "__main__":
    unittest.main()
