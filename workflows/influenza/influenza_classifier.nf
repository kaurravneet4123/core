#!/opt/software/conda2/envs/NextFlow/bin/nextflow

// Copyright (C) 2019 NIBSC/MHRA
// Author: Francesco Lescai francesco.lescai@nibsc.org

// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

params.help = null

log.info ""
log.info "-------------------------------------------------------------------------"
log.info "  influenza_classifier: Classify composition of influenza HGR samples    "
log.info "-------------------------------------------------------------------------"
log.info "Copyright (C) NIBSC/MHRA"
log.info "This program comes with ABSOLUTELY NO WARRANTY; for details see LICENSE"
log.info "This is free software, and you are welcome to redistribute it"
log.info "under certain conditions; see LICENSE for details."
log.info "-------------------------------------------------------------------------"
log.info ""
log.info """\

        PARAMETERS RECEIVED:
        --------------------------------
        READS FOLDER: ${params.reads}
        DATABASE FASTA FILE: ${params.origin}
        BLAST DATABASE NAME: ${params.db}
        DESTINATION FOLDER: ${params.output_dir}
        """
        .stripIndent()

if (params.help)
{
    log.info "---------------------------------------------------------------------"
    log.info "  USAGE                                                 "
    log.info "---------------------------------------------------------------------"
    log.info ""
    log.info "nextflow run nibsbioinformatics/core/workflows/influenza/influenza_classifier.nf [OPTIONS]"
    log.info ""
    log.info "Mandatory arguments:"
    log.info "--reads                         READS FOLDER              Folder with sample reads"
    log.info "--origin                        PARENTS FASTA FILE        Fasta file with sequences of viral parents"
    log.ingo "--db                            DB NAME                   Name of Blast DB to be created"
    log.info "--output_dir                    OUTPUT FOLDER             Output for classification results"
    exit 1
}

// initialisation of parameters before passed by command line or config file

params.reads          = null
params.output_dir     = "."
params.origin         = null
params.db             = null

Channel
    .fromFilePairs("$params.reads/*_{R1,R2}*.fastq.gz")
    .ifEmpty { error "Cannot find any reads matching ${params.reads}"}
    .set { samples_ch }

database_fasta_ch = Channel.fromPath(params.origin)
dbName = params.db

process createBlastDatabase {

  tag "${dbFasta.baseName}"
  cpus 1
  queue 'WORK'
  time '1h'
  memory '12 GB'

  // note:
  // the line below presumes you have cloned our github repository
  // under your home directory, in a folder called CODE
  // this way, the pipeline remains portable on any platform by any
  // user, as long as you have cloned our main repository in this way

  // since now (reasons unknown) I get an error in the activate line
  // referring to conda, I try to link my own existing env

  //conda "$HOME/.conda/envs/influenza"
  publishDir "/usr/share/sequencing/references/influenzaDBs", mode: 'copy'

  input:
  file dbFasta from database_fasta_ch

  output:
  file "${dbName}.*" into blast_database_ch

  script:
  """
  /usr/share/sequencing/tools/ncbi-blast-2.9.0+-src/c++/ReleaseMT/bin/makeblastdb -in $dbFasta -out ${dbName} -parse_seqids -dbtype nucl
  """


}


process blastSearch {

  tag "processing sample $sampleId"
  cpus 12
  queue 'WORK'
  time '1h'
  memory '6 GB'

  // note:
  // the line below presumes you have cloned our github repository
  // under your home directory, in a folder called CODE
  // this way, the pipeline remains portable on any platform by any
  // user, as long as you have cloned our main repository in this way

  // since now (reasons unknown) I get an error in the activate line
  // referring to conda, I try to link my own existing env

  //conda "$HOME/.conda/envs/influenza"
  publishDir "${params.output_dir}/${sampleId}", mode: 'copy'

  input:
  set sampleId, file(reads) from samples_ch
  file dbBlastFiles from blast_database_ch.collect()

  output:
  file("${sampleId}.fa") into sequences_ch
  file("${sampleId}_blast_results.txt") into blast_results_ch

  script:
  """
  zcat $reads | /home/AD/flescai/.conda/envs/influenza/bin/seqkit fq2fa -o ${sampleId}.fa

  /usr/share/sequencing/tools/ncbi-blast-2.9.0+-src/c++/ReleaseMT/bin/blastn \
  -query ${sampleId}.fa \
  -db ${dbName} \
  -max_target_seqs 1 \
  -num_threads ${task.cpus} \
  -outfmt '6 qseqid sseqid sgi qstart qend sstart send pident mismatch nident evalue' \
  | sort -k 1,1 -k11,11g > "${sampleId}_blast_results.txt"

  """

}


process Reporting {
  tag "markdown the report"
  cpus 1
  queue 'WORK'
  time '1h'
  memory '3 GB'

  // replaced module load R/3.6.0
  // in script statement with the following
  // conda environment - provided it works
  // conda "$HOME/CODE/core/workflows/influenza/influenza_conda.yml"
  // this is still not working even on latest github compiled code

  publishDir "${params.output_dir}", mode: 'copy'

  input:
  file blast_results from blast_results_ch.collect()

  output:
  file("${dbName}_report.html") into final_report_ch

  script:
  """
  conda activate /home/AD/flescai/.conda/envs/influenza
  
  Rscript $HOME/CODE/core/workflows/influenza/report_run_influenza-report.R \
  $HOME/CODE/core/workflows/influenza/report_influenza_main.Rmd \
  "${dbName}_report.html" \
  ${blast_results}
  """



}


workflow.onComplete {
	log.info ( workflow.success ? "\nDone! Workflow completed\n" : "Oops .. something went wrong\n" )
}
