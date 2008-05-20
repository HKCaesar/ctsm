#! /bin/tcsh -f
#
#=======================================================================
#
#  run-lightning.csh
#
#  Generic batch submission script for lightning using LSF.  
#
#-----------------------------------------------------------------------
# Batch options for machine with LSF batch system. 
# Usage for PathScale compiler (default): 
#   bsub < run-lightning.csh
#-----------------------------------------------------------------------
#
#BSUB -a mpich_gm
#BSUB -x
#BSUB -n 2,4
#BSUB -R "span[ptile=2]"
#BSUB -o clm.o%J
#BSUB -e clm.e%J
#BSUB -q regular
#BSUB -W 0:10                   # wall clock limit
#BSUB -P xxxxxxxx               # Project number to charge to
#
#=======================================================================

#===========================================================================
#=================== THINGS MOST COMONLY CHANGED ===========================

## Default configuration settings:
set spmd     = on       # settings are [on   | off         ] (default is off)
set maxpft   = 4        # settings are 4->17                 (default is 4)
set bgc      = none     # settings are [none | cn | casa   ] (default is none)
set supln    = off      # settings are [on   | off         ] (default is off)
set dust     = off      # settings are [on   | off         ] (default is off)   
set voc      = off      # settings are [on   | off         ] (default is off)   
set rtm      = off      # settings are [on   | off         ] (default is off)   

## IF YOU CHANGE ANY OF THE CONFIGURATION SETTINGS -- DELETE THE $blddir/config_cache.xml AND RESUBMIT
## (see below)
#--------------------------------------------------------------------------------------------
## Run time settings:
set res        = 48x96      # settings are [48x96   | 64x128  | 4x5  | 10x15 | 1.9x2.5 etc.      ]
set mask       = gx3v5      # settings are [default | USGS    | navy | gx3v5 | gx1v5   etc.      ]
set sim_year   = default    # settings are [default | 1890    | 2000 | 2100                      ]
set start_type = arb_ic     # settings are [arb_ic  | startup | continue | branch                ] (default is arb_ic)
set runlen     = 2d         # settings are [ integer<sdy> where s=cpling-step, d=days, y=years   ] (default is 2d)
set start_ymd  = 19980101   # Start date [yyyymmdd]
set cycle_init = 1998       # Initial year to use atm data from
set cycle_beg  = 1948       # Begining year to cycle through for input atm data
set cycle_end  = 2004       # Ending   year to cycle through for input atm data
set ret_pd     = 0          # settings are [0 (no archiving), >0 (days to save to archive)       ]
set resub_date = 0          # settings are [0 (no resubmission), > 0 (date {YYYYMMDD} to run to) ]
set ref_dir    = /CCSM/csm  # reference MSS directory [ used when start_type=branch ]
set ref_case   = clmrun     # reference case id       [ used when start_type=branch ]
set ref_date   = 1998-01-01 # reference date          [ used when start_type=branch ]

#--------------------------------------------------------------------------------------------

## Locations of important directories:
##

## netCDF stuff (MAKE SURE YOU CHANGE THIS -- IF NOT RUNNING AT NCAR)
setenv INC_NETCDF /contrib/2.6/netcdf/3.6.0-p1-pathscale-2.4-64/include
setenv LIB_NETCDF /contrib/2.6/netcdf/3.6.0-p1-pathscale-2.4-64/lib

## MPI stuff (MAKE SURE YOU CHANGE THIS -- IF NOT RUNNING AT NCAR)
set mpich=/contrib/2.6/mpich-gm/1.2.6..14a-pathscale-2.4-64
setenv INC_MPI ${mpich}/include
setenv LIB_MPI ${mpich}/lib

## Location of Pathscale compiler (MAKE SURE YOU CHANGE THIS -- IF NOT RUNNING AT NCAR)
set ps=/contrib/2.6/pathscale/2.4

## Path to binaries needed in script and dynamic libraries needed
setenv PATH ${mpich}/bin:${ps}/bin:/usr/bin:/bin:${PATH}
setenv LD_LIBRARY_PATH ${ps}/lib/2.4:${LD_LIBRARY_PATH}

## ROOT OF CLM DISTRIBUTION - probably needs to be customized.
## Contains the source code for the CLM distribution.
## (the root directory for clm contains the subdirectory "src")
## UTILROOT is the root of the CCSM tools directory
set clmroot   = /fis/cgd/.......      # (MAKE SURE YOU CHANGE THIS!!!)
setenv UTILROOT $clmroot/../../../scripts/ccsm_utils

## ROOT OF CLM DATA DISTRIBUTION - needs to be customized unless running at NCAR.
## Contains the initial and boundary data for the CLM distribution.
setenv CSMDATA /fs/cgd/csm/inputdata

## Location of datm data - needs to be customized unless running at NCAR.
## Contains the location for the datm7 input data
setenv datm_data_dir /cgd/tss/NCEPDATA.datm7.Qian.T62.c060410   # (MAKE SURE YOU CHANGE THIS!!!)

