# Interleaved fastq QC workflow
version 1.0
workflow nmdc_rqcfilter {
    input{
    String  container="bfoster1/img-omics:0.1.9"
    String  bbtools_container="microbiomedata/bbtools:38.96"
    String  workflow_container="microbiomedata/workflowmeta:1.1.1"
    String  proj
    String  prefix=sub(proj, ":", "_")
    String  input_fastq1
    String  input_fastq2
    String  database="/refdata/"
    String  rqc_mem = "115G"
    Int     rqc_thr = 16
    String  interleave_mem = "10G"
    Boolean gcloud_env=false
    }

    call stage {
        input: container=bbtools_container,
            memory=interleave_mem,
            input_fastq1=input_fastq1,
            input_fastq2=input_fastq2
    }
    # Estimate RQC runtime at an hour per compress GB
   call rqcfilter as qc {
        input:
            input_fastq = stage.interleaved_reads,
            database = database,
            gcloud_env = gcloud_env,
            memory = rqc_mem,
            threads = rqc_thr,
            container = bbtools_container
    }
    call make_info_file {
        input: info_file = qc.info_file,
            container = bbtools_container,
            prefix = prefix
    }

    call finish_rqc {
        input: container = workflow_container,
            prefix = prefix,
            filtered = qc.filtered,
            filtered_stats = qc.stat,
            filtered_stats2 = qc.stat2
    }
    output {
        File filtered_final = finish_rqc.filtered_final
        File filtered_stats_final = finish_rqc.filtered_stats_final
        File filtered_stats2_final = finish_rqc.filtered_stats2_final
        File rqc_info = make_info_file.rqc_info
    }
}



task stage {
   input{
    String container
    String memory
    String target_reads_1="raw_reads_1.fastq.gz"
    String target_reads_2="raw_reads_2.fastq.gz"
    String output_interleaved="raw_interleaved.fastq.gz"
    String input_fastq1
    String input_fastq2
   }

   command <<<
       set -oeu pipefail
       if [ $( echo ~{input_fastq1} | egrep -c "https*:") -gt 0 ] ; then
           wget ~{input_fastq1} -O ~{target_reads_1}
           wget ~{input_fastq2} -O ~{target_reads_2}
       else
           ln ~{input_fastq1} ~{target_reads_1} || ln -s ~{input_fastq1} ~{target_reads_1}
           ln ~{input_fastq2} ~{target_reads_2} || ln -s ~{input_fastq2} ~{target_reads_2}
       fi

       reformat.sh -Xmx~{memory} in1=~{target_reads_1} in2=~{target_reads_2} out=~{output_interleaved}
       # Capture the start time
       date --iso-8601=seconds > start.txt

       # Validate that the read1 and read2 files are sorted correct to interleave
       reformat.sh -Xmx~{memory} verifypaired=t in=~{output_interleaved}

   >>>

   output{
      File interleaved_reads = "~{output_interleaved}"
      String start = read_string("start.txt")
   }
   runtime {
     memory: "1 GiB"
     cpu:  2
     maxRetries: 1
     docker: container
   }
}


