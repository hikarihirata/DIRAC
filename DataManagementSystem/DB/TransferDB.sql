SOURCE DIRAC/RequestManagementSystem/DB/RequestDB.sql

-- THESE ARE THE TABLES FOR THE TRANSFER DB
-- Channels,Channel,FTSReq,FileToFTS,FTSReqLogging,FileToCat,ReplicationTree

DROP TABLE IF EXISTS Channels;
CREATE TABLE Channels (
   ChannelID INTEGER NOT NULL AUTO_INCREMENT,
   SourceSite  varchar(32)  NOT NULL,
   DestinationSite varchar(32) NOT NULL,
   Status varchar(32) NOT NULL,
   ChannelName  varchar(32),
   PRIMARY KEY (ChannelID,SourceSite,DestinationSite)
);

DROP TABLE IF EXISTS Channel;
CREATE TABLE Channel (
  ChannelID INTEGER NOT NULL,
  FileID INTEGER NOT NULL,
  Status VARCHAR(32) NOT NULL,
  SourceSURL varchar(256)  NOT NULL,
  TargetSURL varchar(256)  NOT NULL,
  SpaceToken varchar(32)  NOT NULL,
  FileSize INTEGER NOT NULL,
  Retries INTEGER DEFAULT 0,
  SchedulingTime DATETIME NOT NULL,
  SchedulingTimeOrder DOUBLE(11,3) NOT NULL,
  LastUpdate DATETIME NOT NULL,
  LastUpdateTimeOrder DOUBLE(11,3) NOT NULL,
  CompletionTime DATETIME,
  PRIMARY KEY (ChannelID,FileID)
);

DROP TABLE IF EXISTS FTSReq;
CREATE TABLE FTSReq (
  FTSReqID INTEGER NOT NULL AUTO_INCREMENT,
  ChannelID INTEGER NOT NULL,
  Status varchar(32) DEFAULT 'Submitted',
  FTSGUID varchar(64) NOT NULL,
  FTSServer varchar(255) NOT NULL,
  NumberOfFiles INTEGER DEFAULT 0,
  TotalSize bigint(20) DEFAULT 0,
  SubmitTime datetime NOT NULL,
  LastMonitor datetime,
  PercentageComplete float default 0.0,
  PRIMARY KEY (FTSReqID,ChannelID)
);

DROP TABLE IF EXISTS FileToFTS;
CREATE TABLE FileToFTS (
  FileID INTEGER NOT NULL,
  FTSReqID varchar(64) NOT NULL,
  ChannelID INTEGER NOT NULL,
  Status varchar(32) DEFAULT 'Submitted',
  Duration int(8) DEFAULT 0,
  Reason varchar(511),
  Retries int(8) DEFAULT 0,
  FileSize int(11) DEFAULT 0,
  SubmissionTime datetime,
  TerminalTime datetime,
  PRIMARY KEY (FileID,FTSReqID)
);

DROP TABLE IF EXISTS FTSReqLogging;
CREATE TABLE FTSReqLogging (
  FTSReqID INTEGER NOT NULL,
  Event varchar(100),
  EventDateTime datetime
);

DROP TABLE IF EXISTS FileToCat;
CREATE TABLE FileToCat (
  FileID INTEGER NOT NULL,
  ChannelID INTEGER NOT NULL,
  LFN varchar(255) NOT NULL,
  PFN varchar(255) NOT NULL,
  SE  varchar(255) NOT NULL,
  Status varchar(255) NOT NULL DEFAULT 'Executing',
  SubmitTime  datetime NOT NULL,
  CompleteTime datetime,
  PRIMARY KEY (FileID,ChannelID,Status)
);

DROP TABLE IF EXISTS ReplicationTree;
CREATE TABLE ReplicationTree (
  FileID INTEGER NOT NULL,
  ChannelID INTEGER NOT NULL,
  AncestorChannel varchar(8) NOT NULL,
  Strategy varchar(32),
  CreationTime datetime NOT NULL
);
