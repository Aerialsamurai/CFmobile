"""Counts which characters / operators appear in real competitive-programming C++ code, and how costly each is to type on
the iPhone keyboard. Usage: python3 -I tools/research/analyze.py <corpus_dir> <out.json>"""
import collections, json, os, re, sys

root, out = sys.argv[1], sys.argv[2]
SKIP = ("lighting_hdr", "Cpp-How-To-Program", "jadegit")

def strip_comments(src):
    src = re.sub(r"/\*.*?\*/", "", src, flags=re.S)
    return re.sub(r"//[^\n]*", "", src)

files = []
for dp, _, fn in os.walk(root):
    if any(s in dp for s in SKIP): continue
    for f in fn:
        try:
            t = open(os.path.join(dp, f), "r", errors="ignore").read()
        except Exception:
            continue
        if len(t) < 200 or "main" not in t and "solve" not in t and "class" not in t and "struct" not in t:
            continue
        files.append(strip_comments(t))
print("files analysed:", len(files))

chars = collections.Counter()
file_has = collections.Counter()
total_chars = 0
total_lines = 0
for t in files:
    total_chars += len(t); total_lines += t.count("\n") + 1
    c = collections.Counter(ch for ch in t if ch in "!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~")
    chars.update(c)
    for ch in c: file_has[ch] += 1

tokens = [";;", "<<", ">>", "::", "==", "!=", "<=", ">=", "&&", "||", "++", "--", "+=", "-=", "*=", "/=", "%=", "->", "[]", "()", "{}", "<>", "\"\"", "''", "#include", "cin >>", "cin>>", "cout <<", "cout<<", "endl", "\"\\n\"", "'\\n'", ".size()", ".begin()", ".end()", "push_back", "for (", "for(", "while", "return", "long long", "vector<", "pair<", "map<", "set<", "auto", "int main", "{\n"]
tok = {}
for k in tokens:
    n = sum(t.count(k) for t in files)
    tok[k] = n

res = {
    "files": len(files), "chars": total_chars, "lines": total_lines,
    "per_1000_chars": {k: round(v * 1000 / total_chars, 2) for k, v in chars.most_common()},
    "per_line": {k: round(v / total_lines, 3) for k, v in chars.most_common()},
    "files_with_pct": {k: round(100 * file_has[k] / len(files), 1) for k, _ in chars.most_common()},
    "tokens_per_1000_lines": {k: round(v * 1000 / total_lines, 1) for k, v in tok.items()},
}
json.dump(res, open(out, "w"), indent=1)
print("lines:", total_lines, "chars:", total_chars)
print("top symbols per 1000 chars:")
for k, v in list(res["per_1000_chars"].items())[:26]:
    print(f"  {k!r:5} {v:6.2f}   in {res['files_with_pct'][k]:5.1f}% of files   {res['per_line'][k]:.2f}/line")
print("tokens per 1000 lines:")
for k, v in sorted(res["tokens_per_1000_lines"].items(), key=lambda kv: -kv[1])[:28]:
    print(f"  {k!r:12} {v}")
