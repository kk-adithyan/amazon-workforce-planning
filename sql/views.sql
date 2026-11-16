-- SQL views used by the Power BI report (SQLite)

-- vw_cross_training
CREATE VIEW vw_cross_training AS

WITH workforce_gap AS (
    SELECT
        facility_id,
        occupation,
        required_workers - current_workers AS workforce_gap

    FROM (
        SELECT
            lw.facility_id,
            lw.occupation,
            lw.current_workers,

            CAST(
                (
                    fd.avg_daily_demand
                    * lw.current_workers / tw.total_workers
                    + lw.avg_productivity_units_per_worker - 1
                )
                / lw.avg_productivity_units_per_worker
                AS INTEGER
            ) AS required_workers

        FROM workforce lw

        JOIN (
            SELECT
                facility_id,
                SUM(current_workers) AS total_workers
            FROM workforce
            WHERE month = '2025-12-01 00:00:00'
            GROUP BY facility_id
        ) tw
            ON lw.facility_id = tw.facility_id

        JOIN (
            SELECT
                facility_id,
                AVG(units) AS avg_daily_demand
            FROM demand
            WHERE date >= '2025-12-01 00:00:00'
              AND date < '2026-01-01 00:00:00'
            GROUP BY facility_id
        ) fd
            ON lw.facility_id = fd.facility_id

        WHERE lw.month = '2025-12-01 00:00:00'
    )
),

surplus AS (
    SELECT
        facility_id,
        occupation AS source_occupation,
        ABS(workforce_gap) AS surplus_workers
    FROM workforce_gap
    WHERE workforce_gap < 0
),

shortage AS (
    SELECT
        facility_id,
        occupation AS target_occupation,
        workforce_gap AS shortage_workers
    FROM workforce_gap
    WHERE workforce_gap > 0
),

skill_overlap AS (
    SELECT
        s.source_occupation,
        t.target_occupation,
        COUNT(DISTINCT s.skill) AS matching_skills
    FROM (
        SELECT DISTINCT
            occupation AS source_occupation,
            skill
        FROM skill_requirements
    ) s

    JOIN (
        SELECT DISTINCT
            occupation AS target_occupation,
            skill
        FROM skill_requirements
    ) t
        ON s.skill = t.skill

    GROUP BY
        s.source_occupation,
        t.target_occupation
),

target_skill_count AS (
    SELECT
        occupation AS target_occupation,
        COUNT(DISTINCT skill) AS total_required_skills
    FROM skill_requirements
    GROUP BY occupation
)

SELECT
    f.country,
    f.city,
    su.facility_id,

    su.source_occupation,
    sh.target_occupation,

    su.surplus_workers,
    sh.shortage_workers,

    so.matching_skills,

    ROUND(
        100.0 *
        so.matching_skills /
        tc.total_required_skills,
        2
    ) AS skill_overlap_percentage,

    CASE
        WHEN
            1.0 *
            so.matching_skills /
            tc.total_required_skills >= 0.66
        THEN 'Potential Cross-Training'

        ELSE 'Low Compatibility'
    END AS recommendation

FROM surplus su

JOIN shortage sh
    ON su.facility_id = sh.facility_id

JOIN skill_overlap so
    ON su.source_occupation = so.source_occupation
    AND sh.target_occupation = so.target_occupation

JOIN target_skill_count tc
    ON sh.target_occupation = tc.target_occupation

JOIN facilities f
    ON su.facility_id = f.facility_id

WHERE
    su.source_occupation IN (
        'Packers and packagers',
        'Industrial truck operators'
    )

AND
    sh.target_occupation IN (
        'Stockers and order fillers',
        'Laborers and material movers'
    );

-- vw_facility_risk
CREATE VIEW vw_facility_risk AS

