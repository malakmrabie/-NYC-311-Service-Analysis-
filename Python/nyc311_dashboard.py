import base64
import glob
import os

import numpy as np
import pandas as pd
import plotly.express as px
import streamlit as st

# ───────────────────────── Paths ─────────────────────────
BASE = r"C:\NYC 311 Service Request"
MODEL_DIR = os.path.join(BASE, "Modeled_Tables")
BG_PATH = os.path.join(BASE, "Python", "Picture2.jpg")      # hero banner image
APP_BG_PATH = os.path.join(BASE, "Python", "bg.jpg")       # full-page background image

SAMPLE_ROWS = 100_000      # Fast mode sample size
DEFAULT_VIEW_H = 940       # usable browser height in px (adjust from the sidebar slider)
SLA_HOURS = 72             # timeliness threshold used in KPI + agency SLA chart

st.set_page_config(page_title="NYC 311 Dashboard", layout="wide",
                   initial_sidebar_state="collapsed")

DAY_ORDER = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
PART_ORDER = ["Morning (5–11)", "Afternoon (12–16)", "Evening (17–20)", "Night (21–4)"]
H = 220          # current chart height – set per page in the app section at the bottom
EXCL0 = False    # set from the sidebar: drop 00:00 timestamps in the Time Patterns page

# ───────────────────────── Theme (orange palette) ─────────────────────────
C1, C2, C3, C4, C5 = "#ff580f", "#ff7e26", "#ff9c59", "#ffa472", "#ffc99d"
ORANGE, PINK, PURPLE = C1, C2, C3      # legacy names
SEQ = [C1, C3, C5, C2, C4, "#d94a0c", "#b33e0a", "#ffe0c2"]
SCALE = ["#ffe0c2", C5, C3, C1]
MAP_SCALE = ["#ffe0c2", C5, C3, C2, C1]
STATUS_MAP = {"Closed": C1, "Open": C5, "Pending": C3, "Assigned": C2,
              "Started": C4, "In Progress": "#ffe0c2"}
SERIF = "Playfair Display, Georgia, serif"


def img_to_css_url(path, fallback):
    if not path:
        return fallback
    ext = os.path.splitext(path)[1].lower().lstrip(".")
    mime = "image/png" if ext == "png" else "image/webp" if ext == "webp" else "image/jpeg"
    try:
        with open(path, "rb") as f:
            b64 = base64.b64encode(f.read()).decode()
        return f"url(data:{mime};base64,{b64})"
    except Exception:
        return fallback


