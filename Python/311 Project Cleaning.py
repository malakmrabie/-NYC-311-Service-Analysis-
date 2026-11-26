# %%
"""
NYC 311 (2024) - data cleaning script  (VS Code / Windows version)

Run as a script:   python clean_nyc311.py
Or cell by cell:   install the Jupyter extension in VS Code, then click "Run Cell" above each "# %%"

Needs: pandas  (pip install pandas)
Memory: loading ~3.4M rows can use several GB of RAM -> use 64-bit Python and close heavy apps.
"""

# %%
import os
import pandas as pd

# ---- Paths (Windows) -------------------------------------------------------
# r"..." (raw string) so the backslashes are not treated as escape characters
path = r"C:\NYC 311 Service Request\Row Data\NYC_311_2024_ALL_MONTHS.csv"

out_dir = r"C:\NYC 311 Service Request\Python\Cleaned Data"
out_path = os.path.join(out_dir, "NYC_311_2024_CLEANED.csv")
os.makedirs(out_dir, exist_ok=True)   # create the output folder if it doesn't exist

# %%
# Read a 100K-row sample first just to inspect the structure
df = pd.read_csv(path, nrows=100000, low_memory=False)

# %%
print(df.shape)
print(df.head())
df.info()

# %%
print(df[["created_date", "closed_date"]].head())

# %%
# convert dates (created, closed, resolution update, due) from str to datetime
date_cols = ["created_date", "closed_date", "resolution_action_updated_date", "due_date"]
for col in date_cols:
    df[col] = pd.to_datetime(df[col])
print(df[date_cols].dtypes)

# %%
# find duplicates
print(df.duplicated().sum())                 # fully identical rows
print(df["unique_key"].duplicated().sum())   # repeated IDs

# %%
# missing values with percentage, biggest to smallest
print((df.isnull().mean() * 100).sort_values(ascending=False).round(2))

# %%
# drop columns with more than 90% missing (9 columns)
cols_to_drop = [
    "taxi_company_borough", "road_ramp", "bridge_highway_direction", "due_date",
    "facility_type", "bridge_highway_segment", "bridge_highway_name",
    "taxi_pick_up_location", "vehicle_type",
]
df = df.drop(columns=cols_to_drop)
print(df.shape)

# %%
# Load the full file, keeping only the columns we need
keep_cols = df.columns.tolist()   # the 34 columns left
date_cols = ["created_date", "closed_date", "resolution_action_updated_date"]
full = pd.read_csv(
    path,
    usecols=keep_cols,
    parse_dates=date_cols,
    low_memory=False,
    # encoding="utf-8",   # uncomment if Windows raises a UnicodeDecodeError
)
print(full.shape)

# %%
del df   # free memory

# %%
# re-check the full data
print(full[["created_date", "closed_date", "resolution_action_updated_date"]].dtypes)
print(full["created_date"].min())
print(full["closed_date"].max())

# %%
print(full["created_date"].dt.year.value_counts().sort_index())

# %%
# check the dates and quality
date_columns = ["created_date", "closed_date", "resolution_action_updated_date"]
for col in date_columns:
    print(f"\n{col}")
    print("Minimum:", full[col].min())
    print("Maximum:", full[col].max())
print("closed before created:", (full["closed_date"] < full["created_date"]).sum())

# %%
# duplicates on the full data
print(full.duplicated().sum())                # fully identical rows
print(full["unique_key"].duplicated().sum())  # repeated IDs

# %%
# missing values on the full data
print((full.isnull().mean() * 100).sort_values(ascending=False).round(2).head(15))

# %%
# why is closed_date missing?
print(full.loc[full["closed_date"].isnull(), "status"].value_counts())

# %%
# inspect the bad rows (closed before created)
bad = full[full["closed_date"] < full["created_date"]].copy()
bad["diff_hours"] = (bad["created_date"] - bad["closed_date"]).dt.total_seconds() / 3600
print(bad["diff_hours"].describe())
print(bad["agency"].value_counts().head())

# %%
print(bad[bad["agency"] == "DOT"]["complaint_type"].value_counts().head())

# %%
# identify invalid dates and replace invalid closed dates with NaT
condition = full["closed_date"] < full["created_date"]
full.loc[condition, "closed_date"] = pd.NaT
print((full["closed_date"] < full["created_date"]).sum())   # should be 0

# %%
print(full["closed_date"].dtype)
print(full["closed_date"].isnull().sum())

# %%
closed_no_date = full[(full["status"] == "Closed") & (full["closed_date"].isnull())]
print(len(closed_no_date))
print(closed_no_date["agency"].value_counts().head(10))
print(closed_no_date["complaint_type"].value_counts().head(10))
print(closed_no_date["resolution_action_updated_date"].notnull().sum())

# %%
both = full[full["closed_date"].notnull() & full["resolution_action_updated_date"].notnull()].copy()
both["gap_hours"] = (both["resolution_action_updated_date"] - both["closed_date"]).dt.total_seconds() / 3600
print(both["gap_hours"].describe())
print((both["gap_hours"] == 0).sum())
print(closed_no_date["agency"].value_counts().head(10))
print(closed_no_date["complaint_type"].value_counts().head(10))

# %%
# Comments: Homeless Person Assistance 27553 - the closing date is almost never recorded,
# even though the status says Closed. Removing them would wipe nearly all homeless
# assistance requests out of the dataset, and every count and chart by complaint type
# would be wrong.

# %%
# Calculate resolution time in hours
full["Resolution_Hours"] = (full["closed_date"] - full["created_date"]).dt.total_seconds() / 3600

