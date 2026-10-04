#!/usr/bin/env python3
"""Offline tutorial checks. No Redis connection or Enterprise validation."""
import ast
import json
import logging
from pathlib import Path
import random
import re
from types import SimpleNamespace

ROOT = Path(__file__).resolve().parents[1]
files = {p.name: p.read_text(encoding="utf-8") for p in ROOT.glob("*.md")}
python_blocks = 0
for name, content in files.items():
    if content.count("```") % 2:
        raise AssertionError(f"Unbalanced fences: {name}")
    for target in re.findall(r"\]\(([^)]+)\)", content):
        if "://" not in target and not target.startswith("#"):
            assert (ROOT / target.split("#")[0]).exists(), (name, target)
    for snippet in re.findall(r"```python\n(.*?)\n```", content, re.S):
        ast.parse(snippet, filename=name)
        python_blocks += 1

class RedisError(Exception):
    pass

class Cache:
    def __init__(self):
        self.values = {}
        self.clock = 0
        self.read_error = False
        self.write_error = False

    def get(self, key):
        if self.read_error:
            raise RedisError("read unavailable")
        entry = self.values.get(key)
        if entry is None:
            return None
        value, deadline = entry
        if deadline <= self.clock:
            del self.values[key]
            return None
        return value

    def set(self, key, value, ex):
        if self.write_error:
            raise RedisError("write unavailable")
        self.values[key] = (value, self.clock + ex)
        return True

    def ttl(self, key):
        if self.get(key) is None:
            return -2
        return int(self.values[key][1] - self.clock)

    def expire(self, key, seconds):
        if self.get(key) is None:
            return False
        self.values[key] = (self.values[key][0], self.clock + seconds)
        return True

    def delete(self, key):
        return int(self.values.pop(key, None) is not None)

snippet = re.findall(r"```python\n(.*?)\n```",
                     files["06-implementing-cache-aside.md"], re.S)[0]
tree = ast.parse(snippet)
fn = next(n for n in tree.body
          if isinstance(n, ast.FunctionDef) and n.name == "get_product")
cache = Cache()
namespace = dict(cache=cache, json=json, random=random,
                 logger=logging.getLogger("offline-review"),
                 redis=SimpleNamespace(exceptions=SimpleNamespace(RedisError=RedisError)))
exec(compile(ast.Module(body=[fn], type_ignores=[]), "<tutorial06>", "exec"), namespace)
get_product = namespace["get_product"]
source = {"id": 1001, "name": "Keyboard", "price": 49.99}
reads = 0
key = "tutorial:catalog:product:1001:v1"

def fetch(product_id):
    global reads
    reads += 1
    return dict(source)

assert get_product(1001, fetch) == source and reads == 1
assert get_product(1001, fetch) == source and reads == 1
source["price"] = 44.99
cache.delete(key)
assert get_product(1001, fetch)["price"] == 44.99 and reads == 2
cache.clock += 301
assert get_product(1001, fetch) == source and reads == 3
for invalid in ("{broken", "null", "[]", '{"id":1002,"name":"Wrong","price":1}',
                '{"id":1001,"name":"Demo","price":true}'):
    cache.set(key, invalid, ex=300)
    before = reads
    assert get_product(1001, fetch) == source and reads == before + 1
cache.read_error = True
assert get_product(1001, fetch) == source
cache.read_error = False
cache.delete(key)
cache.write_error = True
assert get_product(1001, fetch) == source and key not in cache.values
cache.write_error = False
assert get_product(9999, lambda _: None) is None
assert "tutorial:catalog:product:9999:v1" not in cache.values

def source_failure(_):
    raise RuntimeError("Source unavailable")

try:
    get_product(9998, source_failure)
    raise AssertionError("Source errors must propagate")
except RuntimeError:
    pass
# Execute the actual Tutorial 12 lab with virtual time and the cache model.
import builtins
lab_cache = Cache()
lab_ns = dict(json=json, random=random,
              cache=lab_cache, logger=logging.getLogger("offline-review"),
              redis=SimpleNamespace(exceptions=SimpleNamespace(
                  RedisError=RedisError, ConnectionError=RedisError)))
original_import = builtins.__import__
def lab_import(name, *args, **kwargs):
    if name == "time":
        return SimpleNamespace(sleep=lambda seconds: setattr(
            lab_cache, "clock", lab_cache.clock + seconds))
    return original_import(name, *args, **kwargs)
lab_ns["__builtins__"] = dict(vars(builtins), __import__=lab_import)
exec(compile(ast.Module(body=[fn], type_ignores=[]), "<tutorial06>", "exec"), lab_ns)
lab = re.findall(r"```python\n(.*?)\n```",
                 files["12-production-readiness-and-end-to-end-lab.md"], re.S)[0]
exec(compile(lab, "<tutorial12>", "exec"), lab_ns)

print(f"PASS: {python_blocks} Python blocks parsed; relative links checked")
print("PASS: miss/hit, invalidation, expiration, invalid JSON/schema, read/write failure, missing source, source error")
print("LIMIT: in-memory simulation; no Redis, TLS, client-library, failover, restore, or performance validation")