def set_style(hero_path, app_bg_path=None):
    hero_img = img_to_css_url(hero_path, "linear-gradient(135deg,#1a1040,#3a1f5a)")
    app_img = img_to_css_url(app_bg_path, hero_img)

    st.markdown(f"""
    <style>
    @import url('https://fonts.googleapis.com/css2?family=Playfair+Display:wght@600;800&display=swap');

    .stApp {{
        background-image:
            linear-gradient(180deg, rgba(10,15,31,0.60) 0%, rgba(10,15,31,0.40) 100%),
            {app_img};
        background-size: cover;
        background-position: center center;
        background-repeat: no-repeat;
        background-attachment: fixed;
    }}

    header[data-testid="stHeader"] {{background:transparent; height:0;}}
    #MainMenu, footer {{visibility:hidden;}}
    .block-container {{padding:0.5rem 1rem 0.2rem 1rem; max-width:100%;}}
    div[data-testid="stVerticalBlock"] {{gap:0.45rem;}}
    div[data-testid="stMarkdownContainer"] p {{margin:0;}}
    div[data-testid="stMarkdownContainer"], .stMarkdown {{margin-bottom:0 !important;}}
    div[data-testid="stMarkdownContainer"] > *:last-child {{margin-bottom:0 !important;}}
    div[data-testid="stToolbar"], .stDeployButton {{display:none !important;}}
    .stApp .stMarkdown p {{color:#fff;}}

    /* hero banner */
    .hero {{padding:0 4px 8px 4px; background:none !important; border:none !important;
            box-shadow:none !important; border-radius:0 !important;}}
    .hero .t1 {{font-family:{SERIF}; font-size:3.2rem; font-weight:800; color:#f6efe6;
               line-height:1.05; display:inline-block;}}
    .hero .t1 span {{background:linear-gradient(90deg,{C1},{C2},{C3});
                    -webkit-background-clip:text; background-clip:text; color:transparent;}}
    .hero .t2 {{letter-spacing:.24em; font-size:1.3rem; color:#fff; display:inline-block;
               margin-left:18px;}}
    .hero .t3 {{letter-spacing:.16em; font-size:.95rem; color:#e9dfd6; margin-top:2px;}}

    /* nav */
    div[role="radiogroup"] {{display:flex; flex-direction:row; justify-content:center;
             gap:15px; padding:6px 0 10px 0;}}
    div[role="radiogroup"] label {{background:rgba(20,27,52,.78);
             backdrop-filter: blur(6px);
             border:1px solid rgba(255,126,38,.55); border-radius:10px;
             padding:8px 20px; cursor:pointer;}}
    div[role="radiogroup"] label p {{font-size:1rem !important; color:#fff !important;}}

    /* charts as cards */
    div[data-testid="stPlotlyChart"] {{background:rgba(14,20,40,.82);
             backdrop-filter: blur(6px);
             border-radius:12px; padding:2px; border:1px solid rgba(255,126,38,.22);}}

    /* KPI cards */
    .kpi {{display:flex; align-items:center; gap:10px; border-radius:12px; padding:6px 12px;
           border:1px solid rgba(255,255,255,.14); height:66px; margin-bottom:6px;
           backdrop-filter: blur(6px);}}
    .kpi .ic {{width:38px; height:38px; min-width:38px; border-radius:50%; display:flex;
              align-items:center; justify-content:center; font-size:1.2rem;
              background:rgba(255,255,255,.18);}}
    .kpi .l {{font-family:{SERIF}; font-size:.95rem; color:#fff; line-height:1.1;}}
    .kpi .v {{font-size:1.45rem; font-weight:700; color:#fff; line-height:1.15;}}
    .kpi .s {{font-size:.72rem; font-weight:400; color:#e6d3c3;}}
    .k1 {{background:linear-gradient(135deg,rgba(255,88,15,.65),rgba(14,20,40,.88));}}
    .k2 {{background:linear-gradient(135deg,rgba(255,126,38,.60),rgba(14,20,40,.88));}}
    .k3 {{background:linear-gradient(135deg,rgba(255,156,89,.55),rgba(14,20,40,.88));}}
    .k4 {{background:linear-gradient(135deg,rgba(255,164,114,.50),rgba(14,20,40,.88));}}
    .k5 {{background:linear-gradient(135deg,rgba(255,201,157,.45),rgba(14,20,40,.88));}}

    /* filters */
    div[data-testid="stMultiSelect"] label p {{color:#e9dfd6 !important; font-size:.85rem;}}
    div[data-baseweb="select"] > div {{background:rgba(24,32,60,.85) !important; min-height:38px;
             border:1px solid rgba(255,255,255,.16) !important; border-radius:8px;}}
    div[data-baseweb="select"] span, div[data-baseweb="select"] input,
    div[data-baseweb="select"] div {{color:#fff !important; font-size:.9rem;}}
    span[data-baseweb="tag"] {{background:{C1} !important;}}
    div[data-baseweb="popover"] ul {{background:#1B1440 !important;}}
    div[data-baseweb="popover"] li {{color:#fff !important;}}
    div[data-baseweb="popover"] li:hover {{background:#5a2a14 !important;}}
    </style>""", unsafe_allow_html=True)


def hero():
    st.markdown("""
    <div class="hero">
      <div class="t1">NYC <span>311</span></div>
      <div class="t2">SERVICE REQUEST ANALYTICS</div>
      <div class="t3">2024 &nbsp;|&nbsp; Citywide Service Performance</div>
    </div>""", unsafe_allow_html=True)


def sty(fig, h=None, title=None, sub=None, legend=True):
    h = h or H
    t = None
    if title:
        txt = title
        if sub:
            txt += f" <span style='font-size:11px;color:#d9c3b0'>· {sub}</span>"
        t = dict(text=txt, font=dict(size=16, family=SERIF), x=0.02, y=0.97, yanchor="top")
    fig.update_layout(
        template="plotly_dark", height=h, colorway=SEQ,
        paper_bgcolor="rgba(0,0,0,0)", plot_bgcolor="rgba(0,0,0,0)",
        margin=dict(l=8, r=8, t=36 if title else 6, b=54 if legend else 6),
        font=dict(size=13, color="#fff"), title=t, showlegend=legend,
        legend=dict(orientation="h", yref="container", y=0.0, yanchor="bottom",
                    x=0, xanchor="left", title=None, font=dict(size=11)),
    )
    # no grid lines / zero line / axis lines
    fig.update_xaxes(automargin=True, tickfont=dict(size=11),
                     showgrid=False, zeroline=False, showline=False)
    fig.update_yaxes(automargin=True, tickfont=dict(size=11),
                     showgrid=False, zeroline=False, showline=False)
    return fig


