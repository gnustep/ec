
#import <Foundation/Foundation.h>

#import "EcAlarm.h"
#import	"EcAlarmDestination.h"
#import	"EcAlarmSinkSNMP.h"
#import "EcProcess.h"

static EcAlarmSinkSNMP	*alarmSink = nil;	// The singleton

@interface	EcAlarmSinkSNMP (Private)

/* Archives the SNMP data to persistent storage so we can re-load it on
 * startup.  Also stores a description of the active alarms for readability.
 */
- (void) _store;

/* Sends the alarm out as an SNMP trap.
 * If forceClear is YES then sends the trap with a cleared severity
 * irrespective of the actual severity stored in the alarm object.
 */
- (void) _trap: (EcAlarm*)alarm forceClear: (BOOL)forceClear;

@end

#include <net-snmp/net-snmp-config.h>
#include <net-snmp/net-snmp-includes.h>
#include <net-snmp/agent/net-snmp-agent-includes.h>
#include <net-snmp/library/snmp_assert.h>

#include <time.h>

static NSString		*persistentStore = nil;
static int32_t		notificationID = 0;
static NSUInteger	managedObjectsCount = 0;
static NSMutableArray	*managedObjects = nil;

static netsnmp_tdata	*alarmsTable = 0;
static netsnmp_tdata	*objectsTable = 0;

/* The following scalar variables are made available via SNMP OIDs.
 * The agent will handle all GET and (if applicable) SET requests
 * to these variables, changing the values as needed.
 */
static int32_t	resyncFlag = 0; 	/* normally not re-syncing */
static int	resyncTimer = 0;	/* seconds since started */
static int32_t	trapSequenceNumber = 0; /* XXX: set default value */
static int32_t	pollHeartBeat = 5;      /* heartbeat every 5 minutes */

/* SNMP data structure for an alarm table row entry
 */
struct alarmsTable_entry
{
  /* Index
   */
  int32_t	notificationID;

  /* Column values
   */
  int32_t	perceivedSeverity;
  char		firstEventDate[32];
  size_t	firstEventDate_len;
  char		eventDate[32];
  size_t	eventDate_len;
  char		managedObject[128];
  size_t	managedObject_len;
  int32_t	ideventType;
  int32_t	idprobableCause;
  char		specificProblem[256];
  size_t	specificProblem_len;
  char		proposedRepairAction[256];
  size_t	proposedRepairAction_len;
  char		additionalText[256];
  size_t	additionalText_len;
  char		trendIndicator[2];
  size_t	trendIndicator_len;

  int		valid;
};

/* SNMP data structure for a managed objects table row entry
 */
struct objectsTable_entry
{
  /* Index
   */
  char            objectId[128];
  size_t          objectId_len;

  int             valid;
};

/*
 * function declarations
 */

static BOOL
heartbeat(time_t now);

static void
init_EcTrapSink(void);

static Netsnmp_Node_Handler alarmsTable_handler;

static Netsnmp_Node_Handler objectsTable_handler;

static netsnmp_tdata_row *
alarmsTable_createEntry(int32_t notificationID);

static int
pollHeartBeat_handler(netsnmp_mib_handler *handler,
  netsnmp_handler_registration *reginfo,
  netsnmp_agent_request_info *reqinfo,
  netsnmp_request_info *requests);

static netsnmp_tdata_row *
objectsTable_createEntry(NSString *objectId);

/*
 * column number definitions for table alarmsTable
 */
#define COLUMN_NOTIFICATIONID		1
#define COLUMN_PERCEIVEDSEVERITY	2
#define COLUMN_FIRSTEVENTDATE		3
#define COLUMN_EVENTDATE		4
#define COLUMN_MANAGEDOBJECT		5
#define COLUMN_IDEVENTTYPE		6
#define COLUMN_IDPROBABLECAUSE		7
#define COLUMN_SPECIFICPROBLEM		8
#define COLUMN_PROPOSEDREPAIRACTION	9
#define COLUMN_ADDITIONALTEXT		10
#define COLUMN_TRENDINDICATOR		11

/*
 * column number definitions for table objectsTable
 */
#define COLUMN_OBJECTID		1


@interface	EcAlarmSinkSNMP (SNMP)

- (BOOL) snmpClearAlarms: (NSString*)managed;

- (void) snmpHousekeeping;

@end




/* alarmTrap stuff
 */
static oid      snmptrap_oid[] = { 1, 3, 6, 1, 6, 3, 1, 1, 4, 1, 0 };

static oid	*additionalText_oid = 0;
static size_t	additionalText_len = 0;
static oid	*alarmsTable_oid = 0;
static size_t	alarmsTable_len = 0;
static oid	*alarmTrap_oid = 0;
static size_t	alarmTrap_len = 0;
static oid	*eventDate_oid = 0;
static size_t	eventDate_len = 0;
static oid	*eventType_oid = 0;
static size_t	eventType_len = 0;
static oid	*firstEventDate_oid = 0;
static size_t	firstEventDate_len = 0;
static oid	*ideventType_oid = 0;
static size_t	ideventType_len = 0;
static oid	*idprobableCause_oid = 0;
static size_t	idprobableCause_len = 0;
static oid	*notificationID_oid = 0;
static size_t	notificationID_len = 0;
static oid	*objectId_oid = 0;
static size_t	objectId_len = 0;
static oid	*objectsTable_oid = 0;
static size_t	objectsTable_len = 0;
static oid	*perceivedSeverity_oid = 0;
static size_t	perceivedSeverity_len = 0;
static oid	*pollHeartBeat_oid = 0;
static size_t	pollHeartBeat_len = 0;
static oid	*proposedRepairAction_oid = 0;
static size_t	proposedRepairAction_len = 0;
static oid	*resyncFlag_oid = 0;
static size_t	resyncFlag_len = 0;
static oid	*specificProblem_oid = 0;
static size_t	specificProblem_len = 0;
static oid	*trapSequenceNumber_oid = 0;
static size_t	trapSequenceNumber_len = 0;
static oid	*trendIndicator_oid = 0;
static size_t	trendIndicator_len = 0;


static const char *
stringFromDate(NSDate *d)
{
  NSCalendarDate	*c;

  c = [NSCalendarDate dateWithTimeIntervalSinceReferenceDate:
    [d timeIntervalSinceReferenceDate]];
  [c setCalendarFormat: @"%Y%m%d %H:%M:%S"];
  return [[c description] UTF8String];
}

