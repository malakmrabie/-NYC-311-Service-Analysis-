CREATE DATABASE IF NOT EXISTS nyc_311_service;
USE nyc_311_service;
DROP TABLE IF EXISTS nyc_311_2024_all_months ;
CREATE TABLE nyc_311_2024_all_months (
    unique_key LONGTEXT,
    created_date LONGTEXT,
    closed_date LONGTEXT,
    agency LONGTEXT,
    agency_name LONGTEXT,
    complaint_type LONGTEXT,
    descriptor LONGTEXT,
    location_type LONGTEXT,
    incident_zip LONGTEXT,
    incident_address LONGTEXT,
    street_name LONGTEXT,
    cross_street_1 LONGTEXT,
    cross_street_2 LONGTEXT,
    intersection_street_1 LONGTEXT,
    intersection_street_2 LONGTEXT,
    address_type LONGTEXT,
    city LONGTEXT,
    landmark LONGTEXT,
    status LONGTEXT,
    resolution_description LONGTEXT,
    resolution_action_updated_date LONGTEXT,
    community_board LONGTEXT,
    council_district LONGTEXT,
    police_precinct LONGTEXT,
    bbl LONGTEXT,
    borough LONGTEXT,
    x_coordinate_state_plane LONGTEXT,
    y_coordinate_state_plane LONGTEXT,
    open_data_channel_type LONGTEXT,
    park_facility_name LONGTEXT,
    park_borough LONGTEXT,
    latitude LONGTEXT,
    longitude LONGTEXT,
    descriptor_2 LONGTEXT,
    facility_type LONGTEXT,
    bridge_highway_name LONGTEXT,
    bridge_highway_segment LONGTEXT,
    taxi_pick_up_location LONGTEXT,
    vehicle_type LONGTEXT,
    bridge_highway_direction LONGTEXT,
    road_ramp LONGTEXT,
    taxi_company_borough LONGTEXT,
    due_date LONGTEXT
);

LOAD DATA LOCAL INFILE
'C:/NYC 311 Service Request/NYC_311_2024_ALL_MONTHS.csv'

INTO TABLE nyc_311_2024_all_months

CHARACTER SET utf8mb4

FIELDS TERMINATED BY ','
ENCLOSED BY '"'
ESCAPED BY '"'

LINES TERMINATED BY '\n'

IGNORE 1 ROWS

(
    unique_key,
    created_date,
    closed_date,
    agency,
    agency_name,
    complaint_type,
    descriptor,
    location_type,
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
    status,
    resolution_description,
    resolution_action_updated_date,
    community_board,
    council_district,
    police_precinct,
    bbl,
    borough,
    x_coordinate_state_plane,
    y_coordinate_state_plane,
    open_data_channel_type,
    park_facility_name,
    park_borough,
    latitude,
    longitude,
    descriptor_2,
    facility_type,
    bridge_highway_name,
    bridge_highway_segment,
    taxi_pick_up_location,
    vehicle_type,
    bridge_highway_direction,
    road_ramp,
    taxi_company_borough,
    due_date
);

SELECT COUNT(*) AS Total_Rows
FROM nyc_311_2024_all_months;

SELECT
    COUNT(*) AS Total_Rows,
    COUNT(DISTINCT unique_key) AS Unique_Requests,
    COUNT(*) - COUNT(DISTINCT unique_key) AS Duplicate_Or_Null_Keys
FROM nyc_311_2024_all_months;


USE nyc_311_service;

ALTER TABLE nyc_311_2024_all_months
RENAME COLUMN created_date TO created_datetime;

ALTER TABLE nyc_311_2024_all_months
RENAME COLUMN closed_date TO closed_datetime;