## $wrkdir is a working directory where the model will be built and run.
## $blddir is the directory where model will be compiled.
## $rundir is the directory where the model will be run.
## $cfgdir is the directory containing the CLM configuration scripts.
## $casdir  is the directoyr this script is found in.
## $arcdir  is the directory where the archiving scripts are found.
## $usr_src is the directory where any modified source code is put.
set case     = clmrun                 # changed by create_newcase
set wrkdir   = /ptmp/$LOGNAME         # changed by create_newcase
set blddir   = $wrkdir/$case/bld
set rundir   = $wrkdir/$case
set cfgdir   = $clmroot/bld
set casdir   = $clmroot/bld           # changed by create_newcase
set arcdir   = $clmroot/../../../scripts/ccsm_utils/Tools/archiving
set usr_src  = $clmroot/bld/usr.src

#=================== END OF THINGS MOST COMONLY CHANGED ====================
#===========================================================================

## Ensure that run and build directories exist
mkdir -p $rundir                || echo "cannot create $rundir" && exit 1
mkdir -p $blddir                || echo "cannot create $blddir" && exit 1

## Build (or re-build) executable
set flags = "-fc pathf90 -linker mpif90 "
set flags = "$flags -maxpft $maxpft -bgc $bgc -supln $supln -voc $voc -rtm $rtm -dust $dust -usr_src $usr_src"
if ($spmd == on)  set flags = "$flags -spmd"
if ($spmd == off) set flags = "$flags -nospmd"

echo "cd $blddir"
cd $blddir                  || echo "cd $blddir failed" && exit 1
set config="$blddir/config_cache.xml"
## Check if config_cache.xml file exists -- if so just run make -- if NOT then run configure.
## IF YOU CHANGE ANY OF THE CONFIGURATION SETTINGS -- DELETE THE $blddir/config_cache.xml AND RESUBMIT
#--------------------------------------------------------------------------------------------
if ( ! -f $config ) then
    echo "flags to configure are $flags"
    $cfgdir/configure $flags    || echo "configure failed" && exit 1
    echo "Building CLM in $blddir ..."
    gmake -j8 >&! MAKE.out      || echo "CLM build failed: see $blddir/MAKE.out" && exit 1
else
    echo "Re-building CLM in $blddir ..."
    rm -f Depends
    gmake -j8 >&! REMAKE.out      || echo "CLM build failed: see $blddir/REMAKE.out" && exit 1
endif

## Create the namelist
cd $rundir                      || echo "cd $blddir failed" && exit 1

### Get restart files to branch from for a branch case

set set_restart_file = " "
set set_restbfile    = " "
set set_restsfile    = " "
set set_nrevsn       = " "
if ( $start_type == branch )then
   echo "Get branch restart files"
   set restart_file = "$ref_case.cpl.r.$ref_date-00000.nc"
   set restbfile    = "$ref_case.datm7.rb.$ref_date-00000.nc"
   set restsfile    = "$ref_case.datm7.rs.$ref_date-00000.bin"
   set nrevsn       = "$ref_case.clm2.r.$ref_date-00000.nc"
   if ( ! -f $restart_file ) $UTILROOT/Tools/ccsm_msread $ref_dir/$ref_case/cpl/rest/$restart_file $restart_file
   if ( ! -f $restbfile    ) $UTILROOT/Tools/ccsm_msread $ref_dir/$ref_case/atm/rest/$restbfile    $restbfile
   if ( ! -f $restsfile    ) $UTILROOT/Tools/ccsm_msread $ref_dir/$ref_case/atm/rest/$restsfile    $restsfile
   if ( ! -f $nrevsn       ) $UTILROOT/Tools/ccsm_msread $ref_dir/$ref_case/lnd/rest/$nrevsn       $nrevsn
   set set_restart_file = " restart_file = '$restart_file'"
   set set_restbfile    = " restbfile    = '$restbfile'"
   set set_restsfile    = " restsfile    = '$restsfile'"
   set set_nrevsn       = " nrevsn       = '$nrevsn'"
endif
#
# If you want to include a specific input file to clm simply add it to the clm_inparm namelist below
# e.g.
#    finidat = '$CSMDATA/lnd/clm2/inidata_3.1/offline/clmi_0000-01-01_064x128_c070403.nc'
#
set stop_final = 99991231
if ( $resub_date > 0 ) set stop_final = $resub_date
set set_restart_option = " "
set_restart_option = " restart_option = 'yearly'"
cat >! lndinput << EOF
 &drv_in
 $set_restart_option
 $set_restart_file
 $set_restbfile
 $set_restsfile
 start_ymd      =  $start_ymd
 start_tod      =  0
 stop_ymd       = $stop_final
 /
 &clm_inparm
 $set_nrevsn
 dtime          =  1800
 irad           = -1
 wrtdia         = .true.
 hist_dov2xy    = .true.
 hist_nhtfrq    =  -24
 hist_mfilt     =  1
 hist_crtinic   = 'NONE'
 /