def show(fig, key):
    st.plotly_chart(fig, use_container_width=True, key=key, config={"displayModeBar": False})


def kpi(col, cls, icon, label, value, sub=""):
    col.markdown(f'<div class="kpi {cls}"><div class="ic">{icon}</div><div>'
                 f'<div class="l">{label}</div>'
                 f'<div class="v">{value} <span class="s">{sub}</span></div></div></div>',
                 unsafe_allow_html=True)


# ───────────────────────── Data loading ─────────────────────────
def norm(s):
    return "".join(ch for ch in str(s).lower() if ch.isalnum())


def pick(df, names):
    m = {norm(c): c for c in df.columns}
    for n in names:
        if norm(n) in m:
            return m[norm(n)]
    return None


ALIAS = {
    "id": ["ID", "unique_key"],
    "status": ["status"],
    "agency": ["agency", "agency_name"],
    "complaint": ["complaint_type", "complaint"],
    "loc_type": ["location_type"],
    "borough": ["borough"],
    "channel": ["open_data_channel_type", "channel", "channel_type"],
    "res_cat": ["Resolution_Category", "category"],
    "hours": ["Resolution_Hours"],
    "lat": ["latitude", "lat"],
    "lon": ["longitude", "lon", "lng"],
    "hour": ["Created_Hour"],
    "created_time": ["Created_Time"],
    "m_created": ["_m_created"],
    "wd_created": ["_wd_created"],
    "m_closed": ["_m_closed"],
    "wd_closed": ["_wd_closed"],
}


def read_any(p):
    if p.lower().endswith(".csv"):
        return pd.read_csv(p, low_memory=False)
    if p.lower().endswith(".parquet"):
        return pd.read_parquet(p)
    return pd.read_excel(p)


@st.cache_data(show_spinner="Loading modeled tables ...")
def load():
    files = [f for f in glob.glob(os.path.join(glob.escape(MODEL_DIR), "**", "*"), recursive=True)
             if os.path.isfile(f) and f.lower().endswith((".csv", ".xlsx", ".xls", ".parquet"))]
    if not files:
        found = os.listdir(MODEL_DIR) if os.path.isdir(MODEL_DIR) else "FOLDER NOT FOUND"
        raise FileNotFoundError(f"No csv/xlsx/parquet files in {MODEL_DIR}. Folder content: {found}")

    def find(*kws):
        for f in files:
            b = os.path.basename(f).lower()
            if any(k in b for k in kws):
                return f
        return None

    fact_p = find("fact", "service_request", "service request", "311")
    if not fact_p:
        fact_p = max(files, key=os.path.getsize)
    fact = read_any(fact_p)

    for kws in [("dim_date",), ("agency",), ("channel", "chennel"), ("city",),
                ("complaint",), ("location",), ("res_category",)]:
        p = find(*kws)
        if not p:
            continue
        dim = read_any(p)
        if kws[0] == "dim_date":
            cc, xc = pick(dim, ["Created_Date"]), pick(dim, ["Closed_Date"])
            if cc:
                d_cr = pd.to_datetime(dim[cc], errors="coerce")
                dim["_m_created"] = d_cr.dt.to_period("M").astype(str)
                dim["_wd_created"] = d_cr.dt.day_name()
            if xc:
                d_cl = pd.to_datetime(dim[xc], errors="coerce")
                dim["_m_closed"] = d_cl.dt.to_period("M").astype(str)
                dim["_wd_closed"] = d_cl.dt.day_name()
        keys = [c for c in dim.columns if c.lower().endswith("key") and c in fact.columns]
        if not keys:
            continue
        dim = dim.drop(columns=[c for c in dim.columns if c in fact.columns and c not in keys])
        fact = fact.merge(dim.drop_duplicates(keys), on=keys, how="left")

    out = pd.DataFrame(index=fact.index)
    for k, names in ALIAS.items():
        c = pick(fact, names)
        out[k] = fact[c] if c else np.nan

    if out["hour"].isna().all() and out["created_time"].notna().any():
        s = out["created_time"].astype(str)
        u = s.unique()
        m = pd.Series(pd.to_datetime(u, errors="coerce").hour, index=u)
        out["hour"] = s.map(m)

    out["hours"] = pd.to_numeric(out["hours"], errors="coerce")
    out.loc[out["hours"] < 0, "hours"] = np.nan
    out["is_closed"] = out["status"].astype(str).str.upper().eq("CLOSED")
    out["lat"] = pd.to_numeric(out["lat"], errors="coerce")
    out["lon"] = pd.to_numeric(out["lon"], errors="coerce")
    out = out.drop(columns=["created_time"])

    # time-of-day / weekday-vs-weekend features
    out["hour"] = pd.to_numeric(out["hour"], errors="coerce")
    h = out["hour"]
    out["day_part"] = np.select(
        [h.between(5, 11), h.between(12, 16), h.between(17, 20), h.notna()],
        PART_ORDER[:3] + [PART_ORDER[3]], default="Unknown")
    wd = out["wd_created"].astype(str)
    out["day_type"] = np.where(wd.isin(["Saturday", "Sunday"]), "Weekend",
                               np.where(wd.isin(DAY_ORDER), "Weekday", "Unknown"))

    # unify borough casing (BRONX / Bronx -> Bronx, UNSPECIFIED -> Unspecified)
    out["borough"] = out["borough"].astype("string").str.strip().str.title()

    for c in ["status", "agency", "complaint", "loc_type", "borough", "channel",
              "res_cat", "m_created", "m_closed", "wd_closed", "wd_created",
              "day_part", "day_type"]:
        out[c] = out[c].astype("string").fillna("Unknown").astype("category")
    return out


