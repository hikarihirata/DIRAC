"""
  Defines the plugin to take storage space information given by WLCG Accounting Json
  https://twiki.cern.ch/twiki/bin/view/LCG/AccountingTaskForce#Storage_Space_Accounting
  https://twiki.cern.ch/twiki/pub/LCG/AccountingTaskForce/storage_service_v4.txt
  https://docs.google.com/document/d/1yzCvKpxsbcQC5K9MyvXc-vBF1HGPBk4vhjw3MEXoXf8
"""
import json
import gfal2  # pylint: disable=import-error
import os
import tempfile
import shutil

from DIRAC import gLogger, gConfig
from DIRAC import S_OK, S_ERROR


class WLCGAccountingJson(object):
  """ .. class:: WLCGAccountingJson

  Occupancy plugin to return the space information given by WLCG Accouting Json
  """
  def __init__(self, se):
    self.se = se
    self.log = se.log.getSubLogger('WLCGAccountingJson')
    self.name = self.se.name

  def getOccupancy(self, **kwargs):
    """ Returns the space information given by LCG Accouting Json

        :returns: S_OK with dict (keys: SpaceReservation, Total, Free)
    """
    occupancyLFN = kwargs['occupancyLFN']

    if not occupancyLFN:
      return S_ERROR("Failed to get occupancyLFN")

    tmpDirName = tempfile.mkdtemp()
    filePath = os.path.join(tmpDirName, os.path.basename(occupancyLFN))

    for storage in self.se.storages:
      try:
        ctx = gfal2.creat_context()
        params = ctx.transfer_parameters()
        params.overwrite = True
        res = storage.updateURL(occupancyLFN)
        if not res['OK']:
          continue
        occupancyURL = res['Value']
        ctx.filecopy(params, occupancyURL, 'file://' + filePath)

      except gfal2.GError as e:
        detailMsg = "Failed to copy file %s to destination url %s: [%d] %s" % (
            occupancyURL, filePath, e.code, e.message)
        self.log.debug("Exception while copying", detailMsg)
        continue

      else:
        break

    if not os.path.isfile(filePath):
      return S_ERROR('No WLCGAccountingJson file of %s is downloaded.' % (self.name))

    with open(filePath, 'r') as path:
      occupancyDict = json.load(path)

    # delete temp dir
    shutil.rmtree(tmpDirName)

    try:
      storageShares = occupancyDict['storageservice']['storageshares']
    except KeyError as e:
      return S_ERROR('Could not find %s key in %s at %s' % (str(e), occupancyLFN, self.name))

    # get storageReservation
    spaceReservation = self.se.options.get('SpaceReservation')
    if not spaceReservation:
      self.log.debug(
          'Get SpaceToken in storage parameters instead of SpaceReservation because it is not defined in CS')
      for storage in self.se.storages:
        SEparams = storage.getParameters()
        if not SEparams:
          self.log.debug('Could not get storage parameters at %s' % (self.name))
          continue
        if 'SpaceToken' in SEparams:
          spaceReservation = SEparams['SpaceToken']
          break
        else:
          self.log.debug('Could not find SpaceToken key in storage parameters at %s' % (self.name))
          continue

    # get storageshares in WLCGAccountingJson file
    storageSharesSR = None
    if spaceReservation:
      for storageshare in storageShares:
        if storageshare.get('name') == spaceReservation:
          storageSharesSR = storageshare
          break
    else:
      self.log.debug('Get storageShares, and get spaceReservation in storageShares')
      shareLen = []
      for storage in self.se.storages:
        basePath = storage.getParameters()['Path']
        for share in storageShares:
          shareLen.append((share, len(os.path.commonprefix([share['path'][0], basePath]))))
      storageSharesSR = max(shareLen, key=lambda x: x[1])[0]
      spaceReservation = storageSharesSR.get('name')

    sTokenDict = {}
    sTokenDict['SpaceReservation'] = spaceReservation
    try:
      sTokenDict['Total'] = storageSharesSR['totalsize']
      sTokenDict['Free'] = sTokenDict['Total'] - storageSharesSR['usedsize']
    except KeyError as e:
      return S_ERROR('Could not find %s key in %s storageshares' % (str(e), spaceReservation))

    return S_OK(sTokenDict)
