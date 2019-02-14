#!/bin/bash

#dependencies
# binaries in bin/
# fsl



function die {
 echo $1 >&2
 exit 1
}

execpath=`dirname $0`
execpath=`realpath $execpath`

participant_label=
matching_T1w=

if [ "$#" -lt 3 ]
then
 echo "Usage: $0 <bids_dir> <output_dir> participant <optional arguments>"
 echo "          [--participant_label PARTICIPANT_LABEL [PARTICIPANT_LABEL...]]"
# echo "          [--matching_T1w MATCHING_STRING]"
 echo ""
 exit 1
fi


in_bids=$1
out_folder=$2
analysis_level=$3


shift 3

######################################################################################
# parameter initialization
######################################################################################
while :; do
      case $1 in
     -h|-\?|--help)
	     usage
            exit
              ;;
     --n_cpus )       # takes an option argument; ensure it has been specified.
          if [ "$2" ]; then
                n_cpus=$2
                  shift
	      else
              die 'error: "--n_cpus" requires a non-empty option argument.'
            fi
              ;;
      --participant_label )       # takes an option argument; ensure it has been specified.
            if [ "$2" ]; then
                  participant_label=$2
                    shift
         	  else
                die 'error: "--participant" requires a non-empty option argument.'
              fi
                ;;
       --participant_label=?*)
            participant_label=${1#*=} # delete everything up to "=" and assign the remainder.
              ;;
            --participant_label=)         # handle the case of an empty --participant=
          die 'error: "--participant_label" requires a non-empty option argument.'
            ;;

     --matching_T1w )       # takes an option argument; ensure it has been specified.
          if [ "$2" ]; then
                matching_T1w=$2
                  shift
	      else
              die 'error: "--matching_T1w" requires a non-empty option argument.'
            fi
              ;;
     --matching_T1w=?*)
          matching_T1w=${1#*=} # delete everything up to "=" and assign the remainder.
            ;;
          --matching_T1w=)         # handle the case of an empty --acq=
         die 'error: "--matching_T1w" requires a non-empty option argument.'
          ;;


      -?*)
            printf 'WARN: Unknown option (ignored): %s\n' "$1" >&2
              ;;
     *)               # Default case: No more options, so break out of the loop.
          break
    esac

 shift
  done


shift $((OPTIND-1))


#echo matching_T1w=$matching_T1w
echo participant_label=$participant_label

if [ -e $in_bids ]
then
	in_bids=`realpath $in_bids`
else
	echo "ERROR: bids_dir $in_bids does not exist!"
	exit 1
fi


if [ "$analysis_level" = "participant" ]
then
 echo " running participant level analysis"
 else
  echo "only participant level analysis is enabled"
  exit 0
fi


mkdir -p $out_folder
out_folder=`realpath $out_folder`




participants=$in_bids/participants.tsv

work_folder=$out_folder/work

echo mkdir -p $work_folder
mkdir -p $work_folder 

if [ ! -e $participants ]
then
    #participants tsv not required by bids, so if it doesn't exist, create one for temporary use
    participants=$work_folder/participants.tsv
    echo participant_id > $participants
    pushd $in_bids
    ls -d sub-* >> $participants
    popd 
fi


echo $participants


if [ -n "$matching_T1w" ]
then
  searchstring_T1w=\*${matching_T1w}\*MP2RAGE*T1w.nii*
else
  searchstring_T1w=*T1w.nii*
fi

if [ -n "$participant_label" ]
then
subjlist=`echo $participant_label | sed  's/,/\ /g'`
else
subjlist=`tail -n +2 $participants | awk '{print $1}'`
fi

echo $subjlist

for subj in $subjlist
do

######################################################################################
# variable initialization (template: prepdwi)
######################################################################################

#add on sub- if not exists
if [ ! "${subj:0:4}" = "sub-" ]
then
  subj="sub-$subj"
