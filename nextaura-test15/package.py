from pathlib import Path
import base64, hashlib, plistlib, shutil, subprocess, sys

root = Path(sys.argv[1])
guard = Path(sys.argv[2])
preview = Path(sys.argv[3])
out = Path(sys.argv[4])
work = Path(sys.argv[5])
if work.exists(): shutil.rmtree(work)
(work/'stage').mkdir(parents=True)
(work/'control').mkdir(parents=True)

parts = sorted((root/'nextaura-test15/base').glob('part*.b64'))
if not parts: raise SystemExit('base package chunks missing')
raw = base64.b64decode(''.join(p.read_text() for p in parts))
base_deb = work/'base.deb'
base_deb.write_bytes(raw)
expected = (root/'nextaura-test15/base/sha256.txt').read_text().strip().split()[0]
actual = hashlib.sha256(raw).hexdigest()
if actual != expected: raise SystemExit(f'base checksum mismatch: {actual} != {expected}')

subprocess.run(['dpkg-deb','-x',str(base_deb),str(work/'stage')],check=True)
subprocess.run(['dpkg-deb','-e',str(base_deb),str(work/'control')],check=True)

dylib_dir = work/'stage/Library/MobileSubstrate/DynamicLibraries'
dylib_dir.mkdir(parents=True,exist_ok=True)
shutil.copy2(guard,dylib_dir/'ZZNextAuraSwitcherOpeningGuard.dylib')
shutil.copy2(preview,dylib_dir/'ZZNextAuraSwitcherSettingsPreview.dylib')

spring_filter = {'Filter': {'Bundles': ['com.apple.springboard']}}
prefs_filter = {'Filter': {'Bundles': ['com.apple.Preferences']}}
with (dylib_dir/'ZZNextAuraSwitcherOpeningGuard.plist').open('wb') as f:
    plistlib.dump(spring_filter,f,fmt=plistlib.FMT_XML,sort_keys=False)
with (dylib_dir/'ZZNextAuraSwitcherSettingsPreview.plist').open('wb') as f:
    plistlib.dump(prefs_filter,f,fmt=plistlib.FMT_XML,sort_keys=False)

bundle = work/'stage/Library/PreferenceBundles/UnlockVibratePrefs.bundle'
app_path = bundle/'AppSwitcher.plist'
with app_path.open('rb') as f: app = plistlib.load(f)
items = app.get('items',[])
if items:
    items[0]['footerText'] = ('The preview above updates immediately as options change. The real App Switcher changes only after tapping Apply Switcher Changes (Respring). When opening from Home or any app, SafeSuite effects are blocked until the first deliberate horizontal swipe.')
items = [item for item in items if item.get('label') not in ('Live Modification','Refresh Live Switcher','Show Live Preview')]
app['items'] = items
with app_path.open('wb') as f: plistlib.dump(app,f,fmt=plistlib.FMT_XML,sort_keys=False)

control = work/'control/control'
lines=[]
for line in control.read_text().splitlines():
    if line.startswith('Version:'): line='Version: 4.4.9-test15'
    elif line.startswith('Name:'): line='Name: NextAura Tester'
    elif line.startswith('Description:'):
        line=('Description: Private RootHide tester 15. Adds an embedded live visual App Switcher preview inside Settings, blocks only SafeSuite-originated transforms while the switcher opens from Home or any app so Apple\'s stock opening animation remains intact, releases the chosen effect after the first deliberate horizontal swipe, keeps Respring as the real apply action, and preserves switcher-only reset controls.')
    lines.append(line)
control.write_text('\n'.join(lines)+'\n')

pkg = work/'pkg'
shutil.copytree(work/'stage',pkg)
shutil.copytree(work/'control',pkg/'DEBIAN')
for script in ('preinst','postinst','prerm','postrm'):
    path=pkg/'DEBIAN'/script
    if path.exists(): path.chmod(0o755)
out.parent.mkdir(parents=True,exist_ok=True)
if out.exists(): out.unlink()
subprocess.run(['dpkg-deb','--root-owner-group','-Zzstd','-b',str(pkg),str(out)],check=True)
sha=hashlib.sha256(out.read_bytes()).hexdigest()
(out.parent/(out.name+'.sha256')).write_text(f'{sha}  {out.name}\n')
print(out)
print(sha)
