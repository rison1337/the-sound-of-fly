"""Quick look at the MaleCNS v1.0 feather files: schema, row counts, id cardinality.

Usage: python tools/inspect_data.py [weights|annotations|neurotransmitters]
"""
import sys

import pyarrow.feather as feather

FILES = {
    "weights": r"D:\fly-data\connectome-weights-male-cns-v1.0-minconf-0.5.feather",
    "annotations": r"D:\fly-data\body-annotations-male-cns-v1.0-minconf-0.5.feather",
    "neurotransmitters": r"D:\fly-data\body-neurotransmitters-male-cns-v1.0.feather",
}

which = sys.argv[1] if len(sys.argv) > 1 else "weights"
table = feather.read_table(FILES[which], memory_map=True)

print(f"== {which} ==")
print("rows:", table.num_rows)
print("columns:", table.schema.names)
print(table.slice(0, 5).to_pandas().to_string())

id_cols = [c for c in table.schema.names if "root_id" in c or c in ("bodyId", "body_id")]
for col in id_cols[:2]:
    print(f"unique {col}:", len(table.column(col).unique()))
