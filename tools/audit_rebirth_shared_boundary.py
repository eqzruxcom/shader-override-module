"""Fail-closed boundary audit for five pinned native Remake lighting variants.

This is a narrow structural proof for these exact shaders, not a general DXBC
uniformity analyzer. The existing preserved native binaries remain authoritative.
"""
import argparse
import hashlib
import json
import re
from pathlib import Path


def sha(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest().upper()


def require(test, message):
    if not test:
        raise ValueError(message)


def writes(lines, register):
    reg, lanes = register.split(".")
    found=[]
    for i, line in enumerate(lines):
        m=re.match(r"\w+(?:_\w+)* (r\d+)\.([xyzw]+),", line)
        if m and m[1]==reg and set(m[2]) & set(lanes):
            found.append((i,line))
    return found


def audit(directory):
    receipt=json.loads((directory/"candidate.json").read_text())
    require(len(receipt["variants"])==5, "Expected five pinned variants")
    offsets=[None,"0x00008700","0x00010e00","0x00019500","0x00021c00"]
    reports=[]
    for v, offset in zip(receipt["variants"], offsets):
        name=v["shaderHash"]
        binary=directory/"validation"/(name+"-original.bin")
        listing=directory/"validation"/(name+"-original.asm")
        require(sha(binary)==v["originalSha256"], "Native binary changed")
        lines=[s.strip() for s in listing.read_text().splitlines() if s.strip() and not s.lstrip().startswith("//")]
        first=lines.index("dcl_thread_group 16, 16, 1")+1
        tile_slot=11 if v["depthSlot"]==5 else 10
        structured_slot=tile_slot+1
        head=[]
        if offset is not None:
            head.append(f"iadd r0.x, vThreadGroupID.x, l({offset})")
            address="r0.xxxx"
        else:
            address="vThreadGroupID.xxxx"
        head += [f"ld_indexable(buffer)(uint,uint,uint,uint) r0.x, {address}, t{tile_slot}.xyzw",
                 "and r1.x, r0.x, l(255)", "ushr r1.y, r0.x, l(8)",
                 "imad r0.yz, r1.xxyx, l(0, 16, 16, 0), vThreadIDInGroup.xxyx",
                 "iadd r1.xy, r0.yzyy, cb0[1].xyxx",
                 f"ld_structured_indexable(structured_buffer, stride=80)(mixed,mixed,mixed,mixed) r0.w, r0.x, l(0), t{structured_slot}.xxxx",
                 "ine r2.x, cb0[4].y, l(0)", "ult r2.y, l(64), r0.w", "and r2.x, r2.y, r2.x",
                 "if_nz r2.x", "store_uav_typed u0.xyzw, r1.xyyy, l(2.000000,0,0,1.000000)", "ret", "endif"]
        require(lines[first:first+len(head)]==head, f"Unaudited thread/tile/debug prefix: {name}")
        anchor=lines.index(v["insertion"])
        require(lines.count(v["insertion"])==1 and lines.count(v["indexCapture"])==1, "Ambiguous insertion")
        stack=[]; top_loops=[]; anchor_stack=None; loop_end=None
        for i,line in enumerate(lines):
            if i==anchor:
                anchor_stack=list(stack)
            if line=="loop":
                if not stack: top_loops.append(i)
                stack.append(("loop",i))
            elif line.startswith("if_"):
                stack.append(("if",i))
            elif line in ("endif","endloop"):
                kind="if" if line=="endif" else "loop"
                require(stack and stack[-1][0]==kind,"Unbalanced native flow")
                opened=stack.pop()
                if opened in (anchor_stack or []): loop_end=i
        require(not stack and len(top_loops)==2 and anchor_stack==[("loop",top_loops[1])],
                "Insertion is not directly in the outer common light loop")
        start=top_loops[1]
        match=re.fullmatch(r"uge (r\d+\.[xyzw]), (r\d+\.[xyzw]), r0.w",lines[start+1])
        require(match is not None and lines[start+2]==f"breakc_nz {match[1]}","Unknown light loop bound")
        counter=match[2]
        require(lines[start-3]==f"mov {counter}, l(0)" and
                writes(lines[start-3:loop_end+1],counter)==[(0,f"mov {counter}, l(0)"),(loop_end-start+2,f"iadd {counter}, {counter}, l(1)")],
                "Light counter can vary per pixel or changes unexpectedly")
        require([line for _,line in writes(lines[first+len(head):loop_end+1],"r0.w")]==["umin r0.w, r0.w, l(64)"],"Light count mutated")
        require(not writes(lines[first+len(head):loop_end+1],"r0.x"),"Tile identity mutated")
        require(not writes(lines[first+len(head):loop_end+1],"r1.xy"),"Pixel mapping mutated")
        require(not any(re.match(r"(?:ret|continue|call|label|sync|discard)",s) for s in lines[start:loop_end]),"Unsafe native loop escape/side effect")
        require(sum(s.startswith("breakc") for s in lines[start:loop_end])==1,"Extra light-loop break")
        require(not any(s.startswith("dcl_tgsm") for s in lines),"Native shared memory conflict")
        capture_index=lines.index(v["indexCapture"])
        require(capture_index==start+8,"Unexpected light-index capture boundary")
        # Exact packed index extraction: common tile, common counter, read-only data.
        reg=v["indexCapture"].split()[1].rstrip(",")
        require(lines[start+3]==f"and {reg}, {counter}, l(-4)" and lines[start+4]==f"iadd {reg}, {reg}, l(16)","Unknown packed-list offset")
        require(lines[start+5]==f"ld_structured_indexable(structured_buffer, stride=80)(mixed,mixed,mixed,mixed) {reg}, r0.x, {reg}, t{structured_slot}.xxxx", "Unknown light index resource")
        bitfield=re.fullmatch(r"bfi (r\d+\.[xyzw]), l\(2\), l\(3\), "+re.escape(counter)+r", l\(0\)",lines[start+6])
        require(bitfield is not None and lines[start+7]==f"ushr {reg}, {reg}, {bitfield[1]}","Unknown packed index shift")
        require(len([s for s in lines if s=="ret"])==2, "Unaudited early return")
        reports.append({"shaderHash":name,"originalSha256":sha(binary),"assemblySha256":sha(listing),
                        "instructionsSha256":hashlib.sha256("\n".join(lines).encode("utf-8")).hexdigest().upper(),
                        "groupSize":[16,16,1],"tileListSlot":tile_slot,"tileRecordsSlot":structured_slot,
                        "outerCounter":counter,"insertion":v["insertion"],"indexCapture":v["indexCapture"],
                        "commonOuterLightLoop":True,"groupUniformEarlyDebugReturn":True,
                        "nativeSharedMemoryBytes":0,"barriersMustPrecedePerPixelContributionGate":True})
    return {"schemaVersion":1,"result":"verified-pinned-native-boundary","variants":reports,
            "runtimeEligible":False,"scriptSha256":sha(Path(__file__)),
            "limits":["Requires captured native input/index at the specified anchors",
                      "Requires group-uniform control/light selection around barriers",
                      "16x16 group origins must preserve absolute 2x2 quads (even viewport origin)",
                      "All threads, including invalid receivers and zero native contributions, reach both barriers",
                      "Shared writes must be complete before reads, and readers complete before next light overwrites",
                      "Does not prove donor raster/helper equivalence, motion quality or hardware cost"]}


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("candidate",type=Path)
    p.add_argument("output",type=Path)
    args=p.parse_args()
    repo=Path(__file__).resolve().parents[1]
    out=args.output.resolve()
    require(out.is_relative_to(repo/"artifacts") and out!=repo/"artifacts" and not out.exists(),"Use a fresh artifact directory")
    report=audit(args.candidate.resolve())
    out.mkdir(parents=True)
    (out/"boundary.json").write_text(json.dumps(report,indent=2)+"\n",encoding="utf-8")
    print(json.dumps(report,indent=2))


if __name__=="__main__":
    main()