/* Function to send heartbeat alarm iff the pollHeartBeat interval has passed.
 */
static BOOL
heartbeat(time_t now)
{
  static time_t		last = 0;
  struct tm		*t;
  char			timestamp[18];
  netsnmp_variable_list	*var_list = NULL;
  const char		*trapName = "HEARTBEAT TRAP";
  const int32_t	cause = 0;
  const int32_t	notification = 0;
  const int32_t	severity = 4;
  const int32_t	eventType = 2;

  /* Build current timestamp and send a heartbeat
   */
  now = time(0);
  if (((now - last) / 60) < pollHeartBeat)
    {
      return NO;	/* Not yet time for a heartbeat */
    }
  last = now;
  t = gmtime(&now);
  sprintf(timestamp, "%04d%02d%02d %02d:%02d:%02d",
    t->tm_year + 1900, t->tm_mon + 1, t->tm_mday,
    t->tm_hour, t->tm_min, t->tm_sec);

  /*
   * Set the snmpTrapOid.0 value
   */
  snmp_varlist_add_variable(&var_list,
			    snmptrap_oid, OID_LENGTH(snmptrap_oid),
			    ASN_OBJECT_ID,
			    (u_char*)alarmTrap_oid,
			    alarmTrap_len * sizeof(oid));

  if (++trapSequenceNumber <= 0) trapSequenceNumber = 1;
  snmp_varlist_add_variable(&var_list,
			    trapSequenceNumber_oid,
			    trapSequenceNumber_len,
			    ASN_INTEGER,
			    (u_char*)&trapSequenceNumber,
			    sizeof(trapSequenceNumber));

  snmp_varlist_add_variable(&var_list,
			    notificationID_oid,
			    notificationID_len, ASN_INTEGER,
			    (u_char*)&notification, /* Special for heartbeat */
			    sizeof(notification));

  snmp_varlist_add_variable(&var_list,
			    perceivedSeverity_oid,
			    perceivedSeverity_len,
			    ASN_INTEGER,
			    (u_char*)&severity,	/* warning */
			    sizeof(severity));

  snmp_varlist_add_variable(&var_list,
			    firstEventDate_oid,
			    firstEventDate_len,
			    ASN_OCTET_STR,
			    0,	/* not required */
			    0);

  snmp_varlist_add_variable(&var_list,
			    eventDate_oid, eventDate_len,
			    ASN_OCTET_STR,
			    (u_char*)timestamp,
			    strlen(timestamp));

  snmp_varlist_add_variable(&var_list,
			    objectId_oid, objectId_len,
			    ASN_OCTET_STR,
			    0,	/* not required */
			    0);

  snmp_varlist_add_variable(&var_list,
			    ideventType_oid, ideventType_len,
			    ASN_INTEGER,
			    (u_char*)&eventType,	/* heartbeat */
			    sizeof(eventType));

  snmp_varlist_add_variable(&var_list,
			    idprobableCause_oid,
			    idprobableCause_len, ASN_INTEGER,
			    (u_char*)&cause,
			    sizeof(cause));

  snmp_varlist_add_variable(&var_list,
			    specificProblem_oid,
			    specificProblem_len,
			    ASN_OCTET_STR,
			    0,	/* not required */
			    0);

  snmp_varlist_add_variable(&var_list,
			    proposedRepairAction_oid,
			    proposedRepairAction_len,
			    ASN_OCTET_STR,
			    0,	/* not required */
			    0);

  snmp_varlist_add_variable(&var_list,
			    additionalText_oid,
			    additionalText_len,
			    ASN_OCTET_STR,
			    (u_char*)trapName,
			    strlen(trapName));

  snmp_varlist_add_variable(&var_list,
			    trendIndicator_oid,
			    trendIndicator_len,
			    ASN_OCTET_STR,
			    0,	/* not required */
			    0);
  /*
   * Send the trap to the list of configured destinations
   *  and clean up
   */
  DEBUGMSGTL(("EcTrapSink", "Sending heartbeat trap.\n"));
  send_v2trap(var_list);
  snmp_free_varbind(var_list);
  return YES;
}

static void
setAlarmTableEntry(netsnmp_tdata_row *row, EcAlarm *alarm)
{
  struct alarmsTable_entry	*e;
  const char			*s;

  [alarm setExtra: (void*)row];
  [alarm freeze];		// Once it's in the snmp table, no more change
  e = (struct alarmsTable_entry *)row->data;

  e->notificationID = [alarm notificationID];

  e->perceivedSeverity = [alarm perceivedSeverity];

  s = stringFromDate([alarm firstEventDate]);
  strcpy(e->firstEventDate, s);
  e->firstEventDate_len = strlen(s);

  s = stringFromDate([alarm eventDate]);
  strcpy(e->eventDate, s);
  e->eventDate_len = strlen(s);

  s = [[alarm managedObject] UTF8String];
  strcpy(e->managedObject, s);
  e->managedObject_len = strlen(s);

  e->ideventType = [alarm eventType];

  e->idprobableCause = [alarm probableCause];

  s = [[alarm specificProblem] UTF8String];
  strcpy(e->specificProblem, s);
  e->specificProblem_len = strlen(s);

  s = [[alarm proposedRepairAction] UTF8String];
  strcpy(e->proposedRepairAction, s);
  e->proposedRepairAction_len = strlen(s);

  s = [[alarm additionalText] UTF8String];
  strcpy(e->additionalText, s);
  e->additionalText_len = strlen(s);

  e->trendIndicator[0] = [alarm trendIndicator];
  if (0 == e->trendIndicator[0])
    {
      e->trendIndicator_len = 0;
    }
  else
    {
      e->trendIndicator_len = 1;
      e->trendIndicator[1] = 0;
    }
}

/* Regular timer called at one second intervals to check for updates from
 * alarm sources, update SNMP tables, generate alerts, and send heartbeats
 */
static void
housekeeping(unsigned int clientreg, void *clientarg)
{
  if (0 == resyncFlag)
    {
      resyncTimer = 0;
    }
  else
    {
      /* We automatically leave resync mode after five minutes (300 seconds)
       * if resync mode has not been turned off via SNMP.
       */
      if (300 <= ++resyncTimer)
	{
	  resyncTimer = 0;
	  resyncFlag = 0;
	}
    }
  [alarmSink snmpHousekeeping];
}


