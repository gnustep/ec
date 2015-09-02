
/** Enterprise Control Configuration and Logging

   Copyright (C) 2012 Free Software Foundation, Inc.

   Written by: Richard Frith-Macdonald <rfm@gnu.org>
   Date: Febrary 2010
   Originally developed from 1996 to 2012 by Brainstorm, and donated to
   the FSF.

   This file is part of the GNUstep project.

   This library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Lesser General Public
   License as published by the Free Software Foundation; either
   version 3 of the License, or (at your option) any later version.

   This library is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
   Library General Public License for more details.

   You should have received a copy of the GNU Lesser General Public
   License along with this library; if not, write to the Free
   Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
   Boston, MA 02111 USA.

   */

#import <Foundation/Foundation.h>

#import "EcAlarm.h"
#import "EcAlarmSinkSNMP.h"
#import "EcAlerter.h"
#import "EcClientI.h"
#import "EcHost.h"
#import "EcProcess.h"
#import "EcUserDefaults.h"
#import "NSFileHandle+Printf.h"

/*
 * Catagory so that NSHost objects can be safely used as dictionary keys.
 */
@implementation	NSHost (ControlExtension)
- (id) copyWithZone: (NSZone*)z
{
  return RETAIN(self);
}
@end

static EcAlarmSinkSNMP	        *sink = nil;

static NSMutableDictionary      *lastAlertInfo = nil;

static NSTimeInterval	pingDelay = 240.0;

static int      alertAlarmThreshold = EcAlarmSeverityMajor;
static int      reminderInterval = 0;

static int	comp_len = 0;

static int	comp(NSString *s0, NSString *s1)
{
  if ([s0 length] > [s1 length])
    {
      comp_len = -1;
      return -1;
    }
  if ([s1 compare: s0
	  options: NSCaseInsensitiveSearch|NSLiteralSearch
	    range: NSMakeRange(0, [s0 length])] == NSOrderedSame)
    {
      comp_len = [s0 length];
      if (comp_len == [s1 length])
	{
	  return 0;
	}
      else
	{
	  return 1;
	}
    }
  else
    {
      comp_len = -1;
      return -1;
    }
}

static NSString*	cmdWord(NSArray* a, unsigned int pos)
{
  if (a != nil && [a count] > pos)
    {
      return [a objectAtIndex: pos];
    }
  else
    {
      return @"";
    }
}


@interface	CommandInfo : EcClientI
{
  NSArray	*servers;
}
- (NSString*) serverByAbbreviation: (NSString*)s;
- (NSArray*) servers;
- (void) setServers: (NSArray*)s;
@end

@implementation CommandInfo

- (void) dealloc
{
  DESTROY(servers);
  [super dealloc];
}

- (NSString*) serverByAbbreviation: (NSString*)s
{
  NSString	*svr;
  int		i;
  int		best_pos = -1;
  int		best_len = 0;

  /*
   *	Special case - a numeric value is used as an index into the array.
   */
  if (isdigit(*[s cString]))
    {
      i = [s intValue];
      if (i >= 0 && i < [servers count])
	{
	  svr = [servers objectAtIndex: i];
	  return svr;
	}
    }

  for (i = 0; i < [servers count]; i++)
    {
      svr = [servers objectAtIndex: i];
      if (comp(s, svr) == 0)
	{
	  return svr;
	}
      if (comp_len > best_len)
	{
	  best_len = comp_len;
	  best_pos = i;
	}
    }
  if (best_pos >= 0)
    {
      svr = [servers objectAtIndex: best_pos];
      return svr;
    }
  return nil;
}

- (NSArray*) servers
{
  return servers;
}

- (void) setServers: (NSArray*)s
{
  ASSIGN(servers, s);
}
@end


@interface	ConsoleInfo : EcClientI
{
  NSString	*cserv;
  NSString	*chost;
  NSString	*pass;
  BOOL		general;
  BOOL		warnings;
  BOOL		errors;
  BOOL		alerts;
}
- (id) initFor: (id)o
	  name: (NSString*)n
	  with: (id<CmdClient>)s
	  pass: (NSString*)p;
- (NSString*) chost;
- (NSString*) cserv;
- (BOOL) getAlerts;
- (BOOL) getErrors;
- (BOOL) getGeneral;
- (BOOL) getWarnings;
- (NSString*) pass;
- (NSString*) promptAfter: (NSString*)msg;
- (void) setAlerts: (BOOL)flag;
- (void) setConnectedHost: (NSString*)c;
- (void) setConnectedServ: (NSString*)c;
- (void) setErrors: (BOOL)flag;
- (void) setGeneral: (BOOL)flag;
- (void) setWarnings: (BOOL)flag;
@end

@implementation ConsoleInfo

- (NSString*) chost
{
  return chost;
}

- (NSString*) cserv
{
  return cserv;
}

- (void) dealloc
{
  DESTROY(chost);
  DESTROY(cserv);
  DESTROY(pass);
  [super dealloc];
}

- (BOOL) getAlerts
{
  return alerts;
}

- (BOOL) getErrors
{
  return errors;
}

- (BOOL) getGeneral
{
  return general;
}

- (BOOL) getWarnings
{
  return warnings;
}

- (id) initFor: (id)o
	  name: (NSString*)n
	  with: (id<CmdClient>)s
	  pass: (NSString*)p
{
  self = [super initFor: o name: n with: s];
  if (self != nil)
    {
      pass = [p copy];
      chost = nil;
      cserv = nil;
      general = NO;
      warnings = NO;
      alerts = YES;
      errors = YES;
    }
  return self;
}

- (NSString*) pass
{
  return pass;
}

- (NSString*) promptAfter: (NSString*)msg
{
  if (chost && cserv)
    {
      return [NSString stringWithFormat: @"%@\n%@:%@> ", msg, chost, cserv];
    }
  else if (chost)
    {
      return [NSString stringWithFormat: @"%@\n%@:> ", msg, chost];
    }
  else if (cserv)
    {
      return [NSString stringWithFormat: @"%@\n:%@> ", msg, cserv];
    }
  else
    {
      return [NSString stringWithFormat: @"%@\nControl> ", msg];
    }
}

- (void) setAlerts: (BOOL)flag
{
  alerts = flag;
}

- (void) setConnectedHost: (NSString*)c
{
  ASSIGNCOPY(chost, c);
}

- (void) setConnectedServ: (NSString*)c
{
  ASSIGNCOPY(cserv, c);
}

- (void) setErrors: (BOOL)flag
{
  errors = flag;
}

- (void) setGeneral: (BOOL)flag
{
  general = flag;
}

- (void) setWarnings: (BOOL)flag
{
  warnings = flag;
}

@end


@interface	EcControl : EcProcess <Control>
{
  NSFileManager		*mgr;
  NSMutableArray	*commands;
  NSMutableArray	*consoles;
  NSString		*logname;
  NSDictionary		*config;
  NSMutableDictionary	*operators;
  NSMutableDictionary	*fileBodies;
  NSMutableDictionary	*fileDates;
  NSTimer		*timer;
  NSTimer		*terminating;
  unsigned		commandPingPosition;
  unsigned		consolePingPosition;
  NSString		*configFailed;
  NSString		*configIncludeFailed;
  EcAlerter		*alerter;
}
- (NSFileHandle*) openLog: (NSString*)lname;
- (void) cmdGnip: (id <CmdPing>)from
	sequence: (unsigned)num
	   extra: (NSData*)data;
- (void) cmdPing: (id <CmdPing>)from
	sequence: (unsigned)num
	   extra: (NSData*)data;
- (void) cmdQuit: (NSInteger)status;
- (void) command: (NSData*)dat
	    from: (NSString*)f;
- (BOOL) connection: (NSConnection*)ancestor
  shouldMakeNewConnection: (NSConnection*)newConn;
- (id) connectionBecameInvalid: (NSNotification*)notification;
- (EcClientI*) findIn: (NSArray*)a
        byAbbreviation: (NSString*)s;
- (EcClientI*) findIn: (NSArray*)a
		byName: (NSString*)s;
- (EcClientI*) findIn: (NSArray*)a
	      byObject: (id)s;
- (void) information: (NSString*)inf
		type: (EcLogType)t
		  to: (NSString*)to
		from: (NSString*)from;
- (NSData*) registerCommand: (id<Command>)c
		       name: (NSString*)n;
- (NSString*) registerConsole: (id<Console>)c
		         name: (NSString*)n
			 pass: (NSString*)p;
- (void) reply: (NSString*) msg to: (NSString*)n from: (NSString*)c;
- (void) reportAlarm: (EcAlarm*)alarm
            severity: (EcAlarmSeverity)severity
            reminder: (int)reminder;
- (void) reportAlarms;
- (void) servers: (NSData*)d
	      on: (id<Command>)s;
- (void) timedOut: (NSTimer*)t;
- (void) unregister: (id)obj;
- (BOOL) update;
- (void) updateConfig: (NSData*)dummy;
- (id) getInclude: (id)s;
- (id) recursiveInclude: (id)o;
- (id) tryInclude: (id)s multi: (BOOL*)flag;
@end

@implementation	EcControl

- (oneway void) alarm: (in bycopy EcAlarm*)alarm
{
  EcAlarmSeverity	severity;

  /* Now, for critical and major alarms, generate a corresponding old style
   * alert.
   */
  severity = [alarm perceivedSeverity];
  if (EcAlarmSeverityCleared == severity)
    {
      NSArray           *a = [sink alarms];
      NSUInteger        index = [a indexOfObject: alarm];

      if (NSNotFound != index)
        {
          EcAlarm       *old = [a objectAtIndex: index];
          int           notificationID = [old notificationID];
         
          severity = [old perceivedSeverity];
          if (severity <= alertAlarmThreshold && notificationID > 0)
            {
              NSDictionary      *info;
              NSString          *key;

              key = [NSString stringWithFormat: @"%d", notificationID];

              if (nil != (info = [lastAlertInfo objectForKey: key]))
                {
                  int   reminder;

                  reminder = [[info objectForKey: @"Reminder"] intValue];
                  [lastAlertInfo removeObjectForKey: key];
                  [self reportAlarm: old
                           severity: EcAlarmSeverityCleared
                           reminder: reminder];
                }
            }
        }
    }

  /* Now, send the alarm to the alarm sink.
   */
  [sink alarm: alarm];
}

