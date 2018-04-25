#!/bin/sh
#-------------------------------------------------------------------------------
# dirac_ci
#
# Several functions used for Jenkins style jobs
# They may also work on other CI systems
#
#
# fstagni@cern.ch
# 09/12/2014
#-------------------------------------------------------------------------------

# A CI job needs:
#
# === environment variables (minimum set):
# DEBUG
# WORKSPACE
# DIRACBRANCH
#
# === a default directory structure is created:
# ~/TestCode
# ~/ServerInstallDIR
# ~/PilotInstallDIR




# Def of environment variables:

if [ "$DEBUG" ]
then
  echo '==> Running in DEBUG mode'
  DEBUG='-ddd'
else
  echo '==> Running in non-DEBUG mode'
fi

if [ "$WORKSPACE" ]
then
  echo '==> We are in Jenkins I guess'
else
  WORKSPACE=$PWD
fi

if [ "$DIRACBRANCH" ]
then
  echo '==> Working on DIRAC branch ' $DIRACBRANCH
else
  DIRACBRANCH='integration'
fi

# Creating default structure
mkdir -p $WORKSPACE/TestCode # Where the test code resides
TESTCODE=$_
mkdir -p $WORKSPACE/ServerInstallDIR # Where servers are installed
SERVERINSTALLDIR=$_
mkdir -p $WORKSPACE/ClientInstallDIR # Where clients are installed
CLIENTINSTALLDIR=$_
mkdir -p $WORKSPACE/PilotInstallDIR # Where pilots are installed
PILOTINSTALLDIR=$_


# Sourcing utility file
source $TESTCODE/DIRAC/tests/Jenkins/utilities.sh



#...............................................................................
#
# installSite:
#
#   This function will install DIRAC using the dirac-install.py script
#     following (more or less) instructions at dirac.rtfd.org
#
#...............................................................................

function installSite(){
  echo '==> [installSite]'

  prepareForServer

  killRunsv
  findRelease

  generateCertificates

  getCFGFile

  echo '==> Fixing install.cfg file'
  if [ "$LcgVer" ]
  then
    echo '==> Fixing LcgVer to ' $LcgVer
    sed -i s/VAR_LcgVer/$LcgVer/g $SERVERINSTALLDIR/install.cfg
  else
    sed -i s/VAR_LcgVer/$externalsVersion/g $SERVERINSTALLDIR/install.cfg
  fi
  sed -i s,VAR_TargetPath,$SERVERINSTALLDIR,g $SERVERINSTALLDIR/install.cfg
  fqdn=`hostname --fqdn`
  sed -i s,VAR_HostDN,$fqdn,g $SERVERINSTALLDIR/install.cfg

  sed -i s/VAR_DB_User/$DB_USER/g $SERVERINSTALLDIR/install.cfg
  sed -i s/VAR_DB_Password/$DB_PASSWORD/g $SERVERINSTALLDIR/install.cfg
  sed -i s/VAR_DB_RootUser/$DB_ROOTUSER/g $SERVERINSTALLDIR/install.cfg
  sed -i s/VAR_DB_RootPwd/$DB_ROOTPWD/g $SERVERINSTALLDIR/install.cfg
  sed -i s/VAR_DB_Host/$DB_HOST/g $SERVERINSTALLDIR/install.cfg
  sed -i s/VAR_DB_Port/$DB_PORT/g $SERVERINSTALLDIR/install.cfg

  sed -i s/VAR_NoSQLDB_User/$NoSQLDB_USER/g $SERVERINSTALLDIR/install.cfg
  sed -i s/VAR_NoSQLDB_Password/$NoSQLDB_PASSWORD/g $SERVERINSTALLDIR/install.cfg
  sed -i s/VAR_NoSQLDB_Host/$NoSQLDB_HOST/g $SERVERINSTALLDIR/install.cfg
  sed -i s/VAR_NoSQLDB_Port/$NoSQLDB_PORT/g $SERVERINSTALLDIR/install.cfg

  echo '==> Started installing'
  $SERVERINSTALLDIR/dirac-install.py -t fullserver $SERVERINSTALLDIR/install.cfg $DEBUG
  if [ $? -ne 0 ]
  then
    echo 'ERROR: dirac-install.py -t fullserver failed'
    return
  fi

  echo '==> Done installing, now configuring'
  source $SERVERINSTALLDIR/bashrc
  dirac-configure $SERVERINSTALLDIR/install.cfg $DEBUG
  if [ $? -ne 0 ]
  then
    echo 'ERROR: dirac-configure failed'
    return
  fi

  #replace the sources with custom ones if defined
  diracReplace

  dirac-setup-site $DEBUG
  if [ $? -ne 0 ]
  then
    echo 'ERROR: dirac-setup-site failed'
    return
  fi

  echo '==> Completed installation'

}


#...............................................................................
#
# fullInstall:
#
#   This function install all the DIRAC stuff known...
#
#...............................................................................