static void
init_EcTrapSink(void)
{
  netsnmp_handler_registration		*reg;
  netsnmp_table_registration_info	*tinfo;
  netsnmp_watcher_info			*winfo;
  NSString				*oidString;
  NSUserDefaults			*defaults;
  NSArray				*array;
  oid					*oids;
  int					len;
  int					i;

  defaults = [NSUserDefaults standardUserDefaults];
  /* First convert the trap OID from dotted integer format to an array
   * of net-snmp oid values.
   */
  oidString = [defaults stringForKey: @"TrapOID"];
  if (nil == oidString) oidString = @"1.3.6.1.4.1.37374.3.0.1";
  array = [oidString componentsSeparatedByString: @"."];
  alarmTrap_len = [array count];
  alarmTrap_oid = (oid*)malloc(sizeof(oid) * alarmTrap_len);
  for (i = 0; i < alarmTrap_len; i++)
    {
      alarmTrap_oid[i] = [[array objectAtIndex: i] intValue];
    }
  
  /* Now use the dotted integer format 'alarms' OID as the basis to set up
   * all the alarm data OIDs.
   */
  oidString = [defaults stringForKey: @"AlarmsOID"];
  if (nil == oidString) oidString = @"1.3.6.1.4.1.37374.1";
  array = [oidString componentsSeparatedByString: @"."];
  len = [array count];
  oids = (oid*)malloc(sizeof(oid) * (len + 2));
  for (i = 0; i < len; i++)
    {
      oids[i] = [[array objectAtIndex: i] intValue];
    }
  oids[len] = 0;	// alarmsTable
  oids[len+1] = 0;	// alarmsEntry

  alarmsTable_len = len + 2;
  alarmsTable_oid = (oid*)malloc(sizeof(oid) * alarmsTable_len);
  memcpy(alarmsTable_oid, oids, sizeof(oid) * (len + 2));

  resyncFlag_len = len + 1;
  resyncFlag_oid = (oid*)malloc(sizeof(oid) * resyncFlag_len);
  memcpy(resyncFlag_oid, oids, sizeof(oid) * len);
  resyncFlag_oid[len] = 2;

  trapSequenceNumber_len = len + 1;
  trapSequenceNumber_oid = (oid*)malloc(sizeof(oid) * trapSequenceNumber_len);
  memcpy(trapSequenceNumber_oid, oids, sizeof(oid) * len);
  trapSequenceNumber_oid[len] = 3;

  pollHeartBeat_len = len + 1;
  pollHeartBeat_oid = (oid*)malloc(sizeof(oid) * pollHeartBeat_len);
  memcpy(pollHeartBeat_oid, oids, sizeof(oid) * len);
  pollHeartBeat_oid[len] = 4;

  notificationID_len = len + 3;
  notificationID_oid = (oid*)malloc(sizeof(oid) * notificationID_len);
  memcpy(notificationID_oid, oids, sizeof(oid) * (len + 2));
  notificationID_oid[len+2] = 1;

  perceivedSeverity_len = len + 3;
  perceivedSeverity_oid = (oid*)malloc(sizeof(oid) * perceivedSeverity_len);
  memcpy(perceivedSeverity_oid, oids, sizeof(oid) * (len + 2));
  perceivedSeverity_oid[len+2] = 2;

  firstEventDate_len = len + 3;
  firstEventDate_oid = (oid*)malloc(sizeof(oid) * firstEventDate_len);
  memcpy(firstEventDate_oid, oids, sizeof(oid) * (len + 2));
  firstEventDate_oid[len+2] = 3;

  eventDate_len = len + 3;
  eventDate_oid = (oid*)malloc(sizeof(oid) * eventDate_len);
  memcpy(eventDate_oid, oids, sizeof(oid) * (len + 2));
  eventDate_oid[len+2] = 4;

  eventType_len = len + 3;
  eventType_oid = (oid*)malloc(sizeof(oid) * eventType_len);
  memcpy(eventType_oid, oids, sizeof(oid) * (len + 2));
  eventType_oid[len+2] = 6;

  idprobableCause_len = len + 3;
  idprobableCause_oid = (oid*)malloc(sizeof(oid) * idprobableCause_len);
  memcpy(idprobableCause_oid, oids, sizeof(oid) * (len + 2));
  idprobableCause_oid[len+2] = 7;

  specificProblem_len = len + 3;
  specificProblem_oid = (oid*)malloc(sizeof(oid) * specificProblem_len);
  memcpy(specificProblem_oid, oids, sizeof(oid) * (len + 2));
  specificProblem_oid[len+2] = 8;

  proposedRepairAction_len = len + 3;
  proposedRepairAction_oid
    = (oid*)malloc(sizeof(oid) * proposedRepairAction_len);
  memcpy(proposedRepairAction_oid, oids, sizeof(oid) * (len + 2));
  proposedRepairAction_oid[len+2] = 9;

  additionalText_len = len + 3;
  additionalText_oid = (oid*)malloc(sizeof(oid) * additionalText_len);
  memcpy(additionalText_oid, oids, sizeof(oid) * (len + 2));
  additionalText_oid[len+2] = 10;

  trendIndicator_len = len + 3;
  trendIndicator_oid = (oid*)malloc(sizeof(oid) * trendIndicator_len);
  memcpy(trendIndicator_oid, oids, sizeof(oid) * (len + 2));
  trendIndicator_oid[len+2] = 11;

  free(oids);
  oidString = [defaults stringForKey: @"ObjectsOID"];
  if (nil == oidString) oidString = @"1.3.6.1.4.1.37374.2";
  array = [oidString componentsSeparatedByString: @"."];
  len = [array count];
  objectId_len = len + 3;
  objectId_oid = (oid*)malloc(sizeof(oid) * objectId_len);
  for (i = 0; i < len; i++)
    {
      objectId_oid[i] = [[array objectAtIndex: i] intValue];
    }
  objectId_oid[len] = 1;	// objectsTable
  objectId_oid[len+1] = 1;	// objectsEntry
  objectId_oid[len+2] = 1;	// objectId

  objectsTable_len = len + 1;
  objectsTable_oid = (oid*)malloc(sizeof(oid) * objectsTable_len);
  memcpy(objectsTable_oid, objectId_oid, sizeof(oid) * (len + 1));

  /* Create the managed objects table as a read-only item for SNMP.
   */
  reg = netsnmp_create_handler_registration(
    "objectsTable",
    objectsTable_handler,
    objectsTable_oid,
    objectsTable_len,
    HANDLER_CAN_RONLY);
  objectsTable = netsnmp_tdata_create_table("objectsTable", 0);
  tinfo = SNMP_MALLOC_TYPEDEF(netsnmp_table_registration_info);
  netsnmp_table_helper_add_indexes(tinfo,
    ASN_OCTET_STR, /* index: objectId */
    0);
  tinfo->min_column = COLUMN_OBJECTID;
  tinfo->max_column = COLUMN_OBJECTID;
  netsnmp_tdata_register(reg, objectsTable, tinfo);

  /* Create the alarms table as a red-only item for SNMP.
   */
  reg = netsnmp_create_handler_registration(
    "alarmsTable",
    alarmsTable_handler,
    alarmsTable_oid,
    alarmsTable_len,
    HANDLER_CAN_RONLY);
  alarmsTable = netsnmp_tdata_create_table("alarmsTable", 0);
  tinfo = SNMP_MALLOC_TYPEDEF(netsnmp_table_registration_info);
  netsnmp_table_helper_add_indexes(tinfo,
    ASN_INTEGER,   /* index: notificationID */
    0);
  tinfo->min_column = COLUMN_NOTIFICATIONID;
  tinfo->max_column = COLUMN_TRENDINDICATOR;
  netsnmp_tdata_register(reg, alarmsTable, tinfo);

  /* Register scalar watchers for each of the MIB objects.
   */
  reg = netsnmp_create_handler_registration(
    "resyncFlag",
    NULL,
    resyncFlag_oid,
    resyncFlag_len,
    HANDLER_CAN_RWRITE);
  winfo = netsnmp_create_watcher_info(&resyncFlag,
    sizeof(int32_t), ASN_INTEGER, WATCHER_FIXED_SIZE);
  if (netsnmp_register_watched_scalar(reg, winfo) < 0)
    {
      snmp_log(LOG_ERR, "Failed to register watched resyncFlag");
    }

  reg = netsnmp_create_handler_registration(
    "trapSequenceNumber",
    NULL,
    trapSequenceNumber_oid,
    trapSequenceNumber_len,
    HANDLER_CAN_RONLY);
  winfo = netsnmp_create_watcher_info(&trapSequenceNumber,
    sizeof(int32_t), ASN_INTEGER, WATCHER_FIXED_SIZE);
  if (netsnmp_register_watched_scalar(reg, winfo) < 0)
    {
      snmp_log(LOG_ERR, "Failed to register watched trapSequenceNumber");
    }

  reg = netsnmp_create_handler_registration(
    "pollHeartBeat",
    pollHeartBeat_handler,
    pollHeartBeat_oid,
    pollHeartBeat_len,
    HANDLER_CAN_RWRITE);
  winfo = netsnmp_create_watcher_info(&pollHeartBeat,
    sizeof(int32_t), ASN_INTEGER, WATCHER_FIXED_SIZE);
  if (netsnmp_register_watched_scalar(reg, winfo) < 0)
    {
      snmp_log(LOG_ERR, "Failed to register watched pollHeartBeat");
    }

  /* get alarms at one second intervals to do housekeeping.
   */
  snmp_alarm_register(1, SA_REPEAT, housekeeping, NULL);
}



