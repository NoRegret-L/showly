#!/usr/bin/env python3
"""Run before pushing (and in CI); no network or SDK required."""
from pathlib import Path
import ast
from prepare_preview_release import validate_source
root=Path(__file__).resolve().parents[1]
validate_source(root)
for script in (root/"tools").glob("*.py"):
    ast.parse(script.read_text(), filename=str(script))
p=(root/"entry/src/main/ets/pages/Index.ets").read_text()
assert "DetailViewOwner<MediaDetail>" in p
assert "@State detailUi:" in p and "@State detailBusy:" not in p
assert "message:'选择时间范围'" in p
assert "this.detailOwner.current(token,scope,item.id)" in p
assert "this.detailSession.read(scope,item.id,readRevision)" in p
assert "consumer=this.detailConsumer" in p and "readDetails(item,clientId,reload,consumer)" in p
print("Source versions, Python syntax, detail lifecycle and historical dialog assertions passed")