function fullInstallDIRAC(){
  echo '==> [fullInstallDIRAC]'

  finalCleanup

  #basic install, with only the CS (and ComponentMonitoring) running, together with DB InstalledComponentsDB, which is needed)
  installSite
  if [ $? -ne 0 ]
  then
    echo 'ERROR: installSite failed'
    return
  fi

  #Dealing with security stuff
  # generateCertificates
  generateUserCredentials
  if [ $? -ne 0 ]
  then
    echo 'ERROR: generateUserCredentials failed'
    return
  fi

  diracCredentials
  if [ $? -ne 0 ]
  then
    echo 'ERROR: diracCredentials failed'
    return
  fi

  #just add a site
  diracAddSite
  if [ $? -ne 0 ]
  then
    echo 'ERROR: diracAddSite failed'
    return
  fi

  #Install the Framework
  findDatabases 'FrameworkSystem'
  dropDBs
  diracDBs
  if [ $? -ne 0 ]
  then
    echo 'ERROR: diracDBs failed'
    return
  fi

  findServices 'FrameworkSystem'
  diracServices
  if [ $? -ne 0 ]
  then
    echo 'ERROR: diracServices failed'
    return
  fi

  #create groups
  diracUserAndGroup
  if [ $? -ne 0 ]
  then
    echo 'ERROR: diracUserAndGroup failed'
    return
  fi

  echo '==> Restarting Framework ProxyManager'
  dirac-restart-component Framework ProxyManager $DEBUG

  echo '==> Restarting Framework ComponentMonitoring'
  dirac-restart-component Framework ComponentMonitoring $DEBUG

  #Now all the rest

  #DBs (not looking for FrameworkSystem ones, already installed)
  findDatabases 'exclude' 'FrameworkSystem'
  dropDBs
  diracDBs
  if [ $? -ne 0 ]
  then
    echo 'ERROR: diracDBs failed'
    return
  fi

  #upload proxies
  diracProxies
  if [ $? -ne 0 ]
  then
    echo 'ERROR: diracProxies failed'
    return
  fi

  #fix the DBs (for the FileCatalog)
  diracDFCDB
  python $TESTCODE/DIRAC/tests/Jenkins/dirac-cfg-update-dbs.py $DEBUG

  #services (not looking for FrameworkSystem already installed)
  findServices 'exclude' 'FrameworkSystem'
  diracServices
  if [ $? -ne 0 ]
  then
    echo 'ERROR: diracServices failed'
    return
  fi

  #fix the services
  python $TESTCODE/DIRAC/tests/Jenkins/dirac-cfg-update-services.py $DEBUG

  #fix the SandboxStore and other stuff
  python $TESTCODE/DIRAC/tests/Jenkins/dirac-cfg-update-server.py dirac-JenkinsSetup $DEBUG

  echo '==> Restarting WorkloadManagement SandboxStore'
  dirac-restart-component WorkloadManagement SandboxStore $DEBUG

  echo '==> Restarting DataManagement FileCatalog'
  dirac-restart-component DataManagement FileCatalog $DEBUG

  echo '==> Restarting Configuration Server'
  dirac-restart-component Configuration Server $DEBUG

  echo '==> Restarting ResourceStatus ResourceStatus'
  dirac-restart-component ResourceStatus ResourceStatus $DEBUG

  echo '==> Restarting ResourceStatus ResourceManagement'
  dirac-restart-component ResourceStatus ResourceManagement $DEBUG

  echo '==> Restarting ResourceStatus Publisher'
  dirac-restart-component ResourceStatus Publisher $DEBUG

  #agents
  findAgents
  diracAgents
  if [ $? -ne 0 ]
  then
    echo 'ERROR: diracAgents failed'
    return
  fi


}


function clean(){

  #Uninstalling the services
  diracUninstallServices

  #stopping runsv of services and agents
  stopRunsv

  #DBs
  findDatabases
  dropDBs
  mysql -u$DB_ROOTUSER -p$DB_ROOTPWD -h$DB_HOST -P$DB_PORT -e "DROP DATABASE IF EXISTS FileCatalogDB;"
  mysql -u$DB_ROOTUSER -p$DB_ROOTPWD -h$DB_HOST -P$DB_PORT -e "DROP DATABASE IF EXISTS InstalledComponentsDB;"

  #clean all
  finalCleanup
}

############################################
# Pilot
############################################

#...............................................................................
#
# MAIN function: DIRACPilotInstall:
#
#   This function uses the pilot code to make a DIRAC pilot installation
#   The JobAgent is not run here
#
#...............................................................................

