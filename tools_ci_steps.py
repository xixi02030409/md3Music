# -*- coding: utf-8 -*-
"""轻量查 run 步骤结论。用法: python tools_ci_steps.py <run_id>"""
import subprocess, json, urllib.request, sys, os

run_id = sys.argv[1]
tok_file = os.path.join(os.path.dirname(os.path.abspath(__file__)), '.gh_token')
if os.path.exists(tok_file):
    token = open(tok_file).read().strip()
else:
    r = subprocess.run(['git', 'credential', 'fill'],
                       input='protocol=https\nhost=github.com\n\n',
                       capture_output=True, text=True, timeout=60)
    token = [l.split('=', 1)[1] for l in r.stdout.splitlines()
             if l.startswith('password=')][0]
hdr = {'Authorization': 'Bearer ' + token,
       'Accept': 'application/vnd.github+json'}
req = urllib.request.Request(
    'https://api.github.com/repos/xixi02030409/md3Music/actions/runs/%s/jobs'
    % run_id, headers=hdr)
jobs = json.load(urllib.request.urlopen(req, timeout=30))
out = []
for job in jobs['jobs']:
    out.append('JOB: %s %s' % (job['name'], job['conclusion']))
    for s in job['steps']:
        out.append('  %-44s %s' % (s['name'][:44], s['conclusion']))
print('\n'.join(out))