- (NSString*) description
{
  return [NSString stringWithFormat: @"%@ running since %@\n%@\n%@",
    [super description], [self ecStarted], alerter, sink];
}

- (oneway void) domanage: (NSString*)name
{
  [sink domanage: name];
}

- (NSFileHandle*) openLog: (NSString*)lname
{
  NSFileHandle	*lf;

  if ([mgr isWritableFileAtPath: lname] == NO)
    {
      if ([mgr createFileAtPath: lname
		       contents: nil
		     attributes: nil] == NO)
	{
	  NSLog(@"Log file '%@' is not writable and can't be created", lname);
	  return nil;
	}
    }

  lf = [NSFileHandle fileHandleForUpdatingAtPath: lname];
  if (lf == nil)
    {
      NSLog(@"Unable to log to %@", lname);
      return nil;
    }
  [lf seekToEndOfFile];
  return lf;
}

- (void) cmdGnip: (id <CmdPing>)from
	sequence: (unsigned)num
	   extra: (NSData*)data
{
  EcClientI	*r;

  /*
   * See if we have a fitting client - and update records.
   */
  r = [self findIn: commands byObject: (id)from];
  if (r == nil)
    {
      r = [self findIn: consoles byObject: (id)from];
    }
  if (r != nil)
    {
      [r gnip: num];
    }
}

- (BOOL) cmdIsClient
{
  return NO;	// Control is not a client of Command
}

- (void) cmdPing: (id <CmdPing>)from
	sequence: (unsigned)num
	   extra: (NSData*)data
{
  [from cmdGnip: self sequence: num extra: nil];
}

- (void) cmdQuit: (NSInteger)status
{
  [sink shutdown];
  exit (status);
}