fi


    #loop over sub- and sub-/ses-
    for subjfolder in `ls -d $in_bids/$subj/anat $in_bids/$subj/ses-*/anat`
    do
        subj_sess_dir=${subjfolder%/anat}
        subj_sess_dir=${subj_sess_dir##$in_bids/}
        if echo $subj_sess_dir | grep -q '/'
        then
            sess=${subj_sess_dir##*/}
            subj_sess_prefix=${subj}_${sess}
        else
            subj_sess_prefix=${subj}
        fi
        echo subjfolder $subjfolder
        echo subj_sess_dir $subj_sess_dir
        echo sess $sess
        echo subj_sess_prefix $subj_sess_prefix


subj_work_dir=$work_folder/$subj_sess_dir
subj_final_dir=$out_folder/$subj_sess_dir/anat

mkdir -p ${subj_work_dir} # for intermediate files
mkdir -p $subj_final_dir # for final output


echo "Processing subject $subj_sess_prefix"

anatdir=$in_bids/$subj_sess_dir/anat
out_anat=$subj_final_dir

mkdir -p $out_anat


#these are generated from below
t1map=$subj_work_dir/DESPOT1HIFI_T1Map.nifti.nii.gz
m0map=$subj_work_dir/DESPOT1HIFI_MoMap.nifti.nii.gz
b1map=$subj_work_dir/DESPOT1HIFI_B1Map.nifti.nii.gz

if [ ! -e $t1map -o ! -e $m0map -o ! -e $b1map ]
then


despottype=2 	#hifi
spgr_match="$anatdir/*acq-SPGR_*DESPOT.nii.gz"
nspgr=`ls $spgr_match | wc -l`

echo spgr_match $spgr_match
echo nspgr $nspgr

spgr_notmatched=0
for i in `seq 1 $nspgr`
do
 spgr=`ls $spgr_match | head -n $i | tail -n 1`
 json=${spgr%%.nii.gz}.json

# echo $spgr, $json  
 spgr_tr[$i]=`getValueJson.py $json RepetitionTime` #get value, from s to ms
 spgr_tr[$i]=`bashcalc ${spgr_tr[$i]}*1000`
 spgr_fa[$i]=`getValueJson.py $json FlipAngle` 
 spgr_nii[$i]=$spgr
 
 echo spgr_tr[$i] ${spgr_tr[$i]}
 echo spgr_fa[$i] ${spgr_fa[$i]}
 echo spgr_nii[$i] ${spgr_nii[$i]}

 if [ "$i" = 1 ]
 then
   spgr_tr=${spgr_tr[$i]}
 else
    
   if [ ! "${spgr_tr[$i]}" = "$spgr_tr" ]
   then 
    spgr_notmatched=1
    echo "SPGR TR not matched!"
    continue
   fi

 fi
 
done

if [ "spgr_notmatched" = 1 ]
then
  continue
fi

irspgr_match="$anatdir/*acq-IRSPGR_*DESPOT.nii.gz"
nirspgr=`ls $irspgr_match | wc -l`
if [ "$nirspgr" -gt 1 ]
then  
  echo "Only 1 IRSPGR expected, but found $nirspgr"
  continue 
fi


irspgr_nii=`ls $irspgr_match`
json=${irspgr_nii%%.nii.gz}.json


 irspgr_ti=`getValueJson.py $json InversionTime` #get value, from s to ms
 if [ -n "$irspgr_ti" ]
 then
   irspgr_ti=`bashcalc ${irspgr_ti}*1000`
 else
   irspgr_ti=450
 fi

 irspgr_tr=`getValueJson.py $json RepetitionTime` #get value, from s to ms
 irspgr_tr=`bashcalc ${irspgr_tr}*1000`
# irspgr_tr[$i]=`bashcalc ${irspgr_tr[$i]}*1000`
 irspgr_fa=`getValueJson.py $json FlipAngle` 

 echo irspgr_tr ${irspgr_tr}
 echo irspgr_ti ${irspgr_ti}
 echo irspgr_fa ${irspgr_fa}
 echo irspgr_nii ${irspgr_nii}


#hardcoded from pulse sequence:

npulse=78  #readout pulses following inversion
field=3  #field strength
invmode=2  #number of inversions per slice


noiseth=1  #noise threshold scale
smoothb1=1  #smooth B1 field
specklerm=0  #enable error-checking and speckle removal
speckleth=1 #speckle threshold


outdespot=$subj_work_dir/DESPOT1HIFI_T1Map.img


ref=${spgr_nii[1]}


 flirt_params="-bins 64 -cost corratio -searchrx -5 5 -searchry -5 5 -searchrz -5 5 -dof 6  -interp sinc -sincwidth 7 -sincwindow hanning -datatype float -v"

 out=$subj_work_dir/spgr_1.nii.gz
 echo flirt -in $ref -ref $ref -out $out -applyxfm -datatype float -interp sinc -sincwidth 7 -sincwindow hanning -v
 flirt -in $ref -ref $ref -out $out -applyxfm -datatype float -interp sinc -sincwidth 7 -sincwindow hanning -v

#first, use flirt to co-register images to FA18 image
for i in `seq 2 $nspgr`
do

 flo=${spgr_nii[$i]}

 out=$subj_work_dir/spgr_${i}_reg.nii.gz
 out_mat=$subj_work_dir/spgr_${i}_regFlirt.mat


echo flirt -in $flo -ref $ref -out $out -omat $out_mat $flirt_params
 flirt -in $flo -ref $ref -out $out -omat $out_mat $flirt_params


done

#first, use flirt to co-register images to FA18 image
 flo=${irspgr_nii}

 out=$subj_work_dir/irspgr_reg.nii.gz
 out_mat=$subj_work_dir/irspgr_regFlirt.mat

echo flirt -in $flo -ref $ref -out $out -omat $out_mat $flirt_params
 flirt -in $flo -ref $ref -out $out -omat $out_mat $flirt_params




#convert to ANALYZE format and orientation for despot1 processing
for im in `ls $subj_work_dir/{spgr,irspgr}*.nii.gz`
do

  im_ana=${im%%.nii.gz}.ana.img
  im_rot=${im%%.nii.gz}.ana.rot.img
 
  fslchfiletype ANALYZE $im $im_ana
  ReorderImage $im_ana RAS $im_rot PSR

done


despot1_cmd="despot1 $despottype $nspgr ${spgr_tr} $subj_work_dir/spgr_1.ana.rot"
for i in `seq 2 $nspgr`
do
  despot1_cmd="$despot1_cmd $subj_work_dir/spgr_${i}_reg.ana.rot"
done

for i in `seq 1 $nspgr`
do
  despot1_cmd="$despot1_cmd ${spgr_fa[$i]}"
done

despot1_out=$subj_work_dir/despot1
mkdir -p $despot1_out


despot1_cmd="$despot1_cmd $nirspgr $subj_work_dir/irspgr_reg.ana.rot $irspgr_ti $irspgr_tr $irspgr_fa $npulse $field $invmode $subj_work_dir/ $noiseth $smoothb1 $specklerm $speckleth"

echo $despot1_cmd
$despot1_cmd




qform=`fslorient -getqform $ref`
#now convert back to original space
for im in `ls $subj_work_dir/DESPOT1*img`
do

  im_unrot=${im%%.img}.unrot.img
  nii=${im%%.img}.nifti.nii.gz


   ReorderImage $im PSR $im_unrot RAS 
    
   fslchfiletype NIFTI_GZ $im_unrot $nii


   echo fslorient -setqform $qform $nii
   fslorient -setqform $qform $nii
   echo fslorient -copyqform2sform $nii
   fslorient -copyqform2sform  $nii
   echo fslswapdim $nii -x y z $nii
   fslswapdim $nii -x y z $nii

done

else 
     echo "skipping despot1 pre-proc and fitting, since files exist already"
fi



#create syn T1w image 
t1w=$subj_work_dir/DESPOT1HIFI_T1w.nifti.nii.gz
octave --path $execpath/matlab --eval "genDespotSynT1w('$t1map','$t1w')"
#echo "addpath('$execpath/matlab'); genDespotSynT1w('$t1map','$t1w')" | matlab -nodisplay -nosplash

#use M0map to generate soft-masked perform skull-stripping on M0map, then apply to 
softmask=$subj_work_dir/DESPOT1HIFI_MoMap_softmask.nifti.nii.gz
hardmask=$subj_work_dir/DESPOT1HIFI_MoMap_hardmask.nifti.nii.gz

$execpath/bin/genSoftMaskM0 $m0map $hardmask $softmask
t1map_brain=$subj_work_dir/DESPOT1HIFI_T1Map_brain.nifti.nii.gz
m0map_brain=$subj_work_dir/DESPOT1HIFI_MoMap_brain.nifti.nii.gz
b1map_brain=$subj_work_dir/DESPOT1HIFI_B1Map_brain.nifti.nii.gz
t1w_brain=$subj_work_dir/DESPOT1HIFI_T1w_brain.nifti.nii.gz

#use softmasking for all but m0map
fslmaths $softmask  -mul $t1map $t1map_brain
fslmaths $softmask  -mul $b1map $b1map_brain
fslmaths $softmask  -mul $t1w $t1w_brain
fslmaths $hardmask -mul $m0map $m0map_brain


#copy unmasked data
cp -v $t1map $out_anat/${subj_sess_prefix}_acq-DESPOT_T1map.nii.gz
cp -v $b1map  $out_anat/${subj_sess_prefix}_acq-DESPOT_B1map.nii.gz
cp -v $m0map $out_anat/${subj_sess_prefix}_acq-DESPOT_M0map.nii.gz
cp -v $t1w $out_anat/${subj_sess_prefix}_acq-DESPOT_T1w.nii.gz

#copy masked data
cp -v $t1map_brain $out_anat/${subj_sess_prefix}_acq-DESPOT_proc-masked_T1map.nii.gz
cp -v $b1map_brain  $out_anat/${subj_sess_prefix}_acq-DESPOT_proc-masked_B1map.nii.gz
cp -v $m0map_brain $out_anat/${subj_sess_prefix}_acq-DESPOT_proc-masked_M0map.nii.gz
cp -v $t1w_brain $out_anat/${subj_sess_prefix}_acq-DESPOT_proc-masked_T1w.nii.gz



done

done



