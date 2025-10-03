#!/usr/bin/env python3
import sys, re, os
import pandas as pd
import matplotlib.pyplot as plt

infile = sys.argv[1] if len(sys.argv) > 1 else "nsd.txt"
outfile = sys.argv[2] if len(sys.argv) > 2 else "all_metrics_hist.png"

SUF = {"": 1, "K": 10**3, "M": 10**6, "G": 10**9}
val_re = re.compile(r"^\s*([0-9]+)\s*([KMG]?)\s*$")

def parse_num(s):
    m = val_re.match(s.strip())
    return int(m.group(1)) * SUF.get(m.group(2), 1) if m else None

data = {}
current_host = None

with open(infile, "r", encoding="utf-8", errors="ignore") as f:
    for raw in f:
        line = raw.strip()
        if not line:
            continue

        # Detect hostname like "mmstor10"
        if re.match(r"^[A-Za-z0-9_.-]+$", line):
            current_host = line
            continue
        if current_host is None:
            continue

        parts = line.split()
        if len(parts) >= 2:
            metric = " ".join(parts[:-1])
            v = parse_num(parts[-1])
            if v is not None:
                key = f"{current_host}.{metric}"
                # Keep only first occurrence
                if key not in data:
                    data[key] = v

# Build dataframe (one column with values)
df = pd.DataFrame(list(data.items()), columns=["Label", "Value"])
df = df.sort_values(by="Value", ascending=False)

# Plot histogram
plt.figure(figsize=(18, 8))
ax = df.plot(kind="bar", x="Label", y="Value", legend=False, figsize=(18, 8))
ax.set_title("All metrics across all servers")
ax.set_xlabel("Server.Metric")
ax.set_ylabel("Value")
ax.tick_params(axis='x', labelrotation=90)
plt.tight_layout()
plt.savefig(outfile, dpi=120)
print(f"Wrote combined histogram: {outfile}")
