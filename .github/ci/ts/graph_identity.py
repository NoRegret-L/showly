"""Exact input identity for same-run graph replay, not a persistent trust cache."""
import hashlib,json,pathlib
def identity(sources,roots):
    h=hashlib.sha256()
    h.update(json.dumps(list(roots),separators=(",",":")).encode())
    for name,data in sorted(sources.items()):
        h.update(name.encode()+b"\0"+hashlib.sha256(data).digest())
    return h.hexdigest()
