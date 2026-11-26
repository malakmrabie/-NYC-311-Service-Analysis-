USE nyc_311_service;

DROP TABLE IF EXISTS nyc_311_2024_clean;

CREATE TABLE nyc_311_2024_clean AS
SELECT
    t.*,

    DAY(t.Created_Date) AS Created_Day,
    MONTH(t.Created_Date) AS Created_Month,
    MONTHNAME(t.Created_Date) AS Created_Month_Name,
    DAYNAME(t.Created_Date) AS Created_Day_Name,
    HOUR(t.Created_Time) AS Created_Hour,
    YEAR(t.Created_Date) AS Created_Year,

    CASE
        WHEN t.Closed_Date IS NULL OR t.Closed_Time IS NULL THEN NULL
        WHEN t.Created_Date IS NULL OR t.Created_Time IS NULL THEN NULL
        WHEN TIMESTAMP(t.Closed_Date, t.Closed_Time)
             < TIMESTAMP(t.Created_Date, t.Created_Time) THEN NULL
        ELSE ROUND(
            TIMESTAMPDIFF(
                SECOND,
                TIMESTAMP(t.Created_Date, t.Created_Time),
                TIMESTAMP(t.Closed_Date, t.Closed_Time)
            ) / 3600, 2
        )
    END AS Resolution_Hours,

    CASE
        WHEN t.Closed_Date IS NULL THEN 'Open'
        WHEN t.due_date IS NULL THEN 'Missing'
        WHEN TIMESTAMP(t.Closed_Date, t.Closed_Time) <= t.due_date
            THEN 'Within SLA'
        ELSE 'Breached SLA'
    END AS SLA_Status
FROM (
    SELECT
        unique_key,
        CAST(unique_key AS UNSIGNED) AS ID,

STR_TO_DATE(
    NULLIF(LEFT(TRIM(created_datetime), 10), ''),
    '%Y-%m-%d'
) AS Created_Date,

STR_TO_DATE(
    NULLIF(SUBSTRING(TRIM(created_datetime), 12, 8), ''),
    '%H:%i:%s'
) AS Created_Time,

STR_TO_DATE(
    NULLIF(LEFT(TRIM(closed_datetime), 10), ''),
    '%Y-%m-%d'
) AS Closed_Date,

STR_TO_DATE(
    NULLIF(SUBSTRING(TRIM(closed_datetime), 12, 8), ''),
    '%H:%i:%s'
) AS Closed_Time, 

        COALESCE(NULLIF(TRIM(agency), ''), 'Unknown')       AS agency,
        COALESCE(NULLIF(TRIM(agency_name), ''), 'Unknown')  AS agency_name,
        COALESCE(NULLIF(TRIM(complaint_type), ''), 'Unknown') AS complaint_type,
        CAST(COALESCE(NULLIF(TRIM(descriptor), ''), 'Unknown') AS CHAR(255)) AS descriptor,
        COALESCE(NULLIF(TRIM(location_type), ''), 'Unknown') AS location_type,

        incident_zip,
        incident_address,
        street_name,
        cross_street_1,
        cross_street_2,
        intersection_street_1,
        intersection_street_2,
        address_type,
        city,
        landmark,

        COALESCE(NULLIF(TRIM(status), ''), 'Unknown') AS status,

        NULLIF(TRIM(REPLACE(resolution_description, CHAR(13), '')), '') AS resolution_description,

        STR_TO_DATE(NULLIF(REPLACE(LEFT(TRIM(resolution_action_updated_date), 19), 'T', ' '), ''),
                    '%Y-%m-%d %H:%i:%s') AS resolution_action_updated_date,

        CASE
            WHEN community_board IS NULL
              OR TRIM(community_board) = ''
              OR community_board LIKE '%Unspecified%'
            THEN 'Unknown'
            ELSE TRIM(community_board)
        END AS community_board,

        council_district,
        police_precinct,
        bbl,

        CASE
            WHEN borough IS NULL
              OR TRIM(borough) = ''
              OR TRIM(borough) = 'Unspecified'
            THEN 'Unknown'
            ELSE TRIM(borough)
        END AS borough,

        x_coordinate_state_plane,
        y_coordinate_state_plane,

        CASE
            WHEN open_data_channel_type IS NULL
              OR TRIM(open_data_channel_type) = ''
              OR TRIM(open_data_channel_type) = 'Unspecified'
            THEN 'Unknown'
            ELSE TRIM(open_data_channel_type)
        END AS open_data_channel_type,

        park_facility_name,
        park_borough,

        CAST(NULLIF(TRIM(latitude), '')  AS DECIMAL(10,7)) AS latitude,
        CAST(NULLIF(TRIM(longitude), '') AS DECIMAL(10,7)) AS longitude,

        descriptor_2,
        facility_type,
        bridge_highway_name,
        bridge_highway_segment,
        taxi_pick_up_location,
        vehicle_type,
        bridge_highway_direction,
        road_ramp,
        taxi_company_borough,

        STR_TO_DATE(NULLIF(REPLACE(LEFT(TRIM(due_date), 19), 'T', ' '), ''),
                    '%Y-%m-%d %H:%i:%s') AS due_date

    FROM nyc_311_2024_all_months
) AS t;

-- فحوصات
SELECT COUNT(*) AS Total_Rows,
       COUNT(DISTINCT unique_key) AS Unique_Requests,
       COUNT(*) - COUNT(DISTINCT unique_key) AS Duplicate_Or_Null_Keys
FROM nyc_311_2024_clean;

SELECT COUNT(*) AS Total_Rows,
       SUM(created_date IS NULL) AS Missing_Created,
       SUM(closed_date IS NULL) AS Missing_Closed,
       SUM(closed_date < created_date) AS Invalid_Date_Sequence,
       SUM(latitude IS NULL) AS Null_Lat,
       SUM(resolution_description IS NULL) AS Null_Resolution_Text
FROM nyc_311_2024_clean;

SELECT borough, COUNT(*) AS Total FROM nyc_311_2024_clean GROUP BY borough ORDER BY Total DESC;
SELECT open_data_channel_type, COUNT(*) AS Total FROM nyc_311_2024_clean GROUP BY open_data_channel_type ORDER BY Total DESC;

ALTER TABLE nyc_311_2024_clean
    DROP COLUMN incident_zip,
    DROP COLUMN incident_address,
    DROP COLUMN street_name,
    DROP COLUMN cross_street_1,
    DROP COLUMN cross_street_2,
    DROP COLUMN intersection_street_1,
    DROP COLUMN intersection_street_2,
    DROP COLUMN address_type,
    DROP COLUMN city,
    DROP COLUMN landmark,
    DROP COLUMN resolution_action_updated_date,
    DROP COLUMN council_district,
    DROP COLUMN police_precinct,
    DROP COLUMN bbl,
    DROP COLUMN x_coordinate_state_plane,
    DROP COLUMN y_coordinate_state_plane,
    DROP COLUMN park_facility_name,
    DROP COLUMN park_borough,
    DROP COLUMN descriptor_2,
    DROP COLUMN facility_type,
    DROP COLUMN bridge_highway_name,
    DROP COLUMN bridge_highway_segment,
    DROP COLUMN taxi_pick_up_location,
    DROP COLUMN vehicle_type,
    DROP COLUMN bridge_highway_direction,
    DROP COLUMN road_ramp,
    DROP COLUMN taxi_company_borough,
    DROP COLUMN due_date,
    DROP COLUMN unique_key,
    DROP COLUMN SLA_Status;
    

