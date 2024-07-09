# The Data Preprocessing workflow

## Summary

This workflow is a replicate of the [QA protocol](https://jgi.doe.gov/data-and-tools/software-tools/bbtools/bb-tools-user-guide/data-preprocessing/) implemented at JGI for Illumina reads and use the program “rqcfilter2” from BBTools(38:96) which implements them as a pipeline. 

## Required Database

* [RQCFilterData Database](https://portal.nersc.gov/cfs/m3408/db/RQCFilterData.tgz): It is a 106G tar file includes reference datasets of artifacts, adapters, contaminants, phiX genome, host genomes.  

* Prepare the Database

```bash
	mkdir -p refdata
	wget https://portal.nersc.gov/cfs/m3408/db/RQCFilterData.tgz
	tar xvzf RQCFilterData.tgz -C refdata
	rm RQCFilterData.tgz
```

## Running Workflow in Cromwell

Description of the files:
 - `.wdl` file: the WDL file for workflow definition
 - `.json` file: the example input for the workflow
 - `.conf` file: the conf file for running Cromwell.
 - `.sh` file: the shell script for running the example workflow

## The Docker image and Dockerfile can be found here

[microbiomedata/bbtools:38.92](https://hub.docker.com/r/microbiomedata/bbtools)

## Input files

1. fastq (illumina paired-end interleaved fastq), 
3. project name 

```
{
     "metaTReadsQC.input_files": ["/global/cfs/cdirs/m3408/ficus/example/12889.1.295318.GTGCTTAC-GTAAGCAC.fastq.gz"],
    "metaTReadsQC.proj":"nmdc:xxxxxxx"
}
```

## Output files

The output will have one directory named by prefix of the fastq input file and a bunch of output files, including statistical numbers, status log and a shell script to reproduce the steps etc. 

The main QC fastq output is named by prefix.fastq.gz. 

```
|-- nmdc_xxxxxxx_filtered.fastq.gz 
|-- nmdc_xxxxxxx_filterStats.txt
|-- nmdc_xxxxxxx_filterStats2.txt
|-- nmdc_xxxxxxx_qa_stats.json  
|-- filtered/adaptersDetected.fa
|-- filtered/reproduce.sh
|-- filtered/spikein.fq.gz
|-- filtered/status.log
|-- ...
```
