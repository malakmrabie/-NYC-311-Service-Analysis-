USE nyc_311_service;

CREATE TABLE Dim_Agency (
    agency_key  INT AUTO_INCREMENT PRIMARY KEY,
    agency      VARCHAR(100) NOT NULL,
    agency_name VARCHAR(255) NOT NULL,
    UNIQUE KEY uq_agency (agency, agency_name)
);
INSERT INTO Dim_Agency (agency, agency_name)
SELECT DISTINCT agency, agency_name FROM nyc_311_2024_clean;
-- SELECT COUNT(*) AS Agencies FROM Dim_Agency;

#---------------------------------------------------------------------

CREATE TABLE Dim_Channel (
    channel_key INT AUTO_INCREMENT PRIMARY KEY,
    channel     VARCHAR(100) NOT NULL,
    UNIQUE KEY uq_channel (channel)
);
INSERT INTO Dim_Channel (channel)
SELECT DISTINCT open_data_channel_type FROM nyc_311_2024_clean;
-- SELECT COUNT(*) AS Channels FROM Dim_Channel;

#---------------------------------------------------------------------

CREATE TABLE Dim_Complaint (
    complaint_key  INT AUTO_INCREMENT PRIMARY KEY,
    complaint_type VARCHAR(255) NOT NULL,
    descriptor     VARCHAR(255) NOT NULL,
    UNIQUE KEY uq_complaint (complaint_type, descriptor)
);
INSERT INTO Dim_Complaint (complaint_type, descriptor)
SELECT DISTINCT complaint_type, descriptor FROM nyc_311_2024_clean;
-- SELECT COUNT(*) AS Complaints FROM Dim_Complaint;

#---------------------------------------------------------------------

CREATE TABLE Dim_City (
    city_key        INT AUTO_INCREMENT PRIMARY KEY,
    community_board VARCHAR(100) NOT NULL,
    borough         VARCHAR(100) NOT NULL,
    UNIQUE KEY uq_city (community_board, borough)
);
INSERT INTO Dim_City (community_board, borough)
SELECT DISTINCT community_board, borough FROM nyc_311_2024_clean;
-- SELECT COUNT(*) AS Cities FROM Dim_City;

#---------------------------------------------------------------------

CREATE TABLE  Dim_Date (
    date_key           INT AUTO_INCREMENT PRIMARY KEY,
    Created_Date       DATE NOT NULL,
    Closed_Date        DATE NULL,
    Created_Day_Name   VARCHAR(20),
    Created_Month_Name VARCHAR(20),
    Month_Number       TINYINT,
    Day_Type           VARCHAR(10),
    UNIQUE KEY uq_date (Created_Date, Closed_Date)
);

INSERT INTO Dim_Date (
    Created_Date,
    Closed_Date,
    Created_Day_Name,
    Created_Month_Name,
    Month_Number,
    Day_Type
)
SELECT DISTINCT
    Created_Date,
    Closed_Date,
    Created_Day_Name,
    Created_Month_Name,
    Created_Month,
    CASE
        WHEN DAYOFWEEK(Created_Date) IN (1, 7)
        THEN 'Weekend'
        ELSE 'Weekday'
    END
FROM nyc_311_2024_clean
WHERE Created_Date IS NOT NULL
ORDER BY Created_Date, Closed_Date;

#---------------------------------------------------------------------

CREATE TABLE Dim_Location (
    Location_Key INT AUTO_INCREMENT PRIMARY KEY,
    location_type VARCHAR(100),
    latitude DECIMAL(10,7),
    longitude DECIMAL(10,7),

    UNIQUE KEY uq_location (
        location_type,
        latitude,
        longitude
    )
);

INSERT INTO Dim_Location (
    location_type,
    latitude,
    longitude
)
SELECT DISTINCT
    location_type,
    latitude,
    longitude
FROM nyc_311_2024_clean
WHERE latitude IS NOT NULL AND longitude IS NOT NULL;