# ───────────────────────── Helpers ─────────────────────────
def top(df, col, n=10):
    return df[col].value_counts().head(n).rename_axis(col).reset_index(name="Requests")


def short(s, n=26):
    s = str(s)
    return s if len(s) <= n else s[: n - 1] + "…"


def top_filter(df, col, n):
    keep = df[col].value_counts().head(n).index
    return df[df[col].isin(keep)], list(keep)


def month_series(df, col):
    m = df.groupby(col, observed=True).size()
    m = m[m.index.astype(str).str.match(r"^\d{4}-\d{2}$")]
    idx = m.index.astype(str)
    dt = pd.to_datetime(idx + "-01")
    lab = dt.strftime("%b") if dt.year.nunique() == 1 else dt.strftime("%b %y")
    return pd.DataFrame({"Month": list(lab), "Requests": m.values})


def month_line(d, title, key, sub=None):
    fig = px.line(d, x="Month", y="Requests", markers=True)
    fig.update_traces(line_color=C2, marker_color=C2, fill="tozeroy",
                      fillcolor="rgba(255,126,38,.18)")
    fig.update_xaxes(title=None)
    fig.update_yaxes(title=None, rangemode="tozero")
    show(sty(fig, title=title, sub=sub, legend=False), key)


def hbar(d, col, title, key, sub=None, val="Requests", fmt=None):
    """Horizontal bar of `val` per `col`, sorted, colored by value."""
    d = d.copy()
    d[col] = d[col].map(lambda s: short(s, 22))
    d = d.sort_values(val)
    fig = px.bar(d, x=val, y=col, orientation="h", color=val, color_continuous_scale=SCALE)
    if fmt:
        fig.update_traces(texttemplate=fmt, textposition="outside", cliponaxis=False)
    fig.update_coloraxes(showscale=False)
    fig.update_yaxes(title=None, tickfont=dict(size=11))
    fig.update_xaxes(title=None)
    show(sty(fig, title=title, sub=sub, legend=False), key)


def median_hbar(d, col, title, key, top_n=10):
    """Median resolution hours per group (top_n groups by volume). Replaces the old box plots."""
    sub, _ = top_filter(d, col, top_n)
    g = (sub.dropna(subset=["hours"])
            .groupby(col, observed=True)["hours"].median()
            .reset_index(name="Median hours"))
    if g.empty:
        st.info("No resolution-time data.")
        return
    g[col] = g[col].astype(str)
    hbar(g, col, title, key, sub="median hours", val="Median hours", fmt="%{x:.0f}")