- (void) command: (NSData*)dat
	    from: (NSString*)f
{
  NSMutableArray	*cmd;
  ConsoleInfo		*console;

  cmd = [NSPropertyListSerialization
    propertyListWithData: dat
    options: NSPropertyListMutableContainers
    format: 0
    error: 0];
  console = (ConsoleInfo*)[self findIn: consoles byName: f];
  if (console == nil)
    {
      NSString	*m;

      m = [NSString stringWithFormat: cmdLogFormat(LT_ERROR,
        @"command from unregistered console (from %@)"), f];
      [self information: m
		   type: LT_ERROR
		     to: nil
		   from: nil];
    }
  else if (cmd == nil || [cmd count] == 0)
    {
      NSString	*m;

      m = [NSString stringWithFormat: cmdLogFormat(LT_AUDIT,
        @"no command entered (from %@ %@)"), f, [console name]];
      [self information: m
		   type: LT_AUDIT
		     to: [console name]
		   from: nil];
    }
  else
    {
      NSMutableString	*full;
      NSString	*hname = nil;
      NSString	*m = @"";
      NSString	*wd = cmdWord(cmd, 0);
      unsigned	count = [cmd count];
      unsigned	i;
      BOOL	connected = NO;

      /*
       * Log this command!
       */
      full = [[NSMutableString alloc] initWithCapacity: 1024];
      for (i = 0; i < count; i++)
	{
	  [full appendFormat: @" %@", [cmd objectAtIndex: i]];
	}
      [[self cmdLogFile: logname]
	printf: @"%@ %@> %@\n", [NSDate date], [console name], full];
      RELEASE(full);

      if ([console chost] != nil || [console cserv] != nil)
	{
	  connected = YES;
	}
      /* If we have a 'control' command - act as if the console was not
       * connected to a host or server.
       */
      if (comp(wd, @"control") == 0)
	{
	  [cmd removeObjectAtIndex: 0];
	  wd = cmdWord(cmd, 0);
	  connected = NO;
	}
      if (comp(wd, @"password") == 0)
	{
	  NSRange	r = [[console name] rangeOfString: @":"];
	  NSString	*s = [[console name] substringToIndex: r.location];
	  NSMutableDictionary	*d;
	  NSString	*p;
	  NSString	*path;

	  if ([cmd count] != 3)
	    {
	      [self information: @"parameters are old password and new one.\n"
			   type: LT_AUDIT
			     to: [console name]
			   from: nil];
	      return;
	    }
	  if (operators == nil)
	    {
	      operators = [NSMutableDictionary dictionaryWithCapacity: 1];
	      RETAIN(operators);
	      [operators setObject: @"" forKey: s];
	    }
	  d = AUTORELEASE([[operators objectForKey: s] mutableCopy]);
	  p = [d objectForKey: @"Password"];
	  if ([p length] == 0 || [p isEqual: [cmd objectAtIndex: 1]])
	    {
	      [d setObject: [cmd objectAtIndex: 2] forKey: @"Password"];
	      [operators setObject: d forKey: s];
	      p = [operators description];
	      path = [[self cmdDataDirectory] stringByAppendingPathComponent:
		@"Operators.plist"];
	      [p writeToFile: path atomically: YES];
	      [self information: @"new password set.\n"
			   type: LT_AUDIT
			     to: [console name]
			   from: nil];
	      return;
	    }
	  else
	    {
	      [self information: @"old password is incorrect.\n"
			   type: LT_AUDIT
			     to: [console name]
			   from: nil];
	      return;
	    }
	}

      /*
       *	If we are not connected, but have an 'on ....' at the start of
       *	the command line, then we send to the specified host as if we
       *	were connected to it.
       */
      if (connected)
	{
	  hname = [console chost];
	}
      else if (comp(wd, @"on") == 0)
	{
	  [cmd removeObjectAtIndex: 0];
	  wd = cmdWord(cmd, 0);
	  hname = AUTORELEASE(RETAIN(wd));
	  if ([hname length] > 0)
	    {
	      CommandInfo	*c;

	      c = (CommandInfo*)[self findIn: commands byAbbreviation: hname];
	      if (c)
		{
		  hname = [c name];
		  [cmd removeObjectAtIndex: 0];
		}
	      else
		{
		  [self information: @"Attempt to work on unknown host"
			       type: LT_AUDIT
				 to: [console name]
			       from: nil];
		  return;
		}
	      wd = cmdWord(cmd, 0);
	    }
	  else
	    {
	      hname = nil;
	    }
	}

      if (connected == YES || hname != nil)
	{
	  NSArray	*hosts;

	  /* Make an array of hosts to work with - the connected host
	   * or all hosts.  If the connected host has gone away - disconnect.
	   */
	  if (hname == nil)
	    {
	      hosts = [NSArray arrayWithArray: commands];
	    }
	  else
	    {
	      CommandInfo	*c;

	      c = (CommandInfo*)[self findIn: commands byName: hname];
	      if (c)
		{
		  hosts = [NSArray arrayWithObject: c];
		}
	      else
		{
		  if (connected)
		    {
		      [console setConnectedHost: nil];
		    }
		  [self information: @"Host has gone away"
			       type: LT_ERROR
				 to: [console name]
			       from: nil];
		  return;
		}
	    }

	  if ([wd length] == 0)
	    {
	      /* Quietly ignore.	*/
	    }
	  else
	    {
	      BOOL	foundServer = NO;
	      int	i;

	      m = nil;	/* Let remote host generate messages. */

	      /* Perform operation on connected host (or all hosts if
	       * not connected to a host).
	       */
	      for (i = 0; i < [hosts count]; i++)
		{
		  CommandInfo	*c = [hosts objectAtIndex: i];

		  if ([commands indexOfObjectIdenticalTo: c] != NSNotFound)
		    {
		      if (NO == connected || [console cserv] == nil)
			{
			  foundServer = YES;
			  NS_DURING
			    {
			      NSData	*dat = [NSPropertyListSerialization
				dataFromPropertyList: cmd
				format: NSPropertyListBinaryFormat_v1_0
				errorDescription: 0];
			      [[c obj] command: dat
					    to: nil
					  from: [console name]];
			    }
			  NS_HANDLER
			    {
			      NSLog(@"Caught: %@", localException);
			    }
			  NS_ENDHANDLER
			}
		      else
			{
			  NSString	*to;

			  to = [c serverByAbbreviation: [console cserv]];
			  if (to)
			    {
			      foundServer = YES;
			      NS_DURING
				{
				  NSData	*dat;

				  dat = [NSPropertyListSerialization
				    dataFromPropertyList: cmd
				    format: NSPropertyListBinaryFormat_v1_0
				    errorDescription: 0];
				  [[c obj] command: dat
						to: to
					      from: [console name]];
				}
			      NS_HANDLER
				{
				  NSLog(@"Caught: %@", localException);
				}
			      NS_ENDHANDLER
			    }
			}
		    }
		}
	      if (foundServer == NO)
		{
		  [console setConnectedServ: nil];
		  [self information: @"Server has gone away"
			       type: LT_AUDIT
				 to: [console name]
			       from: nil];
		}
	    }
	}
      else if ([wd length] == 0)
	{
	  /* Quietly ignore.	*/
	}
      else if (comp(wd, @"alarms") >= 0)
	{
	  NSArray	*a = [sink alarms];

	  if (0 == [a count])
	    {
	      m = @"No alarms currently active.\n";
	    }
	  else
	    {
	      int	i;

	      a = [a sortedArrayUsingSelector: @selector(compare:)];
	      m = @"Current alarms -\n";
	      for (i = 0; i < [a count]; i++)
		{
		  EcAlarm	*alarm = [a objectAtIndex: i];

		  m = [m stringByAppendingString: [alarm description]];
		  m = [m stringByAppendingString: @"\n"];
		}
	    }
	}
      else if (comp(wd, @"archive") >= 0)
	{
	  NSCalendarDate	*when = [NSCalendarDate date];
	  NSString		*sub;
	  int			yy, mm, dd;

	  yy = [when yearOfCommonEra];
	  mm = [when monthOfYear];
	  dd = [when dayOfMonth];

	  sub = [NSString stringWithFormat: @"%04d-%02d-%02d", yy, mm, dd];
	  m = [NSString stringWithFormat: @"\n%@\n\n", [self cmdArchive: sub]];
	}
      else if (comp(wd, @"clear") >= 0)
	{
	  NSArray	*a = [sink alarms];

	  wd = cmdWord(cmd, 1);
	  if ([wd length] > 0 && [wd intValue] > 0)
	    {
	      EcAlarm	*alarm = nil;
	      int	n = [wd intValue];
	      int	i = [a count];

	      while (i-- > 0)
		{
		  alarm = [a objectAtIndex: i];
		  if ([alarm notificationID] == n)
		    {
		      break;
		    }
		  alarm = nil;
		}
	      if (nil == alarm)
		{
		  m = @"No alarm found with that notificationID\n";
		}
	      else
		{
		  m = [NSString stringWithFormat: @"Clearing %@\n", alarm];
		  alarm = [alarm clear];
		  [self alarm: alarm];
		}
	    }
	  else
	    {
	      m = @"The 'clear' command requires an alarm notificationID\n"
	        @"This is the unique identifier used for working with\n"
	        @"external SNMP monitoring systems.\n";
	    }
	}
      else if (comp(wd, @"connect") >= 0)
	{
	  wd = cmdWord(cmd, 1);
	  if ([wd length] == 0)
	    {
	      [console setConnectedServ: nil];
	    }
	  else
	    {
	      [console setConnectedServ: wd];
	    }
	}
      else if (comp(wd, @"config") >= 0)
	{
	  BOOL	changed;

	  changed = [self update];
	  if (configFailed != nil)
	    {
	      m = configFailed;
	    }
	  else
	    {
	      if (configIncludeFailed != nil)
		{
		  m = [NSString stringWithFormat:
		    @"Configuration file re-read and loaded, but %@",
		    configIncludeFailed];
		}
	      else if (YES == changed)
		{
		  m = @"Configuration file re-read ... updates handled.\n";
		}
	      else
		{
		  m = @"Configuration file re-read ... UNCHANGED.\n";
		}
	    }
	}
      else if (comp(wd, @"flush") >= 0)
	{
	  [alerter flushSms];
	  [alerter flushEmail];
	  m = @"Flushed alert messages\n";
	}
      else if (comp(wd, @"help") >= 0)
	{
	  wd = cmdWord(cmd, 1);
	  if ([wd length] == 0)
	    {
	      m = @"Commands are -\n"
	      @"Help\tAlarms\tArchive\tClear\tConfig\tConnect\t"
	      @"Flush\tHost\tList\tMemory\tOn\t"
	      @"Password\tRepeat\tQuit\tSet\tStatus\tTell\tUnset\n\n"
	      @"Type 'help' followed by a command word for details.\n"
	      @"Use 'tell xxx help' to get help for a specific process.\n"
	      @"A command line consists of a sequence of words, "
	      @"the first of which is the command to be executed. "
	      @"A word can be a simple sequence of non-space characters, "
	      @"or it can be a 'quoted string'. "
	      @"Simple words are converted to lower case before "
	      @"matching them against commands and their parameters. "
	      @"Text in a 'quoted string' is NOT converted to lower case "
	      @"but a '\\' character is treated in a special manner -\n"
	      @"  \\b is replaced by a backspace\n"
	      @"  \\f is replaced by a formfeed\n"
	      @"  \\n is replaced by a linefeed\n"
	      @"  \\r is replaced by a carriage-return\n"
	      @"  \\t is replaced by a tab\n"
	      @"  \\0 followed by up to 3 octal digits is replaced"
	      @" by the octal value\n"
	      @"  \\x followed by up to 2 hex digits is replaced"
	      @" by the hex value\n"
	      @"  \\ followed by any other character is replaced by"
	      @" the second character.\n"
	      @"  This permits use of quotes and backslashes inside"
	      @" a quoted string.\n";
	    }
	  else
	    {
	      if (comp(wd, @"Alarms") >= 0)
		{
		  m = @"Alarms\nLists the currently active alarms ordered "
		      @"by their notificationIDs.\n"
                      @"The notification ID is the unique identifier used "
                      @"for working with\n"
                      @"external SNMP monitoring systems.\n";
		}
	      else if (comp(wd, @"Archive") >= 0)
		{
		  m = @"Archive\nArchives the log file. The archived log "
		      @"file is stored in a subdirectory whose name is of "
		      @"the form YYYY-MM-DD being the date at "
		      @"which the archive was created.\n";
		}
	      else if (comp(wd, @"Clear") >= 0)
		{
		  m = @"Clear\n\n"
                      @"Instructs the Control server to clear "
		      @"an alarm (identified by numeric\n"
                      @"notificationID).\n\n"
		      @"NB. This command clears the alarm in the "
		      @"central records of the Control server,\n"
                      @"NOT in the originating process.\n"
                      @"This feature means that you can clear "
                      @"an alarm centrally while the underlying\n"
                      @"problem has not been corrected and, "
                      @"because the originating process has\n"
                      @"already forwarded the alarm it will "
                      @"not re-raise it with the central system.\n"
                      @"This can be useful where you wish to "
                      @"suppress some sort of repeated nagging by\n"
                      @"the central system.\n"
                      @"To reset things so the alarm may be "
                      @"raised again you must issue a 'clear'\n"
                      @"command directly to the originatig process itsself.\n";
		}
	      else if (comp(wd, @"Config") >= 0)
		{
		  m = @"Config\nInstructs the Control server to re-load "
		      @"it's configuration information and pass it on to "
		      @"all connected Command servers.\n";
		}
	      else if (comp(wd, @"Connect") >= 0)
		{
		  m = @"Connect name\nInstructs the Control server that "
		      @"commands from your console should go to servers "
		      @"whose names match the value you give.\n"
		      @"To remove this association, you will need to type "
		      @"the command 'control connect'\n'";
		}
	      else if (comp(wd, @"Flush") >= 0)
		{
		  m = @"Flush\nInstructs the Control server that messages "
		      @"about errors and alerts which are currently saved "
		      @"in the batching process should be sent out.\n";
		}
	      else if (comp(wd, @"Host") >= 0)
		{
		  m = @"Host name\nInstructs the Control server that "
		      @"commands from your console should go to the host "
		      @"whose names match the value you give.\n"
		      @"To remove this association, you will need to type "
		      @"the command 'control host'\n'";
		}
	      else if (comp(wd, @"List") >= 0)
		{
		  m = @"List\nLists all the connected commands.\n"
		      @"List consoles\nLists all the connected consoles.\n";
		}
	      else if (comp(wd, @"Memory") >= 0)
		{
		  m = @"Memory\nDisplays recent memory allocation stats.\n"
		      @"Memory all\nDisplays all memory allocation stats.\n";
		}
	      else if (comp(wd, @"On") >= 0)
		{
		  m = @"On host ...\nSends a command to the named host.\n"
                      @"eg. 'on remotehost tell myserver help'.\n";
		}
	      else if (comp(wd, @"Password") >= 0)
		{
		  m = @"Password <oldpass> <newpass>\nSets your password.\n";
		}
	      else if (comp(wd, @"Quit") >= 0)
		{
		  m = @"Quit 'self'\n"
		      @"Shuts down the Control server process - don't do "
		      @"this lightly - all other servers are coordinated "
		      @"by the Control server\n"
		      @"\nUse 'on <host> quit <name>' to shut down "
		      @"individual servers on the specified host.\n"
		      @"\nUse 'on <host> quit all' to shut down all the "
		      @"servers on the specified host.\n"
		      @"\nUse 'on <host> quit self' to shut down the "
		      @"Command server on the specified host - be careful "
		      @"using this - the other servers on a host are all "
		      @"coordinated (and log through) the Command server.\n";
		}
	      else if (comp(wd, @"Repeat") >= 0)
		{
		  m = @"Repeat\nRepeat the last command.\n";
		}
	      else if (comp(wd, @"Set") >= 0)
		{
		  m = @"Set\n"
		      @"Changes settings -\n"
		      @"  set display warnings\n"
		      @"    displays warning messages from the server to "
		      @"which you are connected.\n"
		      @"  set display general\n"
		      @"    display warning messages (if selected) "
		      @"from ALL servers, not just connected ones.\n"
		      @"  set display errors\n"
		      @"    displays error messages.\n"
		      @"  set display alerts\n"
		      @"    displays alert messages.\n"
		      @"\n";
		}
	      else if (comp(wd, @"Status") >= 0)
		{
		  m = @"Status\nInstructs the Control server to report its "
		      @"current status ... mostly the buffered alert and "
		      @"error messages waiting to be sent out.\n";
		}
	      else if (comp(wd, @"Tell") >= 0)
		{
		  m = @"Tell 'name' 'command'\n"
		      @"Sends the command to the named client.\n"
		      @"eg. 'tell myserver help'.\n";
		}
	      else if (comp(wd, @"UnSet") >= 0)
		{
		  m = @"UnSet\n"
		      @"Changes settings -\n"
		      @"  unset display general\n"
		      @"  unset display warnings\n"
		      @"  unset display errors\n"
		      @"  unset display alerts\n"
		      @"\n";
		}
	    }
	}
      else if (comp(wd, @"host") >= 0)
	{
	  wd = cmdWord(cmd, 1);
	  if ([wd length] == 0)
	    {
	      [console setConnectedHost: nil];
	    }
	  else
	    {
	      CommandInfo	*c;

	      c = (CommandInfo*)[self findIn: commands byAbbreviation: wd];
	      if (c)
		{
		  [console setConnectedHost: [c name]];
		}
	    }
	}
      else if (comp(wd, @"list") >= 0)
	{
	  wd = cmdWord(cmd, 1);
	  if ([wd length] > 0 && comp(wd, @"consoles") >= 0)
	    {
	      if ([consoles count] == 1)
		{
		  m = @"No other consoles currently connected.\n";
		}
	      else
		{
		  int	i;

		  m = @"Current console processes -\n";
		  for (i = 0; i < [consoles count]; i++)
		    {
		      ConsoleInfo	*c;

		      c = (ConsoleInfo*)[consoles objectAtIndex: i];
		      if (c == console)
			{
			  m = [m stringByAppendingFormat:
			      @"%2d.   your console\n", i];
			}
		      else
			{
			  m = [m stringByAppendingFormat:
			      @"%2d.   %s\n", i, [[c name] cString]];
			}
		    }
		}
	    }
	  else
	    {
	      if ([commands count] == 0)
		{
		  if (nil == alerter)
		    {
		      m = @"No database/alerter available.\n";
		    }
		  else
		    {
		      m = @"No hosts currently connected.\n";
		    }
		}
	      else
		{
		  int	i;

		  m = @"Current server hosts -\n";
		  for (i = 0; i < [commands count]; i++)
		    {
		      CommandInfo*	c;

		      c = (CommandInfo*)[commands objectAtIndex: i];
		      m = [m stringByAppendingFormat:
			  @"%2d. %-32.32s\n", i, [[c name] cString]];
		      if ([c servers] == nil || [[c servers] count] == 0)
			{
			  m = [m stringByAppendingString:
				  @"    no servers connected\n"];
			}
		      else
			{
			  NSArray	*svrs = [c servers];
			  int		j;

			  for (j = 0; j < [svrs count]; j++)
			    {
			      m = [m stringByAppendingFormat:
				  @"    %2d. %@\n", j,
				      [svrs objectAtIndex: j]];
			    }
			}
		    }
		}
	    }
	}
      else if (comp(wd, @"memory") >= 0)
	{
	  if (GSDebugAllocationActive(YES) == NO)
	    {
	      m = @"Memory statistics were not being gathered.\n"
		  @"Statistics Will start from NOW.\n";
	    }
	  else
	    {
	      const char*	list;

	      wd = cmdWord(cmd, 1);
	      if ([wd length] > 0 && comp(wd, @"all") >= 0)
		{
		  list = GSDebugAllocationList(NO);
		}
	      else
		{
		  list = GSDebugAllocationList(YES);
		}
	      m = [NSString stringWithCString: list];
	    }
	}
      else if (comp(wd, @"quit") >= 0)
	{
	  m = @"Try 'help quit' for information about shutting down.\n";
	  wd = cmdWord(cmd, 1);
	  if ([wd length] > 0 && comp(wd, @"self") == 0)
	    {
	      [alerter flushSms];
	      [alerter flushEmail];
	      DESTROY(alerter);
	      exit(0);
	    }
	}
      else if (comp(wd, @"set") >= 0)
	{
	  m = @"ok - set confirmed.\n";
	  wd = cmdWord(cmd, 1);
	  if ([wd length] == 0)
	    {
	      m = @"no parameter to 'set'\n";
	    }
	  else if (comp(wd, @"display") >= 0)
	    {
	      wd = cmdWord(cmd, 2);
	      if ([wd length] == 0)
		{
		  m = [NSString stringWithFormat: @"display settings -\n"
		    @"general: %d warnings: %d errors: %d alerts: %d\n",
		    [console getGeneral], [console getWarnings],
		    [console getErrors], [console getAlerts]];
		}
	      else if (comp(wd, @"alerts") >= 0)
		{
		  [console setAlerts: YES];
		}
	      else if (comp(wd, @"errors") >= 0)
		{
		  [console setErrors: YES];
		}
	      else if (comp(wd, @"general") >= 0)
		{
		  [console setGeneral: YES];
		}
	      else if (comp(wd, @"warnings") >= 0)
		{
		  [console setWarnings: YES];
		}
	      else
		{
		  m = @"unknown parameter to 'set display'\n";
		}
	    }
	  else
	    {
	      m = @"unknown parameter to 'set'\n";
	    }
	}
      else if (comp(wd, @"status") >= 0)
	{
	  m = [self description];
	}
      else if (comp(wd, @"tell") >= 0)
	{
	  wd = cmdWord(cmd, 1);
	  if ([wd length] > 0)
	    {
	      NSString	*dest = AUTORELEASE(RETAIN(wd));
	      int	i;
	      NSArray	*a = [[NSArray alloc] initWithArray: commands];

	      [cmd removeObjectAtIndex: 0];
	      [cmd removeObjectAtIndex: 0];
	      if (comp(dest, @"all") == 0)
		{
		  dest = nil;
		}

	      for (i = 0; i < [a count]; i++)
		{
		  CommandInfo*	c = (CommandInfo*)[a objectAtIndex: i];

		  if ([commands indexOfObjectIdenticalTo: c] != NSNotFound)
		    {
		      NSString	*to;

		      if (dest)
			{
			  to = [c serverByAbbreviation: dest];
			  if (to != nil)
			    {
			      NS_DURING
				{
				  NSData	*dat;

				  dat = [NSPropertyListSerialization
				    dataFromPropertyList: cmd
				    format: NSPropertyListBinaryFormat_v1_0
				    errorDescription: 0];
				  [[c obj] command: dat
						to: to
					      from: [console name]];
				}
			      NS_HANDLER
				{
				  NSLog(@"Caught: %@", localException);
				}
			      NS_ENDHANDLER
			    }
			}
		      else
			{
			  int	j;

			  for (j = 0; j < [[c servers] count]; j++)
			    {
			      to = [[c servers] objectAtIndex: j];
			      NS_DURING
				{
				  NSData	*dat;

				  dat = [NSPropertyListSerialization
				    dataFromPropertyList: cmd
				    format: NSPropertyListBinaryFormat_v1_0
				    errorDescription: 0];
				  [[c obj] command: dat
						to: to
					      from: [console name]];
				}
			      NS_HANDLER
				{
				  NSLog(@"Caught: %@",
					localException);
				}
			      NS_ENDHANDLER
			    }
			}
		    }
		}
	      m = nil;
	    }
	  else
	    {
	      m = @"Tell where?.\n";
	    }
	}
      else if (comp(wd, @"unset") >= 0)
	{
	  m = @"ok - unset confirmed.\n";
	  wd = cmdWord(cmd, 1);
	  if ([wd length] == 0)
	    {
	      m = @"no parameter to 'set'\n";
	    }
	  else if (comp(wd, @"display") >= 0)
	    {
	      wd = cmdWord(cmd, 2);
	      if ([wd length] == 0)
		{
		  m = [NSString stringWithFormat: @"display settings -\n"
		    @"general: %d warnings: %d errors: %d alerts: %d\n",
		    [console getGeneral], [console getWarnings],
		    [console getErrors], [console getAlerts]];
		}
	      else if (comp(wd, @"alerts") >= 0)
		{
		  [console setAlerts: NO];
		}
	      else if (comp(wd, @"errors") >= 0)
		{
		  [console setErrors: NO];
		}
	      else if (comp(wd, @"general") >= 0)
		{
		  [console setGeneral: NO];
		}
	      else if (comp(wd, @"warnings") >= 0)
		{
		  [console setWarnings: NO];
		}
	      else
		{
		  m = @"unknown parameter to 'unset display'\n";
		}
	    }
	  else
	    {
	      m = @"unknown parameter to 'unset'\n";
	    }
	}
      else
	{
	  m = [NSString stringWithFormat: @"Unknown command - '%@'\n", wd];
	}

      if (m != nil)
	{
	  [self information: m
		       type: LT_AUDIT
			 to: [console name]
		       from: nil];
	}
    }
}

