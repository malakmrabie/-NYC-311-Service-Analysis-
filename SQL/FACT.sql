USE nyc_311_service;

DROP TABLE IF EXISTS Fact_Service_Request;
CREATE TABLE Fact_Service_Request (
    ID                  BIGINT PRIMARY KEY NOT NULL,
    Created_Time        TIME NOT NULL,
    Close_Time          TIME NULL,
	Created_Hour        TINYINT NULL,
    status              VARCHAR(100),
    Resolution_Hours    DECIMAL(12,2),
    Resolution_Category VARCHAR(100),
    agency_key          INT NOT NULL,
    channel_key         INT NOT NULL,
    city_key            INT NOT NULL,
    complaint_key       INT NOT NULL,
    date_key            INT NOT NULL,
    location_key        INT NULL,
    Category_Key        INT NULL
);

INSERT INTO Fact_Service_Request
SELECT
    c.ID,
    c.Created_Time,
    c.Closed_Time,
	c.Created_Hour,
    c.status,
    c.Resolution_Hours,
    COALESCE(cat.category, 'No Resolution Text'), 
    a.agency_key,
    ch.channel_key,
    ci.city_key,
    cp.complaint_key,
    d.date_key,
    l.Location_Key,
    cat.category_key
FROM nyc_311_2024_clean c
JOIN dim_date      d  ON d.Created_Date = c.Created_Date AND d.Closed_Date <=> c.Closed_Date
JOIN dim_agency    a  ON a.agency = c.agency AND a.agency_name = c.agency_name
JOIN dim_channel   ch ON ch.channel = c.open_data_channel_type
JOIN dim_city      ci ON ci.community_board = c.community_board AND ci.borough = c.borough
JOIN dim_complaint cp ON cp.complaint_type = c.complaint_type AND cp.descriptor = c.descriptor
LEFT JOIN dim_location l  ON l.location_type = c.location_type AND l.latitude  = c.latitude AND l.longitude = c.longitude
LEFT JOIN dim_res_category cat ON cat.resolution_description = c.resolution_description
WHERE c.ID IS NOT NULL AND c.Created_Date IS NOT NULL;
/*
SELECT
  (SELECT COUNT(*) FROM nyc_311_2024_clean WHERE ID IS NOT NULL AND Created_Date IS NOT NULL) AS Expected,
  (SELECT COUNT(*) FROM Fact_Service_Request) AS Fact_Rows,
  (SELECT COUNT(*) FROM Fact_Service_Request WHERE location_key IS NULL) AS No_Location;
  */

ALTER TABLE Fact_Service_Request
    ADD CONSTRAINT fk_f_agency   FOREIGN KEY (agency_key)    REFERENCES dim_agency(agency_key),
    ADD CONSTRAINT fk_f_channel  FOREIGN KEY (channel_key)   REFERENCES dim_channel(channel_key),
    ADD CONSTRAINT fk_f_city     FOREIGN KEY (city_key)      REFERENCES dim_city(city_key),
    ADD CONSTRAINT fk_f_comp     FOREIGN KEY (complaint_key) REFERENCES dim_complaint(complaint_key),
    ADD CONSTRAINT fk_f_date     FOREIGN KEY (date_key)      REFERENCES dim_date(date_key),
    ADD CONSTRAINT fk_f_location FOREIGN KEY (location_key)  REFERENCES dim_location(Location_Key),
    ADD CONSTRAINT fk_f_category FOREIGN KEY (Category_Key)  REFERENCES dim_res_category(category_key);