/*
 * create a new row in the table
 */
static netsnmp_tdata_row *
alarmsTable_createEntry(int32_t notificationID)
{
  struct alarmsTable_entry	*entry;
  netsnmp_tdata_row		*row;

  entry = SNMP_MALLOC_TYPEDEF(struct alarmsTable_entry);
  if (!entry)
    {
      return NULL;
    }
  row = netsnmp_tdata_create_row();
  if (!row)
    {
      SNMP_FREE(entry);
      return NULL;
    }
  row->data = entry;
  entry->notificationID = notificationID;
  netsnmp_tdata_row_add_index(row,
    ASN_INTEGER, &(entry->notificationID), sizeof(entry->notificationID));
  netsnmp_tdata_add_row(alarmsTable, row);
  return row;
}


static int
pollHeartBeat_handler(netsnmp_mib_handler *handler,
  netsnmp_handler_registration *reginfo,
  netsnmp_agent_request_info *reqinfo,
  netsnmp_request_info *requests)
{
  int32_t	*pollHeartBeat_cache = NULL;
  int32_t	tmp;

  DEBUGMSGTL(("EcTrapSink", "Got instance request:\n"));

  switch (reqinfo->mode)
    {
      case MODE_GET:
	snmp_set_var_typed_value(requests->requestvb, ASN_INTEGER,
	  (u_char*) &pollHeartBeat, sizeof(pollHeartBeat));
	break;

      case MODE_SET_RESERVE1:
	if (requests->requestvb->type != ASN_INTEGER)
	  netsnmp_set_request_error(reqinfo, requests, SNMP_ERR_WRONGTYPE);
	break;

      case MODE_SET_RESERVE2:
	/*
	 * store old info for undo later 
	 */
	memdup((u_char**)&pollHeartBeat_cache,
	  (u_char*)&pollHeartBeat, sizeof(pollHeartBeat));
	if (pollHeartBeat_cache == NULL)
	  {
	    netsnmp_set_request_error(reqinfo, requests,
	      SNMP_ERR_RESOURCEUNAVAILABLE);
	    return SNMP_ERR_NOERROR;
	  }
	netsnmp_request_add_list_data(requests,
				      netsnmp_create_data_list
				      ("EcTrapSink",
				       pollHeartBeat_cache, free));
	break;

      case MODE_SET_ACTION:
	/*
	 * update current 
	 */
	tmp = *(requests->requestvb->val.integer);
	if (tmp > 0)
	  {
	    pollHeartBeat = tmp;
	    [alarmSink _store];
	    DEBUGMSGTL(("EcTrapSink", "updated pollHeartBeat -> %d\n", tmp));
	  }
	else
	  {
	    DEBUGMSGTL(("EcTrapSink", "ignored pollHeartBeat -> %d\n", tmp));
	    netsnmp_set_request_error(reqinfo, requests, SNMP_ERR_WRONGVALUE);
	  }
	break;

      case MODE_SET_UNDO:
	pollHeartBeat =
	  *((int32_t*)netsnmp_request_get_list_data(requests, "EcTrapSink"));
	break;

      case MODE_SET_COMMIT:
      case MODE_SET_FREE:
	/*
	 * nothing to do 
	 */
	break;
    }

  return SNMP_ERR_NOERROR;
}

