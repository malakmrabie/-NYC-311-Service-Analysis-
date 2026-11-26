import glob
import os
import pyarrow.parquet as pq
import pyarrow.csv as pacsv

folder = os.path.dirname(os.path.abspath(__file__))   # فولدر السكريبت نفسه
files = sorted(glob.glob(os.path.join(folder, "311_2024_*.parquet")))
out_path = os.path.join(folder, "311_2024_all.csv")

print("Files found:", len(files))
if not files:
    raise SystemExit("No parquet files found in: " + folder)

writer = None
total = 0

for f in files:
    pf = pq.ParquetFile(f)
    for batch in pf.iter_batches(batch_size=200_000):
        if writer is None:
            writer = pacsv.CSVWriter(out_path, batch.schema)
        writer.write_batch(batch)
        total += batch.num_rows
    print(os.path.basename(f), "done")

writer.close()
print("Total rows:", total)