- (BOOL) connection: (NSConnection*)ancestor
  shouldMakeNewConnection: (NSConnection*)newConn
{
  [[NSNotificationCenter defaultCenter]
      addObserver: self
      selector: @selector(connectionBecameInvalid:)
      name: NSConnectionDidDieNotification
      object: (id)newConn];
  [newConn setDelegate: self];
  return YES;
}

- (id) connectionBecameInvalid: (NSNotification*)notification
{
  id conn = [notification object];

  [[NSNotificationCenter defaultCenter] removeObserver: self
				  name: NSConnectionDidDieNotification
				object: conn];

  if ([conn isKindOfClass: [NSConnection class]])
    {
      NSMutableArray	*a = [NSMutableArray arrayWithCapacity: 2];
      NSMutableString	*m;
      unsigned		i;

      /*
       *	Now remove any consoles that have disconnected.
       */
      m = [NSMutableString stringWithCapacity: 100];
      i = [consoles count];
      while (i-- > 0)
	{
	  ConsoleInfo	*o = (ConsoleInfo*)[consoles objectAtIndex: i];

	  if ([[o obj] connectionForProxy] == conn)
	    {
	      [a addObject: o];
	      [m appendFormat: cmdLogFormat(LT_AUDIT,
		@"removed (lost) console '%@'"), [o name]];
	      [consoles removeObjectAtIndex: i];
	      if (i <= consolePingPosition && consolePingPosition > 0)
		{
		  consolePingPosition--;
		}
	    }
	}

      if ([m length] > 0)
	{
	  [self information: m
		       type: LT_AUDIT
			 to: nil
		       from: nil];
	  [m setString: @""];
	}

      /*
       *	Now remove the commands from the active list.
       */
      i = [commands count];
      while (i-- > 0)
	{
	  CommandInfo*	o = (CommandInfo*)[commands objectAtIndex: i];

	  if ([[o obj] connectionForProxy] == conn)
	    {
	      EcAlarm	*e;
	      NSString	*s;

	      [a addObject: o];
	      s = EcMakeManagedObject([o name], @"Command", nil);
	      e = [EcAlarm alarmForManagedObject: s
		at: nil
		withEventType: EcAlarmEventTypeProcessingError
		probableCause: EcAlarmSoftwareProgramAbnormallyTerminated
		specificProblem: @"Host command/control availability"
		perceivedSeverity: EcAlarmSeverityCritical
		proposedRepairAction: @"Check network/host/process"
		additionalText: @"remove (lost) host"];
	      [self alarm: e];
	      [commands removeObjectAtIndex: i];
	      if (i <= commandPingPosition && commandPingPosition > 0)
		{
		  commandPingPosition--;
		}
	    }
	}
      [a removeAllObjects];
    }
  else
    {
      [self error: "non-Connection sent invalidation"];
    }
  if (nil != terminating && 0 == [commands count])
    {
      [self cmdQuit: 0];
    }
  return self;
}

