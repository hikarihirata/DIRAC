"""
  Defines the plugin to take storage space information given by WLCG Accounting Json
  https://twiki.cern.ch/twiki/bin/view/LCG/AccountingTaskForce#Storage_Space_Accounting
  https://twiki.cern.ch/twiki/pub/LCG/AccountingTaskForce/storage_service_v4.txt
  https://docs.google.com/document/d/1yzCvKpxsbcQC5K9MyvXc-vBF1HGPBk4vhjw3MEXoXf8/edit
"""
import json
import gfal2  # pylint: disable=import-error
import os
import tempfile
import shutil

from DIRAC import gLogger, gConfig
from DIRAC import S_OK, S_ERROR


class WLCGAccountingJson2(object):
  """ .. class:: WLCGAccountingJson

  Occupancy plugin to return the space information given by WLCG Accouting Json
  """
  def __init__(self, se):
    self.se = se
    self.log = se.log.getSubLogger('WLCGAccountingJson2')
    self.name = self.se.name
    print self.name

  def getOccupancy(self, **kwargs):
    """ Returns the space information given by LCG Accouting Json

        :returns: S_OK with dict (keys: Total, Free)
    """
    print 'Use Plugin test'
    occupancyLFN = kwargs['occupancyLFN']
    print occupancyLFN
    if not occupancyLFN:
      return S_ERROR("Failed to get LFN of occupancy json file")

    occupancyLFN = '../storagesummary.json'
    SpaceToken = None

    for storage in self.se.storages:
      SEparams = storage.getParameters()
      if not SEparams:
        return res
      baseURL = SEparams['URLBase']
      SpaceToken = SEparams['SpaceToken']
      print SpaceToken

      try:
        tmpDirName = tempfile.mkdtemp()
        ctx = gfal2.creat_context()
        params = ctx.transfer_parameters()
        params.overwrite = True
        occupancyURL = os.path.join(baseURL, occupancyLFN)
        print occupancyURL
        filePath = os.path.join(tmpDirName, os.path.basename(occupancyLFN))
        ctx.filecopy(params, occupancyURL, 'file://' + filePath)
        with open(filePath, 'r') as path:
          occupancyDict = json.load(path)

      except gfal2.GError as e:
        detailMsg = "Failed to copy file %s to destination url %s: [%d] %s" % (
            occupancyURL, filePath, e.code, e.message)
        LOG.debug("Exception while copying", detailMsg)
        continue

      finally:
        # delete temp dir
        shutil.rmtree(tmpDirName)

    if 'storageservice' not in occupancyDict:
      return S_ERROR('Could not find storageservice component in %s at %s' % (occupancyLFN, self.name))
    storageservice = occupancyDict['storageservice']

    if 'storageshares' not in storageservice:
      return S_ERROR('Could not find storageshares component in %s at %s' % (occupancyLFN, self.name))
    storageshares = occupancyDict['storageservice']['storageshares']

    storagesharesST = None
    for key in storageshares:
      if key['name'] != SpaceToken:
        continue
      storagesharesST = key

    if not storagesharesST:
      return S_ERROR('Could not find %s component in storageshares of %s at %s' % (
          self.spacetoken, occupancyLFN, self.name))

    sTokenDict = {}
    if 'totalsize' not in storagesharesST:
      return S_ERROR('Could not find totalsize key in storageshares')
    sTokenDict['Total'] = storagesharesST['totalsize']

    if 'usedsize' not in storagesharesST:
      return S_ERROR('Could not find usedsize key in storageshares')
    sTokenDict['Free'] = sTokenDict['Total'] - storagesharesST['usedsize']

    return S_OK(sTokenDict)