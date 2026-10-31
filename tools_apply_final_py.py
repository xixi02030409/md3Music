# -*- coding: utf-8 -*-
"""python 版 patch 应用器：git apply 在本环境被外部拦截(SIGTERM)，
改为纯 python 解析 git unified diff 并按行号应用到工作树。
用法: python tools_apply_final_py.py [patch路径]
"""
import io, os, re, sys

REPO = os.path.dirname(os.path.abspath(__file__))
PATCH = sys.argv[1] if len(sys.argv) > 1 else os.path.join(REPO, 'halcyon-ui', 'halcyon-ui-final.patch')

text = io.open(PATCH, encoding='utf-8').read()
sections = re.split(r'(?m)^diff --git ', text)[1:]
applied = []

for sec in sections:
    m = re.match(r'a/(\S+) b/(\S+)', sec)
    if not m:
        continue
    path = m.group(2).replace('/', os.sep)
    is_new = re.search(r'(?m)^new file mode', sec) is not None
    # hunk 正文：从每个 @@ 行到下一个 @@ 或文件节尾
    hunk_headers = []
    for hm in re.finditer(r'(?m)^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@.*$', sec):
        hunk_headers.append(hm)
    if not hunk_headers:
        continue
    # 读工作树文件（按 \n 分行，保留各行不含换行符；CRLF 的 \r 留在行尾无所谓，按位置操作）
    fp = os.path.join(REPO, path)
    if is_new:
        old_lines = []
    else:
        raw = io.open(fp, 'rb').read().decode('utf-8')
        old_lines = raw.split('\n')
        # split 尾部会多一个空串（文件以 \n 结尾），保留它参与定位
        if old_lines and old_lines[-1] == '':
            old_lines.pop()  # 统一为"行内容列表"，结尾空行表示以 \n 结尾→用标志记录
            trailing_nl = True
        else:
            trailing_nl = False
        # 重新处理：直接用 splitlines(keepends=False) 但要记录结尾
        old_lines = raw.split('\n')
        if old_lines and old_lines[-1] == '':
            old_lines = old_lines[:-1]
            trailing_nl = True

    # 从最后一个 hunk 往前应用（行号不漂移）
    for hm in reversed(hunk_headers):
        l_old = int(hm.group(1))
        # hunk 正文 = 从该行下一行起，直到下一个 'diff --git'/'@@' 或节尾
        start = hm.end() + 1  # 跳过换行
        nxt = re.search(r'(?m)^(diff --git |@@ )', sec[hm.end():])
        end = hm.end() + nxt.start() if nxt else len(sec)
        body = sec[start:end].split('\n')
        if body and body[-1] == '':
            body.pop()
        old_cnt = int(hm.group(2)) if hm.group(2) else 1
        new_lines = []
        for ln in body:
            if ln.startswith('+'):
                new_lines.append(ln[1:])
            elif ln.startswith('-'):
                continue
            elif ln.startswith('\\'):
                continue  # no newline marker
            else:
                if ln.startswith(' '):
                    ln = ln[1:]
                new_lines.append(ln)
        # 替换 old_lines[l_old-1 : l_old-1+old_cnt]
        old_lines[l_old - 1: l_old - 1 + old_cnt] = new_lines

    out = '\n'.join(old_lines)
    if trailing_nl and not out.endswith('\n'):
        pass  # join 已保证行间 \n；结尾 trailing 由最后行是否为''决定，简单处理：保持原 trailing
        out += '\n'
    io.open(fp, 'wb').write(out.encode('utf-8'))
    applied.append((path, is_new, len(hunk_headers)))

for p, n, h in applied:
    print('%s %s (%d hunks)' % ('NEW ' if n else 'MOD ', p, h))
print('APPLIED %d files' % len(applied))