- (void) dealloc
{
  DESTROY(alerter);
  [self cmdLogEnd: logname];
  if (timer != nil)
    {
      [timer invalidate];
    }
  DESTROY(mgr);
  DESTROY(fileBodies);
  DESTROY(fileDates);
  DESTROY(operators);
  DESTROY(config);
  DESTROY(commands);
  DESTROY(consoles);
  DESTROY(configFailed);
  DESTROY(configIncludeFailed);
  [super dealloc];
}

- (EcClientI*) findIn: (NSArray*)a
	byAbbreviation: (NSString*)s
{
  EcClientI	*o;
  int		i;
  int		best_pos = -1;
  int		best_len = 0;

  /*
   *	Special case - a numeric value is used as an index into the array.
   */
  if (isdigit(*[s cString]))
    {
      i = [s intValue];
      if (i >= 0 && i < [a count])
	{
	  return (EcClientI*)[a objectAtIndex: i];
	}
    }

  for (i = 0; i < [a count]; i++)
    {
      o = (EcClientI*)[a objectAtIndex: i];
      if (comp(s, [o name]) == 0)
	{
	  return o;
	}
      if (comp_len > best_len)
	{
	  best_len = comp_len;
	  best_pos = i;
	}
    }
  if (best_pos >= 0)
    {
      return (EcClientI*)[a objectAtIndex: best_pos];
    }
  return nil;
}

- (EcClientI*) findIn: (NSArray*)a
		byName: (NSString*)s
{
  EcClientI	*o;
  int		i;

  for (i = 0; i < [a count]; i++)
    {
      o = (EcClientI*)[a objectAtIndex: i];

      if (comp([o name], s) == 0)
	{
	  return o;
	}
    }
  return nil;
}

- (EcClientI*) findIn: (NSArray*)a
	      byObject: (id)s
{
  EcClientI	*o;
  int		i;

  for (i = 0; i < [a count]; i++)
    {
      o = (EcClientI*)[a objectAtIndex: i];

      if ([o obj] == s)
	{
	  return o;
	}
    }
  return nil;
}

- (void) information: (NSString*)inf
		type: (EcLogType)t
		  to: (NSString*)to
		from: (NSString*)from
{
  /*
   * Send anything but debug or accounting info to consoles.
   */
  if (t != LT_DEBUG)
    {
      NSArray	*a;
      unsigned	i;

      /*
       * Work with a copy of the consoles array in case one goes away
       * or is added while we are doing this!
       */
      a = [NSArray arrayWithArray: consoles];
      for (i = 0; i < [a count]; i++)
	{
	  ConsoleInfo	*c = [a objectAtIndex: i];
	  NSString	*name = [c name];

	  /*
	   *	If this console has gone away - skip it.
	   */
	  if ([consoles indexOfObjectIdenticalTo: c] == NSNotFound)
	    {
	      continue;
	    }

	  /*
	   *	If 'to' is nil - send to all consoles
	   */
	  if (to != nil && [to isEqual: name] == NO)
	    {
	      continue;
	    }

	  /*
	   *	If this is a warning message and the console is not interested
	   *	in warning then we skip this console.
	   */
	  if (t == LT_WARNING)
	    {
	      if ([c getWarnings] == NO)
		{
		  continue;
		}
	      else if ([c getGeneral] == NO)
		{
		  if (to != nil && [to isEqual: name] == NO)
		    {
		      continue;
		    }
		}
	    }
	  else if (t == LT_ERROR && [c getErrors] == NO)
	    {
	      continue;
	    }
	  else if (t == LT_ALERT && [c getAlerts] == NO)
	    {
	      continue;
	    }

	  NS_DURING
	    {
	      /*
	       *	Finally - we send the message to the console along with
	       *	a prompt.
	       */
	      [[c obj] information: [c promptAfter: inf]];
	    }
	  NS_HANDLER
	    {
	      NSLog(@"Caught: %@", localException);
	    }
	  NS_ENDHANDLER
	}
    }

  /*
   * Log, alerts, and accounting get written to the log file too.
   */
  if (t == LT_AUDIT || t == LT_ALERT)
    {
      [[self cmdLogFile: logname] puts: inf];
    }
  /*
   * Errors and alerts (severe errors) get passed to a handler.
   */
  if (t == LT_ERROR || t == LT_ALERT)
    {
      if (alerter != nil)
        {
	  [alerter handleInfo: inf];
	}
    }
}


- (id) initWithDefaults: (NSDictionary*)defs
{
  ecSetLogsSubdirectory(@"Logs");
  self = [super initWithDefaults: defs];
  if (self != nil)
    {
      commands = [[NSMutableArray alloc] initWithCapacity: 10];
      consoles = [[NSMutableArray alloc] initWithCapacity: 2];
      logname = [[self cmdName] stringByAppendingPathExtension: @"log"];
      RETAIN(logname);
      mgr = [NSFileManager defaultManager];
      RETAIN(mgr);
      if ([self cmdLogFile: logname] == nil)
	{
	  exit(0);
	}
      [self update];
      if (configFailed != nil)
	{
	  [self cmdQuit: 1];
	  return nil;
	}
      if (operators == nil)
	{
	  [self cmdQuit: 1];
	  return nil;
	}
      fileBodies = [[NSMutableDictionary alloc] initWithCapacity: 8];
      fileDates = [[NSMutableDictionary alloc] initWithCapacity: 8];

      timer = [NSTimer scheduledTimerWithTimeInterval: 15.0
					       target: self
					     selector: @selector(timedOut:)
					     userInfo: nil
					      repeats: YES];
      [self timedOut: nil];
    }
  return self;
}

- (int) ecRun
{
  int	result;

  /* Start the SNMP alarm sink before entering run loop.
   */
  NSDictionary *alertConf = [[self cmdDefaults] dictionaryForKey: @"Alerter"];
  NSString *host = [alertConf objectForKey: @"SNMPMasterAgentHost"];
  NSString *port = [alertConf objectForKey: @"SNMPMasterAgentPort"];
  lastAlertInfo = [NSMutableDictionary new];
  sink = [[EcAlarmSinkSNMP alloc] initWithHost: host name: port];

  result = [super ecRun];

  [sink shutdown];
  DESTROY(sink);

  return result;
}

- (void) quitAll
{
  NSArray       *hosts;
  NSUInteger	i;

  hosts = [[commands copy] autorelease];
  i = [hosts count];
  while (i-- > 0)
    {
      CommandInfo	*c = [hosts objectAtIndex: i];

      if ([commands indexOfObjectIdenticalTo: c] != NSNotFound)
        {
          NS_DURING
            {
              [[c obj] terminate];
            }
          NS_HANDLER
            {
              NSLog(@"Caught: %@", localException);
            }
          NS_ENDHANDLER
        }
    }
  if (0 == [commands count])
    {
      [self cmdQuit: 0];
    }
}

- (NSData*) registerCommand: (id<Command>)c
		       name: (NSString*)n
{
  NSMutableDictionary	*dict;
  CommandInfo		*obj;
  CommandInfo		*old;
  NSHost		*h;
  NSString		*m;
  EcAlarm		*a;
  id			o;

  if (nil == alerter)
    {
      [self update];		// Regenerate info from Control.plist
      if (nil == alerter)
	{
	  return nil;			// Not fully configured yet
	}
    }
  [(NSDistantObject*)c setProtocolForProxy: @protocol(Command)];
  dict = [NSMutableDictionary dictionaryWithCapacity: 3];

  h = [NSHost hostWithWellKnownName: n];
  if (nil == h)
    {
      h = [NSHost hostWithName: n];
    }
  if (nil == h)
    {
      m = [NSString stringWithFormat:
	  @"Rejected new host with bad name '%@' at %@\n", n, [NSDate date]];
      [self information: m
		   type: LT_AUDIT
		     to: nil
		   from: nil];
      [dict setObject: @"unable to handle given hostname."
	       forKey: @"rejected"];
      return [NSPropertyListSerialization
	dataFromPropertyList: dict
	format: NSPropertyListBinaryFormat_v1_0
	errorDescription: 0];
    }
  n = [h wellKnownName];

  old = (CommandInfo*)[self findIn: commands byObject: c];
  if (old != nil && [[old name] isEqual: n])
    {
      obj = old;
      m = [NSString stringWithFormat:
	  @"Re-registered existing host with name '%@' at %@\n",
	      n, [NSDate date]];
      [self information: m
		   type: LT_AUDIT
		     to: nil
		   from: nil];
    }
  else
    {
      /*
       *	Create a new reference for this client.
       */
      obj = [[CommandInfo alloc] initFor: c
				    name: n
				    with: self];

      old = (CommandInfo*)[self findIn: commands byName: n];
      [commands addObject: obj];
      RELEASE(obj);
      [commands sortUsingSelector: @selector(compare:)];
      if (nil == old)
        {
          m = [NSString stringWithFormat:
              @"Registered new host with name '%@' at %@\n",
                  n, [NSDate date]];
          [self domanage: EcMakeManagedObject(n, @"Command", nil)];
        }
      else
        {
          [old setObj: nil];
          m = [NSString stringWithFormat:
              @"Re-registered host with name '%@' at %@\n",
                  n, [NSDate date]];
          [commands removeObjectIdenticalTo: old];
        }
      [self information: m
                   type: LT_AUDIT
                     to: nil
                   from: nil];
    }

  /* Inform SNMP monitoring of new Command server.
   */
  a = [EcAlarm alarmForManagedObject: EcMakeManagedObject(n, @"Command", nil)
    at: nil
    withEventType: EcAlarmEventTypeProcessingError
    probableCause: EcAlarmSoftwareProgramAbnormallyTerminated
    specificProblem: @"Host command/control availability"
    perceivedSeverity: EcAlarmSeverityCleared
    proposedRepairAction: nil
    additionalText: nil];
  [self alarm: a];

  /*
   *	Return configuration information - general stuff, plus
   *	host specific stuff.
   */
  o = [config objectForKey: @"*"];
  if (o != nil)
    {
      [dict setObject: o forKey: @"*"];
    }
  o = [config objectForKey: h];
  if (o != nil)
    {
      [dict setObject: o forKey: n];
    }
  if (operators != nil)
    {
      [dict setObject: operators forKey: @"Operators"];
    }
  return [NSPropertyListSerialization
    dataFromPropertyList: dict
    format: NSPropertyListBinaryFormat_v1_0
    errorDescription: 0];
}