/** handles requests for the alarmsTable table */
static int
alarmsTable_handler(netsnmp_mib_handler *handler,
                    netsnmp_handler_registration *reginfo,
                    netsnmp_agent_request_info *reqinfo,
                    netsnmp_request_info *requests)
{
  netsnmp_request_info		*request;
  netsnmp_table_request_info	*table_info;
  struct alarmsTable_entry	*table_entry;

  switch (reqinfo->mode)
    {
      /*
       * Read-support (also covers GetNext requests)
       */
      case MODE_GET:
	for (request = requests; request; request = request->next)
	  {
	    table_entry = (struct alarmsTable_entry *)
		netsnmp_tdata_extract_entry(request);
	    table_info = netsnmp_extract_table_info(request);

	    switch (table_info->colnum)
	      {
		case COLUMN_NOTIFICATIONID:
		  if (!table_entry)
		    {
		      netsnmp_set_request_error(reqinfo, request,
						SNMP_NOSUCHINSTANCE);
		      continue;
		    }
		  snmp_set_var_typed_integer(request->requestvb, ASN_INTEGER,
					     table_entry->notificationID);
		  break;

		case COLUMN_PERCEIVEDSEVERITY:
		  if (!table_entry)
		    {
		      netsnmp_set_request_error(reqinfo, request,
						SNMP_NOSUCHINSTANCE);
		      continue;
		    }
		  snmp_set_var_typed_integer(request->requestvb, ASN_INTEGER,
					     table_entry->perceivedSeverity);
		  break;

		case COLUMN_FIRSTEVENTDATE:
		  if (!table_entry)
		    {
		      netsnmp_set_request_error(reqinfo, request,
						SNMP_NOSUCHINSTANCE);
		      continue;
		    }
		  snmp_set_var_typed_value(request->requestvb, ASN_OCTET_STR,
					   (u_char *) table_entry->
					   firstEventDate,
					   table_entry->firstEventDate_len);
		  break;

		case COLUMN_EVENTDATE:
		  if (!table_entry)
		    {
		      netsnmp_set_request_error(reqinfo, request,
						SNMP_NOSUCHINSTANCE);
		      continue;
		    }
		  snmp_set_var_typed_value(request->requestvb, ASN_OCTET_STR,
					   (u_char *) table_entry->eventDate,
					   table_entry->eventDate_len);
		  break;

		case COLUMN_MANAGEDOBJECT:
		  if (!table_entry)
		    {
		      netsnmp_set_request_error(reqinfo, request,
						SNMP_NOSUCHINSTANCE);
		      continue;
		    }
		  snmp_set_var_typed_value(request->requestvb, ASN_OCTET_STR,
					   (u_char *) table_entry->
					   managedObject,
					   table_entry->managedObject_len);
		  break;

		case COLUMN_IDEVENTTYPE:
		  if (!table_entry)
		    {
		      netsnmp_set_request_error(reqinfo, request,
						SNMP_NOSUCHINSTANCE);
		      continue;
		    }
		  snmp_set_var_typed_integer(request->requestvb, ASN_INTEGER,
					     table_entry->ideventType);
		  break;

		case COLUMN_IDPROBABLECAUSE:
		  if (!table_entry)
		    {
		      netsnmp_set_request_error(reqinfo, request,
						SNMP_NOSUCHINSTANCE);
		      continue;
		    }
		  snmp_set_var_typed_integer(request->requestvb, ASN_INTEGER,
					     table_entry->idprobableCause);
		  break;

		case COLUMN_SPECIFICPROBLEM:
		  if (!table_entry)
		    {
		      netsnmp_set_request_error(reqinfo, request,
						SNMP_NOSUCHINSTANCE);
		      continue;
		    }
		  snmp_set_var_typed_value(request->requestvb, ASN_OCTET_STR,
					   (u_char *) table_entry->
					   specificProblem,
					   table_entry->specificProblem_len);
		  break;

		case COLUMN_PROPOSEDREPAIRACTION:
		  if (!table_entry)
		    {
		      netsnmp_set_request_error(reqinfo, request,
						SNMP_NOSUCHINSTANCE);
		      continue;
		    }
		  snmp_set_var_typed_value(request->requestvb, ASN_OCTET_STR,
					   (u_char *) table_entry->
					   proposedRepairAction,
					   table_entry->
					   proposedRepairAction_len);
		  break;

		case COLUMN_ADDITIONALTEXT:
		  if (!table_entry)
		    {
		      netsnmp_set_request_error(reqinfo, request,
						SNMP_NOSUCHINSTANCE);
		      continue;
		    }
		  snmp_set_var_typed_value(request->requestvb, ASN_OCTET_STR,
					   (u_char *) table_entry->
					   additionalText,
					   table_entry->additionalText_len);
		  break;

		case COLUMN_TRENDINDICATOR:
		  if (!table_entry)
		    {
		      netsnmp_set_request_error(reqinfo, request,
						SNMP_NOSUCHINSTANCE);
		      continue;
		    }
		  snmp_set_var_typed_value(request->requestvb, ASN_OCTET_STR,
					   (u_char *) table_entry->
					   trendIndicator,
					   table_entry->trendIndicator_len);
		  break;

		default:
		  netsnmp_set_request_error(reqinfo, request,
					    SNMP_NOSUCHOBJECT);
		  break;
	      }
	  }
	break;
    }
  return SNMP_ERR_NOERROR;
}

/*
 * create a new row in the table
 */
static netsnmp_tdata_row *
objectsTable_createEntry(NSString *objectId)
{
  struct objectsTable_entry	*entry;
  netsnmp_tdata_row		*row;
  const char			*str;

  entry = SNMP_MALLOC_TYPEDEF(struct objectsTable_entry);
  if (!entry)
    {
      return NULL;
    }
  row = netsnmp_tdata_create_row();
  if (!row)
    {
      SNMP_FREE(entry);
      return NULL;
    }
  row->data = entry;
  str = [objectId UTF8String];
  entry->objectId_len = strlen(str);
  strcpy(entry->objectId, str);
  netsnmp_tdata_row_add_index(row, ASN_OCTET_STR,
    entry->objectId, entry->objectId_len);
  netsnmp_tdata_add_row(objectsTable, row);
  return row;
}


