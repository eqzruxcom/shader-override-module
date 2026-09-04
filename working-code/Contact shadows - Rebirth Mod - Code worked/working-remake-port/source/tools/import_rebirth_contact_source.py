"""Reproducible donor extraction. Emits an apply_patch patch; never edits files.

The ray section is retained verbatim after LF normalization, except one explicit
depth-resource access substitution. No ray math, branches or loop changes.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
DONOR = ROOT/'reference/ShaderInjector'
COMMIT = 'bab25809b375f028b7c0fb603d804426f38c9b8e'
LOCAL = 'ModifiedShaders/Includes/PixelShaderPass_LocalLight.hlsl'
RANDOM = 'ModifiedShaders/Includes/LibraryRandom.hlsl'
OUTPUT = 'src/ThirdParty/ShaderInjector'

def pinned(path):
    data = subprocess.check_output(['git','-C',str(DONOR),'show',f'{COMMIT}:{path}'])
    text = data.decode('utf-8-sig').replace('\r\n','\n')
    working = (DONOR/path).read_text(encoding='utf-8-sig')
    if text != working:
        raise SystemExit(f'Donor working source differs from pinned commit: {path}')
    return text

def sha(text):
    return hashlib.sha256(text.encode()).hexdigest().upper()

parser = argparse.ArgumentParser()
parser.add_argument('--emit-patch',action='store_true')
args = parser.parse_args()
local, random = pinned(LOCAL), pinned(RANDOM)
start = local.index('#if defined(CONTACT_SHADOWS_IMPROVED_THICKNESS)\n    float PerspectiveCorrectDepth(')
end = local.index('//||||||||||||||||||||||||||||||| SHADING - DEFAULT LIT',start)
section = local[start:end].rstrip()+'\n'
resource = 'SceneTexturesStruct_SceneDepthTexture.SampleLevel(View_SharedPointClampedSampler, uv, 0.0).r'
replacement = 'Redx11ContactSampleDeviceDepth(uv)'
if section.count(resource) != 1:
    raise SystemExit('Unexpected donor resource expression count')
ray = section.replace(resource,replacement)
noise_start = random.index('float InterleavedGradientNoise(float2 pixCoord, int frameCount)')
noise_end = random.index('\n}',noise_start)+2
noise = random[noise_start:noise_end]+'\n'
checker_statement = 'bool checkerboardTest = ((pixelPos.x + pixelPos.y + (int)View_TemporalAAParams.x) & 1) != 0;'
average_statement = 'contactShadow = saturate((lane0 + lane1 + lane2 + lane3) * 0.5 - 1.0);'
for statement in (checker_statement, average_statement):
    if local.count(statement) != 1:
        raise SystemExit('Unexpected donor reconstruction statement count')
# Only the SM6 lane-access plumbing is replaced by explicit scalar parameters.
# These two algorithm statements are copied unchanged from the pinned caller.
reconstruction = ('bool Redx11RebirthCheckerboard(int2 pixelPos, float4 View_TemporalAAParams)\n{\n    '
    +checker_statement+'\n    return checkerboardTest;\n}\n\n'
    +'float Redx11RebirthQuadAverage(float4 lanes)\n{\n'
    +'    float lane0=lanes.x, lane1=lanes.y, lane2=lanes.z, lane3=lanes.w;\n'
    +'    float contactShadow;\n    '+average_statement+'\n    return contactShadow;\n}\n')
header = '// Generated from ShaderInjector '+COMMIT+'.\n// MIT, Copyright (c) 2026 David Matos. See LICENSE.txt and provenance.json.\n// Regenerate/check with tools/import_rebirth_contact_source.py.\n'
config = {}
for line in local.splitlines():
    if line.startswith('#define CONTACT_SHADOW') or line.startswith('#define RANDOM_'):
        parts=line.split(maxsplit=2)
        config[parts[1]]=parts[2] if len(parts)>2 else True
outputs = {
    f'{OUTPUT}/RebirthContactRay.hlsl':header+ray,
    f'{OUTPUT}/RebirthContactNoise.hlsl':header+noise,
    f'{OUTPUT}/RebirthContactReconstruction.hlsl':header+reconstruction,
    f'{OUTPUT}/LICENSE.txt':(ROOT/'licenses/ShaderInjector-MIT.txt').read_text(),
}
provenance = dict(repository='https://github.com/frostbone25/ShaderInjector',commit=COMMIT,
    sourcePath=LOCAL,sourceLfSha256=sha(local),rayFirstLine=local[:start].count('\n')+1,
    originalRayLfSha256=sha(section),adaptedRayLfSha256=sha(ray),
    substitutions=[dict(before=resource,after=replacement,count=1,reason='Remake point-depth binding')],
    noiseSourcePath=RANDOM,noiseSourceLfSha256=sha(random),noiseFunctionLfSha256=sha(noise),
    reconstructionStatements=[dict(statement=s,lfSha256=sha(s),sourceLine=local[:local.index(s)].count('\n')+1)
        for s in (checker_statement,average_statement)],
    reconstructionAdaptation='Unchanged parity and averaging statements; explicit scalar lanes replace SM6 quad access. Caller must supply matching neighbors/phase.',
    donorConfiguration=config,files=[dict(path=p,lfSha256=sha(t)) for p,t in outputs.items()])
outputs[f'{OUTPUT}/provenance.json']=json.dumps(provenance,indent=2)+'\n'
if args.emit_patch:
    print('*** Begin Patch')
    for path,new in outputs.items():
        target=ROOT/path
        if target.exists():
            old=target.read_text(encoding='utf-8')
            if old==new:
                continue
            print('*** Update File: '+target.as_posix())
            print('@@')
            print('\n'.join('-'+line for line in old.splitlines()))
        else:
            print('*** Add File: '+target.as_posix())
        print('\n'.join('+'+line for line in new.splitlines()))
    print('*** End Patch')
else:
    for path,expected in outputs.items():
        if not (ROOT/path).exists() or (ROOT/path).read_text(encoding='utf-8')!=expected:
            raise SystemExit('Generated source mismatch: '+path)
    print('PASS: pinned donor ray logic preserved; one resource substitution; noise and reconstruction algorithm statements unchanged.')