def lock_to_nyc(fig):
    """Restrict panning / zooming-out to the NYC area so the world map never shows."""
    bounds = dict(west=-74.3, east=-73.65, south=40.45, north=40.95)
    view = dict(bounds=bounds, center={"lat": 40.7128, "lon": -74.0060}, zoom=9.6)
    try:
        fig.update_layout(map=view)
    except ValueError:   # older plotly
        fig.update_layout(mapbox=view)
    return fig


def map_insight(df, h):
    """Slow-areas map only: size = number of requests, color = median resolution hours."""
    m = df.dropna(subset=["lat", "lon"])
    m = m[m["lat"].between(40.45, 40.95) & m["lon"].between(-74.3, -73.65)]
    if m.empty:
        st.info("No latitude/longitude in the fact table.")
        return

    center = {"lat": 40.7128, "lon": -74.0060}
    g = m.assign(la=m["lat"].round(2), lo=m["lon"].round(2))
    agg = (g.groupby(["la", "lo"], observed=True)
            .agg(Requests=("lat", "size"), Median_h=("hours", "median"))
            .reset_index())
    agg = agg[agg["Requests"] >= 30].dropna(subset=["Median_h"])   # ignore tiny cells
    if agg.empty:
        st.info("Not enough data for the selected filters.")
        return
    agg["Median_h"] = agg["Median_h"].clip(upper=agg["Median_h"].quantile(0.95))
    hover = {"la": False, "lo": False, "Requests": ":,", "Median_h": ":.1f"}
    try:
        fig = px.scatter_map(agg, lat="la", lon="lo", size="Requests", color="Median_h",
                             size_max=22, zoom=9.6, center=center, opacity=0.8,
                             map_style="carto-darkmatter", color_continuous_scale=MAP_SCALE,
                             hover_data=hover)
    except AttributeError:   # older plotly
        fig = px.scatter_mapbox(agg, lat="la", lon="lo", size="Requests", color="Median_h",
                                size_max=22, zoom=9.6, center=center, opacity=0.8,
                                mapbox_style="carto-darkmatter",
                                color_continuous_scale=MAP_SCALE, hover_data=hover)
    fig.update_coloraxes(colorbar=dict(title="Median h", len=0.5, thickness=10))
    show(lock_to_nyc(sty(fig, h=h, title="Areas With the Slowest Resolution",
                         sub="size = requests · color = median hours", legend=False)), "g_map")


# ───────────────────────── Pages ─────────────────────────
def page_overview(df):
    total = len(df)
    closed = int(df["is_closed"].sum())
    avg_h, med_h = df["hours"].mean(), df["hours"].median()
    cl = df.loc[df["is_closed"], "hours"].dropna()
    timely = (cl <= SLA_HOURS).mean() * 100 if len(cl) else float("nan")
    avg_txt = "–" if pd.isna(avg_h) else (f"{avg_h/24:,.1f} d" if avg_h >= 48 else f"{avg_h:,.1f} h")
    med_txt = "–" if pd.isna(med_h) else f"{med_h:,.1f} h"

    c = st.columns(5, gap="small")
    kpi(c[0], "k1", "📄", "Total Requests", f"{total:,}")
    kpi(c[1], "k2", "⏱", "Open Requests", f"{total - closed:,}")
    kpi(c[2], "k3", "✅", "Closed Requests", f"{closed:,}")
    kpi(c[3], "k4", "📅", "Avg. Resolution Time", avg_txt, f"median {med_txt}")
    kpi(c[4], "k5", "🎯", "SLA / Timeliness", "–" if pd.isna(timely) else f"{timely:,.1f}%",
        f"≤ {SLA_HOURS // 24} days")

    a, b, c3 = st.columns([1.5, 1.1, 1.1], gap="small")
    with a:
        month_line(month_series(df, "m_created"), "Monthly Number of Service Requests",
                   "ov_trend", "trend over time")
    with b:
        hbar(top(df, "complaint", 10), "complaint", "Top 10 Complaint Types by Volume", "ov_top10")
    with c3:
        hbar(top(df, "borough", 6), "borough", "Number of Requests per Borough", "ov_bor")

    a, b = st.columns([1.6, 1.0], gap="small")
    with a:
        d = top(df, "agency", 10)
        d["agency"] = d["agency"].map(lambda s: short(s, 14))
        fig = px.bar(d, x="agency", y="Requests", color="Requests", color_continuous_scale=SCALE)
        fig.update_traces(texttemplate="%{y:,}", textposition="outside", cliponaxis=False)
        fig.update_coloraxes(showscale=False)
        fig.update_xaxes(title=None)
        fig.update_yaxes(title=None, visible=False,
                         range=[0, d["Requests"].max() * 1.15])   # مساحة فوق أعلى عمود للرقم
        show(sty(fig, title="Top 10 Agencies by Number of Requests",
                 sub="agency workload", legend=False), "ov_agency")
    with b:
        d = top(df, "status", 6)
        fig = px.pie(d, names="status", values="Requests", hole=0.6,
                     color="status", color_discrete_map=STATUS_MAP, color_discrete_sequence=SEQ)
        fig.update_traces(textinfo="percent", textposition="inside", marker_line_width=0)
        fig.update_layout(uniformtext_minsize=11, uniformtext_mode="hide")
        sty(fig, title="Share of Requests by Status", sub="open vs. closed")
        fig.update_layout(margin=dict(l=8, r=8, t=36, b=6),
                          legend=dict(orientation="v", yref="paper", y=0.5, yanchor="middle",
                                      x=1.0, xanchor="right", font=dict(size=12)))
        show(fig, "ov_status")