WITH facility_summary AS (
    SELECT
        f.country,
        f.city,
        f.facility_id,

        SUM(w.current_workers) AS current_workers,

        SUM(
            CAST(
                (
                    d.avg_daily_demand
                    * w.current_workers / tw.total_workers
                    + w.avg_productivity_units_per_worker - 1
                )
                / w.avg_productivity_units_per_worker
                AS INTEGER
            )
        ) AS required_workers,

        d.avg_daily_demand

    FROM workforce w

    JOIN (
        SELECT
            facility_id,
            SUM(current_workers) AS total_workers
        FROM workforce
        WHERE month = '2025-12-01 00:00:00'
        GROUP BY facility_id
    ) tw
        ON w.facility_id = tw.facility_id

    JOIN (
        SELECT
            facility_id,
            AVG(units) AS avg_daily_demand
        FROM demand
        WHERE date >= '2025-12-01 00:00:00'
          AND date < '2026-01-01 00:00:00'
        GROUP BY facility_id
    ) d
        ON w.facility_id = d.facility_id

    JOIN facilities f
        ON w.facility_id = f.facility_id

    WHERE w.month = '2025-12-01 00:00:00'

    GROUP BY
        f.country,
        f.city,
        f.facility_id,
        d.avg_daily_demand
),

risk_metrics AS (
    SELECT
        *,
        required_workers - current_workers AS workforce_gap,

        100.0 *
        (required_workers - current_workers)
        / required_workers AS shortage_percentage

    FROM facility_summary
),

normalized AS (
    SELECT
        *,

        shortage_percentage /
        MAX(shortage_percentage) OVER ()
        AS shortage_score,

        workforce_gap /
        MAX(workforce_gap) OVER ()
        AS gap_score,

        avg_daily_demand /
        MAX(avg_daily_demand) OVER ()
        AS demand_score

    FROM risk_metrics
)

SELECT
    country,
    city,
    facility_id,
    current_workers,
    required_workers,
    workforce_gap,

    ROUND(shortage_percentage, 2)
        AS shortage_percentage,

    ROUND(avg_daily_demand, 2)
        AS avg_daily_demand,

    ROUND(
        (
            shortage_score * 0.50
            + gap_score * 0.30
            + demand_score * 0.20
        ) * 100,
        2
    ) AS workforce_risk_score,

    CASE
        WHEN (
            shortage_score * 0.50
            + gap_score * 0.30
            + demand_score * 0.20
        ) * 100 >= 75
            THEN 'Critical'

        WHEN (
            shortage_score * 0.50
            + gap_score * 0.30
            + demand_score * 0.20
        ) * 100 >= 50
            THEN 'High'

        WHEN (
            shortage_score * 0.50
            + gap_score * 0.30
            + demand_score * 0.20
        ) * 100 >= 25
            THEN 'Moderate'

        ELSE 'Low'
    END AS risk_level

FROM normalized;

-- vw_occupation_gap
CREATE VIEW vw_occupation_gap AS

WITH workforce_requirement AS (
    SELECT
        w.facility_id,
        w.occupation,
        w.current_workers,
        w.avg_productivity_units_per_worker,

        CAST(
            (
                d.avg_daily_demand
                * w.current_workers / tw.total_workers
                + w.avg_productivity_units_per_worker - 1
            )
            / w.avg_productivity_units_per_worker
            AS INTEGER
        ) AS required_workers

    FROM workforce w

    JOIN (
        SELECT
            facility_id,
            SUM(current_workers) AS total_workers
        FROM workforce
        WHERE month = '2025-12-01 00:00:00'
        GROUP BY facility_id
    ) tw
        ON w.facility_id = tw.facility_id

    JOIN (
        SELECT
            facility_id,
            AVG(units) AS avg_daily_demand
        FROM demand
        WHERE date >= '2025-12-01 00:00:00'
          AND date < '2026-01-01 00:00:00'
        GROUP BY facility_id
    ) d
        ON w.facility_id = d.facility_id

    WHERE w.month = '2025-12-01 00:00:00'
)