- (NSString*) registerConsole: (id<Console>)c
			 name: (NSString*)n
			 pass: (NSString*)p
{
  id		obj;
  NSString	*m;

  [(NSDistantObject*)c setProtocolForProxy: @protocol(Console)];
  obj = [self findIn: consoles byName: n];
  if (obj != nil)
    {
      m = [NSString stringWithFormat:
	@"%@ rejected console with info '%@' (already registered by name)\n",
	[NSDate date], n];
      [self information: m
		   type: LT_AUDIT
		     to: nil
		   from: nil];
      return @"Already registered by that name";
    }
  obj = [self findIn: consoles byObject: c];
  if (obj != nil)
    {
      m = [NSString stringWithFormat:
	@"%@ rejected console with info '%@' (already registered)\n",
	[NSDate date], n];
      [self information: m
		   type: LT_AUDIT
		     to: nil
		   from: nil];
      return @"Already registered";	/* Already registered.	*/
    }
  if (operators != nil)
    {
      NSRange		r = [n rangeOfString: @":"];
      NSString		*s = [n substringToIndex: r.location];
      NSDictionary	*info = [operators objectForKey: s];
      NSString		*passwd = [info objectForKey: @"Password"];

      if (nil == info)
        {
          /* If Operators.plist contains a user with an empty string as
           * a name, this will match any login attempt not already matched.
           */
          info = [operators objectForKey: @""];
          passwd = [info objectForKey: @"Password"];
        }
      if (info == nil)
	{
	  m = [NSString stringWithFormat:
	    @"%@ rejected console with info '%@' (unknown operator)\n",
	    [NSDate date], n];
	  [self information: m
		       type: LT_AUDIT
			 to: nil
		       from: nil];
	  return @"Unknown user name";
	}
      else if (passwd && [passwd length] && [passwd isEqual: p] == NO)
	{
	  m = [NSString stringWithFormat:
	    @"%@ rejected console with info '%@' (bad password)\n",
	    [NSDate date], n];
	  [self information: m
		       type: LT_AUDIT
			 to: nil
		       from: nil];
	  return @"Bad username/password combination";
	}
    }
  obj = [[ConsoleInfo alloc] initFor: c name: n with: self pass: p];
  [consoles addObject: obj];
  [consoles sortUsingSelector: @selector(compare:)];
  RELEASE(obj);
  m = [NSString stringWithFormat: @"%@ registered new console with info '%@'\n",
    [NSDate date], n];
  [self information: m
	       type: LT_AUDIT
		 to: nil
	       from: nil];
  return nil;
}

- (void) reply: (NSString*) msg to: (NSString*)n from: (NSString*)c
{
  [self information: msg type: LT_AUDIT to: n from: c];
}

- (void) reportAlarm: (EcAlarm*)alarm
            severity: (EcAlarmSeverity)severity
            reminder: (int)reminder
{
  NSString      *additional;
  NSString	*component;
  NSString	*connector;
  NSString	*identifier;
  NSString	*instance;
  NSString	*message;
  NSString	*repair;
  NSString	*spacing1;
  NSString	*spacing2;

  instance = [alarm moInstance];
  if ([instance length] == 0)
    {
      instance = @"";
      connector = @"";
    }
  else
    {
      connector = @"-";
    }

  component = [alarm moComponent];
  if (0 == [component length])
    {
      component = @"";
    }
  else
    {
      component = [NSString stringWithFormat: @"(%@)", component];
    }

  additional = [alarm additionalText];
  if ([additional length] == 0)
    {
      additional = @"";
      spacing1 = @"";
    }
  else
    {
      spacing1 = @": ";
    }

  repair = [alarm proposedRepairAction];
  if ([repair length] == 0)
    {
      repair = @"";
      spacing2 = @"";
    }
  else
    {
      spacing2 = @", ";
    }

  identifier = [NSString stringWithFormat: @"%d", [alarm notificationID]];

  alarm = [[alarm copy] autorelease];
  if (EcAlarmSeverityCleared == severity)
    {
      [alarm setExtra: @"Clear"];
      message = [NSString stringWithFormat:
        @"Clear %@ (%@)\n%@%@%@%@%@ - '%@%@%@%@' on %@",
        identifier, [EcAlarm stringFromSeverity: [alarm perceivedSeverity]],
        [alarm specificProblem], spacing1,
        additional, spacing2, repair,
        [alarm moProcess], connector, instance,
        component, [alarm moHost]];
      [alarm setExtra: @"Clear"];
    }
  else
    {
      if (reminder > 0)
        {
          [alarm setExtra: @"Reminder"];
        }
      else
        {
          [alarm setExtra: @"Alarm"];
        }
      message = [NSString stringWithFormat:
        @"Alarm %@ (%@)\n%@%@%@%@%@ - '%@%@%@%@' on %@",
        identifier, [EcAlarm stringFromSeverity: [alarm perceivedSeverity]],
        [alarm specificProblem], spacing1,
        additional, spacing2, repair,
        [alarm moProcess], connector, instance,
        component, [alarm moHost]];
      if (reminder > 0)
        {
          [alarm setExtra: @"Reminder"];
        }
      else
        {
          [alarm setExtra: @"Alarm"];
        }
    }

  [alerter handleEvent: message
              withHost: [alarm moHost]
             andServer: [alarm moProcess]
             timestamp: [alarm eventDate]
            identifier: identifier
                 alarm: alarm
              reminder: reminder];
}

- (void) reportAlarms
{
  NSMutableDictionary           *current;
  NSEnumerator                  *enumerator;
  EcAlarm                       *alarm;
  NSDate                        *now;
  NSString                      *key;
  NSArray	                *a;

  now = [NSDate date];
  a = [sink alarms];
  current = [NSMutableDictionary dictionaryWithCapacity: [a count]];
  enumerator = [a objectEnumerator];
  while (nil != (alarm = [enumerator nextObject]))
    {
      int               notificationID = [alarm notificationID];
      EcAlarmSeverity	severity = [alarm perceivedSeverity];

      if (notificationID > 0 && severity <= alertAlarmThreshold)
        {
          NSDictionary          *info;
          NSDate                *when;
          int                   reminder;
          NSTimeInterval        ti;

          ti = reminderInterval * 60.0;

          key = [NSString stringWithFormat: @"%d", notificationID];
          [current setObject: alarm forKey: key];
          info = [lastAlertInfo objectForKey: key];
          if (nil == info)
            {
              when = nil;
              reminder = 0;
            }
          else
            {
              when = [info objectForKey: @"When"];
              reminder = [[info objectForKey: @"Reminder"] intValue];
            }
          if (nil == when
            || (ti > 0.0 && [now timeIntervalSinceDate: when] > ti))
            {
              [self reportAlarm: alarm
                       severity: [alarm perceivedSeverity]
                       reminder: reminder];
              info = [NSDictionary dictionaryWithObjectsAndKeys:
                now, @"When",
                [NSNumber numberWithInt: reminder + 1], @"Reminder",
                nil];
              [lastAlertInfo setObject: info forKey: key];
            }
        }
    }

  /* Remove any alarms which no longer exist.
   */
  enumerator = [[lastAlertInfo allKeys] objectEnumerator];
  while (nil != (key = [enumerator nextObject]))
    {
      alarm = [current objectForKey: key];
      if (nil == alarm)
        {
          [lastAlertInfo removeObjectForKey: key];
        }
    }
}

- (oneway void) requestConfigFor: (id<CmdConfig>)c
{
  return;
}

- (void) servers: (NSData*)d
	      on: (id<Command>)s
{
  NSArray	*a;
  CommandInfo	*o;

  a = [NSPropertyListSerialization propertyListWithData: d
    options: NSPropertyListMutableContainers
    format: 0
    error: 0];
  o = (CommandInfo*)[self findIn: commands byObject: s];
  if (o != nil)
    {
      [o setServers: a];
    }
}

- (void) terminate: (NSTimer*)t
{
  if (nil == terminating)
    {
      [self information: @"Handling terminate."
                   type: LT_AUDIT
                     to: nil
                   from: nil];
    }

  if (nil == terminating)
    {
      terminating = [NSTimer scheduledTimerWithTimeInterval: 10.0
	target: self selector: @selector(terminate:)
	userInfo: [NSDate new]
	repeats: YES];
    }

  [self quitAll];

  if (t != nil)
    {
      NSDate	*when = (NSDate*)[t userInfo];

      if ([when timeIntervalSinceNow] < -60.0)
	{
	  [[self cmdLogFile: logname]
	    puts: @"Final shutdown.\n"];
	  [terminating invalidate];
	  terminating = nil;
	  [self cmdQuit: 0];
	}
    }
}

- (void) terminate
{
  [self terminate: nil];
}