function DIRACPilotInstall(){

  prepareForPilot

  default

  findRelease

  #Don't launch the JobAgent here
  cwd=$PWD
  cd $PILOTINSTALLDIR
  if [ $? -ne 0 ]
  then
    echo 'ERROR: cannot change to ' $PILOTINSTALLDIR
    return
  fi

  if [ $GATEWAY ]
  then
    GATEWAY="-W "$GATEWAY
  fi

  if [ $lcgVersion ]
  then
    lcgVersion="-g "$lcgVersion
  fi

  commandList="GetPilotVersion,CheckWorkerNode,InstallDIRAC,ConfigureBasics,CheckCECapabilities,CheckWNCapabilities,ConfigureSite,ConfigureArchitecture,ConfigureCPURequirements"
  options="-S $DIRACSETUP -r $projectVersion $lcgVersion -C $CSURL -N $JENKINS_CE -Q $JENKINS_QUEUE -n $JENKINS_SITE -M 1 --cert --certLocation=/home/dirac/certs/ $GATEWAY"

  if [ "$customCommands" ]
  then
    echo 'Using custom command list'
    commandList=$customCommands
  fi

  if [ "$customOptions" ]
  then
    echo 'Using custom options'
    options="$options -o $customOptions"
  fi

  echo $( eval echo Executing python dirac-pilot.py $options -X $commandList $DEBUG)
  python dirac-pilot.py $options -X $commandList $DEBUG
  if [ $? -ne 0 ]
  then
    echo 'ERROR: pilot script failed'
    return
  fi

  cd $cwd
  if [ $? -ne 0 ]
  then
    echo 'ERROR: cannot change to ' $cwd
    return
  fi
}


function fullPilot(){

  #first simply install via the pilot
  DIRACPilotInstall
  if [ $? -ne 0 ]
  then
    echo 'ERROR: pilot installation failed'
    return
  fi

  #this should have been created, we source it so that we can continue
  source $PILOTINSTALLDIR/bashrc
  if [ $? -ne 0 ]
  then
    echo 'ERROR: cannot source bashrc'
    return
  fi

  #Adding the LocalSE and the CPUTimeLeft, for the subsequent tests
  dirac-configure -FDMH --UseServerCertificate -L $DIRACSE $DEBUG
  if [ $? -ne 0 ]
  then
    echo 'ERROR: cannot configure'
    return
  fi

  #Configure for CPUTimeLeft and more
  python $TESTCODE/DIRAC/tests/Jenkins/dirac-cfg-update.py -o /DIRAC/Security/UseServerCertificate=True $DEBUG
  if [ $? -ne 0 ]
  then
    echo 'ERROR: cannot update the CFG'
    return
  fi

  #Getting a user proxy, so that we can run jobs
  downloadProxy
  #Set not to use the server certificate for running the jobs
  dirac-configure -FDMH -o /DIRAC/Security/UseServerCertificate=False $DEBUG
  if [ $? -ne 0 ]
  then
    echo 'ERROR: cannot run dirac-configure'
    return
  fi
}


####################################################################################
# submitAndMatch
#
# This installs a DIRAC client, then use it to submit jobs to DIRAC.Jenkins.ch,
# then we run a pilot that should hopefully match those jobs

function submitAndMatch(){

  # Here we submit the jobs (to DIRAC.Jenkins.ch)
  installDIRAC # This installs the DIRAC client
  if [ $? -ne 0 ]
  then
    echo 'ERROR: failure installing the DIRAC client'
    return
  fi

  submitJob # This submits the jobs
  if [ $? -ne 0 ]
  then
    echo 'ERROR: failure submitting the jobs'
    return
  fi

  # Then we run the full pilot, including the JobAgent, which should match the jobs we just submitted
  cd $PILOTINSTALLDIR
  if [ $? -ne 0 ]
  then
    echo 'ERROR: cannot change to ' $PILOTINSTALLDIR
    return
  fi
  prepareForPilot
  default

  if [ ! -z "$PILOT_VERSION" ]
  then
    echo -e "==> Running python dirac-pilot.py -S $DIRACSETUP -r $PILOT_VERSION -g $lcgVersion -C $CSURL -N $JENKINS_CE -Q $JENKINS_QUEUE -n $JENKINS_SITE --cert --certLocation=/home/dirac/certs/ -M 3 $DEBUG"
    python dirac-pilot.py -S $DIRACSETUP -r $PILOT_VERSION -g $lcgVersion -C $CSURL -N $JENKINS_CE -Q $JENKINS_QUEUE -n $JENKINS_SITE --cert --certLocation=/home/dirac/certs/ -M 3 $DEBUG
    if [ $? -ne 0 ]
    then
      echo 'ERROR: dirac-pilot failure'
      return
    fi
  else
    echo -e "==> Running python dirac-pilot.py -S $DIRACSETUP -g $lcgVersion -C $CSURL -N $JENKINS_CE -Q $JENKINS_QUEUE -n $JENKINS_SITE --cert --certLocation=/home/dirac/certs/ -M 3 $DEBUG"
    python dirac-pilot.py -S $DIRACSETUP -g $lcgVersion -C $CSURL -N $JENKINS_CE -Q $JENKINS_QUEUE -n $JENKINS_SITE --cert --certLocation=/home/dirac/certs/ -M 3 $DEBUG
    if [ $? -ne 0 ]
    then
      echo 'ERROR: dirac-pilot failure'
      return
    fi
  fi
}
