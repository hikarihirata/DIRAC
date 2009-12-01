# $HeadURL$
__RCSID__ = "$Id$"
"""  TopErrorMessagesReporter produces a list with the most common errors 
   injected in the SystemLoggingDB and sends a notification to a mailing 
   list and specific users. 
"""

from DIRAC                                           import S_OK, S_ERROR, gConfig
from DIRAC.Core.Base.AgentModule                     import AgentModule
from DIRAC.ConfigurationSystem.Client.PathFinder     import getDatabaseSection
from DIRAC.FrameworkSystem.DB.SystemLoggingDB          import SystemLoggingDB
from DIRAC.FrameworkSystem.Client.NotificationClient import NotificationClient
from DIRAC.Core.Utilities                            import List
from DIRAC.Core.Utilities                            import date, toString, fromString, day, hour

class TopErrorMessagesReporter( AgentModule ):

  def initialize( self ):
     
    self.SystemLoggingDB = SystemLoggingDB()
    
    self.agentName = self.am_getModuleParam( 'fullName' )

    self.notification = NotificationClient()

    mailList = self.am_getOption( "MailList", [] )

    userString = self.am_getOption( "Reviewer", 'mseco' )
    userList = List.fromChar( userString, "," )
    self.log.debug( "Users to be notified", ": " + userString )
    for user in userList:
      retval = gConfig.getOption( "/Registry/Users/" + user + "/email" )
      if not retval['OK']:
        self.log.warn( "Could not get user's mail", retval['Message'] )
      else:
        mailList.append( retval['Value'] )
    
    if not len( mailList ):
      errString = "There are no valid users in the list"
      varString = "[" + ','.join( userList ) + "]"
      self.log.error( errString, varString )
      return S_ERROR( errString + varString )
    
    self.log.info("List of mails to be notified", ','.join(mailList))
    self._mailAddress = mailList
    self._threshold = int( self.am_getOption( 'Threshold', 10 ) )
    
    self.__days = self.am_getOption( 'QueryPeriod',7 )
    self._period=int( self.__days ) * day
    self._limit = int ( self.am_getOption( 'NumberOfErrors', 10 ) )
    
    string = "The %i most common errors in the SystemLoggingDB" %  self._limit
    self._subject = string + " for the last %s days" % self.__days
    return S_OK()

  def execute( self ):
    """ The main agent execution method
    """
    limitDate = date() - self._period
    limitDateString = toString( limitDate )
    tableList = [ "MessageRepository", "FixedTextMessages", "Systems",  
                  "SubSystems" ]
    columnsList = [ "SystemName", "SubSystemName", "count(*) as entries",
                    "FixedTextString" ]
    cmd = "SELECT " + ', '.join( columnsList ) + " FROM " \
          + " NATURAL JOIN ".join( tableList ) \
          + " WHERE MessageTime > '%s'" % limitDate \
          + " GROUP BY FixedTextString HAVING entries > %s" % self._threshold \
          + " ORDER BY entries DESC LIMIT %i;" % self._limit
    
    result = self.SystemLoggingDB._query( cmd )
    if not result['OK']: 
      return result

    messageList = result['Value']

    if messageList == 'None' or messageList == ():
      self.log.warn( 'The DB query returned an empty result' )
      return S_OK()
      
    mailBody ='\n'
    for message in messageList:
      mailBody = mailBody + "Count: "+str(message[2])+"\tError: '"\
                 + message[3] + "'\tSystem: '" + message[0]\
                 + "'\tSubsystem: '" + message[1] + "'\n"

    mailBody = mailBody + "\n\n-------------------------------------------------------\n"\
               + "Please do not reply to this mail. It was automatically\n"\
               + "generated by a Dirac Agent.\n"
                 
    result = self.SystemLoggingDB._getDataFromAgentTable( self.agentName )
    self.log.debug( result )
    if not result['OK']:
      errorString = "Could not get the date when the last mail was sent"
      self.log.error( errorString )
      return S_ERROR( errorString )
    else:
      if len(result['Value']):  
        self.log.debug( "date value: %s" % fromString( result['Value'][0][0][1:-1] ) )
        lastMailSentDate = fromString( result['Value'][0][0][1:-1] )
      else:
        lastMailSentDate = limitDate - 1 * day
        result = self.SystemLoggingDB._insertDataIntoAgentTable( self.agentName, lastMailSentDate )
        if not result['OK']:
          errorString="Could not insert data into the DB"
          self.log.error( errorString, result['Message'] )
          return S_ERROR( errorString + ": " + result['Message'] )

    self.log.debug("limitDate: %s\t" % limitDate \
                   + "lastMailSentDate: %s\n" % lastMailSentDate ) 
    if lastMailSentDate > limitDate:
      self.log.info( "The previous report was sent less "\
                     +" than %s days ago" % self.__days )
      return S_OK()
    
    dateSent = toString( date() )
    self.log.info( "The list with the top errors has been sent" )

    result = self.SystemLoggingDB._insertDataIntoAgentTable( self.agentName, dateSent )
    if not result['OK']:
      errorString="Could not insert data into the DB"
      self.log.error( errorString, result['Message'] )
      return S_ERROR( errorString + ": " + result['Message'] )
      
    result = self.notification.sendMail( self._mailAddress, self._subject, 
                                         mailBody )
    if not result[ 'OK' ]:
      self.log.warn( "The notification could not be sent" )
      return S_OK()

    return S_OK( "The list with the top errors has been sent" )
