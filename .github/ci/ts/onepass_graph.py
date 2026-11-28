#!/usr/bin/env python3
"""Experimental cold graph execution, independent of the audit baseline.

Run each historical fixture exactly once, suspend its eligible tsc call while
capturing inputs, union compatible graphs, then resume the original assertions.
Compare to independent capture only AFTER this run. Unsupported calls or failed
groups fall back to the real compiler. Nothing enters the release workflow.
"""
import importlib.util,json,os,pathlib,shutil,subprocess,sys,tempfile,time
here=pathlib.Path(__file__).resolve().parent
root=here.parents[2]
spec=importlib.util.spec_from_file_location("regressions",root/"harmonyos/tools/run_regressions.py")
suite=importlib.util.module_from_spec(spec);spec.loader.exec_module(suite)
queue=pathlib.Path(os.environ["SHOWLY_ONEPASS_QUEUE"]).resolve()
queue.mkdir(parents=True,exist_ok=True)
real=os.environ["SHOWLY_REAL_TSC"]
start=time.monotonic()
processes={};logs={};starts={};finished={};handled=set();groups_count=0;hits=0
def group_compile(projects):
    global groups_count,hits
    groups=[]
    for p in projects:
        sources={x.name:x.read_bytes() for x in (p/"sources").glob("*.ts")}
        roots=set(json.loads((p/"roots.json").read_text()))
        globals_={n:v for n,v in sources.items() if n.endswith(".d.ts") or not any(t in v for t in (b"export ",b"import "))}
        for g in groups:
            if globals_==g["globals"] and all(g["sources"].get(n,v)==v for n,v in sources.items()):
                g["sources"].update(sources);g["roots"].update(roots);g["projects"].append(p);break
        else:groups.append({"globals":globals_,"sources":sources,"roots":roots,"projects":[p]})
    for g in groups:
        groups_count+=1
        with tempfile.TemporaryDirectory() as tmp:
            work=pathlib.Path(tmp)
            for n,v in g["sources"].items(): (work/n).write_bytes(v)
            result=subprocess.run([real,"--strict","--target","ES2020","--module","commonjs",*sorted(g["roots"])],cwd=work,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
            try:
                if result.returncode: raise RuntimeError(result.stdout)
                lists=json.loads(subprocess.check_output(["node",str(here/"project_outputs.cjs")],input=json.dumps([str(p) for p in g["projects"]]),text=True))
                for p,names in zip(g["projects"],lists):
                    if not names or not all((work/n).is_file() for n in names):
                        (p/"fallback").touch()
                    else:
                        for n in names: shutil.copyfile(work/n,p/"outputs"/n)
                        hits+=1
            except Exception as e:
                print(f"one-pass group fallback: {e}",flush=True)
                for p in g["projects"]: (p/"fallback").touch()
            for p in g["projects"]: (p/"done").touch()
assert len(suite.TESTS)==34 and len(set(suite.TESTS))==34
SPECIALISTS=["test_custom_lists.py","test_statistics.py","test_list_persistence.py","test_ratings.py","test_people.py","test_availability.py","test_comments.py","test_gallery.py","test_sync_coordinator.py","test_observation_delta.py","test_sync_batch_index.py","test_sync_schedule.py","test_background_observation.py","test_startup_read_state.py","test_manual_sync.py","test_export_evidence.py","test_sync_merge_batch.py","test_sync_metadata_archive.py","test_archive_sync.py","test_sync_run_state.py"]
specialists_mode='--specialists' in sys.argv[1:]
tests=SPECIALISTS if specialists_mode else suite.TESTS
assert len(set(tests))==len(tests)
try:
    for name in tests:
        env=os.environ.copy();env["SHOWLY_ONEPASS_TEST"]=name
        env["PATH"]=str(here/"onepass-bin")+os.pathsep+env["PATH"]
        log=queue/(name+".log");logs[name]=log
        starts[name]=time.monotonic()
        with log.open("w") as out:
            processes[name]=subprocess.Popen([sys.executable,str(suite.ROOT/name)],env=env,stdout=out,stderr=subprocess.STDOUT)
    while len(finished)<len(processes):
        for name,p in processes.items():
            if name not in finished and p.poll() is not None:
                finished[name]=(p.returncode,time.monotonic()-starts[name])
        pending=[p for p in sorted(queue.iterdir()) if p.is_dir() and (p/"ready").exists() and p not in handled]
        waiting={(p/"test.txt").read_text() for p in pending}
        active=set(processes)-set(finished)
        if pending and active.issubset(waiting):
            group_compile(pending);handled.update(pending)
        elif active: time.sleep(0.05)
    failures=[]
    for name in tests:
        code,elapsed=finished[name]
        print(f"--- {name} {elapsed:.3f}s exit={code} ---\n{logs[name].read_text()}",flush=True)
        if code: failures.append(name)
    print(f"{len(tests)-len(failures)}/{len(tests)} passed in {time.monotonic()-start:.3f}s; failures={failures}",flush=True)
    print(f"onepass_groups={groups_count} onepass_shared_projects={hits} captured_projects={len(handled)}",flush=True)
    sys.exit(int(bool(failures) or (not specialists_mode and hits==0)))
finally:
    for p in processes.values():
        if p.poll() is None:p.terminate()
