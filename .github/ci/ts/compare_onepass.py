#!/usr/bin/env python3
import collections,json,os,pathlib,hashlib
from graph_identity import identity
def inventory(root):
    records=collections.Counter()
    for p in pathlib.Path(root).iterdir():
        if not (p/"roots.json").is_file():continue
        sources={x.name:x.read_bytes() for x in (p/"sources").glob("*.ts")}
        key=identity(sources,json.loads((p/"roots.json").read_text()))
        outputs=tuple(sorted((x.name,hashlib.sha256(x.read_bytes()).hexdigest()) for x in (p/"outputs").glob("*.js")))
        assert outputs,f"Missing outputs: {p}"
        records[(key,outputs)]+=1
    return records
a=inventory(os.environ["SHOWLY_GRAPH_CAPTURE"])
b=inventory(os.environ["SHOWLY_ONEPASS_QUEUE"])
assert a and a==b,f"Independent/cold graph output mismatch: {sum((a-b).values())} missing, {sum((b-a).values())} unexpected"
print(f"cold_onepass_verified_projects={sum(b.values())} verified_emitted_files={sum(len(key[1])*n for key,n in b.items())}")
