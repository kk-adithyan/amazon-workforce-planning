"""Builds vw_scenario_results.csv: six-month workforce gap under three scenarios.

Scenario gap = required workers - current workers + expected exits (6 months).
Required workers scale with demand; expected exits use the Dec-2025 monthly
attrition rate per facility and occupation, raised by the attrition uplift.
Scenario values come from the scenario_inputs table (Peak: +20% demand,
High Attrition: +5% relative increase in the attrition rate).
"""
import sqlite3
import pandas as pd

DB = "amazon_workforce_planning.db"
HORIZON_MONTHS = 6
SCENARIOS = {"Baseline": (0, 0), "Peak": (0.20, 0), "High Attrition": (0, 0.05)}

c = sqlite3.connect(DB)
w = pd.read_sql("select facility_id, occupation, soc_code, current_workers, "
                "avg_productivity_units_per_worker as prod from workforce "
                "where month = '2025-12-01 00:00:00'", c)
d = pd.read_sql("select facility_id, avg(units) as dem from demand "
                "where date >= '2025-12-01 00:00:00' and date < '2026-01-01 00:00:00' "
                "group by facility_id", c)
a = pd.read_sql("select facility_id, soc_code, employees_left, opening_headcount "
                "from attrition where month = '2025-12-01 00:00:00'", c)
f = pd.read_sql("select facility_id, city, country from facilities", c)

df = w.merge(d, on="facility_id").merge(a, on=["facility_id", "soc_code"]).merge(f, on="facility_id")
total_workers = df.groupby("facility_id").current_workers.transform("sum")
df["rate"] = df.employees_left / df.opening_headcount

out = []
for name, (demand_up, attrition_up) in SCENARIOS.items():
    x = df.copy()
    demand_share = x.dem * (1 + demand_up) * x.current_workers / total_workers
    x["required_workers"] = ((demand_share + x["prod"] - 1) / x["prod"]).astype(int)
    x["expected_exits"] = (x.current_workers * x.rate * (1 + attrition_up) * HORIZON_MONTHS).round().astype(int)
    x["scenario_gap"] = x.required_workers - x.current_workers + x.expected_exits
    x["scenario"] = name
    out.append(x)

cols = ["scenario", "facility_id", "city", "country", "occupation",
        "current_workers", "required_workers", "expected_exits", "scenario_gap"]
pd.concat(out)[cols].to_csv("vw_scenario_results.csv", index=False)