task rqcfilter{
    input{
        File? input_fastq
        String container
        String database
        String rqcfilterdata = database + "/RQCFilterData"
        Boolean gcloud_env=false
        String gcloud_db_path = "/cromwell_root/workflows_refdata/refdata/RQCFilterData"
        Array[File]? gcloud_db= if (gcloud_env) then [database] else []
        String? memory
        Int? threads
        String filename_outlog="stdout.log"
        String filename_errlog="stderr.log"
        String filename_stat="filtered/filterStats.txt"
        String filename_stat2="filtered/filterStats2.txt"
        String filename_stat_json="filtered/filterStats.json"
        String filename_reproduce="filtered/reproduce.sh"
    }

     command<<<
        export TIME="time result\ncmd:%C\nreal %es\nuser %Us \nsys  %Ss \nmemory:%MKB \ncpu %P"
        set -eou pipefail
        if ~{gcloud_env}; then
            dbdir=`ls -d /mnt/*/*/RQCFilterData`
            if [ ! -z $dbdir ]; then
                ln $dbdir ~{gcloud_db_path} || ln -s $dbdir ~{gcloud_db_path}
            else
                echo "Cannot find gcloud refdb" 1>&2
            fi
        fi
        
        rqcfilter2.sh \
            barcodefilter=f \
            chastityfilter=f \
            clumpify=t \
            extend=f \
            jni=t \
            usejni=f \
            khist=t \
            log=status.log \
            maq=10 \
            maxns=1 \
            minlen=51 \
            mlf=0.33 \
            mtst=t \
            outribo=ribo.fq.gz \
            path=filtered \
            phix=t \
            pigz=t \
            qtrim=r \
            removecat=t \
            removedog=t \
            removehuman=t \
            removemicrobes=t \
            removemouse=t \
            removeribo=t \
            rna=t \
            rqcfilterdata=~{if gcloud_env then gcloud_db_path else rqcfilterdata} \
            sketch=t \
            stats=~{filename_stat} \
            trimfragadapter=t \
            trimpolyg=5 \
            trimq=0 \
            unpigz=t \
            ~{if (defined(memory)) then "-Xmx" + memory else "-Xmx101077m" } \
            ~{if (defined(threads)) then "threads=" + threads else "threads=auto" } \
            in=~{input_fastq} \
            > >(tee -a  ~{filename_outlog}) \
            2> >(tee -a ~{filename_errlog}  >&2)

            # moved input file to end for processing of resubmit.sh line, the rest is kinda alphabetized 

        python <<CODE
        import json
        f = open("~{filename_stat}",'r')
        d = dict()
        for line in f:
            if not line.rstrip():continue
            key,value=line.rstrip().split('=')
            d[key]=float(value) if 'Ratio' in key else int(value)

        with open("~{filename_stat_json}", 'w') as outfile:
            json.dump(d, outfile)
        CODE
        >>>

     output {
            File stdout = filename_outlog
            File stderr = filename_errlog
            File stat = filename_stat
            File stat2 = filename_stat2
            File info_file = filename_reproduce
            File filtered = "filtered/raw.anqrpht.fastq.gz"
            File json_out = filename_stat_json
     }
     runtime {
        docker: container
        memory: "140 GiB"
        cpu:  16
    }
}

task make_info_file {
    input{
        File   info_file
        String prefix
        String container
    }

    command<<<
        set -oeu pipefail
        sed -n 2,5p ~{info_file} 2>&1 | \
          sed -e 's/^#//; s/in=[^ ]*/in=filename.fastq.gz/; s/#//g; s/BBTools/BBTools(1)/g;' > \
         ~{prefix}_readsQC.info
        echo -e "\n(1) B. Bushnell: BBTools software package, http://bbtools.jgi.doe.gov/" >> \
         ~{prefix}_readsQC.info
         # perl -ne 's:in=/.*/(.*) :in=$1:; s/#//; s/BBTools/BBTools(1)/; print;' > \ # for container microbiomedata/workflowmeta:1.1.1
    >>>

    output {
        File rqc_info = "~{prefix}_readsQC.info"
    }
    runtime {
        memory: "1 GiB"
        cpu:  1
        maxRetries: 1
        docker: container
    }
}

task finish_rqc {
    input {
        File   filtered_stats
        File   filtered_stats2
        File   filtered
        String container
        String prefix
    }

    command<<<

        set -oeu pipefail
        end=`date --iso-8601=seconds`
        # Generate QA objects
        ln ~{filtered} ~{prefix}_filtered.fastq.gz || ln -s ~{filtered} ~{prefix}_filtered.fastq.gz
        ln ~{filtered_stats} ~{prefix}_filterStats.txt || ln -s ~{filtered_stats} ~{prefix}_filterStats.txt
        ln ~{filtered_stats2} ~{prefix}_filterStats2.txt || ln -s ~{filtered_stats2} ~{prefix}_filterStats2.txt

       # Generate stats but rename some fields untilt the script is fixed.
       /scripts/rqcstats.py ~{filtered_stats} > stats.json
       ln stats.json ~{prefix}_qa_stats.json || ln -s stats.json ~{prefix}_qa_stats.json

    >>>
    output {
        File filtered_final = "~{prefix}_filtered.fastq.gz"
        File filtered_stats_final = "~{prefix}_filterStats.txt"
        File filtered_stats2_final = "~{prefix}_filterStats2.txt"
    }

    runtime {
        docker: container
        memory: "1 GiB"
        cpu:  1
    }
}