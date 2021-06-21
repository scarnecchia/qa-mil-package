![alt text](resources/logo.png)

# Data Quality Review and Characterization Programs

## Quality Assurance (QA) Mother Infant Linkage (MIL) Package

### Overview

This document describes the program package used to perform quality assurance (QA) review and characterization of Mother Infant Linkage (MIL) data in the [Sentinel Common Data Model](https://dev.sentinelsystem.org/projects/SCDM/repos/sentinel_common_data_model/browse) (SCDM) format. This program package helps to ensure the data meets the necessary standards for data transformation consistency and quality.

Analytic programs that are executed against data that is not in SCDM format will likely yield errors. Successful execution of the QA MIL package indicates that the source data adheres to SCDM rules. Note that data must be in the form of SAS&reg; datasets in order to use these analytic programs.

The specifications for the QA Package can be found in the [QA Documentation repository](https://dev.sentinelsystem.org/projects/SENTINEL/repos/sentinel-quality-assurance-documentation/browse).

#### To View Analytic Request Packages
* Click the drop-down menu in the top left-hand corner 
* Choose the Request ID representing the analysis of interest
* Click the "..." button
* Select "Download" from the menu that appears

![Screenshot of master branch dropdown menu closed](resources/dropdown-menu1.PNG)  

<br>

![Screenshot of master branch dropdown menu open](resources/dropdown-menu2.PNG)

<br>

![Screenshot of master branch dropdown menu with download button](resources/dropdown-menu3.PNG)  


#### Analytic Request Package Folder Structure  
* <b> docs:</b> is where specifications are saved; specifications provide details about the request's the parameters, as well as information about each analytic scenario that is represented in the input files
* <b> dplocal:</b> is where datasets with patient identifiers are saved (For more information about Sentinel's privacy standards, please refer to [The Sentinel System Principles and Policies](https://www.sentinelinitiative.org/principles-and-policies-privacy).)
* <b> inputfiles:</b> contains SAS datasets specific to the given analysis; and lookup files that were created by the Sentinel Operations Center
* <b> msoc:</b> is where program results are saved
* <b> sasprograms:</b> contains the file(s) to be executed

### Folder Structure

- **docs**: Contains specifications which details QA MIL functionality and provides a description of the datasets output by the QA MIL Package into the `dplocal` and `msoc` folders
- **dplocal**: is where datasets with patient identifiers are saved. For more information about Sentinel's privacy standards, please refer to **[The Sentinel System Principles and Policies](https://www.sentinelinitiative.org/principles-and-policies-privacy)**
- **inputfiles**: is the subfolder containing all input files and lookup tables needed to execute a request. Input files contain information on what tables should be output and the type of analyses conducted on the variables in each table.
- **msoc**: is where aggregated program results are saved
- **sasprograms**: contains the file(s) to be executed

### Requirements

- UNIX/Linux or Windows environment
- SAS version 9.4 or higher (as of OY 2021)
- SCDM formatted data (Medicare Claims Synthetic Public Use Files are available in the Sentinel Common Data Model Format **[here](https://www.sentinelinitiative.org/sentinel/surveillance-tools/software-toolkits/Medicare-SynPUFs-in-SCDM)**)

### Getting Started

- Review the QA Package Documentation (available **[here](https://dev.sentinelsystem.org/projects/SENTINEL/repos/sentinel-quality-assurance-documentation/browse?at=refs%2Ftags%2Fv7.0.0)**)
- Open `sasprograms\00.0_scdm_mil_data_qa_review_master_file.sas`
- Go to section 1 of program header and specify the following parameters:
  - Define path(s)s to:
    - SCDM MIL table under review 
	- Source files utilized to create SCDM MIL table 
	- Common Components (CC) request associated with the ETL under review 
	- This QA package, not including the request ID
	- Location of previously approved Phase A SCDM tables 
  - The Extract Transform Load (ETL) number for this request (prior ETL + 1)
  - The SCDM version of the ETL under review
  - The name of the SCDM datasets 
  
- Go to section 2 of program header and specify the following parameters
  - Individual request ID tokens
  - Extract Transform Load (ETL) number for this request (prior ETL + 1)
  
- Close and run `00.0_scdm_mil_data_qa_review_master_file.sas` in batch mode

### Output

The program package generates a series of aggregated output tables that help determine whether the data conform to SCDM specifications, maintain integrity across variables and across tables, and trend as expected over time. Details on the output structure can be found in the documentation; details on how to interpret the output can be found in the data dictionary.

### Additional Information

The Sentinel Operations Center has limited capacity to support use of our tools. However, we welcome feedback, comments, and suggestions pertaining to our documentation or tools. Email us **[here](mailto:info@sentinelsystem.org?subject=Git)**.

<br>
<br>
________________________________________________________________

<br>
<span id="navigationbar.csv">

|<b>Navigate to: |
|------|
|[SASPrograms](https://dev.sentinelsystem.org/projects/QA/repos/qa_mil_package/browse/sasprograms?at=refs%2Fheads%2FDEV-16706)|
|[MSOC](https://dev.sentinelsystem.org/projects/QA/repos/qa_mil_package/browse/msoc?at=refs%2Fheads%2FDEV-16706)|
|[DPLOCAL](https://dev.sentinelsystem.org/projects/QA/repos/qa_mil_package/browse/dplocal?at=refs%2Fheads%2FDEV-16706)|
|[InputFiles](https://dev.sentinelsystem.org/projects/QA/repos/qa_mil_package/browse/inputfiles?at=refs%2Fheads%2FDEV-16706)|
|[Docs](https://dev.sentinelsystem.org/projects/QA/repos/qa_mil_package/browse/docs?at=refs%2Fheads%2FDEV-16706)|
|[Home Page](https://dev.sentinelsystem.org/projects/QA/repos/qa_mil_package/browse/readme.md?at=DEV-16706)|
</span>
