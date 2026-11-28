#!/usr/bin/env python3
"""Measure compatible union graphs, never replace historical test execution.
Group only flat, non-conflicting source graphs with identical declaration sets.
Compare every independently emitted JS file byte-for-byte. Incompatible graphs
are isolated, not silently accepted. A failed union is an experimental failure.
"""
import hashlib,json,os,pathlib,subprocess,tempfile,time,shutil
from graph_identity import identity
root=pathlib.Path(os.environ["SHOWLY_GRAPH_CAPTURE"])
real=os.environ["SHOWLY_REAL_TSC"]
groups=[]
replay=os.environ.get('SHOWLY_GRAPH_REPLAY')
replay_root=pathlib.Path(replay) if replay else None
if replay_root: replay_root.mkdir(parents=True,exist_ok=True)
for p in sorted(root.iterdir()):
    if not (p/"roots.json").is_file(): continue
    sources={x.name:x.read_bytes() for x in (p/"sources").glob("*.ts")}
    decl={n:v for n,v in sources.items() if n.endswith(".d.ts")}
    roots=set(json.loads((p/"roots.json").read_text()))
    # Files without module boundaries may introduce globals. Group their
    # contents as declarations too; otherwise never mix their contexts.
    globals_={n:v for n,v in sources.items() if n.endswith(".d.ts") or not any(t in v for t in (b"export ",b"import "))}
    for g in groups:
        if g["globals"]==globals_ and all(g["sources"].get(n,v)==v for n,v in sources.items()):
            g["sources"].update(sources);g["roots"].update(roots);g["projects"].append(p);break
    else: groups.append({"globals":globals_,"sources":sources,"roots":roots,"projects":[p]})
start=time.monotonic()
compared=0
for g in groups:
    with tempfile.TemporaryDirectory() as tmp:
        work=pathlib.Path(tmp)
        for n,v in g["sources"].items(): (work/n).write_bytes(v)
        subprocess.run([real,"--strict","--target","ES2020","--module","commonjs",*sorted(g["roots"])],cwd=work,check=True)
        for p in g["projects"]:
            for out in (p/"outputs").glob("*.js"):
                assert (work/out.name).is_file() and (work/out.name).read_bytes()==out.read_bytes(),f"Different output: {out.name}"
                compared+=1
            if replay_root:
                key=identity({x.name:x.read_bytes() for x in (p/"sources").glob("*.ts")},json.loads((p/"roots.json").read_text()))
                dest=replay_root/key
                dest.mkdir(exist_ok=True)
                outputs={out.name:hashlib.sha256((work/out.name).read_bytes()).hexdigest() for out in (p/"outputs").glob("*.js")}
                for name in outputs: shutil.copyfile(work/name,dest/name)
                (dest/"manifest.json").write_text(json.dumps(outputs,sort_keys=True))
print(f"graph_projects={sum(len(g['projects']) for g in groups)} graph_groups={len(groups)} emitted_files_verified={compared} union_compile_seconds={time.monotonic()-start:.3f}")
assert compared>0
