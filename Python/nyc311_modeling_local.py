# -*- coding: utf-8 -*-
"""
NYC 311 - Star-schema modeling (local Windows version)

Requirements:  pip install pandas numpy pyarrow
Run:           python nyc311_modeling_local.py
"""

import gc
import zipfile
from pathlib import Path

import numpy as np  
import pandas as pd 
    
# ----------------------------------------------------------------------
# 1) PATHS  (edit only this block)
# ----------------------------------------------------------------------
CSV_PATH = Path(
    r"C:\NYC 311 Service Request\Python\Cleaned Data\NYC_311_2024_CLEANED.csv"
)
BASE_DIR = Path(r"C:\NYC 311 Service Request")

# category.csv is the classification source; the updates file is optional
CATEGORY_CSV = Path(r"C:\NYC 311 Service Request\Python\category.csv" )  # resolution_description -> category
UPDATES_CSV = BASE_DIR / "Resolution_Category_Updates.csv"  # 283 updates

OUTPUT_DIR = Path(r"C:\NYC 311 Service Request\Python\Modeled_Tables")   
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

assert CSV_PATH.exists(), f"CSV not found: {CSV_PATH}"
print("CSV found:", CSV_PATH)

# ----------------------------------------------------------------------
# 2) LOAD
# ----------------------------------------------------------------------
NEEDED = [
    "unique_key", "created_date", "closed_date", "agency", "agency_name",
    "complaint_type", "descriptor", "location_type", "status",
    "resolution_description", "community_board", "borough",
    "open_data_channel_type", "latitude", "longitude", "Resolution_Hours",
]

header = pd.read_csv(CSV_PATH, nrows=0).columns.tolist()
missing_cols = [c for c in NEEDED if c not in header]
if missing_cols:
    raise SystemExit(
        f"These columns are not in the CSV: {missing_cols}\n"
        f"Columns found: {header}\n"
        "Rename them in NEEDED (or in the CSV) and run again."
    )

df = pd.read_csv(CSV_PATH, usecols=NEEDED, dtype="string[pyarrow]")
df = df.rename(columns={"unique_key": "ID"})
original_rows = len(df)
print(f"Requests loaded: {original_rows:,} | columns: {df.shape[1]}")


def parse_dt(series):
    try:
        return pd.to_datetime(series)
    except (ValueError, TypeError):
        return pd.to_datetime(series, format="mixed")


for col in ["created_date", "closed_date"]:
    df[col] = parse_dt(df[col])

for col in ["latitude", "longitude", "Resolution_Hours"]:
    df[col] = pd.to_numeric(df[col], errors="raise").astype("Float64")

print("Missing IDs:", df["ID"].isna().sum())
print("Duplicate IDs:", df["ID"].duplicated().sum())
print("Missing created dates:", df["created_date"].isna().sum())
print("Missing closed dates:", df["closed_date"].isna().sum())
assert df["ID"].notna().all(), "Missing request IDs need checking."
assert df["ID"].is_unique, "Duplicate request IDs need checking."
print("Request ID checks passed.")


# ----------------------------------------------------------------------
# 3) DIMENSIONS
# ----------------------------------------------------------------------
def make_dimension(data, columns, key_name):
    dim = data[columns].drop_duplicates().reset_index(drop=True).copy()
    dim.insert(0, key_name, np.arange(1, len(dim) + 1, dtype=np.int64))
    return dim


dim_agency = make_dimension(df, ["agency", "agency_name"], "agency_key")
dim_complaint = make_dimension(df, ["complaint_type", "descriptor"], "complaint_key")
dim_channel = make_dimension(df, ["open_data_channel_type"], "channel_key")
dim_city = make_dimension(df, ["community_board", "borough"], "city_key")
dim_location = make_dimension(
    df, ["location_type", "latitude", "longitude"], "location_key"
)

# Dim_Date: one row per Created_Date + Closed_Date + Created_Hour combination
df["Created_Date"] = df["created_date"].dt.normalize()
df["Closed_Date"] = df["closed_date"].dt.normalize()
df["Created_Hour"] = df["created_date"].dt.hour.astype("Int64")

date_columns = ["Created_Date", "Closed_Date", "Created_Hour"]
dim_date = make_dimension(df, date_columns, "date_key")

dim_date["Created_Year"] = dim_date["Created_Date"].dt.year.astype("Int64")
dim_date["Month_Number"] = dim_date["Created_Date"].dt.month.astype("Int64")
dim_date["Created_Month_Name"] = dim_date["Created_Date"].dt.month_name()
dim_date["Created_Day_Name"] = dim_date["Created_Date"].dt.day_name()

day_number = dim_date["Created_Date"].dt.day_of_week
dim_date["Day_Type"] = "Unknown"
dim_date.loc[day_number < 5, "Day_Type"] = "Weekday"
dim_date.loc[day_number >= 5, "Day_Type"] = "Weekend"

hour = dim_date["Created_Hour"]
dim_date["Time_Period"] = "Unknown"
dim_date.loc[hour.between(6, 17).fillna(False), "Time_Period"] = "Day"
dim_date.loc[(hour.notna() & ~hour.between(6, 17)).fillna(False), "Time_Period"] = "Night"

