#!/usr/bin/env python3
"""Conservative, experimental file-access exclusion list. Never production."""
import pathlib,sys,re,os
base=pathlib.Path(sys.argv[1]).resolve()
sdk=base/"command-line-tools/sdk"
assert sdk.is_dir()
trace=pathlib.Path(sys.argv[2])
out=pathlib.Path(sys.argv[3])
names=set();paths=set();enumerated=set()
for log in trace.parent.glob(trace.name+"*"):
    for line in log.open(errors="replace"):
        for token in re.findall(r'"([^"\\]*(?:\\.[^"\\]*)*)"|<([^<>]+)>',line):
            value=token[0] or token[1]
            if not value:continue
            names.add(pathlib.PurePosixPath(value).name)
            if value.startswith(str(sdk)+"/"):paths.add(os.path.normpath(value))
        if "getdents64(" in line:
            for value in re.findall(r"<([^<>]+)>",line):
                if value.startswith(str(sdk)+"/"):enumerated.add(os.path.normpath(value))
assert paths,"No SDK paths recorded; refuse pruning"
# Keep symlinks and resolved targets, executable files, files in enumerated
# directories, and any observed basename (relative opens conservatively kept).
protected=set()
for p in sdk.rglob("*"):
    if p.is_symlink():
        resolved=p.resolve()
        if resolved.is_dir():
            protected.add(str(resolved)+"/")
        else:paths.add(str(resolved))
total=kept=excluded=0;exclude=[]
for p in sdk.rglob("*"):
    if p.is_symlink() or not p.is_file():continue
    size=p.stat().st_size;total+=size
    if str(p) in paths or p.name in names or str(p.parent) in enumerated or p.stat().st_mode&0o111 or any(str(p).startswith(q) for q in protected):
        kept+=size;continue
    rel=p.relative_to(base).as_posix()
    # GNU tar wildcard exclusion list: reject metacharacters.
    if re.search(r"[*?\[\]\\\n\r]",rel):kept+=size;continue
    exclude.extend([rel,"./"+rel]);excluded+=size
out.write_text("\n".join(exclude)+"\n" if exclude else "")
print(f"SDK closure candidate: observed={len(paths)} enumerated={len(enumerated)} excluded_files={len(exclude)//2} excluded_bytes={excluded} kept_bytes={kept} total_bytes={total}")
