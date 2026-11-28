#!/usr/bin/env python3
import pathlib,re,sys
def inventory(file):
    text=pathlib.Path(file).read_text()
    tests=re.findall(r"^--- (test_[^ ]+\.py) [0-9.]+s exit=(\d+) ---$",text,re.M)
    assert len(tests)==34 and len(dict(tests))==34 and all(status=="0" for _,status in tests)
    elapsed=re.search(r"34/34 passed in ([0-9.]+)s",text)
    assert elapsed
    return dict(tests),float(elapsed.group(1)),text
a,base,_=inventory(sys.argv[1])
b,replay,log=inventory(sys.argv[2])
assert a==b
hits=log.count("GRAPH_REPLAY_HIT")
fallback=log.count("GRAPH_REPLAY_FALLBACK")
assert hits>0
print(f"34/34 equivalent test exits; shared_hits={hits} fallback={fallback} independent_suite_seconds={base:.3f} replay_suite_seconds={replay:.3f}")
print("Replay timing excludes capture/validation/union preparation; do not claim cold CI speedup.")
