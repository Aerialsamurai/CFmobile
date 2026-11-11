"""Samples C++ files from public competitive-programming repositories to measure which symbols people type most.
Only used for statistics (the files are not redistributed or committed).
Usage: python3 -I tools/research/fetch_corpus.py <out_dir>
"""
import json, os, random, sys, time, urllib.request
from concurrent.futures import ThreadPoolExecutor

OUT = sys.argv[1]
REPOS = [
    "Waqar-107/Codeforces", "kantuni/Codeforces", "VastoLorde95/Competitive-Programming",
    "Saurav-Paul/Codeforces-Problem-Solution-By-Saurav-Paul", "abeaumont/competitive-programming",
    "manishbisht/Competitive-Programming", "RahulSurana123/competitive_coding", "lakshyaaa2410/Codeforces-Solutions",
    "sauravbharti021/Codeforces-Solutions", "afrozchakure/Competitive-Programming-Solutions", "notabhishek/Competitive-Programming",
    "hiepxuan2008/competitive-programming", "bira37/problem-solving", "truongcongthanh2000/TrainACM-ICPC-OLP",
]
PER_REPO = 150
random.seed(7)

def get(url, as_json=False):
    req = urllib.request.Request(url, headers={"User-Agent": "cfmobile-research"})
    with urllib.request.urlopen(req, timeout=40) as r:
        data = r.read()
    return json.loads(data) if as_json else data

def fetch_one(args):
    repo, branch, path = args
    dest = os.path.join(OUT, repo.replace("/", "__"), path.replace("/", "__"))
    if os.path.exists(dest):
        return 1
    try:
        data = get(f"https://raw.githubusercontent.com/{repo}/{branch}/{path}")
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        open(dest, "wb").write(data)
        return 1
    except Exception:
        return 0

jobs = []
for repo in REPOS:
    try:
        meta = get(f"https://api.github.com/repos/{repo}", True)
        branch = meta["default_branch"]
        tree = get(f"https://api.github.com/repos/{repo}/git/trees/{branch}?recursive=1", True)
    except Exception as e:
        print("skip", repo, e); continue
    files = [t["path"] for t in tree.get("tree", []) if t["type"] == "blob" and t["path"].lower().endswith((".cpp", ".cc", ".cxx")) and t.get("size", 0) < 30000]
    random.shuffle(files)
    pick = files[:PER_REPO]
    print(repo, "->", len(files), "cpp files, sampling", len(pick))
    jobs += [(repo, branch, p) for p in pick]
    time.sleep(1)

with ThreadPoolExecutor(16) as ex:
    ok = sum(ex.map(fetch_one, jobs))
print("downloaded", ok, "of", len(jobs))
