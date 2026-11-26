
import duckdb
from pathlib import Path

# Get script directory
folder_path = Path(__file__).resolve().parent

# Parquet files
parquet_files = [
    str(folder_path / f"311_2024_{month:02d}.parquet")
    for month in range(1, 13)
]

# Output CSV
output_file = folder_path / "NYC_311_2024_ALL_MONTHS_MERGED.csv"

# Check files
for file in parquet_files:
    if not Path(file).exists():
        raise FileNotFoundError(f"Missing file: {file}")

print("All 12 Parquet files found.")

# Connect to DuckDB
con = duckdb.connect()

try:
    print("Reading Parquet files...")

    # Read all files
    data = con.read_parquet(parquet_files)

    print("Starting CSV export...")

    # Export directly using DuckDB relation API
    data.write_csv(
        str(output_file),
        header=True
    )

    print("Conversion completed successfully!")
    print(f"Output file: {output_file}")
    print(f"File size: {output_file.stat().st_size / (1024**3):.2f} GB")

finally:
    con.close()
