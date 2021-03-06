#!/bin/bash

# AUTHOR / DATE
#   Ludo Pagie; March 22, 2016; iPCR-map-BC_160322.bash

# INTRO / BACKGROUND
#   bash script (awk, bowtie2, samtools and cutadapt) to process raw fastq
#   files containing data from iPCR samples. The barcodes and gDNA are
#   extracted from the reads and the gDNA is aligned to the reference genome. 
#   Barcodes with length != 20, or which contain N's are discarded, as are
#   reads with a MAPQ less then 20. The aligned and filtered paired reads are
#   written to stdout in bedpelike format including the barcode and sorted
#   (alphabetically) on barcode.
#
# USAGE / INPUT / ARGUMENTS / OUTPUT
# USAGE:
#   required:
#   - fastq files for input are given as final arguments 
####   -f: directory containing fastq file(s)
#   -o: output directory
#   optional:
#   -f: forward adapter sequence
#   -r: reverse adapter sequence
#   -d: digestion site
#   -l: log-filename [stdout]
#   -n: number of cores used in parallel processes (10)
#   -i: (optional) index file for bowtie2
# INPUT:
#   iPCR fastq files
# OUTPUT:
#   tabular txt file in bedpe-like format

# VERSIONS:
#   -160322: initial version, VERSION set to 0.0.1

# TODO
#   - parameterize filter criteria (min MAPQ score, BC length, etc)

SCRIPTNAME=iPCR-map-BC_160322.bash
VERSION=0.0.1 # YYMMDD

# EXTERNAL SOFTWARE
GAWK=/usr/bin/gawk
BOWTIE2=bowtie2
CUTADAPT=$HOME/vanSteensel/src/cutadapt-stable_1.2.1/bin/cutadapt
CUTADAPT=cutadapt
CUTADAPT=$HOME/python_virt_env_cutadapt/bin/cutadapt
SAMTOOLS=$HOME/vanSteensel/bin/samtools

# GLOBAL VARIABLES
NCORES=10
MIN_READ_LENGTH=5
MAX_INSERT_LENGTH=1000
export BOWTIE2_INDEXES=$HOME/data/bowtie2-indexes/
BOWTIE2_REFSEQ="hg19_ch1-22_XYM"
ADPTR_FORW_SEQ="CCTAGCTAACTATAACGGTCCTAAGGTAGCGAACCAGTGAT"
ADPTR_REV_SEQ="CCAGTCGT"
RESTRICT_SITE="CATG"
CLEAN=true;

# PARSE OPTIONS
OPTIND=1         # Reset in case getopts has been used previously in the shell.
USAGE=
usage() {
  echo >&2 "usage: ${SCRIPTNAME} -ofrdlnc"
  echo >&2 "OPTIONS:"
  echo >&2 "  -o: directory for generated count-table files  [required]"
  echo >&2 "  -f: forward read adapter sequence [CCTAGCTAACTATAACGGTCCTAAGGTAGCGAACCAGTGAT]"
  echo >&2 "  -r: reverse read adapter sequence [CCAGTCGT]"
  echo >&2 "  -d: digestion site used for minimzing iPCR circle [CATG]"
  echo >&2 "  -l: set name of logfile [default: stdout]"
  echo >&2 "  -n: number of cores used where possible [default: 10]"
  echo >&2 "  -c: clean up intermediate files [true]"
  echo >&2 "  -i: index file for bowtie2 [hg19_ch1-22_XYM]"
  echo >&2 ""
  exit 1;
}

while getopts "h?f:o:r:d:l:n:i:c" opt; do
  case $opt in
    l)
      LOG=$OPTARG;
      ;;
    n)
      NCORES=$OPTARG;
      ;;
    f)
      ADPTR_FORW_SEQ=$OPTARG;
      ;;
    r)
      ADPTR_REV_SEQ=$OPTARG;
      ;;
    d)
      RESTRICT_SITE=$OPTARG;
      ;;
    o)
      OUTDIR=$OPTARG;
      ;;
    c)
      CLEAN=false;
      ;;
    i)
      BOWTIE2_REFSEQ=$OPTARG;
        # test whether supplied index name contains a path
	echo ${BOWTIE2_REFSEQ}
        IPATH=`dirname ${BOWTIE2_REFSEQ}`;
        echo "Bowtie index path = $IPATH";
        if [[ "$IPATH" != "." ]]; then
          export BOWTIE2_INDEXES=$IPATH;
        fi;
      ;;
    \?)
      echo "option not recognized: "$opt
      usage
      ;;
  esac
