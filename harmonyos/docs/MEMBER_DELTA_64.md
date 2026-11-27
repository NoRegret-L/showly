# Build 64: membership and sort reconciliation

Pinned upstream e08cb90: MyShowsRepository/MyMoviesRepository load-by-ID and transactional membership, ProgressMoviesViewModel/MyShowsViewModel/MyMoviesViewModel cancel older loads, BaseAdapter AsyncListDiffer. Android may still fully load on an event; this is not a claim of measured native parity.

MediaInputVersion now has a separate acknowledgement cursor spanning publications. Unknown order changes or cloud/account changes force the complete path. LibraryProjectionSession uses the original resolver for dirty IDs and merges added/removed targets using record, watchlist, remote-show and lexical local-catalog precedence. Exact previous objects remain unchanged. A new checkpoint or incomplete evidence forces full computation. No authority/sync schema change.

StableDisplayOrder reconciles exact typed movie and collection candidates; surviving relative source order must match. Comparator configuration (including pin/hidden versions, scope, query, options, time and language) is still fenced. Changed eligibility, values, additions and removals are removed and reinserted with the original comparator and source ordinal. Full candidate snapshot preparation and linear output copies remain; a relative reorder or changed basis uses full sort. Existing PageDisplayRows diff publication remains unchanged.

Search wire packs seven scalar fields into columns, retaining row order and all model fields; search logic and cancellation are unchanged. Host tests measure UTF-8 input bytes and output parity, not device CPU or IPC time. Packing still traverses the full catalog. No third-party dependencies or empirical hyperparameters. Native tracing retained from Build 63; no device traces captured.
