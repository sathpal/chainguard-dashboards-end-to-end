"""List every container image a directory tree refers to, with where it is referenced.

  inventory.py <dir>     prints: image <TAB> file:line

Covers the three places images usually hide: FROM in Dockerfiles (build-stage names skipped), image: in Kubernetes
manifests, and repository/tag pairs in Helm values files. Template expressions are skipped; the values they read are
found in values.yaml. Standard library only.
"""
import os
import re
import sys

root = sys.argv[1]
for dirpath, _, files in os.walk(root):
    for name in sorted(files):
        path = os.path.join(dirpath, name)
        rel = os.path.relpath(path, root)
        lines = open(path, errors="replace").read().splitlines()
        if name == "Dockerfile" or name.endswith(".Dockerfile"):
            stages = set()
            for i, line in enumerate(lines, 1):
                m = re.match(r"\s*FROM\s+(?:--platform=\S+\s+)?(\S+)(?:\s+AS\s+(\S+))?", line, re.I)
                if m:
                    if m.group(1).lower() not in stages and m.group(1).lower() != "scratch":
                        print(f"{m.group(1)}\t{rel}:{i}")
                    if m.group(2):
                        stages.add(m.group(2).lower())
        elif name.endswith((".yaml", ".yml")):
            repo = None
            for i, line in enumerate(lines, 1):
                m = re.match(r"\s*-?\s*image:\s*[\"']?([^\"'\s{]+)[\"']?\s*$", line)
                if m:
                    print(f"{m.group(1)}\t{rel}:{i}")
                m = re.match(r"\s*repository:\s*[\"']?([^\"'\s]+)", line)
                if m:
                    repo = (m.group(1), i)
                m = re.match(r"\s*tag:\s*[\"']?([^\"'\s]+)", line)
                if m and repo:
                    print(f"{repo[0]}:{m.group(1)}\t{rel}:{repo[1]}")
                    repo = None