# ----------------------------------------------------------------------
# 4) DIM_RESOLUTION (text -> category)
# ----------------------------------------------------------------------
dim_resolution = make_dimension(df, ["resolution_description"], "Category_Key")

assert CATEGORY_CSV.exists(), f"Category file not found: {CATEGORY_CSV}"

mapping = pd.read_csv(CATEGORY_CSV, encoding="utf-8-sig", dtype="string")
lower = {c.lower().strip(): c for c in mapping.columns}
desc_col = next((lower[c] for c in
                 ["resolution_description", "resolution_d", "description"] if c in lower), None)
cat_col = next((lower[c] for c in
                ["category", "resolution_category"] if c in lower), None)
if desc_col is None or cat_col is None:
    raise SystemExit(
        f"Could not find the description/category columns in category.csv.\n"
        f"Columns found: {mapping.columns.tolist()}"
    )

mapping = (
    mapping[[desc_col, cat_col]]
    .rename(columns={desc_col: "resolution_description", cat_col: "Resolution_Category"})
    .dropna(subset=["resolution_description"])
    .drop_duplicates()
)
assert not mapping["resolution_description"].duplicated().any(), (
    "A description has more than one category in category.csv."
)
mapping["resolution_description"] = mapping["resolution_description"].astype("string[pyarrow]")
print(f"Category file rows: {len(mapping):,}")

dim_resolution = dim_resolution.merge(
    mapping, on="resolution_description", how="left", validate="many_to_one"
)
dim_resolution["Resolution_Category"] = (
    dim_resolution["Resolution_Category"].astype("string").fillna("Unmapped")
)

# Blank descriptions
blank = dim_resolution["resolution_description"].isna() | (
    dim_resolution["resolution_description"].str.strip().eq("").fillna(False)
)
dim_resolution.loc[blank, "Resolution_Category"] = "Missing description"

# Apply the manual updates (283 rows) if the file exists
if UPDATES_CSV.exists():
    updates = pd.read_csv(UPDATES_CSV, encoding="utf-8-sig")
    updates = updates.rename(columns={"mapping_key": "Category_Key"})
    assert updates["Category_Key"].is_unique

    check = updates.merge(
        dim_resolution[["Category_Key", "resolution_description"]],
        on="Category_Key", how="left", suffixes=("_file", "_model"),
        validate="one_to_one", indicator=True,
    )
    assert check["_merge"].eq("both").all(), "Some update keys do not match."
    assert (
        check["resolution_description_file"]
        .eq(check["resolution_description_model"])
        .fillna(False)
        .all()
    ), "Descriptions do not match the model. Keys changed - regenerate the updates file."

    dim_resolution.to_parquet(
        OUTPUT_DIR / "Dim_Res_Category_before_updates.parquet", index=False
    )
    lookup = updates.set_index("Category_Key")["Proposed_Category"]
    new_cat = dim_resolution["Category_Key"].map(lookup)
    ok = new_cat.notna()
    dim_resolution.loc[ok, "Resolution_Category"] = new_cat.loc[ok]
    updates.to_csv(
        OUTPUT_DIR / "Resolution_Category_Update_Log.csv",
        index=False, encoding="utf-8-sig",
    )
    print(f"Applied {int(ok.sum())} category updates.")
else:
    print("Updates CSV not found -> skipped.")

print("Unmapped descriptions:", int(dim_resolution["Resolution_Category"].eq("Unmapped").sum()))

# ----------------------------------------------------------------------
# 5) FACT TABLE
# ----------------------------------------------------------------------
relationships = [
    (dim_agency, ["agency", "agency_name"], "agency_key"),
    (dim_complaint, ["complaint_type", "descriptor"], "complaint_key"),
    (dim_channel, ["open_data_channel_type"], "channel_key"),
    (dim_city, ["community_board", "borough"], "city_key"),
    (dim_location, ["location_type", "latitude", "longitude"], "location_key"),
    (dim_date, date_columns, "date_key"),
    (dim_resolution, ["resolution_description"], "Category_Key"),
]

for dimension, join_cols, key in relationships:
    df = df.merge(
        dimension[join_cols + [key]],
        on=join_cols, how="left", validate="many_to_one", sort=False,
    )
    assert len(df) == original_rows, f"Row count changed at {key}."
    assert df[key].notna().all(), f"Some requests have no {key}."
    df = df.drop(columns=join_cols)
    print(f"{key}: connected")
    gc.collect()

df = df.rename(columns={
    "created_date": "Created_DateTime",
    "closed_date": "Closed_DateTime",
})

fact_columns = [
    "ID", "Created_DateTime", "Closed_DateTime", "status", "Resolution_Hours",
    "agency_key", "complaint_key", "channel_key", "city_key",
    "date_key", "location_key", "Category_Key",
]
fact = df[fact_columns].copy()
del df
gc.collect()
print(f"Fact rows: {len(fact):,}")