EOF
set bnflags="-case $case -start_type $start_type -config $config -mask $mask -sim_year $sim_year -infile lndinput -runlength $runlen" 
set bnflags="$bnflags -datm_data_dir $datm_data_dir -res $res -csmdata $CSMDATA"
set bnflags="$bnflags -cycle_init $cycle_init -cycle_beg_year $cycle_beg -cycle_end_year $cycle_end"
$cfgdir/build-namelist $bnflags    || echo "build-namelist failed" && exit 1

## Run CLM 
cd $rundir                              || echo "cd $rundir failed" && exit 1
setenv LID "`date +%y%m%d-%H%M%S`"

# Save restart pointer file before run -- to ensure advancing
if ( -f rpointer.lnd ) \cp rpointer.lnd rpointer.lnd.orig

echo "running CLM in $rundir log file out to $rundir/clm.log.$LID"

if ($spmd == on) then
  mpirun.lsf -np 2 $blddir/clm >&! clm.log.$LID || echo "CLM run failed" && exit 1
  set runstatus = $status
else
  $blddir/clm                  >&! clm.log.$LID || echo "CLM run failed" && exit 1
  set runstatus = $status
endif

# Confirm run-status by making sure clm is advancing
# by checking that rpointer.lnd files are changing
if ( ! -f rpointer.lnd      && $runstatus == 0 ) set runstatus = 1
if (   -f rpointer.lnd.orig && $runstatus == 0 )then
   diff rpointer.lnd rpointer.lnd.orig > /dev/null
   if ( $status == 0 ) set runstatus = 1
endif

# Get date from restart pointer file
set end_date=`perl -e '$_ = <>; /\.r\.([0-9]+)-([0-9]+)-([0-9]+)-[0-9]+\.nc/; print "${1}${2}${3}";' rpointer.lnd`

## POST-PROCESSING vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv
## see the README in the archiving dir for more info how to use these scripts
if ( $ret_pd > 0 ) then

   ## GENERAL ARCHIVING SETTINGS
   setenv ARCH_CASE $case                #casename - required

   ## SHORT-TERM ARCHIVE SETTINGS
   setenv STA_ROOT                $wrkdir              #root path - required
   setenv STA_SAVE_INTERIM_RFILES TRUE                 #false->will archive only restart files from end of block run

   ## call to short-term archive script
   $arcdir/st_archive.sh

   ## Write out long-term archive script in case directory (so can easily run it by hand later)
   cat >! $casdir/run-lightning.csh.lt_archive << EOF
#!/bin/csh -f
#
# Long-term archive script in case directory.
#
   set casdir=$casdir
   set arcdir=$arcdir
   set ret_pd=$ret_pd
   set case=$case

   ## GENERAL ARCHIVING SETTINGS
   setenv ARCH_CASE $ARCH_CASE           #casename - required

   ## SHORT-TERM ARCHIVE SETTINGS
   setenv STA_ROOT                $wrkdir  #root path - required
   setenv STA_SAVE_INTERIM_RFILES $STA_SAVE_INTERIM_RFILES

   ## LONG-TERM ARCHIVE SETTINGS
   set uc_logname = `sh -c 'echo ${LOGNAME} | tr [a-z] [A-Z]'`
   setenv   LTA_ROOT /${uc_logname}/csm  #root path - required
   setenv   LTA_RETENTION   $ret_pd      #retention period (days)
   setenv   LTA_ANN_TARRING FALSE        #tar up monthly files into annual files
   setenv   LTA_INTEGRITY   NORMAL       #archival validated by file size only (vs HIGH)
   setenv   LTA_COS         rel=ec       #ec->economy class of service (just one copy archived)
   unsetenv LTA_WPWD                     #do NOT have write passwords (or password to use if changed to setenv)

   ## call to long-term archive script - will spawn batch job
   cd \$casdir
   \$arcdir/lt_archive.sh -f
EOF
   chmod +x $casdir/run-lightning.csh.lt_archive
   # Run the long-term archive script
   $casdir/run-lightning.csh.lt_archive

endif

# -------------------------------------------------------------------------
# Resubmit another run script
# -------------------------------------------------------------------------

if ( $runstatus == 0 && $resub_date > 0 && $resub_date > $end_date ) then
  echo "Resubmit job until reach $resub_date"
  cd $casdir
  sed '1,/^set *start_type = .*/s//set start_type = continue/' \
         run-lightning.csh > run-lightning.csh.continue
  if ( $status != 0 ) echo "Error in sed"
  if ( $status != 0 ) exit -1
  egrep "^set start_type = continue" run-lightning.csh.continue >> /dev/null
  set grepstatus = $status
  if ( $grepstatus != 0 ) echo "Do NOT resubmit as case is NOT set to continue"
  if ( $grepstatus != 0 ) exit -1
  bsub < run-lightning.csh.continue
else if ( $runstatus == 0 && $resub_date > 0 && $resub_date > $end_date ) then
  echo "Would have resubmited job -- but runstatus was NOT successful..."
endif


exit 0
