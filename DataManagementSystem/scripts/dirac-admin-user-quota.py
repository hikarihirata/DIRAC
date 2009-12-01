#!/usr/bin/env python
########################################################################
# $HeadURL$
########################################################################
__RCSID__   = "$Id$"
__VERSION__ = "$Revision: 1.2 $"
import DIRAC
from DIRAC.Core.Base import Script
Script.parseCommandLine()
users = Script.getPositionalArgs()

from DIRAC import gLogger, gConfig
from DIRAC.Core.Utilities.List import sortList
from DIRAC.Core.Security.Misc import getProxyInfo

res = getProxyInfo(False,False)
if not res['OK']:
  gLogger.error("Failed to get client proxy information.",res['Message'])
  DIRAC.exit(2)
proxyInfo = res['Value']
userGroup = proxyInfo['group']
if userGroup != 'diracAdmin':
  gLogger.error("Not authorized to obtain user quotas. Please obtain admin role and try again.")
  DIRAC.exit(-2)

if not users:
  res = gConfig.getSections('/Registry/Users')
  if not res['OK']:
    gLogger.error("Failed to retrieve user list from CS",res['Message'])
    DIRAC.exit(2)
  users = res['Value']

gLogger.info("-"*30)
gLogger.info("%s|%s" % ('Username'.ljust(15),'Quota (GB)'.rjust(15)))
gLogger.info("-"*30)
for user in sortList(users):
  quota = gConfig.getValue('/Registry/Users/%s/Quota' % user,0)
  if not quota:
    quota = gConfig.getValue('/Registry/DefaultStorageQuota')
  gLogger.info("%s|%s" % (user.ljust(15),str(quota).rjust(15)))
gLogger.info("-"*30)
DIRAC.exit(0)
