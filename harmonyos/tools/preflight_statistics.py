from pathlib import Path
root=Path(__file__).resolve().parents[1]/"entry/src/main/ets"
page=(root/"pages/StatisticsPage.ets").read_text()
index=(root/"pages/Index.ets").read_text()
assert "StatisticsPage({" in index and "key===this.currentProgressScope()" in index
assert "this.signal.cancel()" in page and "this.owner.clear()" in page
assert "readDetailSection" in page and "readSeasonPresentation" in page
assert "readRatings" in page and "this.allowed(signal)" in page
print("Statistics route, scope, cache and cancellation source assertions passed")