- (void) timedOut: (NSTimer*)t
{
  static BOOL	inTimeout = NO;
  NSDate	*now = [t fireDate];

  if (now == nil)
    {
      now = [NSDate date];
    }

  [[self cmdLogFile: logname] synchronizeFile];
  if (inTimeout == NO)
    {
      NSString  *alive;
      NSString  *mesg;
      NSString  *ver;
      unsigned	count;

      inTimeout = YES;

      count = [commands count];
      while (count-- > 0)
	{
	  EcClientI	*r = [commands objectAtIndex: count];
	  NSDate	*d = [r lastUnanswered];

	  if (d != nil && [d timeIntervalSinceDate: now] < -pingDelay)
	    {
	      EcAlarm	*a;
	      NSString	*s;
	      NSString	*t;

	      s = EcMakeManagedObject([r name], @"Command", nil);
	      t = [NSString stringWithFormat:
		@"failed to respond for over %d seconds", (int)pingDelay];
	      a = [EcAlarm alarmForManagedObject: s
		at: nil
		withEventType: EcAlarmEventTypeProcessingError
		probableCause: EcAlarmSoftwareProgramAbnormallyTerminated
		specificProblem: @"Host command/control availability"
		perceivedSeverity: EcAlarmSeverityCritical
		proposedRepairAction: @"Check network/host/process"
		additionalText: t];
	      [self alarm: a];
	      [[[r obj] connectionForProxy] invalidate];
	      [commands removeObjectIdenticalTo: r];
	    }
	}

      count = [consoles count];
      while (count-- > 0)
	{
	  EcClientI	*r = [consoles objectAtIndex: count];
	  NSDate	*d = [r lastUnanswered];

	  if (d != nil && [d timeIntervalSinceDate: now] < -pingDelay)
	    {
	      NSString	*m;

	      m = [NSString stringWithFormat: cmdLogFormat(LT_WARNING,
		@"Operator '%@' failed to respond for over %d seconds"),
		[r name], (int)pingDelay];
	      [[[r obj] connectionForProxy] invalidate];
	      [consoles removeObjectIdenticalTo: r];
	      [self information: m type: LT_WARNING to: nil from: nil];
	    }
	}

      /*
       * We ping each client in turn.  If there are fewer than 4 clients,
       * we skip timeouts so that clients get pinged no more frequently
       * than one per 4 timeouts.
       */
      count = [commands count];
      if (commandPingPosition >= 4 && commandPingPosition >= count)
	{
	  commandPingPosition = 0;
	}
      if (commandPingPosition < count)
	{
	  [[commands objectAtIndex: commandPingPosition++] ping];
	}

      count = [consoles count];
      if (consolePingPosition >= 4 && consolePingPosition >= count)
	{
	  consolePingPosition = 0;
	}
      if (consolePingPosition < count)
	{
	  [[consoles objectAtIndex: consolePingPosition++] ping];
	}

      /*
       * Write heartbeat file to let external programs know we are alive.
       */
      ver = [[self cmdDefaults] stringForKey: @"ControlVersion"];
      if (nil == ver)
        {
          mesg = [NSString stringWithFormat: @"Heartbeat: %@\n", now];
        }
      else
        {
          mesg = [NSString stringWithFormat: @"Heartbeat: %@\nVersion: %@\n",
            now, ver];
        }
      alive = [NSString stringWithFormat: @"/tmp/%@.alive", [self cmdName]];
      [mesg writeToFile: alive atomically: YES];
      [mgr changeFileAttributes: [NSDictionary dictionaryWithObjectsAndKeys:
        [NSNumber numberWithInt: 0666], NSFilePosixPermissions,
        nil] atPath: alive];
    }
  [self reportAlarms];
  inTimeout = NO;
  if (nil != terminating && 0 == [commands count])
    {
      [self cmdQuit: 0];
    }
}

- (id) recursiveInclude: (id)o
{
  id	tmp;

  if ([o isKindOfClass: [NSArray class]] == YES)
    {
      NSMutableArray	*n;
      unsigned		i;
      unsigned		c = [o count];

      n = [[NSMutableArray alloc] initWithCapacity: c];
      for (i = 0; i < c; i++)
	{
	  id	tmp = [o objectAtIndex: i];

	  if ([tmp isKindOfClass: [NSString class]] == YES)
	    {
	      BOOL	multi = NO;

	      tmp = [self tryInclude: tmp multi: &multi];
	      if (multi == YES)
		{
		  [n addObjectsFromArray: tmp];
		}
	      else if (tmp != nil)
		{
		  [n addObject: tmp];
		}
	    }
	  else
	    {
	      tmp = [self recursiveInclude: tmp];
	      if (tmp != nil)
		{
		  [n addObject: tmp];
		}
	    }
	}
      return AUTORELEASE(n);
    }
  else if ([o isKindOfClass: [NSDictionary class]] == YES)
    {
      NSMutableDictionary	*n;
      NSEnumerator		*e = [o keyEnumerator];
      NSString			*k;
      unsigned			c = [o count];

      n = [[NSMutableDictionary alloc] initWithCapacity: c];
      while ((k = [e nextObject]) != nil)
	{
	  id	tmp = [self tryInclude: k multi: 0];

	  if ([tmp isKindOfClass: [NSDictionary class]] == YES)
	    {
	      [n addEntriesFromDictionary: tmp];
	    }
	  else
	    {
	      tmp = [self recursiveInclude:
			    [(NSDictionary *)o objectForKey: k]];
	      if (tmp != nil)
		{
		  [n setObject: tmp forKey: k];
		}
	    }
	}
      return AUTORELEASE(n);
    }
  else
    {
      tmp = [self tryInclude: o multi: 0];
      return tmp;
    }
}

- (id) getInclude: (id)s
{
  NSString	*base = [self cmdDataDirectory];
  NSString	*file;
  id		info;
  NSRange	r;

  r = [s rangeOfCharacterFromSet: [NSCharacterSet whitespaceCharacterSet]];

  if (r.length == 0)
    {
      return s;		// Not an include.
    }

  file = [s substringFromIndex: NSMaxRange(r)];
  if ([file isAbsolutePath] == NO)
    {
      file = [base stringByAppendingPathComponent: file];
    }
  if ([mgr isReadableFileAtPath: file] == NO)
    {
      NSString	*e;

      e = [NSString stringWithFormat: @"Unable to read file for '%@'\n", s];
      ASSIGN(configIncludeFailed, e);
      [[self cmdLogFile: logname] printf: @"%@", configIncludeFailed];
      return nil;
    }
  info = [NSString stringWithContentsOfFile: file];
  if (info == nil)
    {
      NSString	*e;

      e = [NSString stringWithFormat: @"Unable to load string for '%@'\n", s];
      ASSIGN(configIncludeFailed, e);
      [[self cmdLogFile: logname] printf: @"%@", configIncludeFailed];
      return nil;
    }
  NS_DURING
    {
      info = [info propertyList];
    }
  NS_HANDLER
    {
      NSString	*e;

      e = [NSString stringWithFormat: @"Unable to parse for '%@' - %@\n",
	s, localException];
      ASSIGN(configIncludeFailed, e);
      [[self cmdLogFile: logname] printf: @"%@", configIncludeFailed];
      info = nil;
    }
  NS_ENDHANDLER
  s = info;
  return s;
}

- (id) tryInclude: (id)s multi: (BOOL*)flag
{
  if (flag != 0)
    {
      *flag = NO;
    }
  if ([s isKindOfClass: [NSString class]] == YES)
    {
      if ([s hasPrefix: @"#include "] == YES)
	{
	  s = [self getInclude: s];
	}
      else if ([s hasPrefix: @"#includeKeys "] == YES)
	{
	  s = [self getInclude: s];
	  if ([s isKindOfClass: [NSDictionary class]] == YES)
	    {
	      s = [s allKeys];
	    }
	  if (flag != 0 && [s isKindOfClass: [NSArray class]] == YES)
	    {
	      *flag = YES;
	    }
	}
      else if ([s hasPrefix: @"#includeValues "] == YES)
	{
	  s = [self getInclude: s];
	  if ([s isKindOfClass: [NSDictionary class]] == YES)
	    {
	      s = [s allValues];
	    }
	  if (flag != 0 && [s isKindOfClass: [NSArray class]] == YES)
	    {
	      *flag = YES;
	    }
	}
    }
  return s;
}

- (oneway void) unmanage: (NSString*)name
{
  [sink unmanage: name];
}

- (void) unregister: (id)obj
{
  NSString	*m;
  EcClientI	*o = [self findIn: commands byObject: obj];

  if (o == nil)
    {
      o = [self findIn: consoles byObject: obj];
      if (o == nil)
	{
	  m = [NSString stringWithFormat:
	    @"%@ unregister by unknown host/console\n", [NSDate date]];
	}
      else
	{
	  m = [NSString stringWithFormat:
	    @"%@ removed (unregistered) console - '%@'\n",
	    [NSDate date], [o name]];
	  [o setUnregistered: YES];
	  [consoles removeObjectIdenticalTo: o];
	}
    }
  else
    {
      [self unmanage: EcMakeManagedObject([o name], @"Command", nil)];

      m = [NSString stringWithFormat:
	@"%@ removed (unregistered) host - '%@'\n", [NSDate date], [o name]];
      [o setUnregistered: YES];
      [commands removeObjectIdenticalTo: o];
    }
  [self information: m
	       type: LT_AUDIT
		 to: nil
	       from: nil];
  if (nil != terminating && 0 == [commands count])
    {
      [self cmdQuit: 0];
    }
}


- (Class)_loadClassFromBundle: (NSString*)bundleName
{
  NSString *path = nil;
  Class c = Nil;
  NSBundle *bundle = nil;
  path = [NSSearchPathForDirectoriesInDomains(NSLibraryDirectory,
    NSLocalDomainMask, YES) lastObject];
  path = [path stringByAppendingPathComponent: @"Bundles"];
  path = [path stringByAppendingPathComponent: bundleName];
  path = [path stringByAppendingPathExtension: @"bundle"];
  bundle = [NSBundle bundleWithPath: path];

  if (nil == bundle)
    {
      [[self cmdLogFile: logname] printf: 
       @"Couldn't load bundle '%@'", bundleName];
    }
  else if (Nil == (c = [bundle principalClass]))
    {
      [[self cmdLogFile: logname] printf: 
        @"Couldn't load principal class from %@"
        @" at %@.", bundleName, path];
    }
  else if (NO == [c isSubclassOfClass: [EcAlerter class]])
    {
      [[self cmdLogFile: logname] printf: 
        @"%@ is not a subclass of EcAlerter", 
        NSStringFromClass(c)];
      c = Nil;
    }
  return c;
}

