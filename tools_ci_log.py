# -*- coding: utf-8 -*-
"""拉取指定 Actions run 的失败日志。用法: python tools_ci_log.py <run_id>"""
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


def get_log(url):
    req = urllib.request.Request(url, headers=hdr)

    class NR(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, *a, **k):
            return None
    op = urllib.request.build_opener(NR)
    try:
        return op.open(req, timeout=60).read()
    except urllib.error.HTTPError as e:
        if e.status == 302:
            return urllib.request.urlopen(e.headers['Location'],
                                          timeout=120).read()
        raise


jobs = json.loads(get_log(
    'https://api.github.com/repos/xixi02030409/md3Music'
    '/actions/runs/%s/jobs' % run_id))
for job in jobs['jobs']:
    for s in job['steps']:
        if s['conclusion'] not in ('success', 'skipped', None):
            print('FAIL STEP:', s['name'])
    if job['conclusion'] == 'failure':
        text = get_log(job['url'] + '/log').decode('utf-8', 'ignore')
        for line in text.splitlines():
            low = line.lower()
            if '##[error]' in line or low.startswith('error:') \
                    or ' error:' in low[:80] or 'exception' in low[:80]:
                print(line[:240])
