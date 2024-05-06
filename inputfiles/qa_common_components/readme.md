![alt text](https://dev.sentinelsystem.org/projects/AP/repos/sentinel-analytic-packages/raw/resources/logo.png?at=refs%2Fheads%2Fmaster)

# Data Quality Review and Characterization Programs

## Sentinel Common Components

Sentinel Common Components is a SAS® program package which provisions commonly used metadata to subsequently run distributed SAS packages—e.g., location of Sentinel Common Data Model (SCDM) formatted tables, SCDM table names, refresh version, minimum and maximum dates of data-completeness. This simplifies the set-up of subsequent Sentinel distributed packages, such as the [Query Request Package](https://dev.sentinelsystem.org/projects/AD/repos/qrp/browse) (QRP) and the [Mother-Infant Linkage (MIL) QA Package](https://dev.sentinelsystem.org/projects/QA/repos/qa_mil_package/browse).

For more information on how these programs use Common Components in their setup set-up, please see:

- the [QRP Program Package and Execution documentation](https://dev.sentinelsystem.org/projects/SENTINEL/repos/sentinel-routine-querying-tool-documentation/browse/files/file510-typeall-programpackage.md)
- the [MIL QA Program Package Setup documentation](https://dev.sentinelsystem.org/pages/SENTINEL/sentinel-quality-assurance-documentation/master/browse/qmr-getting-started.html)

This package also has the ability to execute the Sentinel Snapshot package. The Snapshot package includes SAS programs and input files that operate together to produce a set of aggregate tables based on a Data Partner's SCDM tables for the purpose of data characterization.

### Folder Structure

- **docs**: contains the QA Common Components functional specifications
- **dplocal**: houses saved datasets with patient identifiers. For more information about Sentinel's privacy standards, please refer to **[The Sentinel System Principles and Policies](https://www.sentinelinitiative.org/principles-and-policies-privacy)**
- **inputfiles**: a subfolder that contains all input files and lookup tables needed to execute a request. Input files contain information on what tables should be output and the type of analyses conducted on the variables in each table
    - **dp_metadata**: folder contains QA package  output metadata files specific to a particular ETL
    - **cc_test**: folder contains the program modules and input files used to test the setup of the CC parameters
    - **cc_utility**: folder contains program module cc_macvars.sas used to setup the CC parameters
    - **snapshot**: contains the program modules and input files used to generate snapshot output
- **msoc**: houses saved aggregated program results
- **sasprograms**: contains the file(s) to be executed

### Requirements

- UNIX/Linux or Windows environment
- SAS version 9.4 or higher
- SCDM formatted data
- The following SAS datasets, output by a completed run of the [Sentinel Quality Assurance Package](https://dev.sentinelsystem.org/projects/QA/repos/qa_package/browse) or the [MIL QA Package](https://dev.sentinelsystem.org/projects/QA/repos/qa_mil_package/browse):
    - `all_l1_cont`
    - `etl_version`
    - `minmax_dates`
    - `qa_cc_metadata`

### Package Setup

Follow these steps to set-up the Common Components package for execution:

1. Clone this repository: `git clone https://dev.sentinelsystem.org/scm/qa/qa_common_components.git`
    1. Rename the repository folder to reflect the RequestID used for this run of Common Components. Sentinel RequestIDs use the following convention `PROJID_WPTYPE_WPID_DPID_VERID`—e.g., `soc_cca_wp999_nsdp_v01`
2. From the QA Package executed against the SCDM tables in question, find copy the files `all_l1_cont`, `etl_version`, `minmax_dates`, and `qa_cc_metadata` from the QA Package `msoc` directory to QA Common Components `inputfiles/dp_metadata`
3. Populate the parameters in QA Common Components `sasprograms\00.0_soc_qa_cc_master_file.sas` following instructions in the code. For more information on any of these parameters, please refer to the functional specifications found in the `docs` folder
4. When set-up is complete, please execute the program use SAS' batch mode

### What does "Common Components" mean?

“Common components” generally refers to software modules that are widely used within a software system to provide commonly needed services—e.g. data/methods—through a defined interface.  In the context of the Sentinel Distributed Database (SDD), Common Components provides site-specific values for standard macro variables that are referenced by Sentinel distributed SAS queries at execution time. The use of common components by Sentinel distributed SAS queries  streamlines the distributed query process and minimizes the chances of errors—e.g., executing a query against a non-approved ETL, executing a query using the wrong values for min/max dates of completeness, etc.

### Additional Information

The Sentinel Operations Center has limited capacity to support use of our tools. However, we welcome feedback, comments, and suggestions pertaining to our documentation or tools. Email us **[here](mailto:info@sentinelsystem.org?subject=Git)**.

#### Disclosure

Sentinel is sponsored by the [U.S. Food and Drug Administration (FDA)](http://www.fda.gov/) to monitor the safety of FDA-regulated medical products. Sentinel is one piece of the [Sentinel Initiative](http://www.fda.gov/Safety/FDAsSentinelInitiative/default.htm), a multi-faceted effort by the FDA to develop a national electronic system that complements previously existing methods of safety surveillance. Sentinel Collaborators include Data and Academic Partners that provide access to health care data and ongoing scientific, technical, methodological, and organizational expertise. The Sentinel Operations Center is funded by the FDA through the Department of Health and Human Services (HHS) Task order 75F40119D10037.