SELECT
    f.country,
    f.city,
    wr.facility_id,
    wr.occupation,

    wr.current_workers,

    wr.required_workers,

    wr.required_workers - wr.current_workers
        AS workforce_gap,

    ROUND(
        100.0 *
        (wr.required_workers - wr.current_workers)
        / wr.required_workers,
        2
    ) AS gap_percentage,

    CASE
        WHEN wr.required_workers > wr.current_workers
            THEN 'Workforce Shortage'

        WHEN wr.required_workers < wr.current_workers
            THEN 'Potential Surplus'

        ELSE 'Balanced'
    END AS workforce_status

FROM workforce_requirement wr

JOIN facilities f
    ON wr.facility_id = f.facility_id

ORDER BY
    workforce_gap DESC;

-- vw_scenario_planning
CREATE VIEW vw_scenario_planning AS

WITH workforce_gap AS (
    SELECT
        facility_id,
        occupation,
        current_workers,
        required_workers,
        required_workers - current_workers AS workforce_gap

    FROM (
        SELECT
            lw.facility_id,
            lw.occupation,
            lw.current_workers,

            CAST(
                (
                    fd.avg_daily_demand
                    * lw.current_workers / tw.total_workers
                    + lw.avg_productivity_units_per_worker - 1
                )
                / lw.avg_productivity_units_per_worker
                AS INTEGER
            ) AS required_workers

        FROM workforce lw

        JOIN (
            SELECT
                facility_id,
                SUM(current_workers) AS total_workers
            FROM workforce
            WHERE month = '2025-12-01 00:00:00'
            GROUP BY facility_id
        ) tw
            ON lw.facility_id = tw.facility_id

        JOIN (
            SELECT
                facility_id,
                AVG(units) AS avg_daily_demand
            FROM demand
            WHERE date >= '2025-12-01 00:00:00'
              AND date < '2026-01-01 00:00:00'
            GROUP BY facility_id
        ) fd
            ON lw.facility_id = fd.facility_id

        WHERE lw.month = '2025-12-01 00:00:00'
    )
),

stockers AS (
    SELECT
        facility_id,
        workforce_gap AS shortage
    FROM workforce_gap
    WHERE occupation = 'Stockers and order fillers'
      AND workforce_gap > 0
),

surplus AS (
    SELECT
        facility_id,
        SUM(ABS(workforce_gap)) AS potential_surplus
    FROM workforce_gap
    WHERE occupation IN (
        'Packers and packagers',
        'Industrial truck operators'
    )
    AND workforce_gap < 0
    GROUP BY facility_id
)

SELECT
    f.country,
    f.city,
    s.facility_id,

    s.shortage AS stocker_shortage,

    COALESCE(
        p.potential_surplus,
        0
    ) AS potential_surplus,

    MIN(
        s.shortage,
        COALESCE(p.potential_surplus, 0)
    ) AS optimistic_redeployment,

    MAX(
        s.shortage -
        COALESCE(p.potential_surplus, 0),
        0
    ) AS optimistic_external_hiring,

    MIN(
        s.shortage,
        ROUND(
            COALESCE(p.potential_surplus, 0) * 0.6667
        )
    ) AS base_redeployment,

    MAX(
        s.shortage -
        ROUND(
            COALESCE(p.potential_surplus, 0) * 0.6667
        ),
        0
    ) AS base_external_hiring,

    MIN(
        s.shortage,
        ROUND(
            COALESCE(p.potential_surplus, 0) * 0.50
        )
    ) AS conservative_redeployment,

    MAX(
        s.shortage -
        ROUND(
            COALESCE(p.potential_surplus, 0) * 0.50
        ),
        0
    ) AS conservative_external_hiring

FROM stockers s

LEFT JOIN surplus p
    ON s.facility_id = p.facility_id

JOIN facilities f
    ON s.facility_id = f.facility_id

GROUP BY
    f.country,
    f.city,
    s.facility_id,
    s.shortage,
    p.potential_surplus;

