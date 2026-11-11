"""Samples C++ files from public GitLab competitive-programming projects, to measure which symbols people type most.
Only used for statistics (files are not redistributed or committed).
Usage: python3 -I tools/research/fetch_corpus_gitlab.py <out_dir>
"""
import json, os, random, sys, time, urllib.parse, urllib.request
from concurrent.futures import ThreadPoolExecutor

OUT = sys.argv[1]
API = "https://gitlab.com/api/v4"
random.seed(11)

def get(url, as_json=True):
    req = urllib.request.Request(url, headers={"User-Agent": "cfmobile-research"})
    with urllib.request.urlopen(req, timeout=40) as r:
        data = r.read()
    return json.loads(data) if as_json else data

cands = {}
for q in ["codeforces", "competitive programming", "competitive-programming", "cp solutions", "acm icpc", "algorithms cpp", "leetcode cpp", "atcoder", "codechef", "spoj"]:
    try:
        for p in get(f"{API}/projects?search={urllib.parse.quote(q)}&order_by=star_count&sort=desc&per_page=25&visibility=public"):
            cands[p["id"]] = p
    except Exception as e:
        print("search fail", q, e)
    time.sleep(0.3)
print("candidate projects:", len(cands))

chosen = []
for pid, p in cands.items():
    try:
        langs = get(f"{API}/projects/{pid}/languages")
    except Exception:
        continue
    if langs.get("C++", 0) >= 40:          # mostly C++
        chosen.append(p)
    time.sleep(0.15)
print("mostly-C++ projects:", len(chosen))

jobs = []
for p in chosen[:40]:
    pid, ref = p["id"], p.get("default_branch") or "master"
    paths = []
    try:
        page = 1
        while page <= 6:
            items = get(f"{API}/projects/{pid}/repository/tree?recursive=true&per_page=100&page={page}&ref={ref}")
            if not items: break
            paths += [i["path"] for i in items if i["type"] == "blob" and i["path"].lower().endswith((".cpp", ".cc", ".cxx"))]
            if len(items) < 100: break
            page += 1
    except Exception as e:
        print("tree fail", p["path_with_namespace"], e); continue
    random.shuffle(paths)
    pick = paths[:120]
    print(p["path_with_namespace"], len(paths), "cpp files, sampling", len(pick))
    jobs += [(pid, ref, path, p["path_with_namespace"]) for path in pick]

def fetch(job):
    pid, ref, path, name = job
    dest = os.path.join(OUT, name.replace("/", "__"), path.replace("/", "__"))
    if os.path.exists(dest): return 1
    try:
        data = get(f"{API}/projects/{pid}/repository/files/{urllib.parse.quote(path, safe='')}/raw?ref={urllib.parse.quote(ref)}", as_json=False)
        if len(data) > 40000: return 0
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        open(dest, "wb").write(data)
        return 1
    except Exception:
        return 0

with ThreadPoolExecutor(12) as ex:
    ok = sum(ex.map(fetch, jobs))
print("downloaded", ok, "of", len(jobs))
