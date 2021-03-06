##
## allhic pipeline
##          snakemake pipeline for executing ALLHiC diploid
## Examples:
##          snakemake -s allhic_diploid_pipeline.smk \
##              --configfile config_allhic_diploid_pipeline.yaml \
##              -j 12 \
##              --cluster "qsub -l select=1:ncpus={threads} -q workq -j oe"
##---------------------------------------------------------------------------
## 
## genome:
##         tig.fasta
##
## sample:
##         - AD
##
## ncpus:
##         20
##
## enzyme:
##         HINDIII
##
## cluster_N:
##         1
## tag:
##         - R1
##         - R2

import os
import os.path as op
import glob
import sys


__version__ = "v1.0"


enzyme_repo = {"MBOI":"GATC","HINDIII":"AAGCTT"}


FA = config['genome']
SAMPLE = config['sample'][0]
enzyme = config['enzyme'].upper()
enzyme_base = enzyme_repo[enzyme]
N = config["cluster_N"]
ncpus = config['ncpus']
fq_suffix = config['fq_suffix']
tag1 = config['tag'][0]

SAMPLES = list(map(op.basename, glob.glob("data/*{}.{}".format(tag1, fq_suffix))))
SAMPLES = list(map(lambda x: x.replace("."+fq_suffix, "").replace("_"+tag1, ""), SAMPLES))

rule all:
    input:
        # lambda wildcards: "process/{}.bwa_aln.REduced.paired_only.bam".format(config['sample'][0])
        "allhic_result/groups.asm.fasta"

rule fa_index:
    input:
        FA
    output:
        "{input}.bwt",
        "{input}.fai"
    log:
        "logs/{input}.log"
    shell:
        "samtools faidx {input} & bwa index -a bwtsw {input} 2>{log}"



rule bwa_aln:
    input:
        fabwt = lambda wildcards: "{}.bwt".format(FA),
        fq = expand("data/{{sample}}_{tag}.{fq_suffix}", tag=config['tag'], fq_suffix=[fq_suffix])
    output:
        "bwa_result/{sample}_{tag}.sai"
    log:
        "logs/{sample}_{tag}.log"
    threads: ncpus
    shell:
        "bwa aln -t {threads} {FA} {input.fq} > {output} 2>{log}"


rule bwa_sampe:
    input:
        fq = expand("data/{{sample}}_{tag}.fastq.gz", tag=config["tag"]),
        sai = expand("bwa_result/{{sample}}_{tag}.sai", tag=config["tag"]),
        
    output:
        "bwa_result/{sample}.bwa_sampe.bam"
    log:
        "logs/{sample}.bwa_sampe.log"
    shell:
        "bwa sampe {FA} {input.sai} {input.fq} | samtools view -bS > {output}"

rule merge_bam:
    input:
        bam = expand("bwa_result/{sample}.bwa_sampe.bam", sample=SAMPLES)
    output:
        expand("bwa_result/{name}.bwa_merged.bam", name=config['sample'])
    log:
        expand("logs/{name}.bwa_merged.log", name=config['sample'])
    threads: ncpus
    shell:
        "samtools merge -@ {threads} {output} {input.bam} 1>{log} 2>&1"



rule preprocess_bam:
    input:
        bam = "bwa_result/{sample}.bwa_merged.bam"
    output:
        "bwa_result/{sample}.bwa_merged.REduced.paired_only.bam"
    log:
        "logs/{sample}_preprocess.log"
    params:
       enzyme = config["enzyme"]
    shell:
        "PreprocessSAMs.pl {input} {FA} {params.enzyme} 2>&1 1>{log}"


rule filter_bam:
    input:
        "bwa_result/{sample}.bwa_merged.REduced.paired_only.bam"
    output:
        "allhic_result/{sample}.clean.sam"
    log:
        "logs/{sample}_filter.log"
    shell:
        "filterBAM_forHiC.pl {input} {output} 1>{log} 2>&1"


rule sam2bam:
    input:
        "allhic_result/{sample}.clean.sam"
    output:
        "allhic_result/{sample}.clean.bam"
    log:

    threads: ncpus
    shell:
        "samtools view -@ {threads} -bt {FA}.fai {input} > {output}"

rule partition:
    input:
        lambda wildcards: "allhic_result/{}.clean.bam".format(SAMPLE)
    output:
        expand("allhic_result/{sample}.clean.counts_{enzyme_base}.{N}g{n}.txt",
            sample=(SAMPLE,), enzyme_base=(enzyme_base,), N=(N,), n=range(1,N+1))
    log:
        "logs/{}_partition.log".format(SAMPLE)
    shell:
        "ALLHiC_partition -b {input} -r {FA} -e {enzyme_base} -k {N} 1>{log} 2>&1"

rule extract:
    input:
        bam = "allhic_result/{sample}.clean.bam",
        #txt = "allhic_result/{sample}.clusters.txt"
        txt = expand("allhic_result/{sample}.clean.counts_{enzyme_base}.{N}g{n}.txt",
            sample=(SAMPLE,), enzyme_base=(enzyme_base,), N=(N,), n=range(1,N+1))

    output:
        "allhic_result/{sample}.clean.clm",
    log:
        "logs/{sample}_extract.log"
    shell:
        "allhic extract {input.bam} {FA} --RE {enzyme_base} 2>{log}"

rule optimize:
    input:
        clm = "allhic_result/{sample}.clean.clm",
        txt = "allhic_result/{sample}.clean.counts_{enzyme_base}.{N}g{n}.txt"
    output:
        "allhic_result/{sample}.clean.counts_{enzyme_base}.{N}g{n}.tour"
    log:
        "logs/{sample}_{enzyme_base}.{N}g{n}_optimize.log"
    shell:
        "allhic optimize {input.txt} {input.clm} 2>{log}"

rule build:
    input:
        expand("allhic_result/{sample}.clean.counts_{enzyme_base}.{N}g{n}.tour",
            sample=(SAMPLE,), enzyme_base=(enzyme_base,), N=(N,), n=range(1,N+1))
    output:
        "allhic_result/groups.asm.fasta"
    log:
        "logs/allhic_build.log"
    shell:
        "cd allhic_result/ && ALLHiC_build ../{FA} 2 > ../{log}"