done
shift $(( OPTIND - 1 ))

# retrieve input fastq files from command line
declare -a INPUTFILES=( "$@" );
# make pathname of inputfiles absolute
for (( i=0; i<${#INPUTFILES[@]}; i++ )); do
  D=`dirname "${INPUTFILES[$i]}"`
  B=`basename "${INPUTFILES[$i]}"`
  DD="`cd $D 2>/dev/null && pwd || echo $D`"
  INPUTFILES[$i]="${DD}/$B"
done
# exit if no filenames are given; print usage
if [ ${#@} -eq 0 ]; then
  echo -e >&2 "\nERROR: no fastq input files, aborting\n"
  usage
fi

# check all required options are set
# if [ -z ${FASTQDIR+x} ]; then echo "option -f not set (directory containing fastq files)"; usage; exit 1; fi
if [ -z ${OUTDIR+x} ]; then echo "option -o not set (directory for output files)"; usage; exit 1; fi
# if [ -z ${ADPTR_SEQ+x} ]; then echo "option -a not set (adapter sequence for parsing reads)"; usage; exit 1; fi

# define function log which writes (status lines) to stderr and (if logfile is given) to LOG
if [ ! -z ${LOG+x} ]; then 
  exec 1>>${LOG}
fi

# print values of variables and CLI args for log
# print header for log
######################
LINE="running "${SCRIPTNAME}" (version: "$VERSION")"
SEPARATOR=$(head -c ${#LINE} </dev/zero | tr '\0' '=')
echo $SEPARATOR; echo $LINE; echo $SEPARATOR
echo "script context"
echo "=============="
starttime=$(date +%c)
echo "starting date/time = "${starttime}
echo "User set variables:"
echo "==================="
# echo "directory containing input fastq files=${FASTQDIR}"
echo "directory for output files=${OUTDIR}"
echo "adapter sequence=${ADPTR_SEQ}"
echo "LOG=${LOG}"
echo "NCORES=${NCORES}"
echo "MIN_READ_LENGTH=${MIN_READ_LENGTH}"
echo "MAX_INSERT_LENGTH=${MAX_INSERT_LENGTH}"
echo "BOWTIE2_INDEXES=${BOWTIE2_INDEXES}"
echo "BOWTIE2_REFSEQ=${BOWTIE2_REFSEQ}"
echo "ADPTR_FORW_SEQ=${ADPTR_FORW_SEQ}"
echo "ADPTR_REV_SEQ=${ADPTR_REV_SEQ}"
echo "RESTRICT_SITE=${RESTRICT_SITE}"
echo "CLEAN=${CLEAN}"
echo ""
echo "fastq files for input:"
echo "================================="
for f in $INPUTFILES; do echo $f; done
echo ""
# print some software version info
echo "Used software:"
echo "=============="
echo "unix/host"; uname -a; echo "---------------";
echo "bash:"; bash --version 2>&1 head -3; echo "---------------";
echo "gawk:"; echo "executable used: ${GAWK}"; ${GAWK} --version; echo "---------------";
echo "cutadapt:"; echo "executable used: ${CUTADAPT}"; ${CUTADAPT} --version; echo "---------------";
echo "bowtie2:"; echo "executable used: ${BOWTIE2}"; ${BOWTIE2} --version; echo "---------------";
echo "samtools:"; echo "executable used: ${SAMTOOLS}"; ${SAMTOOLS} 2>&1 | head -3; echo "---------------";
echo "python:"; echo "executable used: python"; ((python --version) 2>&1);
echo "=============="
echo ""

# check required subdirectories exist
if [ ! -d ${OUTDIR} ]; then mkdir -p ${OUTDIR}; echo "making directory \"${OUTDIR}\" for output"; echo ""; fi

# the reads come in paired end format; we need a name for each sample
# samplenames will be stored in $BASEFILES
# fastq file names with forward/reverse reads will be in $FORWFILES/$REVFILES respectively
BASEFILES=`for i in "${INPUTFILES[@]}"; do echo $( basename $i ) | \
  ${GAWK} ' { STR=$1; sub(/_[12].clean.fq.gz/,"",STR); print STR } '; done | uniq`;
# JuAsuRE40_1_DO16085631-1_HW3VKCCXX_L5_1.clean.fq.gz
  # ${GAWK} ' { STR=$1; sub(/_R?[12](_001)?.f.*q.gz$/,"",STR); print STR } '; done | uniq`;
declare -A FORWFILES=();
declare -A REVFILES=();
  echo "ls :"
  ls ${INPUTFILES[@]} | grep ".*.gz"
for BASE in $BASEFILES; do 
  FORWFILES[$BASE]=`ls ${INPUTFILES[@]} | grep $BASE".*_1.clean.fq.gz" `
  REVFILES[$BASE]=`ls ${INPUTFILES[@]} | grep $BASE".*_2.clean.fq.gz" `
  # FORWFILES[$BASE]=`ls ${INPUTFILES[@]} | grep $BASE"_R\?1\(_001\)\?.f.*q.gz$" `
  # REVFILES[$BASE]=`ls ${INPUTFILES[@]} | grep $BASE"_R\?2\(_001\)\?.f.*q.gz$" `     
  #ls ${INPUTFILES[@]}
  echo "base = "${BASE}
  echo "forw = "${FORWFILES[$BASE]}
  echo "rev = "${REVFILES[$BASE]}
done

# setwd processing directory
cd ${OUTDIR}

echo "finished prepping for processing"
echo "================================"

echo "starting to loop over (paired end) fastq files" 
echo "=============================================="

function split_fastq {
  local FASTQ=$1
  # split fastq
  # first we need to figure out the number of lines per split file we need
  local nline=`zcat ${FASTQ} | wc -l`
  # divide by 4 to get number of reads in the fastq file
  local nread=$((nline/4))
  # divide by NCORES to get number of reads per split datafile
  nread=$((nread/NCORES))
  # division is integer based and so we possibly lose some digits in previous statement
  # we correct by adding 1 to nread to ensure the sum of (NCORES * nread) >= total number of reads
  nread=$((nread+1))
  # the number of lines in the split fastq files is nread*4
  nline=$((nread*4))

  zcat ${FASTQ}  | \
#    head -10000 | \
    ${GAWK} -v "NL=${nline}" '
      BEGIN { CNT=1 } 
      NR%NL == 1 { 
        file = sprintf("split_%04d.fastq", CNT); 
        CNT++ 
      } 
      { print > file }'
}

function trim_reads {
  local FASTQ=$1 # fastq filename
  local DIR=$2   # forward or reverse read; values can be 'forw'/'rev'

  echo "trim_reads called with args: $1, $2."

  # set adapter sequence depending on direction $DIR
  case ${DIR} in
    "forw")
      export ADPTR=${ADPTR_FORW_SEQ}
      ;;
    "rev")
      export ADPTR=${ADPTR_REV_SEQ}
      ;;
    *)
      >&2 echo "function trim_reads called with wrong direction argument (${DIR}), aborting"
      exit 1 
      ;;
  esac
  
  echo "trimming reads with adptr = ${ADPTR}, direction = ${DIR}"

  # the fastq file is split using awk (which turns out much faster than unix split)
  echo "splitting fastq file for parallel processing"
  split_fastq ${FASTQ}
  echo "finished splitting fastq file for parallel processing"
  echo ""
  
  # parallel trimming using gnu parallel:
  export CUTADAPT
  export RESTRICT_SITE
  export ADPTR
  export DIR

#  CMD="${CUTADAPT} -g ${ADPTR} -o {.}_${DIR}_trimmed.fastq --info-file={.}_${DIR}_trimmed.info -O4 {} > {.}_${DIR}_trimmed.stats;\
#    ${CUTADAPT} -a ${RESTRICT_SITE} -o {.}_${DIR}_trimmed_${RESTRICT_SITE}.fastq -O4 {.}_${DIR}_trimmed.fastq > {.}_${DIR}_trimmed_${RESTRICT_SITE}.stats"
  CMD="${CUTADAPT} -g ${ADPTR} -o {.}_${DIR}_trimmed.fastq --info-file={.}_${DIR}_trimmed.info -O4 {} > {.}_${DIR}_trimmed.stats;"
  echo "cutadapt command = ${CMD}"
  parallel -j ${NCORES} ${CMD} :::  split*fastq
  
  echo "Merging the split result files"
  # merge the fastq and stats files, generate the output files in the parent directory:
  
  cat *_${DIR}_trimmed.fastq > ../${BASE}_${DIR}_trimmed.fastq
  cat *_${DIR}_trimmed.info > ../${BASE}_${DIR}_trimmed.info
  cat *_${DIR}_trimmed.stats > ../${BASE}_${DIR}_trimmed.stats
#  cat *_${DIR}_trimmed_${RESTRICT_SITE}.fastq > ../${BASE}_${DIR}_trimmed_${RESTRICT_SITE}.fastq
#  cat *_${DIR}_trimmed_${RESTRICT_SITE}.stats > ../${BASE}_${DIR}_trimmed_${RESTRICT_SITE}.stats
  pushd ../
  ln -s ${BASE}_${DIR}_trimmed.fastq ${BASE}_${DIR}_trimmed_${RESTRICT_SITE}.fastq
  ln -s ${BASE}_${DIR}_trimmed.stats ${BASE}_${DIR}_trimmed_${RESTRICT_SITE}.stats
  popd
  echo "Finished merging the split result files"
}

function filter_read_length {
  local BASE=$1

  # remove all reads which are $MIN_READ_LENGTH basepairs or shorter
  ##################################################################
  local FORW=${BASE}_forw_trimmed_${RESTRICT_SITE}.fastq
  local REV=${BASE}_rev_trimmed_${RESTRICT_SITE}.fastq
  local FORW_FLTR=${BASE}_forw_trimmed_${RESTRICT_SITE}.fastq.fltr
  local REV_FLTR=${BASE}_rev_trimmed_${RESTRICT_SITE}.fastq.fltr
  local INFO_FORW=${BASE}_forw_trimmed.info
  local STATS=${BASE}.stats

echo "in filter_length:"
echo "FORW = $FORW"
echo "REV = $REV"
echo "FORW_FLTR = $FORW_FLTR"
echo "REV_FLTR = $REV_FLTR"
echo "INF_FW = $INFO_FORW"
echo "STATS = $STATS"

#  cp ${FORW} ttt.forw
#  cp ${REV} ttt.rev


  ${GAWK} -v file1=${FORW}  -v file2=${REV} -v out1=${FORW_FLTR} -v out2=${REV_FLTR} -v info=${INFO_FORW} -v min_length=${MIN_READ_LENGTH} '
  BEGIN {
    OFS="\n"
    FS="\t"
    incl=0;
    excl=0;
    while((getline id1 < file1)>0) { 
      getline seq1 < file1; getline p1 < file1; getline qual1 < file1; 
      getline id2 <file2; getline seq2 < file2; getline p2 < file2; getline qual2 < file2;
      if ( length(seq1) > min_length && length(seq2) > min_length ) {
        print id1,seq1,p1,qual1 > out1;
        print id2,seq2,p2,qual2 > out2;
        incl++;
      } else {
        excl++;
      }
    }
    print "removed "excl" paired-end reads for which either forward or reverse read were "min_length"bp or shorter\n";
    print incl" reads passed this filter\n\n";
  }' > ${STATS}
  # rename filtered fastq files to org name
  mv -f ${FORW_FLTR} ${FORW}
  mv -f ${REV_FLTR} ${REV}

}

for BASE in ${BASEFILES}; do 
  echo "processing ${BASE} files"; echo ""

  ### FORWARD READS TRIMMING ######
  #################################
  FORW=${FORWFILES[$BASE]}
  echo "forward reads file = ${FORW}"

  # create tmp dir for splitting and processing
  PROCDIR=`mktemp -d ./tmp_split_${BASE}.XXXXXXXXXX`
  echo "tmpdir = ${PROCDIR}"
  # and go there
  cd ${PROCDIR}

  # trim forw read
  echo "starting to trim adapter in forward reads; trim adapter from 5'" 
  echo "and trim all after digest restriction site (${RESTRICT_SITE}) site on 3'"
  echo ""
  trim_reads ${FORW} "forw"
  # go back to bparent directory and delete the temporary processing directory
  cd ../
  rm -rf ${PROCDIR}
  echo -e "finished trimming adapter in forward reads\n\n"

  ### REVERSE READS TRIMMING ######
  #################################
  REV=${REVFILES[$BASE]}
  echo "reverse reads file = ${REV}"

  # create tmp dir for splitting and processing
  PROCDIR=`mktemp -d ./tmp_split_${BASE}.XXXXXXXXXX`
  echo "tmpdir = ${PROCDIR}"
  # and go there
  cd ${PROCDIR}

  # trim reverse read
  echo "starting to trim adapter in reverse reads; trim adapter from 5'" 
  echo "and trim all after digest restriction site (${RESTRICT_SITE}) site on 3'"
  trim_reads ${REV} "rev"
  # go back to bparent directory and delete the temporary processing directory
  cd ../
  rm -rf ${PROCDIR}
  echo -e "finished trimming adapter in reverse reads\n\n"

  # remove all reads which are $MIN_READ_LENGTH basepairs or shorter
  ##################################################################
  echo "starting to filtered reads too short for aligning to genome"
  filter_read_length ${BASE}
  echo "finished filtered read on length"
  echo ""

  ### ALIGNMENT OF PAIRED_END READS, plus filtering on concordant reads and sorting on readID ######
  ##################################################################################################
  echo "starting alignment"
  FORW=${BASE}_forw_trimmed_${RESTRICT_SITE}.fastq
  REV=${BASE}_rev_trimmed_${RESTRICT_SITE}.fastq
  BAM=${BASE}.bam
  BAM_SRT=${BAM%.bam}_fltr_nameSrt.bam
  STATS=${BASE}.stats

  CMD="(${BOWTIE2} -p ${NCORES} -x ${BOWTIE2_REFSEQ} -1 $FORW -2 $REV -X ${MAX_INSERT_LENGTH} | \
    ${SAMTOOLS} view -b -f2 -u - -o - | \
    ${SAMTOOLS} sort -n - -o ${BAM_SRT} -T ${BAM%.bam}_srt -@ ${NCORES} ) 2>> ${STATS}"

  echo "command to run bowtie = ${CMD}"

  eval $CMD

##    ( ${BOWTIE2} -p ${NCORES} -x ${BOWTIE2_REFSEQ} -1 $FORW -2 $REV -X ${MAX_INSERT_LENGTH} | \
##      ${SAMTOOLS} view -b -f2 -u - -o - | \
##      ${SAMTOOLS} sort -n - -o ${BAM_SRT} -T ${BAM%.bam}_srt -@ ${NCORES} ) 2>> ${STATS}
  echo -e "alignment done\n"

  ### CONVERT BAM FILE INTO BEDPE FILE ###########
  ################################################
  echo "starting conversion of bam file to bedpe file"
  ## convert bam to bed file (in bedpe format)
  BEDPE=${BAM%.bam}.mate1_bedpe

  ${SAMTOOLS} view ${BAM_SRT} | \
    ${GAWK} '
  function RevComp( theBases ) {
  # from http://www.blossomassociates.net/molbio/revcomp.awk
  answer = "";
  l = length( theBases );
  for ( i = l; 0 < i; i-- ) {
    b = substr( theBases, i, 1 );

    if ( "c" == b ) b = "g";
    else if ( "g" == b ) b = "c";
    else if ( "a" == b ) b = "t";
    else if ( "t" == b ) b = "a";
    else if ( "u" == b ) b = "a";

    else if ( "C" == b ) b = "G";
    else if ( "G" == b ) b = "C";
    else if ( "A" == b ) b = "T";
    else if ( "T" == b ) b = "A";
    else if ( "U" == b ) b = "A";

    else if ( "m" == b ) b = "k";
    else if ( "r" == b ) b = "y";
    #   else if ( "w" == b ) b = "w";
    #   else if ( "s" == b ) b = "s";
    else if ( "y" == b ) b = "r";
    else if ( "k" == b ) b = "m";
    else if ( "v" == b ) b = "b";
    else if ( "h" == b ) b = "d";
    else if ( "d" == b ) b = "h";
    else if ( "b" == b ) b = "v";
    #   else if ( "x" == b ) b = "x";
    else if ( "n" == b ) b = "x";

    else if ( "M" == b ) b = "K";
    else if ( "R" == b ) b = "Y";
    #   else if ( "W" == b ) b = "W";
    #   else if ( "S" == b ) b = "S";
    else if ( "Y" == b ) b = "R";
    else if ( "K" == b ) b = "M";
    else if ( "V" == b ) b = "B";
    else if ( "H" == b ) b = "D";
    else if ( "D" == b ) b = "H";
    else if ( "B" == b ) b = "V";
    #   else if ( "X" == b ) b = "X";
    else if ( "N" == b ) b = "N";

    #   else if ( "." == b ) b = ".";

    answer = answer b;
  }
  return answer;
}

function CIGAR2length( cigar ) {
  # compute from a CIGAR string the length of the aligned genomic region:
  # first; CIGAR operators which appear only once do not have a counter in
  # fromt of them. First I will place a '1' in front of those so afterwards I
  # can easioly split the CIGAR string and have counts and operators
  # separately.
  # if first character is not a count but a CIGAR operator (MDINSHP=X), put a 1 in front of it
  mod=gensub("^([MDINSHP=X])", "1\\1",1,cigar);
  # for all consecutive pairs of CIGAR operators insert a 1 as count for the 2nd operator
  mod=gensub("([MDINSHP=X])([MDINSHP=X])", "\\11\\2",1,cigar);
  while (mod != cigar) {
    cigar=mod;
    mod=gensub("([MDINSHP=X])([MDINSHP=X])", "\\11\\2",1,cigar);
  }

  # split CIGAR string into an array of the counts and an array of the CIGAR operators
  split(cigar, counts, /[MDINSHP=X]+/);
  split(cigar, ops, /[[:digit:]]+/);
  # map the operators to 0,1; depending on whether the operators corresponds to
  # an increase in length of the aligned genomic region
  for (i in ops) {
    gsub("[MDNPX=]", "1", ops[i]) # these ops increase genomic alignment
    gsub("[ISH]", "0", ops[i]) # these ops do not increase genomic alignment
  }
  # compute the total length by multiplying the counts and the lengths of the operators
  len=0;
  for (i=1; i<length(counts); i++) {
    len = len + (counts[i]*ops[i+1])
  }
  return len;
}

BEGIN { 
  FS  = "\t";
  OFS = "\t";
  flag_properPair = lshift(1, 1); # bit-4 flag
  flag_firstInPair = lshift(1, 6);
  flag_readReverseStrand = lshift(1, 4);
};

{
  flag_1=$2;
  # This read should always be the first in pair
  if (! and (flag_1, flag_firstInPair))
    print("The first read is not first in pair!!!!\tFLAG = "flag_1", ("flag_firstInPair")");

  # check this read pair is a concordant pair, otherwise skip the entire pair
  if (! and(flag_1, flag_properPair) ) {
    # if we read a discordant read-pair skip the entire pair (ie also read next read and then go the next pair)
    getline;
    next;
  }
  # store alignment data of first read in pair
  read[1, "MAPQ"]  = $5;
  read[1, "SEQ"]   = $10;
  read[1, "START"] = $4;
  read[1, "FLAG"]  = $2;
  read[1, "CIGAR"] = $6;
  read[1, "RNAME"] = $3;
  read[1, "ID"]    = $1;
  # get MD field from optional fields
  read[1, "MD"]    = "";
  for (i=12; i<NF; i++) {
    if ($i ~ /MD:Z:/) {
      read[1, "MD"]=$i;
      break;
    }
  }
  # get optional XS:i: field from optional fields
  read[1, "XS"]    = "F";
  for (i=12; i<NF; i++) {
    if ($i ~ /XS:i:/) {
      read[1, "XS"]="T";
      break;
    }
  }
  # compute end position on genome
  read[1, "END"] = read[1,"START"] - 1 + CIGAR2length(read[1, "CIGAR"])

  # read second read in pair and parse data
  getline;
  read[2, "MAPQ"]  = $5;
  read[2, "SEQ"]   = $10;
  read[2, "START"] = $4;
  read[2, "FLAG"]  = $2;
  read[2, "CIGAR"] = $6;
  # get MD field from optional fields
  read[2, "MD"]    = "";
  for (i=12; i<NF; i++) {
    if ($i ~ /MD:Z:/) {
      read[2, "MD"]=$i;
      break;
    }
  }
  # get optional XS:i: field from optional fields
  read[2, "XS"]    = "F";
  for (i=12; i<NF; i++) {
    if ($i ~ /XS:i:/) {
      read[2, "XS"]="T";
      break;
    }
  }
  # compute end position on genome
  read[2, "END"] = read[2,"START"] - 1 + CIGAR2length(read[2, "CIGAR"])

  # is the fragment on the forward or on the reverse strand
  if ( and(read[1, "FLAG"], flag_readReverseStrand) ) {
    strand="-";
    # read on reverse strand; reverse-complement the sequence
    read[1, "SEQ"]=RevComp(read[1, "SEQ"]);
  }
  else {
    strand="+";
    # read on reverse strand; reverse-complement the sequence
    read[2, "SEQ"]=RevComp(read[2, "SEQ"]);
  }

  # which read is first on forw strand
  if (strand == "+") {
    first_read=1;
  } else {
    first_read=2;
  }
  last_read=3-first_read;

  # print the bedpe output, including the extra data, in the following format:
  # readID seqname start end strand end.2 start.2 MAPQ.1 MAPQ.2 MD.1 MD.2 SEQ.1 SEQ.2
  print( read[1, "ID"],
         read[1, "RNAME"],
	 read[first_read, "START"],
	 read[last_read, "END"],
	 strand,
	 read[first_read, "END"],
	 read[last_read, "START"],
	 read[first_read, "MAPQ"],
	 read[last_read, "MAPQ"],
	 read[first_read, "MD"],
	 read[last_read, "MD"],
	 read[first_read, "XS"],
	 read[last_read, "XS"],
	 read[first_read, "SEQ"],
	 read[last_read, "SEQ"])
}
' > ${BEDPE}

  ## add barcode sequence from INFO file to BEDPE file
  # $INFO is the info-file created while trimming the forward read by
  # cutadapt (ie very first step)
  mv ${BEDPE} ${BEDPE}.tmp
  # merge barcodes from $INFO into $BEDPE using awk
  # (store readID from column-5 from $BEDPE as key in array 'a' with
  # entire line, except readID, as value. read $INFO, look for key and add barcode
  # sequence $5) to array element
  INFO=${BASE}_forw_trimmed.info
  ${GAWK} -F '\t' ' 
  FNR==NR { 
    a[$1]=substr($0, index($0,$2)); 
    next
  }
  { 
    # LP140424; trim readIDs differently for NKI formatted readIDs or BGI
    # formatted readIDs
    sub(/\s.*$/,"",$1); # trim readID for NKI format
    sub(/\/1$/,"",$1); # trim readID for bgi format
    # end LP140424
  
    if ( $1 in a ) {
      BC = $5
      len  = length(BC)
      BClen[len]++
      hasN = BC~/N/
      NNN[hasN]++
      if (len==20 && !hasN ) {
	incl++
	a[$1]=a[$1] FS BC;
      }
      else {
	excl++
	delete a[$1]
      }
    }
  }
  END { 
    for (key in a) print a[key];
    print "included = "incl", excl = "excl > "/dev/stderr"

  } ' ${BEDPE}.tmp ${INFO} | \
    # tee /tmp/ttt | \
  # sort resulting bedpe file on seqname and start (latter numeric
  # sort)
  sort -S 50% --parallel=${NCORES} -k1,1 -k2,2n | \
  # remove duplicates and add a count column
  uniq -c |\
  # reorder columns: move count to 7th column
  # and write to $BEDPE the following columns:
  # chr start end length strand barcode count internal-end internal-start MAPQ MD1 MD2 XS1 XS2 SEQ1 SEQ2
  ${GAWK} ' 
  BEGIN{ 
    OFS="\t";
    print("seqname","start","end","length","strand","barcode","count","end.intr","start.intr","MAPQ","MD.1","MD.2","alt.1","alt.2","seq.1","seq.2");
  } 
  { 
    print($2,$3,$4,$4-$3+1,$5,$16,$1,$6,$7,$8,$10,$11,$12,$13,$14,$15)
  } ' > ${BEDPE}
  echo "conversion bam to bedpe done"

  
  # clean or compress text files
  ##############################
  if $CLEAN; then
    rm -f ${FORW_FLTR} ${REV_FLTR} *fastq *bam *bai *info *.tmp
  else
    parallel -j ${NCORES} gzip :::  ${FORW_FLTR} ${REV_FLTR} *fastq *info *.tmp
  fi
  # compress bedpe file
  parallel -j ${NCORES} gzip ::: *bedpe

  echo "finished processing ${BASE} files"
  date 

done



########## DONE ##############
LINE="finished "${SCRIPTNAME}
SEPARATOR=$(head -c ${#LINE} </dev/zero | tr '\0' '=')
echo $SEPARATOR; echo $LINE; echo $SEPARATOR
endtime=$(date +%c)
echo "end date/time = "${endtime}
echo "==================================="
echo ""