print(full["Resolution_Hours"].describe())
print(full["Resolution_Hours"].isnull().sum())
print((full["Resolution_Hours"] == 0).sum())
print((full["Resolution_Hours"] < 0).sum())

# %%
# outliers
print(full["Resolution_Hours"].quantile([0.9, 0.95, 0.99, 0.999]))
print((full["Resolution_Hours"] > 8760).sum())   # took more than one year

zeros = full[full["Resolution_Hours"] == 0]
print(zeros["agency"].value_counts().head())
print(zeros["complaint_type"].value_counts().head())

# %%
# Create two flag columns
full["is_zero_hours"] = full["Resolution_Hours"] == 0      # zero-hour requests
full["is_over_1yr"] = full["Resolution_Hours"] > 8760      # more than one year
print("Zero hour requests:", full["is_zero_hours"].sum())
print("Requests over 1 year:", full["is_over_1yr"].sum())

# %%
zero_hour_records = full[full["is_zero_hours"]]
print(zero_hour_records.head())

# %%
print(zero_hour_records[["agency", "complaint_type", "descriptor", "resolution_description"]].head(10))

# %%
# Analyze the zero hour records
print(zero_hour_records["descriptor"].value_counts().head(10))

# %%
print(full[["incident_zip", "council_district", "bbl"]].dtypes)
print(full["incident_zip"].dropna().astype(str).str.len().value_counts())

# %%
# the short zips
print(full[full["incident_zip"].str.len() == 4]["incident_zip"].tolist())

# any zip that contains non-digits
not_digits = full["incident_zip"].dropna()
not_digits = not_digits[~not_digits.str.fullmatch(r"\d{5}")]
print(len(not_digits))
print(not_digits.value_counts().head())

full["council_district"] = full["council_district"].astype("Int64").astype("string")
print(full[["incident_zip", "council_district", "bbl"]].dtypes)
print(full[["council_district", "bbl"]].head())

# %%
mask = ~full["incident_zip"].str.fullmatch(r"\d{5}", na=True)
print(mask.sum())
full.loc[mask, "incident_zip"] = pd.NA

# %%
full["bbl"] = full["bbl"].astype("Int64").astype("string")
print(full[["incident_zip", "council_district", "bbl"]].dtypes)

# %%
# Standardize text columns
for col in ["borough", "status", "open_data_channel_type", "park_borough"]:
    print(col)
    print(full[col].value_counts(dropna=False))
    print()

# %%
print(full["city"].nunique())
print(full["city"].value_counts().head(25))

# %%
# Check city for spaces and rare values
c = full["city"].dropna()
print((c != c.str.strip()).sum())
print(full["city"].value_counts().tail(30))

# %%
# ignoring the missing rows: is park_borough the same as borough?
mask = full["borough"].notnull()
print((full.loc[mask, "borough"] == full.loc[mask, "park_borough"]).all())

# %%
# Drop park_borough (same data as borough)
full = full.drop(columns=["park_borough"])
print(full.shape)

# %%
# status: replace "Unspecified" with missing
full["status"] = full["status"].replace("Unspecified", pd.NA)
print(full["status"].isnull().sum())

# %%
# Standardize city
full["city"] = full["city"].str.strip().str.upper()
print(full["city"].nunique())

# %%
# check complaint type
ct = full["complaint_type"]
print(ct.nunique())
print(ct.str.strip().str.lower().nunique())

# %%
# the duplicate complaint types
key = full["complaint_type"].str.strip().str.lower()
groups = full.groupby(key)["complaint_type"].unique()
print(groups[groups.apply(len) > 1])

# %%
# Merge the duplicate complaint types
full["complaint_type"] = full["complaint_type"].replace({
    "Elevator": "ELEVATOR",
    "Plumbing": "PLUMBING",
})
print(full["complaint_type"].nunique())

# %%
print(full.shape)

# %%
# remaining missing values
print((full.isnull().mean() * 100).sort_values(ascending=False).round(2).head(20))

# %%
print(full.shape)                           # expect 36 columns
print("park_borough" in full.columns)       # expect False
print(full["complaint_type"].nunique())     # expect 197 if the merge ran
print(full["borough"].isnull().sum())       # expect 2638
print(full["status"].isnull().sum())        # expect 99
print(full["incident_zip"].isnull().sum())  # includes the 5 blanked zips
print("Resolution_Hours" in full.columns, "is_zero_hours" in full.columns)

# %%
full["location_type"] = full["location_type"].fillna("Unknown")
full["city"] = full["city"].fillna("UNKNOWN")
full["descriptor"] = full["descriptor"].fillna("Unknown")

print((full[["location_type", "city", "descriptor"]].isnull().mean() * 100).round(2))

# %%
# Check the coordinates
print(full[["latitude", "longitude"]].describe())

outside = full[
    full["latitude"].notnull() &
    ((full["latitude"] < 40.49) | (full["latitude"] > 40.92) |
     (full["longitude"] < -74.27) | (full["longitude"] > -73.68))
]
print(len(outside))
print(outside[["borough", "city", "latitude", "longitude"]].head(10))

# %%
# final checks
print(full.shape)
print(full.duplicated(subset="unique_key").sum())
print((full["Resolution_Hours"] < 0).sum())
print(full["Resolution_Hours"].isnull().sum())
print(full["is_zero_hours"].sum(), full["is_over_1yr"].sum())
print(full["created_date"].min(), full["created_date"].max())
print(full.dtypes)

# %%
# save (close the file in Excel first, otherwise you get PermissionError)
full.to_csv(out_path, index=False)
print("saved ->", out_path)