def page_complaint_agency(df):
    a, b = st.columns(2, gap="small")
    with a:
        # which complaint types are the slowest (among the highest-volume ones)
        sub, _ = top_filter(df, "complaint", 15)
        g = (sub.groupby("complaint", observed=True)["hours"].median().dropna()
                .reset_index(name="Median hours"))
        g["complaint"] = g["complaint"].astype(str)
        hbar(g, "complaint", "Slowest Complaint Types (Median Hours to Resolve)", "ca_slow",
             sub="top 15 by volume", val="Median hours", fmt="%{x:.0f}")
    with b:
        # SLA: % of closed requests resolved within the threshold, per agency
        sub, keep = top_filter(df, "agency", 10)
        cl = sub[sub["is_closed"]].dropna(subset=["hours"])
        g = (cl.groupby("agency", observed=True)["hours"]
               .apply(lambda s: (s <= SLA_HOURS).mean() * 100)
               .reset_index(name="Within SLA %"))
        g = g[g["agency"].isin(keep)]
        g["agency"] = g["agency"].astype(str)
        hbar(g, "agency", f"% of Requests Closed Within {SLA_HOURS // 24} Days, by Agency", "ca_sla",
             sub="SLA compliance · top 10 agencies", val="Within SLA %", fmt="%{x:.0f}%")

    a, b = st.columns(2, gap="small")
    with a:
        sub, ags = top_filter(df, "agency", 6)
        sub, cps = top_filter(sub, "complaint", 10)
        p = sub.groupby(["complaint", "agency"], observed=True).size().unstack(fill_value=0)
        p = p.reindex(index=[c for c in cps if c in p.index],
                      columns=[x for x in ags if x in p.columns])
        p.index = [short(i, 24) for i in p.index]
        fig = px.imshow(p, aspect="auto", color_continuous_scale=SCALE, text_auto=".2s")
        fig.update_traces(textfont=dict(size=10))
        fig.update_coloraxes(showscale=False)
        fig.update_xaxes(title=None)
        fig.update_yaxes(title=None, tickfont=dict(size=11))
        show(sty(fig, title="Request Volume: Top Complaints × Top Agencies",
                 legend=False), "ca_heat")
    with b:
        median_hbar(df, "agency", "Median Resolution Time by Agency (Hours)", "ca_box", top_n=8)