# ----------------------------------------------------------------------
# 6) VALIDATION
# ----------------------------------------------------------------------
tables = {
    "Dim_Agency": dim_agency,
    "Dim_Complaint": dim_complaint,
    "Dim_Channel": dim_channel,
    "Dim_City": dim_city,
    "Dim_Date": dim_date,
    "Dim_Location": dim_location,
    "Dim_Res_Category": dim_resolution,
    "Fact_Service_Request": fact,
}
dimension_links = [
    ("Dim_Agency", "agency_key"), ("Dim_Complaint", "complaint_key"),
    ("Dim_Channel", "channel_key"), ("Dim_City", "city_key"),
    ("Dim_Date", "date_key"), ("Dim_Location", "location_key"),
    ("Dim_Res_Category", "Category_Key"),
]

assert len(fact) == original_rows
assert fact["ID"].is_unique and fact["ID"].notna().all()

rows = []
for name, key in dimension_links:
    dim = tables[name]
    rows.append({
        "Dimension": name,
        "Key": key,
        "Duplicate_dimension_keys": int(dim[key].duplicated().sum()),
        "Missing_dimension_keys": int(dim[key].isna().sum()),
        "Missing_fact_keys": int(fact[key].isna().sum()),
        "Unmatched_fact_keys": int((fact[key].notna() & ~fact[key].isin(dim[key])).sum()),
    })
validation = pd.DataFrame(rows)
print(validation)
assert validation.drop(columns=["Dimension", "Key"]).eq(0).all().all()
assert not {"location_type", "latitude", "longitude"} & set(fact.columns)
print("ALL MODEL CHECKS PASSED. Requests preserved:", f"{original_rows:,}")

# ----------------------------------------------------------------------
# 7) SAVE + DOCUMENTATION
# ----------------------------------------------------------------------
for name, table in tables.items():
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    table.to_parquet(OUTPUT_DIR / f"{name}.parquet", index=False)
    print("Saved:", name)

validation.to_csv(OUTPUT_DIR / "Model_Validation.csv", index=False)

pd.DataFrame([
    {"Table": n, "Rows": len(t), "Columns": len(t.columns),
     "Saved": (OUTPUT_DIR / f"{n}.parquet").exists()}
    for n, t in tables.items()
]).to_csv(OUTPUT_DIR / "Model_Summary.csv", index=False)

pd.DataFrame([
    {"Dimension": n, "Primary_Key": k, "Fact_Table": "Fact_Service_Request",
     "Foreign_Key": k, "Relationship": "One-to-many"}
    for n, k in dimension_links
]).to_csv(OUTPUT_DIR / "Model_Relationships.csv", index=False)

pks = dict(dimension_links)
pks["Fact_Service_Request"] = "ID"
fks = {k: n for n, k in dimension_links}
dict_rows = []
for tname, table in tables.items():
    for col in table.columns:
        role = "Attribute"
        if col == pks[tname]:
            role = "Primary key"
        elif tname == "Fact_Service_Request" and col in fks:
            role = f"Foreign key -> {fks[col]}"
        elif col == "Resolution_Hours":
            role = "Measure: resolution duration in hours"
        dict_rows.append({
            "Table": tname, "Column": col, "Data_Type": str(table[col].dtype),
            "Role": role, "Missing_Values": int(table[col].isna().sum()),
        })
pd.DataFrame(dict_rows).to_csv(OUTPUT_DIR / "Data_Dictionary.csv", index=False)

# Category summary
counts = fact.groupby("Category_Key").size().rename("Requests").reset_index()
summary = (
    dim_resolution.merge(counts, on="Category_Key", how="left", validate="one_to_one")
    .groupby("Resolution_Category", dropna=False)["Requests"].sum()
    .sort_values(ascending=False).reset_index()
)
summary["Percentage"] = (summary["Requests"] / len(fact) * 100).round(2)
assert summary["Requests"].sum() == len(fact)
summary.to_csv(OUTPUT_DIR / "Resolution_Category_Summary.csv", index=False)
print(summary)

# Review file for anything still unmapped
unmapped = dim_resolution.merge(counts, on="Category_Key", how="left")
unmapped = unmapped[unmapped["Resolution_Category"].eq("Unmapped")].sort_values(
    "Requests", ascending=False
)
unmapped.to_csv(
    OUTPUT_DIR / "Resolution_Mapping_To_Review.csv", index=False, encoding="utf-8-sig"
)

# ----------------------------------------------------------------------
# 8) ZIP PACKAGE
# ----------------------------------------------------------------------
package = BASE_DIR / "NYC311_Model_Final.zip"
files = [OUTPUT_DIR / f"{n}.parquet" for n in tables] + [
    OUTPUT_DIR / f for f in [
        "Model_Summary.csv", "Model_Validation.csv", "Data_Dictionary.csv",
        "Model_Relationships.csv", "Resolution_Category_Summary.csv",
    ]
]
with zipfile.ZipFile(package, "w", compression=zipfile.ZIP_DEFLATED) as z:
    for f in files:
        z.write(f, arcname=f.name)
with zipfile.ZipFile(package) as z:
    assert z.testzip() is None
print("Saved package:", package)
