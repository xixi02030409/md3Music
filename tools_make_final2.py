# -*- coding: utf-8 -*-
"""final 成品补丁 v4：push-work 树专用（在真实仓库生成，autocrlf 原生 clean）。
v4 变更：+secondary_mini_player.dart +halcyon_dock_bar.dart（底栏重做批次）。
用法：python tools_make_final2.py
"""
import io, os, subprocess, sys, tempfile, shutil

REPO = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(REPO, 'halcyon-ui', 'halcyon-ui-final.patch')

FILES = [
    'lib/app.dart',
    'lib/core/layout/bottom_chrome_scope.dart',
    'lib/core/layout/responsive_layout.dart',
    'lib/modules/player/mini_player.dart',
    'lib/modules/player/secondary_mini_player.dart',
    'lib/modules/user/listen_stats_page.dart',
    'lib/widgets/halcyon_glass.dart',
    'lib/widgets/halcyon_dock_bar.dart',
]

def run(cmd, cwd, check=True):
    r = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)
    if check and r.returncode != 0:
        print('CMD FAIL:', ' '.join(cmd))
        print(r.stdout[-1500:]); print(r.stderr[-1500:])
        sys.exit(1)
    return r

# 新文件需要 git add -N 才会出现在 git diff
for f in FILES:
    run(['git', 'add', '-N', f], REPO, check=False)
r = run(['git', 'diff', '--no-color', '--no-ext-diff', '--'] + FILES, REPO)
patch = r.stdout
if not patch:
    print('EMPTY PATCH?'); sys.exit(1)
io.open(OUT, 'w', encoding='utf-8', newline='\n').write(patch)
print('patch written: %d bytes, %d lines' % (len(patch.encode('utf-8')), patch.count('\n')))

# ---- 验证：tmp = HEAD 8 文件 LF blob → apply → 与工作树 clean 版对比 ----
tmp = tempfile.mkdtemp(prefix='final2_verify_')
try:
    run(['git', 'init', '-q', '.'], tmp)
    run(['git', 'config', 'core.autocrlf', 'false'], tmp)
    for f in FILES:
        blob = subprocess.run(['git', 'show', 'HEAD:' + f], cwd=REPO,
                              capture_output=True)
        if blob.returncode != 0:
            continue  # 新文件，补丁创建
        p = os.path.join(tmp, f.replace('/', os.sep))
        os.makedirs(os.path.dirname(p), exist_ok=True)
        io.open(p, 'wb').write(blob.stdout)
    run(['git', 'apply', '--verbose', os.path.abspath(OUT)], tmp)
    bad = 0
    for f in FILES:
        ap = os.path.join(tmp, f.replace('/', os.sep))
        if not os.path.exists(ap):
            continue
        applied = open(ap, 'rb').read()
        wt = open(os.path.join(REPO, f.replace('/', os.sep)), 'rb').read()
        wt_clean = wt.replace(b'\r\n', b'\n')
        if applied != wt_clean:
            print('MISMATCH:', f)
            al, wl = applied.split(b'\n'), wt_clean.split(b'\n')
            for i, (x, y) in enumerate(zip(al, wl)):
                if x != y:
                    print('  line %d:\n   applied: %r\n   workspace: %r' % (i + 1, x[:80], y[:80]))
                    break
            bad += 1
    if bad:
        sys.exit(1)
    print('REPLAY VERIFY: byte-identical OK')
finally:
    shutil.rmtree(tmp, ignore_errors=True)
print('DONE')