- (BOOL) update
{
  NSMutableDictionary	*dict;
  NSDictionary		*conf;
  NSDictionary		*d;
  NSArray		*a;
  NSHost                *host;
  NSString		*base;
  NSString		*path;
  NSString		*str;
  unsigned		count;
  unsigned		i;
  BOOL			changed = NO;
  Class			alerterClass = Nil;

  host = [NSHost currentHost];
  str = [NSHost controlWellKnownName];
  if (nil != str)
    {
      if (NO == [[host wellKnownName] isEqual: str]
        && NO == [[host names] containsObject: str]
        && NO == [[host addresses] containsObject: str])
        {
	  NSLog(@"ControlHost well known name (%@) does not match"
            @" the current host (%@)", str, host);
	  [self cmdQuit: 1];
	  return NO;
        }
    }

  base = [self cmdDataDirectory];
  path = [base stringByAppendingPathComponent: @"AlertConfig.plist"];
  if ([mgr isReadableFileAtPath: path] == NO
    || (d = [NSDictionary dictionaryWithContentsOfFile: path]) == nil
    || (d = [self recursiveInclude: d]) == nil)
    {
      [[self cmdLogFile: logname]
	printf: @"Failed to load %@\n", path];
      return NO;
    }
  else
    {
      NSDictionary      *o = [[self cmdDefaults] dictionaryForKey: @"Alerter"];

      if (nil == o || NO == [o isEqual: d])
        {
	  NSString      *alerterDef;
          NSString      *str;

	  alerterDef = [d objectForKey: @"AlerterBundle"]; 
          str = [d objectForKey: @"AlertAlarmThreshold"];
          if (nil != str)
            {
              alertAlarmThreshold = [str intValue];
              if (alertAlarmThreshold < EcAlarmSeverityCritical)
                {
                  alertAlarmThreshold = EcAlarmSeverityCritical;
                }
              if (alertAlarmThreshold > EcAlarmSeverityWarning)
                {
                  alertAlarmThreshold = EcAlarmSeverityWarning;
                }
            }
          str = [d objectForKey: @"AlertReminderInterval"];
          if (nil != str)
            {
              reminderInterval = [str intValue];
              if (reminderInterval < 0)
                {
                  reminderInterval = 0;
                }
            }

          d = [NSDictionary dictionaryWithObjectsAndKeys:
            d, @"Alerter", nil];
          [[self cmdDefaults] setConfiguration: d];

	  if (nil == alerterDef)
	    {
	      alerterClass = [EcAlerter class];
	    }
	  else
	    {
	      // First, let's try whether this corresponds to
	      // a class we already loaded.
	      alerterClass = NSClassFromString(alerterDef);
	      if (Nil == alerterClass)
		{
		  // We didn't link the class. Try to load it 
		  // from a bundle.
		  alerterClass = 
		    [self _loadClassFromBundle: alerterDef];
		}
	    }
	  if (Nil == alerterClass)
	    {
	      NSLog(@"Could not load alerter class '%@'", alerterDef);
	    }
	  else if ([alerter class] != alerterClass)
	    {
	      DESTROY(alerter);
	    }

	  if (nil == alerter)
	    {
	      alerter = [alerterClass new];
	    }

          changed = YES;
        }
    }

  path = [base stringByAppendingPathComponent: @"Operators.plist"];
  if ([mgr isReadableFileAtPath: path] == NO
    || (d = [NSDictionary dictionaryWithContentsOfFile: path]) == nil
    || (d = [self recursiveInclude: d]) == nil)
    {
      [[self cmdLogFile: logname]
	printf: @"Failed to load %@\n", path];
      return NO;
    }
  else
    {
      if (operators == nil || [operators isEqual: d] == NO)
	{
	  changed = YES;
	  RELEASE(operators);
	  operators = [d mutableCopy];
	}
    }

  DESTROY(configIncludeFailed);
  path = [base stringByAppendingPathComponent: @"Control.plist"];
  if ([mgr isReadableFileAtPath: path] == NO
    || (str = [NSString stringWithContentsOfFile: path]) == nil)
    {
      NSString	*e;

      e = [NSString stringWithFormat:  @"Failed to load %@\n", path];
      ASSIGN(configFailed, e);
      [[self cmdLogFile: logname] printf: @"%@", configFailed];
      return NO;
    }

  NS_DURING
    {
      conf = [str propertyList];
      if ([conf isKindOfClass: [NSDictionary class]] == NO)
	{
	  [NSException raise: NSGenericException
		      format: @"Contents of file not a dictionary"];
	}
    }
  NS_HANDLER
    {
      NSString	*e;

      e = [NSString stringWithFormat:  @"Failed to load %@ - %@\n",
	path, [localException reason]];
      ASSIGN(configFailed, e);
      [[self cmdLogFile: logname] printf: @"%@", configFailed];
      return NO;
    }
  NS_ENDHANDLER

  if (nil != conf)
    {
      NSMutableDictionary	*root;
      NSEnumerator		*rootEnum;
      id			hostKey;

      if ([conf isKindOfClass: [NSDictionary class]] == NO)
	{
	  NSString	*e;

	  e = [NSString stringWithFormat:
	    @"%@ top-level is not a dictionary.\n", path];
	  ASSIGN(configFailed, e);
	  [[self cmdLogFile: logname] printf: @"%@", configFailed];
	  return NO;
	}

      /*
       * Build version with mutable dictionaries at the hosts and
       * applications/classes levels of the configuration.
       */
      conf = [self recursiveInclude: conf];
      [conf writeToFile: @"/tmp/Control.cnf" atomically: YES];
      [mgr changeFileAttributes: [NSDictionary dictionaryWithObjectsAndKeys:
        [NSNumber numberWithInt: 0666], NSFilePosixPermissions,
        nil] atPath: @"/tmp/Control.cnf"];

      root = [NSMutableDictionary dictionaryWithCapacity: [conf count]];
      rootEnum = [conf keyEnumerator];
      while ((hostKey = [rootEnum nextObject]) != nil)
	{
	  NSDictionary		*rootObj;
	  NSMutableDictionary	*host;
	  NSEnumerator		*hostEnum;
	  NSString		*appKey;

	  rootObj = [conf objectForKey: hostKey];

	  if ([rootObj isKindOfClass: [NSDictionary class]] == NO)
	    {
	      NSString	*e;

	      e = [NSString stringWithFormat:
		@"%@ host-level is not a dictionary for '%@'.\n",
		path, hostKey];
	      ASSIGN(configFailed, e);
	      [[self cmdLogFile: logname] printf: @"%@", configFailed];
	      return NO;
	    }
	  if ([hostKey isEqual: @"*"] == NO)
	    {
	      id	o = hostKey;

	      if ([o isEqual: @""]
		|| [o caseInsensitiveCompare: @"localhost"] == NSOrderedSame)
		{
		  hostKey = [NSHost currentHost];
		}
	      else
		{
		  hostKey = [NSHost hostWithWellKnownName: o];
                  if (nil == hostKey)
                    {
                      hostKey = [NSHost hostWithName: o];
                    }
		}
	      if (hostKey == nil)
		{
		  NSString	*e;

		  e = [NSString stringWithFormat:
		    @"%@ host '%@' unknown.\n", path, o];
		  ASSIGN(configFailed, e);
		  [[self cmdLogFile: logname] printf: @"%@", configFailed];
		  return NO;
		}
	    }

	  host = [NSMutableDictionary dictionaryWithCapacity:
	    [rootObj count]];
	  hostEnum = [rootObj keyEnumerator];
	  while ((appKey = [hostEnum nextObject]) != nil)
	    {
	      NSDictionary		*hostObj;
	      NSMutableDictionary	*app;

	      hostObj = [rootObj objectForKey: appKey];
	      if ([hostObj isKindOfClass: [NSDictionary class]] == NO)
		{
		  NSString	*e;

		  e = [NSString stringWithFormat:
		    @"%@ app-level is not a dictionary for '%@'\n",
		    path, appKey];
		  ASSIGN(configFailed, e);
		  [[self cmdLogFile: logname] printf: @"%@", configFailed];
		  return NO;
		}

	      app = [self recursiveInclude: hostObj];
	      [host setObject: app forKey: appKey];
	    }
	  [root setObject: host forKey: hostKey];
	}

      if (config == nil || [config isEqual: root] == NO)
	{
	  changed = YES;
          ASSIGN(config, root);
	}
    }

  if (YES == changed)
    {
      /* Merge the globalconfiguration into this process' user defaults.
       * Don't forget to preserve the Alerter config.
       */
      d = [config objectForKey: @"*"];
      if ([d isKindOfClass: [NSDictionary class]])
        {
          d = [d objectForKey: @"*"];
        }
      if (YES == [d isKindOfClass: [NSDictionary class]])
        {
          dict = [d mutableCopy];
          [dict setObject: [[self cmdDefaults] objectForKey: @"Alerter"]
                   forKey: @"Alerter"];
          [[self cmdDefaults] setConfiguration: dict];
          [dict release];
        }

      dict = [NSMutableDictionary dictionaryWithCapacity: 3];

      /*
       * Now per-host config dictionaries consisting of general and
       * host-specific dictionaries.
       */
      a = [NSArray arrayWithArray: commands];
      count = [a count];
      for (i = 0; i < count; i++)
	{
	  CommandInfo	*c = [a objectAtIndex: i];

	  if ([commands indexOfObjectIdenticalTo: c] != NSNotFound)
	    {
	      id	o;
	      NSHost	*h;

	      [dict removeAllObjects];
	      o = [config objectForKey: @"*"];
	      if (o != nil)
		{
		  [dict setObject: o forKey: @"*"];
		}
	      h = [NSHost hostWithWellKnownName: [c name]];
              if (nil == h)
                {
                  h = [NSHost hostWithName: [c name]];
                }
	      o = [config objectForKey: h];
	      if (o != nil)
		{
		  [dict setObject: o forKey: [c name]];
		}
	      if (operators != nil)
		{
		  [dict setObject: operators forKey: @"Operators"];
		}
	      NS_DURING
		{
		  NSData	*dat;

		  dat = [NSPropertyListSerialization
		    dataFromPropertyList: dict
		    format: NSPropertyListBinaryFormat_v1_0
		    errorDescription: 0];
		  [[c obj] updateConfig: dat];
		}
	      NS_HANDLER
		{
		  [[self cmdLogFile: logname]
		    printf: @"Updating config for '%@':%@",
		    [c name], localException];
		}
	      NS_ENDHANDLER
	    }
	}
    }
  DESTROY(configFailed);

  return changed;
}

- (void) updateConfig: (NSData*)dummy
{
  [self update];
}

@end