def page_geo(df):
    global H
    T = max(340, view_h - 300)          # total height shared by all three columns
    H = (T - 14) // 2                   # height of each of the 2 stacked charts in the middle

    a, b, c = st.columns([1.25, 1.15, 0.8], gap="small")

    # ── Left: tall map (slow areas only) ──
    with a:
        map_insight(df, T)

    # ── Middle: treemap on top, 100% stacked below ──
    with b:
        d = top(df, "loc_type", 15)
        d["Share %"] = d["Requests"] / len(df) * 100
        fig = px.treemap(d, path=["loc_type"], values="Requests", color="Requests",
                         color_continuous_scale=SCALE, custom_data=["Share %"])
        fig.update_traces(texttemplate="%{label}<br>%{customdata[0]:.1f}%",
                          hovertemplate="%{label}<br>%{customdata[0]:.1f}% of all requests<extra></extra>",
                          textfont=dict(size=12))
        fig.update_coloraxes(showscale=False)
        show(sty(fig, title="Share of Requests by Location Type", sub="% of all requests",
                 legend=False), "g_tree")

        sub, lts = top_filter(df, "loc_type", 8)
        sub = sub.assign(loc_type=sub["loc_type"].map(lambda s: short(s, 20)).astype(str),
                         borough=sub["borough"].astype(str))
        g = sub.groupby(["borough", "loc_type"]).size().reset_index(name="Requests")
        fig = px.bar(g, x="borough", y="Requests", color="loc_type", color_discrete_sequence=SEQ)
        fig.update_layout(barmode="relative", barnorm="percent")
        fig.update_xaxes(title=None)
        fig.update_yaxes(title=None)
        show(sty(fig, title="Location Type Mix Within Each Borough (%)", sub="100% stacked"), "g_100")

    # ── Right: tall vertical median chart ──
    with c:
        sub = df[~df["borough"].astype(str).isin(["Unknown", "Unspecified"])]
        sub, _ = top_filter(sub, "borough", 6)
        g = (sub.dropna(subset=["hours"])
                .groupby("borough", observed=True)["hours"].median()
                .reset_index(name="Median hours"))
        g["borough"] = g["borough"].astype(str)
        g = g.sort_values("Median hours", ascending=False)
        fig = px.bar(g, x="borough", y="Median hours", color="Median hours",
                     color_continuous_scale=SCALE)
        fig.update_traces(texttemplate="%{y:.0f}", textposition="outside", cliponaxis=False)
        fig.update_coloraxes(showscale=False)
        fig.update_xaxes(title=None)
        fig.update_yaxes(title=None, visible=False,
                         range=[0, g["Median hours"].max() * 1.15])
        show(sty(fig, h=T, title="Median Resolution Time by Borough (Hours)",
                 sub="median hours", legend=False), "g_box")


def page_time(df):
    d = df[df["hour"].notna()]
    if EXCL0:
        d = d[d["hour"] != 0]
    if d.empty:
        st.info("No hour data for the selected filters.")
        return

    a, b, c3 = st.columns([1.6, 1.0, 1.0], gap="small")
    with a:
        hh = d["hour"].astype(int).value_counts().reindex(range(24), fill_value=0)
        hh = hh.rename_axis("Hour").reset_index(name="Requests")
        fig = px.bar(hh, x="Hour", y="Requests", color="Requests", color_continuous_scale=SCALE)
        fig.update_coloraxes(showscale=False)
        fig.update_xaxes(title=None, dtick=2)
        fig.update_yaxes(title=None)
        show(sty(fig, title="Requests by Hour of Day", sub="peak hours", legend=False), "t_hour")
    with b:
        p = d["day_part"].astype(str).value_counts().reindex(PART_ORDER).fillna(0)
        p = p.rename_axis("Part").reset_index(name="Requests")
        fig = px.bar(p, x="Part", y="Requests", color="Part", color_discrete_sequence=SEQ)
        fig.update_xaxes(title=None, tickangle=-20)
        fig.update_yaxes(title=None)
        show(sty(fig, title="Requests by Time of Day", sub="morning to night", legend=False), "t_part")
    with c3:
        w = d[d["day_type"].astype(str) != "Unknown"]["day_type"].astype(str).value_counts()
        w = w.rename_axis("Type").reset_index(name="Requests")
        fig = px.pie(w, names="Type", values="Requests", hole=0.6,
                     color="Type", color_discrete_map={"Weekday": C1, "Weekend": C5})
        fig.update_traces(textinfo="percent", marker_line_width=0)
        show(sty(fig, title="Weekday vs Weekend Share of Requests"), "t_wk")

    g = d.assign(Day=d["wd_created"].astype(str), Hour=d["hour"].astype(int))
    g = g[g["Day"].isin(DAY_ORDER)].groupby(["Day", "Hour"]).size().unstack(fill_value=0)
    g = g.reindex(index=DAY_ORDER, columns=range(24), fill_value=0)
    g.index = [x[:3] for x in g.index]
    fig = px.imshow(g, aspect="auto", color_continuous_scale=SCALE)
    fig.update_coloraxes(showscale=False)
    fig.update_xaxes(title=None, dtick=2)
    fig.update_yaxes(title=None)
    show(sty(fig, title="Peak Times: Day of Week × Hour of Day", sub="darker = more requests",
             legend=False), "t_heat")


