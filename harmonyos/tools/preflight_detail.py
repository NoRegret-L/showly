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

sections=(root/"entry/src/main/ets/model/DetailSections.ets").read_text()
assert "ids:{trakt:" not in sections and "images?:{" not in sections
for name in ("DetailPeopleSection","DetailRelatedSection"):
    code=(root/"entry/src/main/ets/pages"/(name+".ets")).read_text()
    assert "private visibility(" not in code and "this.updateSectionVisibility(visible&&ratio>0)" in code
print("Detail section ArkTS named types and component visibility assertions passed")

# Refresh accepts exactly one child per branch. Account-keyed ForEach must
# stay inside the single Column, not be a direct child of Refresh.
refresh=p.split("Refresh({ refreshing: $$this.refreshing })",1)[1]
assert "if(this.collectionFilter==='lists'){\n            Column(){\n              ForEach([this.currentProgressScope()]" in refresh
assert "},(scope:string)=>scope)\n            }.width('100%').height('100%')" in refresh
print("Custom lists Refresh single-child branch assertion passed")

# Native two-way binding must retain both dollar signs in the generated source.
assert ".bindSheet($$this.ratingSheetOpen,this.ratingSheet()" in p
assert ".bindSheet($this.ratingSheetOpen" not in p
print("Rating sheet native binding preflight passed")

# Avoid collision with ArkUI CommonAttribute.visibility in custom components.
from pathlib import Path
availability_pages=Path(__file__).resolve().parents[1]/"entry/src/main/ets/pages"
for component in ("StreamingSection","MovieSeriesSection"):
    source=(availability_pages/(component+".ets")).read_text()
    assert "private visibility(" not in source
    assert "private updateSectionVisibility(" in source
    assert "this.updateSectionVisibility(v&&r>0)" in source
print("Availability native visibility method preflight passed")

# Custom component helpers must not shadow inherited ArkUI attributes.
comment_page=(root/"entry/src/main/ets/pages/CommentsPage.ets").read_text()
assert "private key(" not in comment_page and "this.key(" not in comment_page
assert "private commentRowKey(" in comment_page and comment_page.count("this.commentRowKey(")==2
assert ".bindSheet($$this.commentSheetOpen,this.commentSheet()" in p
print("Comments native component key and sheet preflight passed")
