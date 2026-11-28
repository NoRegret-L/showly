#!/usr/bin/env python3
"""SDK-independent early check of all ArkUI struct methods, plus optional SDK declarations."""
import argparse,pathlib,re
root=pathlib.Path(__file__).resolve().parents[1]/"entry/src/main/ets"
parser=argparse.ArgumentParser()
parser.add_argument("--sdk",type=pathlib.Path)
args=parser.parse_args()
# CommonAttribute methods verified in previous native failures, plus common
# native properties. Don't flag plain model classes or component fields.
reserved=set("key visibility width height size padding margin backgroundColor border borderRadius opacity enabled onClick onChange onTouch onAppear onDisAppear bindSheet bindPopup id stateStyles position align translate scale rotate zIndex clip layoutWeight focusable".split())
if args.sdk:
    for path in args.sdk.rglob("common.d.ts"):
        if "component" not in path.parts: continue
        source=path.read_text(errors="ignore")
        # SDK CommonMethod/CommonAttribute names, including inherited overloads.
        for match in re.finditer(r"(?:interface|class)\s+(?:CommonMethod|CommonAttribute)\b[^\{]*\{",source):
            start=match.end();depth=1;end=start
            while end<len(source) and depth:
                if source[end]=="{":depth+=1
                elif source[end]=="}":depth-=1
                end+=1
            reserved.update(re.findall(r"^\s*(\w+)\s*(?:<[^\n]*>)?\s*\(",source[start:end-1],re.M))
# Check methods at struct member indentation, not callback expressions or UI builders.
errors=[];count=0
for path in root.rglob("*.ets"):
    source=path.read_text()
    for n,line in enumerate(source.splitlines(),1):
        if re.search(r"^\s*for\s*\(\s*(?:const|let|var)\s*\[",line):errors.append(f"{path.name}:{n}: ArkTS destructuring loop declaration")
    if not re.search(r"@Component(?:V2)?\b",source):continue
    count+=1
    for n,line in enumerate(source.splitlines(),1):
        m=re.match(r"^\s*(?:(?:private|public|protected|async|static)\s+)+(\w+)\s*\(",line)
        if m and m.group(1) in reserved:errors.append(f"{path.name}:{n}: inherited ArkUI attribute {m.group(1)}")
    for n,line in enumerate(source.splitlines(),1):
        if re.search(r"\.bindSheet\(\$this\.",line):errors.append(f"{path.name}:{n}: single-dollar sheet binding")
assert not errors,"\n".join(errors)
print(f"ArkUI component preflight: {count} files, {len(reserved)} reserved methods, no collision")
