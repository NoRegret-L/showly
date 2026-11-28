#!/usr/bin/env python3
"""Execute the exact historical suite on available CPUs; report every failure."""
import concurrent.futures
import os
from pathlib import Path
import subprocess
import sys
import time
ROOT=Path(__file__).resolve().parent
TESTS=["test_personal_library.py","test_library_index.py","test_show_catalog.py","test_remote_observation.py","test_effective_state.py","test_feature_first.py","test_title_quick.py","test_navigation.py","test_progress_rules.py","test_presentation.py","test_movie_progress.py","test_startup_performance.py","test_persistent_projection.py","test_collection_rules.py","test_batch_projection.py","test_shared_reads.py","test_rendering_performance.py","test_indexed_projection.py","test_display_isolation.py","test_discover_cache.py","test_calendar_local.py","test_presentation_policy.py","test_search_local.py","test_progress_candidates.py","test_cache_lifecycle.py","test_consumer_lifecycle.py","test_scroll_anchor.py","test_viewport_scheduler.py","test_detail_session.py","test_commit_delta.py","test_artwork_pipeline.py","test_projection_delta.py","test_presentation_queue.py","test_page_state_owner.py"]
def run(name):
    start=time.monotonic()
    result=subprocess.run([sys.executable,str(ROOT/name)],stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
    return name,result.returncode,time.monotonic()-start,result.stdout
def main():
    assert len(TESTS)==34 and len(set(TESTS))==34
    # Compile and run independent fixtures in separate temporary directories.
    # OS affinity determines concurrency; executor assigns the next job to
    # whichever worker finishes first, no fixed tuning constant.
    workers=min(len(TESTS),len(os.sched_getaffinity(0)) if hasattr(os,'sched_getaffinity') else (os.cpu_count() or 1))
    print(f"Running {len(TESTS)} regressions with {workers} available CPUs",flush=True)
    start=time.monotonic(); failed=[]
    # Measured Build 75 longest jobs first, remaining stable inventory order.
    previous={"test_presentation_queue.py":16.433,"test_commit_delta.py":10.019,"test_library_index.py":8.915,"test_search_local.py":7.644,"test_projection_delta.py":6.900}
    ordered=sorted(TESTS,key=lambda name:previous.get(name,0),reverse=True)
    with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as pool:
        jobs=[pool.submit(run,name) for name in ordered]
        for job in concurrent.futures.as_completed(jobs):
            name,code,elapsed,output=job.result()
            print(f"--- {name} {elapsed:.3f}s exit={code} ---\n{output}",flush=True)
            if code: failed.append(name)
    print(f"{len(TESTS)-len(failed)}/{len(TESTS)} passed in {time.monotonic()-start:.3f}s; failures={failed}",flush=True)
    return int(bool(failed))
if __name__=='__main__':sys.exit(main())
