# -*- coding: utf-8 -*-
"""final 成品补丁 v5：相对上游基线 48cfaa1 生成（CI 是 checkout 上游后 apply --3way）。

v5 变更（修 v4 基线错误）：v4 对本地 HEAD diff，而本地 HEAD 已含 v2 全部改动，
导致 patch apply 到上游时内容错乱（v2 已有内容被当作删除）。正确口径：
diff(48cfaa1..工作树) —— patch 描述"从上游基线到最终状态"的全部改动。
用法：python tools_make_final2.py
"""
import io, os, subprocess, sys, tempfile, shutil

REPO = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(REPO, 'halcyon-ui', 'halcyon-ui-final.patch')
BASE = '48cfaa1'  # 上游 md3Music 基线（v1 APK 对应的上游提交）

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

# diff 上游基线 → 工作树（8 文件全部 tracked，无需 add -N；保险起见保留）
for f in FILES:
    run(['git', 'add', '-N', f], REPO, check=False)
r = run(['git', 'diff', '--no-color', '--no-ext-diff', BASE, '--'] + FILES, REPO)
patch = r.stdout
if not patch:
    print('EMPTY PATCH?'); sys.exit(1)
io.open(OUT, 'w', encoding='utf-8', newline='\n').write(patch)
print('patch written: %d bytes, %d lines' % (len(patch.encode('utf-8')), patch.count('\n')))

# ---- 验证：tmp = BASE 8 文件 LF blob → apply → 与工作树 clean 版对比 ----
tmp = tempfile.mkdtemp(prefix='final2_verify_')
try:
    run(['git', 'init', '-q', '.'], tmp)
    run(['git', 'config', 'core.autocrlf', 'false'], tmp)
    for f in FILES:
        blob = subprocess.run(['git', 'show', BASE + ':' + f], cwd=REPO,
                              capture_output=True)
        if blob.returncode != 0:
            continue  # 基线不存在的新文件，由补丁创建
        p = os.path.join(tmp, f.replace('/', os.sep))
        os.makedirs(os.path.dirname(p), exist_ok=True)
        io.open(p, 'wb').write(blob.stdout)
    run(['git', 'apply', '--verbose', os.path.abspath(OUT)], tmp)
    bad = 0
    for f in FILES:
        ap = os.path.join(tmp, f.replace('/', os.sep))
        if not os.path.exists(ap):
            print('MISSING after apply:', f); bad += 1; continue
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
    print('REPLAY VERIFY vs BASE %s: byte-identical OK' % BASE)
finally:
    shutil.rmtree(tmp, ignore_errors=True)
print('DONE')