/** handles requests for the objectsTable table */
static int
objectsTable_handler(netsnmp_mib_handler *handler,
                     netsnmp_handler_registration *reginfo,
                     netsnmp_agent_request_info *reqinfo,
                     netsnmp_request_info *requests)
{
  netsnmp_request_info		*request;
  netsnmp_table_request_info	*table_info;
  struct objectsTable_entry	*table_entry;

  switch (reqinfo->mode)
    {
      /*
       * Read-support (also covers GetNext requests)
       */
      case MODE_GET:
	for (request = requests; request; request = request->next)
	  {
	    table_entry = (struct objectsTable_entry *)
		netsnmp_tdata_extract_entry(request);
	    table_info = netsnmp_extract_table_info(request);

	    switch (table_info->colnum)
	      {
		case COLUMN_OBJECTID:
		  if (!table_entry)
		    {
		      netsnmp_set_request_error(reqinfo, request,
						SNMP_NOSUCHINSTANCE);
		      continue;
		    }
		  snmp_set_var_typed_value(request->requestvb, ASN_OCTET_STR,
					   (u_char *) table_entry->objectId,
					   table_entry->objectId_len);
		  break;

		default:
		  netsnmp_set_request_error(
		    reqinfo, request, SNMP_NOSUCHOBJECT);
		  break;
	      }
	  }
	break;
    }
  return SNMP_ERR_NOERROR;
}




static NSLock	*classLock = nil;

@implementation	EcAlarmSinkSNMP

+ (EcAlarmSinkSNMP*) alarmSinkSNMP
{
  EcAlarmSinkSNMP	*sink;

  [classLock lock];
  sink = [alarmSink retain];
  [classLock unlock];
  if (nil == sink)
    {
      sink = [self new];
    }
  return [sink autorelease];
}

+ (void) initialize
{
  if (nil == classLock)
    {
      classLock = [NSLock new];
    }
}

- (id) init
{
  [classLock lock];
  if (nil == alarmSink)
    {
      alarmSink = self = [super init];
    }
  else
    {
      [self release];
      self = [alarmSink retain];
    }
  [classLock unlock];
  return self;
}

- (id) initWithHost: (NSString*)host name: (NSString*)name
{
  [classLock lock];
  if (nil == alarmSink)
    {
      alarmSink = self = [super initWithHost: host name: name];
    }
  else
    {
      [self release];
      self = [alarmSink retain];
    }
  [classLock unlock];
  return self;
}

- (void) run
{
  NSAutoreleasePool	*pool = [NSAutoreleasePool new];
  NSString		*p;
  NSDictionary		*d;

  snmp_enable_calllog();
  snmp_enable_stderrlog();

  /* Make us an agentx client.
   */
  netsnmp_ds_set_boolean(NETSNMP_DS_APPLICATION_ID, NETSNMP_DS_AGENT_ROLE, 1);

  /* Initialize tcpip, if necessary
   */
  SOCK_STARTUP;

  /* Initialize the agent library to use the standard agentx port
   */
  if (nil == _host || [_host isEqual: @""] || [_host isEqual: @"*"])
    {
      ASSIGN(_host, @"localhost");	// Local host
    }
  if (nil == _name || [_name isEqual: @""] || [_name isEqual: @"*"])
    {
      ASSIGN(_name, @"705");		// Standard Agent-X port
    }
  p = [NSString stringWithFormat: @"tcp:%@:%@", _host, _name];
  netsnmp_ds_set_string(NETSNMP_DS_APPLICATION_ID,
    NETSNMP_DS_AGENT_X_SOCKET, [p UTF8String]);
  if (0 != init_agent("EcTrapSink"))
    {
      NSLog(@"Unable to initialise EcTrapSink as an SNMP sub-agent");
    }

  /* Initialize MIB code here
   */
  init_EcTrapSink();

  /* Will read ecAlarmSinkSNMP.conf files.
   */
  init_snmp("EcAlarmSinkSNMP");

  /* Populate tables and set scalar values from  contents of files.
   */
  p = [[EcProc cmdDataDirectory] stringByAppendingPathComponent: @"SNMP.plist"];
  persistentStore = [p copy];
  if ([[NSFileManager defaultManager] isReadableFileAtPath: p] == YES
    && (d = [NSDictionary dictionaryWithContentsOfFile: p]) != nil)
    {
      NSData		*archive;
      NSEnumerator	*enumerator;
      EcAlarm		*alarm;
      NSString		*name;

      /* get trap and notification numbers.
       */
      trapSequenceNumber = [[d objectForKey: @"TrapSequence"] intValue];
      notificationID = [[d objectForKey: @"NotificationID"] intValue];
      pollHeartBeat = [[d objectForKey: @"PollheartBeat"] intValue];
      if (pollHeartBeat < 1) pollHeartBeat = 5;

      /* Get managed objects table and copy it into SNMP table structure.
       */
      managedObjects = [[d objectForKey: @"ManagedObjects"] mutableCopy];
      enumerator = [managedObjects objectEnumerator];
      while (nil != (name = [enumerator nextObject]))
	{
	  objectsTable_createEntry(name);
	}

      /* Get archived current alarms and add them to the active SNMP table.
       */
      archive = [[d objectForKey: @"AlarmsActive"] mutableCopy];
      if (nil != archive)
	{
	  _alarmsActive
	    = [[NSUnarchiver unarchiveObjectWithData: archive] retain];
	}
      enumerator = [_alarmsActive objectEnumerator];
      while (nil != (alarm = [enumerator nextObject]))
	{
	  static netsnmp_tdata_row *row;

	  row = alarmsTable_createEntry([alarm notificationID]);
	  setAlarmTableEntry(row, alarm);
	}
    }
  if (nil == managedObjects)
    {
      managedObjects = [NSMutableArray new];
    }
  managedObjectsCount = [managedObjects count];
  if (nil == _alarmsActive)
    {
      _alarmsActive = [NSMutableSet new];
    }
  [pool release];
  pool = [NSAutoreleasePool new];

  snmp_log(LOG_INFO,"Control-SNMP-agent is up and running.\n");

  _isRunning = YES;
  while (NO == _shouldStop)
    {
      agent_check_and_process(1); /* 0 == don't block */
      [pool release];
      pool = [NSAutoreleasePool new];
    }
  [pool release];

  /* at shutdown time */
  snmp_shutdown("EcTrapSink");
  _isRunning = NO;
  SOCK_CLEANUP;
}

