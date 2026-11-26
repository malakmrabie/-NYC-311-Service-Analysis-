DROP TABLE IF EXISTS Dim_Res_Category;

CREATE TABLE Dim_Res_Category (
    Category_Key         INT AUTO_INCREMENT PRIMARY KEY,
    resolution_description  TEXT         NOT NULL,
    category                VARCHAR(50)  NOT NULL,
	KEY idx_category (category)
);

INSERT INTO Dim_Res_Category (
    resolution_description,
    category
)
SELECT
    x.resolution_description,

    CASE
        WHEN LOWER(x.resolution_description) REGEXP
        'duplicate|already exists|previously reported|previously filed|already has a request|earlier complaint|multiple service requests|another service request|more than one complaint|already reported'
        THEN 'Duplicate / Already Reported'

        WHEN LOWER(x.resolution_description) REGEXP
        'jurisdiction|referred|will refer|refer your|should contact|contact the appropriate|file a service request with|file a new service request with the|needs to be handled by|another entity|transfer this issue|another city agency|informed the responsible public utility'
        THEN 'Referred / Out of Jurisdiction'

        WHEN LOWER(x.resolution_description) REGEXP
        'gain access|gain entry|unable to access|not able to access|could not access|denied access|access warrant|unable to complete|could not complete|not able to complete|enough time|enough information|sufficient|incomplete|could not locate|could not be contacted|unable to reach|unable to contact|get in touch|not respond|requires contact with the complainant|requires an appointment|number provided was incorrect|left a message|message was left|undeliverable|unable to identify|did not include|t include|t submit|is locked|unsafe for inspectors|refused|t accept|did not accept|could not find the location|could not find the site|could not find the address|address was|address you reported|address provided|addressed submitted|invalid|ordered it not'
        THEN 'Access / Information Issue'

        WHEN LOWER(x.resolution_description) REGEXP
        't eligible|ineligible|not eligible|does not meet|t meet|not meeting|exceeds the monetary|cannot receive|not vacant|t vacant|only remove|only clean|being used for parking|under construction|not feasible|denied the|does not rate|privately owned|responsibility of the home|occupied building|occupied structure|business appears'
        THEN 'Not Eligible / Criteria Not Met'

        WHEN LOWER(x.resolution_description) REGEXP
        'no violation|not violate|not a violation|t see|not see|t find|not find|could not find|unable to find|no evidence|no condition|not found|no further action|no action was taken|no work is necessary|no work was needed|t observe|not observe|no graffiti|no encampment|no odors|no health code|no indication|no impact|no asbestos|not necessary|no repair|passed|in compliance|compliance with|meets its standards|meets dot|within acceptable|were gone|owner claimed|not abandoned|t abandoned|not deemed|was not required|temporary condition|isolated|not hazardous|no sewer|no inspection is necessary|no work order was necessary|no litter|did not issue|was not issued|not issued|unable to issue|unsubstantiated'
        THEN 'No Violation / Condition Not Found'

        WHEN LOWER(x.resolution_description) REGEXP
        'violation|summons|arrest|commissioner|vacate order|stop work order|padlock|warning|advisory|written documentation|written notification|pled guilty|oath|unsafe building|corrective action|notified the property owner|ordered|section 8 failure|notice to the responsible party|issued a notice'
        THEN 'Violation / Enforcement Issued'

        WHEN LOWER(x.resolution_description) REGEXP
        '^n/a$|thank you for your report|see notes|notes to customer|customer notes|not available online|administratively|technical|inactivation|withdrew|no further updates|allocated resources|devote resources|call 311 for further'
        THEN 'Administrative / Other'

        WHEN LOWER(x.resolution_description) REGEXP
        'will |created a work order|scheduled|in progress|pending|under review|is reviewing|still open|further investigation|future|expects|expected|requires 30|requires 90|more information will|additional information will'
        THEN 'Pending / Scheduled / In Progress'

        WHEN LOWER(x.resolution_description) REGEXP
        'repaired|cleaned|removed|collected|completed|corrected|resolved|fixed|restored|replaced|plowed|salted|installed|flushed|unlocked|locked the hydrant|shut the|placed|opened fire hydrants|returned the|found the lost|counseled|spoke|mailed you|sent a report|letter of potability|educated|took action|addressed the issue|made a repair|performed|supplemental planting'
        THEN 'Resolved - Action Taken'

        ELSE 'Administrative / Other'
    END AS category

FROM (
    SELECT
        MIN(resolution_description) AS resolution_description
    FROM nyc_311_2024_clean
    WHERE resolution_description IS NOT NULL
      AND TRIM(resolution_description) <> ''
    GROUP BY MD5(LOWER(TRIM(resolution_description)))
) AS x;