def page_resolution(df):
    a, b = st.columns(2, gap="small")
    with a:
        hbar(top(df, "res_cat", 10), "res_cat", "How Requests Were Resolved (Top 10)", "r_cat")
    with b:
        month_line(month_series(df[df["is_closed"]], "m_closed"), "Requests Closed per Month",
                   "r_month", "closing trend")

    a, b = st.columns([1.3, 1.7], gap="small")
    with a:
        sub, _ = top_filter(df, "res_cat", 7)
        sub = sub.assign(res_cat=sub["res_cat"].map(lambda s: short(s, 20)).astype(str),
                         borough=sub["borough"].astype(str))
        g = sub.groupby(["borough", "res_cat"]).size().reset_index(name="Requests")
        fig = px.bar(g, x="Requests", y="borough", color="res_cat", orientation="h",
                     color_discrete_sequence=SEQ)
        fig.update_layout(barmode="relative", barnorm="percent")
        fig.update_yaxes(title=None)
        fig.update_xaxes(title=None)
        show(sty(fig, title="Resolution Outcome Mix by Borough (%)", sub="100% stacked"), "r_catbor")
    with b:
        median_hbar(df, "res_cat", "Median Resolution Time by Resolution Category (Hours)",
                    "r_box", top_n=8)


# ───────────────────────── App ─────────────────────────
set_style(BG_PATH, APP_BG_PATH)

try:
    data = load()
except Exception as e:
    st.error(f"Could not load data: {e}")
    st.stop()

with st.sidebar:
    fast = st.checkbox(f"Fast mode ({SAMPLE_ROWS // 1000}K sample)", value=False)
    EXCL0 = st.checkbox("Time Patterns: exclude 00:00 timestamps", value=False,
                        help="Many 311 records get 00:00:00 as a default time, which inflates "
                             "the midnight hour / Night bucket.")
    view_h = st.slider("Usable page height (px)", 480, 950, DEFAULT_VIEW_H, 10,
                       help="Raise it if there is empty space at the bottom, lower it if the page scrolls.")

hero()

PAGES = {
    "Overview": page_overview,
    "Complaints": page_complaint_agency,
    "Geography": page_geo,
    "Time Patterns": page_time,
    "Resolution": page_resolution,
}

page = st.radio(
    "Choose Dashboard",
    list(PAGES.keys()),
    horizontal=True,
    key="dashboard_navigation",
    label_visibility="collapsed"
)

months = sorted(m for m in data["m_created"].cat.categories if str(m)[:2] == "20")
fc = st.columns(5, gap="small")
filters = {
    "m_created": fc[0].multiselect("📅 Date", months, placeholder="All"),
    "borough": fc[1].multiselect("📍 Borough", sorted(data["borough"].cat.categories),
                                 placeholder="All"),
    "agency": fc[2].multiselect("🏢 Agency", sorted(data["agency"].cat.categories),
                                placeholder="All"),
    "complaint": fc[3].multiselect("📄 Complaint Type", sorted(data["complaint"].cat.categories),
                                   placeholder="All"),
    "status": fc[4].multiselect("🗄 Status", sorted(data["status"].cat.categories),
                                placeholder="All"),
}
df = data
for col, vals in filters.items():
    if vals:
        df = df[df[col].isin(vals)]
if fast and len(df) > SAMPLE_ROWS:
    df = df.sample(SAMPLE_ROWS, random_state=1)

if df.empty:
    st.warning("No data for the selected filters.")
    st.stop()

# chart heights computed from the usable page height so that nothing scrolls
if page == "Overview":
    H = max(150, (view_h - 380) // 2)
else:
    H = max(170, (view_h - 300) // 2)

try:
    PAGES[page](df)
except Exception as e:
    st.error(f"Page '{page}' failed: {type(e).__name__}: {e}")
    st.exception(e)