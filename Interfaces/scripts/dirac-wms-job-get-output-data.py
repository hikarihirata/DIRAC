#!/usr/bin/env python
########################################################################
# $Header: /tmp/libdirac/tmp.stZoy15380/dirac/DIRAC3/DIRAC/Interfaces/scripts/dirac-wms-job-get-output-data.py,v 1.1 2008/11/17 17:14:16 paterson Exp $
# File :   dirac-production-job-get-output-data
# Author : Stuart Paterson
########################################################################
__RCSID__   = "$Id: dirac-wms-job-get-output-data.py,v 1.1 2008/11/17 17:14:16 paterson Exp $"
__VERSION__ = "$Revision: 1.1 $"
from DIRACEnvironment import DIRAC
from DIRAC.Core.Base import Script
from DIRAC.Interfaces.API.Dirac                              import Dirac
import os

Script.parseCommandLine( ignoreErrors = True )
args = Script.getPositionalArgs()

def usage():
  print 'Usage: %s <JobID> |[<JobID>]' %(Script.scriptName)
  DIRAC.exit(2)

if len(args) < 1:
  usage()

dirac=Dirac()
exitCode = 0
errorList = []

for job in args:

  try:
    job = int(job)
  except Exception,x:
    errorList.append( ('Expected integer for jobID', job) )
    exitCode = 2
    continue

  result = dirac.getJobOutputData(job)
  if result['OK']:
    print 'Job %s output data retrieved' %(job)
  else:
    errorList.append( (job, result['Message']) )
    exitCode = 2

for error in errorList:
  print "ERROR %s: %s" % error

DIRAC.exit(exitCode)