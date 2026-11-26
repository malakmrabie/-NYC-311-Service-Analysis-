
from pathlib import Path
import pyarrow.parquet as pq 
from graphviz import Digraph  # type: ignore

import os

os.environ["PATH"] += os.pathsep + r"C:\Program Files\Graphviz\bin" 

# Paths
OUTPUT_DIR = Path(r"C:\NYC 311 Service Request\Python\Modeled_Tables")

# Dimensions and their primary keys
links = [
    ("Dim_Agency", "agency_key"),
    ("Dim_Complaint", "complaint_key"),
    ("Dim_Channel", "channel_key"),
    ("Dim_City", "city_key"),
    ("Dim_Date", "date_key"),
    ("Dim_Location", "location_key"),
    ("Dim_Res_Category", "Category_Key"),
]

fact_name = "Fact_Service_Request"

# Create diagram
diagram = Digraph("NYC311_Model", format="png")

diagram.attr(
    rankdir="LR",
    bgcolor="white",
    nodesep="0.5",
    ranksep="1.2",
    label="NYC 311 - Star Schema Data Model",
    labelloc="t",
    fontsize="22",
    fontname="Arial"
)

# Create each table using plain text labels
def add_table(name, primary_key, color, foreign_keys=None):

    file_path = OUTPUT_DIR / f"{name}.parquet"

    if not file_path.exists():
        raise FileNotFoundError(f"Missing file: {file_path}")

    # Read schema only, not the full dataset
    columns = pq.read_schema(file_path).names

    lines = [name, "------------------------"]

    for column in columns:

        if column == primary_key:
            role = "PK"

        elif foreign_keys and column in foreign_keys:
            role = "FK"

        else:
            role = "   "

        lines.append(f"{role} | {column}")

    diagram.node(
        name,
        label="\n".join(lines),
        shape="box",
        style="rounded,filled",
        fillcolor=color,
        color="#64748b",
        fontname="Arial",
        fontsize="10",
        margin="0.15"
    )


# Fact table foreign keys
fact_foreign_keys = [key for _, key in links]

# Add fact table
add_table(
    fact_name,
    "ID",
    "#FFD59A",
    foreign_keys=fact_foreign_keys
)

# Add dimensions
for name, key in links:

    color = "#CFE3FA" if name == "Dim_Location" else "#CFE3FA"

    add_table(name, key, color)


# Add relationships
for name, key in links:

    diagram.edge(
        name,
        fact_name,
        label=key,
        taillabel="1",
        headlabel="Many",
        dir="none",
        fontsize="9"
    )


# Export PNG
output_path = diagram.render(
    filename="NYC311_Data_Model",
    directory=str(OUTPUT_DIR),
    cleanup=True,
    view=True
)

print("Data model created successfully!")
print("Saved image:", output_path)
