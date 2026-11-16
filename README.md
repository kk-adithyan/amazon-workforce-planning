# Workforce Planning \& Intelligence Dashboard

An end-to-end workforce planning analysis for a six-site fulfilment network, built with **SQL** (SQLite) for data preparation and **Power BI** for reporting. The report answers four questions: how many workers do we have, how many do we need, where is the risk, and what happens if demand or attrition changes.

> \*\*Data note:\*\* this is a modeled dataset built for a portfolio project. Occupation data is based on U.S. Bureau of Labor Statistics (BLS) benchmarks. It is \*\*not\*\* Amazon internal data, and the scenario figures are planning assumptions, not forecasts.

## Dashboard preview

|Overview|Gap analysis|
|-|-|
|!\[Overview](screenshots/01-overview.png)|!\[Gap analysis](screenshots/02-gap-analysis.png)|

|Risk|Intervention|
|-|-|
|!\[Risk](screenshots/03-risk.png)|!\[Intervention](screenshots/04-intervention.png)|

!\[Scenario planning](screenshots/05-scenario.png)

A PDF export of all five pages is in [`dashboard/`](dashboard/).

## Key findings

* The network has **11,070 workers** against a requirement of **14,278**, a gap of **3,208** (22.5% of the requirement).
* **Hyderabad is the only Critical facility** (risk score 99.6). It has the largest gap (705 workers) and the biggest hiring need. The other five facilities are High risk, with scores between 59 and 66.
* The shortage is concentrated in one occupation: **Stockers and order fillers are 2,544 short**, while packers and industrial truck operators are in surplus (-206 and -310).
* Redeploying surplus workers covers only about **343 of the 2,544** stocker shortage in the base case, so about **2,201** must be hired externally (2,028 in the optimistic case, 2,284 in the conservative case).
* Under a **20% demand peak**, the six-month workforce gap rises from **4,225 to 7,076** (about 67% higher). A 5% rise in attrition adds only about 51 extra exits, so demand growth is the bigger staffing risk.

## Report pages

|Page|Question it answers|
|-|-|
|Workforce Overview|What is the current headcount, by facility and occupation?|
|Workforce Gap Analysis|Where and in which jobs is current staffing below requirement?|
|Risk Analysis|Which facilities are under the most workforce and capacity pressure?|
|Workforce Intervention|Should the stocker shortage be met by redeployment or by hiring?|
|Scenario Planning|How does the six-month gap change under Baseline, Peak demand and High attrition?|

## How it was built

**1. Database (SQLite)**
`amazon\_workforce\_planning.db` holds the facilities, monthly workforce snapshots, daily demand, attrition, skill requirements and BLS occupation tables. Four SQL views (see [`sql/views.sql`](sql/views.sql)) prepare the analysis:

|View|Purpose|
|-|-|
|`vw\_facility\_risk`|Current vs required workers, gap, shortage % and risk score per facility|
|`vw\_occupation\_gap`|The same comparison per facility and occupation|
|`vw\_scenario\_planning`|Stocker shortage, redeployable surplus and external hiring (optimistic, base, conservative)|
|`vw\_cross\_training`|Surplus occupations that could be cross-trained into Stockers, with skill overlap|

**2. Scenario model**
[`scripts/build\_scenario\_results.py`](scripts/build_scenario_results.py) builds `vw\_scenario\_results.csv`:

* Required workers scale with demand (Peak = +20%).
* Expected exits = current workers × December 2025 monthly attrition rate × (1 + attrition uplift) × 6 months. High attrition is modeled as a **5% relative increase** in the attrition rate.
* Scenario gap = required workers − current workers + expected exits.

**3. Power BI**
The report uses a star-style model with `facilities` as the central dimension (one-to-many to the fact tables on `facility\_id`). Measures sit in a `\_Measures` table. Current headcount is always taken from the **latest month** (headcount is a snapshot and is never summed across months).

## Repository structure

```
.
├── README.md
├── dashboard/
│   ├── Amazon Workforce Planning.pbix
│   └── Amazon Workforce Planning.pdf
├── data/
│   ├── amazon\_workforce\_planning.db
│   └── views/                  (CSV exports of the SQL views)
├── sql/
│   └── views.sql
├── scripts/
│   └── build\_scenario\_results.py
├── theme/
│   └── workforce\_theme.json
└── screenshots/
```

## How to open the report

1. Open `dashboard/Amazon Workforce Planning.pbix` in **Power BI Desktop** (free).
2. If Power BI asks for the data source, point it to the CSV files in `data/views/`.
3. Use the **City** slicer in the top right. It is synced across all five pages.

## Limitations

* The dataset is modeled, so figures illustrate the method and are not real operating results.
* Required workers use a simple demand ÷ productivity rule. Real planning would also include shift patterns, training time and hiring lead times.
* The six-month scenarios hold productivity constant (productivity uplift is 0).
* Redeployment shares (100%, about 67%, 50%) are assumptions.

## Tools

SQL (SQLite) · Python (pandas) · Power BI (DAX, data modeling) · Git and GitHub

## Author

**Adithyan K K** · B.Sc. Data Science · [LinkedIn](https://www.linkedin.com/in/adithyan-k-k-00b5b52a4) · [GitHub](https://github.com/kk-adithyan)

# amazon-workforce-planning