- (void) setBackups: (NSArray*)backups
{
  if (nil != backups)
    {
      [NSException raise: NSInvalidArgumentException
	format: @"Calling -setBackups: for a sink is not allowed"];
    }
}

- (id<EcAlarmDestination>) setDestination: (id<EcAlarmDestination>)destination
{
  if (nil != destination)
    {
      [NSException raise: NSInvalidArgumentException
	format: @"Calling -setDestination: for a sink is not allowed"];
    }
  return nil;
}

@end

@implementation	EcAlarmSinkSNMP (Private)

- (void) _store
{
  NSMutableDictionary	*d;

  [_alarmLock lock];
  NS_DURING
    {
      d = [NSMutableDictionary dictionaryWithCapacity: 6];
      [d setObject: [NSNumber numberWithInt: notificationID]
	    forKey: @"NotificationID"];
      [d setObject: [NSNumber numberWithInt: trapSequenceNumber]
	    forKey: @"TrapSequence"];
      [d setObject: [NSNumber numberWithInt: pollHeartBeat]
	    forKey: @"PollHeartBeat"];
      [d setObject: managedObjects
	    forKey: @"ManagedObjects"];
      [d setObject: [NSArchiver archivedDataWithRootObject: _alarmsActive]
	    forKey: @"AlarmsActive"];
      [d setObject: _alarmsActive
	    forKey: @"AlarmsDescription"];
      [d writeToFile: persistentStore atomically: YES];
      [_alarmLock unlock];
    }
  NS_HANDLER
    {
      [_alarmLock unlock];
      NSLog(@"Problem storing alarm data to disk ... %@", localException);
    }
  NS_ENDHANDLER
}

- (void) _trap: (EcAlarm*)alarm forceClear: (BOOL)forceClear
{
  NSAutoreleasePool	*pool = [NSAutoreleasePool new];
  netsnmp_variable_list *var_list = NULL;
  int32_t		i;
  const char		*s;
  char			ti[2];

  /*
   * Set the snmpTrapOid.0 value
   */
  snmp_varlist_add_variable(
    &var_list,
    snmptrap_oid,
    OID_LENGTH(snmptrap_oid),
    ASN_OBJECT_ID,
    (u_char*)alarmTrap_oid,
    alarmTrap_len * sizeof(oid));

  /*
   * Add any objects from the trap definition
   */
  if (++trapSequenceNumber <= 0) trapSequenceNumber = 1;
  snmp_varlist_add_variable(
    &var_list,
    trapSequenceNumber_oid,
    trapSequenceNumber_len,
    ASN_INTEGER,
    (u_char*)&trapSequenceNumber,
    sizeof(trapSequenceNumber));

  i = (int32_t)[alarm notificationID];
  snmp_varlist_add_variable(
    &var_list,
    notificationID_oid,
    notificationID_len,
    ASN_INTEGER,
    (u_char*)&i, sizeof(i));

  if (YES == forceClear)
    {
      i = EcAlarmSeverityCleared;
    }
  else
    {
      i = (int32_t)[alarm perceivedSeverity];
    }
  snmp_varlist_add_variable(
    &var_list,
    perceivedSeverity_oid,
    perceivedSeverity_len,
    ASN_INTEGER,
    (u_char*)&i, sizeof(i));

  s = stringFromDate([alarm firstEventDate]);
  snmp_varlist_add_variable(
    &var_list,
    firstEventDate_oid,
    firstEventDate_len,
    ASN_OCTET_STR,
    (u_char*)s, strlen(s));

  s = stringFromDate([alarm eventDate]);
  snmp_varlist_add_variable(
    &var_list,
    eventDate_oid,
    eventDate_len,
    ASN_OCTET_STR,
    (u_char*)s, strlen(s));

  s = [[alarm managedObject] UTF8String];
  snmp_varlist_add_variable(
    &var_list,
    objectId_oid,
    objectId_len,
    ASN_OCTET_STR,
    (u_char*)s, strlen(s));

  i = (int32_t)[alarm eventType];
  snmp_varlist_add_variable(
    &var_list,
    ideventType_oid,
    ideventType_len,
    ASN_INTEGER,
    (u_char*)&i, sizeof(i));

  i = (int32_t)[alarm probableCause];
  snmp_varlist_add_variable(
    &var_list,
    idprobableCause_oid,
    idprobableCause_len,
    ASN_INTEGER,
    (u_char*)&i, sizeof(i));

  s = [[alarm specificProblem] UTF8String];
  snmp_varlist_add_variable(
    &var_list,
    specificProblem_oid,
    specificProblem_len,
    ASN_OCTET_STR,
    (u_char*)s, strlen(s));

  s = [[alarm proposedRepairAction] UTF8String];
  snmp_varlist_add_variable(
    &var_list,
    proposedRepairAction_oid,
    proposedRepairAction_len,
    ASN_OCTET_STR,
    (u_char*)s, strlen(s));

  s = [[alarm additionalText] UTF8String];
  snmp_varlist_add_variable(
    &var_list,
    additionalText_oid,
    additionalText_len,
    ASN_OCTET_STR,
    (u_char*)s, strlen(s));

  ti[0] = (u_char)[alarm trendIndicator];
  ti[1] = 0;
  snmp_varlist_add_variable(
    &var_list,
    trendIndicator_oid,
    trendIndicator_len,
    ASN_OCTET_STR,
    (u_char*)ti, strlen(ti));

  /* Send the trap and clean up
   */
  send_v2trap(var_list);
  snmp_free_varbind(var_list);
  [pool release];
}

@end





@implementation	EcAlarmSinkSNMP (SNMP)

/* Call this only with the lock locked.
 */
- (BOOL) snmpClearAlarms: (NSString*)managed
{
  NSEnumerator	*enumerator;
  EcAlarm	*alarm;
  BOOL		changed = NO;

  /* Enumerate a copy of the _alarmsActive set so that removing objects
   * from the set while enumerating is safe.
   */
  enumerator = [[_alarmsActive allObjects] objectEnumerator];
  while (nil != (alarm = [enumerator nextObject]))
    {
      if ([[alarm managedObject] hasPrefix: managed])
	{
	  netsnmp_tdata_row	*row;

	  /* Remove from the ObjC table.
	   */
	  [_alarmsActive removeObject: alarm];

	  /* Find and remove the SNMP table entry.
	   */
	  row = (netsnmp_tdata_row*)[alarm extra];
	  if (0 != row)
	    {
	      struct alarmsTable_entry *entry;

	      entry = (struct alarmsTable_entry *)
		netsnmp_tdata_remove_and_delete_row(alarmsTable,
		row);
	      if (0 != entry)
		{
		  SNMP_FREE(entry);
		}
	    }

	  /* send the clear for the entry.
	   */
	  [alarmSink _trap: alarm forceClear: YES];
	  changed = YES;
	}
    }
  return changed;
}

- (void) snmpHousekeeping
{
  time_t	now;
  BOOL	changed = NO;

  DEBUGMSGTL(("EcTrapSink", "Housekeeping timer called.\n"));

  [_alarmLock lock];
  if (NO == _inTimeout && YES == _isRunning && NO == _shouldStop)
    {
      _inTimeout = YES;
      if (0 == resyncFlag)
	{
	  /* Check for alarms.
	   */
	  while ([_alarmQueue count] > 0)
	    {
	      id	o = [_alarmQueue objectAtIndex: 0];

	      if (YES == [o isKindOfClass: [EcAlarm class]])
		{
		  EcAlarm	*next = (EcAlarm*)o;
		  EcAlarm	*prev = [_alarmsActive member: next];
		  NSString	*m = [next managedObject];

		  if (nil == prev)
		    {
		      [next setFirstEventDate: [next eventDate]];
		    }
		  else
		    {
		      [next setFirstEventDate: [prev firstEventDate]];
		    }

		  if ([next perceivedSeverity] == EcAlarmSeverityCleared)
		    {
		      if (nil != prev)
			{
			  netsnmp_tdata_row	*row;

			  /* Remove from the ObjC table.
			   */
			  [prev retain];
			  [_alarmsActive removeObject: prev];

			  /* Find and remove the SNMP table entry.
			   */
			  row = (netsnmp_tdata_row*)[prev extra];
			  if (0 != row)
			    {
			      struct alarmsTable_entry *entry;

			      entry = (struct alarmsTable_entry *)
				netsnmp_tdata_remove_and_delete_row(alarmsTable,
				row);
			      if (0 != entry)
				{
				  SNMP_FREE(entry);
				}
			    }

			  /* send the clear for the entry.
			   */
			  [next setNotificationID: [prev notificationID]];
			  [alarmSink _trap: next forceClear: NO];
			  [self alarmFwd: next];
			  [prev release];
			  changed = YES;
			}
		    }
		  else
		    {
		      /* Register any new managed object.
		       */
		      if (NO == [managedObjects containsObject: m])
			{
			  objectsTable_createEntry(m);
			  [managedObjects addObject: m];
			  managedObjectsCount = [managedObjects count];
			  [self domanageFwd: m];
			  changed = YES;
			}

		      if ((nil == prev) || ([next perceivedSeverity]
			!= [prev perceivedSeverity]))
			{
			  netsnmp_tdata_row	*row;

			  if (nil == prev)
			    {
			      row = alarmsTable_createEntry
				([next notificationID]);
			      /* Add and send the new alarm
			       */
			      if (++notificationID <= 0) notificationID = 1;
			      [next setNotificationID: notificationID];
			    }
			  else
			    {
			      prev = [[prev retain] autorelease];
			      [_alarmsActive removeObject: prev];
			      row = (netsnmp_tdata_row*)[prev extra];
			      /* send the clear for the entry.
			       */
			      [next setNotificationID: [prev notificationID]];
			      [alarmSink _trap: prev forceClear: YES];
			    }

			  /* copy new version of data into row
			   * and send new severity trap.
			   */
			  setAlarmTableEntry(row, next);
			  [_alarmsActive addObject: next];
			  [alarmSink _trap: next forceClear: NO];
			  [self alarmFwd: next];
			  changed = YES;
			}
		    }
		}
	      else
		{
		  NSString	*s = [o description];

		  if (YES == [s hasPrefix: @"domanage "])
		    {
		      NSString	*m = [s substringFromIndex: 9];

		      changed = [self snmpClearAlarms: m];
		      if (NO == [managedObjects containsObject: m])
			{
			  objectsTable_createEntry(m);
			  [managedObjects addObject: m];
			  managedObjectsCount = [managedObjects count];
			  changed = YES;
			}
		    }
		  else if (YES == [s hasPrefix: @"unmanage "])
		    {
		      NSString	*m = [s substringFromIndex: 9];

		      if (YES == [managedObjects containsObject: m])
			{
			  const char		*str;
			  netsnmp_tdata_row	*row;

			  changed = YES;
			  [self snmpClearAlarms: m];
			  str = [m UTF8String];
			  row = netsnmp_tdata_row_first(objectsTable);
			  while (0 != row)
			    {
			      struct objectsTable_entry *entry;

			      entry = (struct objectsTable_entry *)row->data;
			      if (0 == strcmp(entry->objectId, str))
				{
				  netsnmp_tdata_remove_and_delete_row
				    (objectsTable, row);
				  SNMP_FREE(entry);
				  break;
				}
			      row = netsnmp_tdata_row_next(objectsTable, row);
			    }
			  [managedObjects removeObject: m];
			  if (YES == [m hasSuffix: @"_"])
			    {
			      NSEnumerator	*e;
			      NSString		*s;

			      e = [[[managedObjects copy] autorelease]
				objectEnumerator];
			      while (nil != (s = [e nextObject]))
				{
				  if (YES == [s hasPrefix: m])
				    {
				      [managedObjects removeObject: s];
				    }
				}
			    }
			  managedObjectsCount = [managedObjects count];
			}
		    }
		  else
		    {
		      NSLog(@"ERROR ... unexpected command '%@'", s);
		    }
		}
	      [_alarmQueue removeObjectAtIndex: 0];
	      [_alarmLock unlock];
	      [_alarmLock lock];
	    }
	}
    }
  [_alarmLock unlock];
  now = time(0);
  if (YES == heartbeat(now))
    {
      changed = YES;
    }
  if (YES == changed)
    {
      [alarmSink _store];
    }
}

@end

