
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

#import "EcProcess.h"
#import "EcAlarm.h"
#import "EcClientI.h"
#import "EcHost.h"
#import "NSFileHandle+Printf.h"

#import "config.h"

#define	DLY	300.0

static const NSTimeInterval   day = 24.0 * 60.0 * 60.0;

static int	tStatus = 0;

static NSTimeInterval	pingDelay = 240.0;

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
      if (comp_len == (int)[s1 length])
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

/* Special configuration options are:
 *
 * CompressLogsAfter
 *   A positive integer number of days after which logs should be compressed
 *   defaults to 14.
 *
 * DeleteLogsAfter
 *   A positive integer number of days after which logs should be deleted.
 *   Constrained to be at least as large as CompressLogsAfter.
 *   Defaults to 1000, but logs may still be deleted as if this were set
 *   to CompressLogsAfter if NodesFree or SpaceFree is reached.
 *
 * Environment
 *   A dictionary setting the default environment for launched processes.
 *
 * Launch
 *   A dictionary describing the processes which the server is responsible
 *   for launching.
 *
 * NodesFree
 *   A string giving a percentage of the total nodes on the disk below
 *   which an alert should be raised. Defaults to 10.
 *   Minimum 2, Maximum 90.
 *
 * SpaceFree
 *   A string giving a percentage of the total space on the disk below
 *   which an alert should be raised. Defaults to 10.
 *   Minimum 2, Maximum 90.
 *
 */
@interface	EcCommand : EcProcess <Command>
{
  NSString		*host;
  id<Control>		control;
  NSMutableArray	*clients;
  NSTimer		*timer;
  NSString		*logname;
  NSMutableDictionary	*config;
  NSDictionary		*launchInfo;
  NSDictionary		*environment;
  NSMutableDictionary	*launches;
  NSMutableSet		*launching;
  NSMutableSet		*alarmed;
  unsigned		pingPosition;
  NSTimer		*terminating;
  NSDate		*lastUnanswered;
  unsigned		fwdSequence;
  unsigned		revSequence;
  float			nodesFree;
  float			spaceFree;
  NSTimeInterval        uncompressed;
  NSTimeInterval        undeleted;
  BOOL                  sweeping;
}
- (NSFileHandle*) openLog: (NSString*)lname;
- (void) cmdGnip: (id <CmdPing>)from
	sequence: (unsigned)num
	   extra: (NSData*)data;
- (void) cmdPing: (id <CmdPing>)from
	sequence: (unsigned)num
	   extra: (NSData*)data;
- (void) cmdQuit: (NSInteger)sig;
- (void) command: (NSData*)dat
	      to: (NSString*)t
	    from: (NSString*)f;
- (NSData *) configurationFor: (NSString *)name;
- (BOOL) connection: (NSConnection*)ancestor
  shouldMakeNewConnection: (NSConnection*)newConn;
- (id) connectionBecameInvalid: (NSNotification*)notification;
- (NSArray*) findAll: (NSArray*)a
      byAbbreviation: (NSString*)s;
- (EcClientI*) findIn: (NSArray*)a
       byAbbreviation: (NSString*)s;
- (EcClientI*) findIn: (NSArray*)a
               byName: (NSString*)s;
- (EcClientI*) findIn: (NSArray*)a
             byObject: (id)s;
- (void) information: (NSString*)inf
		from: (NSString*)s
		type: (EcLogType)t;
- (void) information: (NSString*)inf
		from: (NSString*)s
		  to: (NSString*)d
		type: (EcLogType)t;
- (void) launch;
- (void) logMessage: (NSString*)msg
	       type: (EcLogType)t
	        for: (id<CmdClient>)o;
- (void) logMessage: (NSString*)msg
	       type: (EcLogType)t
	       name: (NSString*)c;
- (NSString*) makeSpace;
- (void) newConfig: (NSMutableDictionary*)newConfig;
- (void) pingControl;
- (void) quitAll;
- (void) requestConfigFor: (id<CmdConfig>)c;
- (NSData*) registerClient: (id<CmdClient>)c
		      name: (NSString*)n;
- (NSData*) registerClient: (id<CmdClient>)c
		      name: (NSString*)n
		 transient: (BOOL)t;
- (void) reply: (NSString*) msg to: (NSString*)n from: (NSString*)c;
- (void) terminate;
- (void) timedOut: (NSTimer*)t;
- (void) unregisterByObject: (id)obj;
- (void) unregisterByName: (NSString*)n;
- (void) update;
- (void) updateConfig: (NSData*)data;
@end

@implementation	EcCommand

- (oneway void) alarm: (in bycopy EcAlarm*)alarm
{
  NS_DURING
    {
      [control alarm: alarm];
    }
  NS_HANDLER
    {
      NSLog(@"Exception sending alarm to Control: %@", localException);
    }
  NS_ENDHANDLER
}

- (oneway void) domanage: (in bycopy NSString*)managedObject
{
  NS_DURING
    {
      [control domanage: managedObject];
    }
  NS_HANDLER
    {
      NSLog(@"Exception sending domanage: to Control: %@", localException);
    }
  NS_ENDHANDLER
}

- (oneway void) unmanage: (in bycopy NSString*)managedObject
{
  NS_DURING
    {
      [control unmanage: managedObject];
    }
  NS_HANDLER
    {
      NSLog(@"Exception sending unmanage: to Control: %@", localException);
    }
  NS_ENDHANDLER
}

- (NSFileHandle*) openLog: (NSString*)lname
{
  NSFileManager	*mgr = [NSFileManager defaultManager];
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

- (void) newConfig: (NSMutableDictionary*)newConfig
{
  NSString	*diskCache;
  NSData	*data;

  diskCache = [[self cmdDataDirectory]
    stringByAppendingPathComponent: @"CommandConfig.cache"];

  if (NO == [newConfig isKindOfClass: [NSMutableDictionary class]]
    || 0 == [newConfig count])
    {
      /* If we are called with a nil argument, we must obtain the config
       * from local disk cache (if available).
       */
      if (nil != (data = [NSData dataWithContentsOfFile: diskCache]))
	{
	  newConfig = [NSPropertyListSerialization
	    propertyListWithData: data
	    options: NSPropertyListMutableContainers
	    format: 0
	    error: 0];
	}
      if (NO == [newConfig isKindOfClass: [NSMutableDictionary class]]
	|| 0 == [newConfig count])
	{
	  return;
	}
    }
  else
    {
      data = nil;
    }

  if (nil == config || [config isEqual: newConfig] == NO)
    {
      NSDictionary	*d;
      NSArray		*a;
      unsigned		i;

      ASSIGN(config, newConfig);

      d = [config objectForKey: [self cmdName]];
      DESTROY(launchInfo);
      DESTROY(environment);
      if ([d isKindOfClass: [NSDictionary class]] == YES)
	{
          NSMutableDictionary   *m;
	  NSString              *k;
          NSString              *err = nil;

          m = [[d mutableCopy] autorelease];
          d = m;
          NS_DURING
            [self cmdUpdate: m];
          NS_HANDLER
            NSLog(@"Problem before updating config (in cmdUpdate:) %@",
              localException);
            err = @"the -cmdUpdate: method raised an exception";
          NS_ENDHANDLER
          if (nil == err)
            {
              NS_DURING
                err = [self cmdUpdated];
              NS_HANDLER
                NSLog(@"Problem after updating config (in cmdUpdated) %@",
                  localException);
                err = @"the -cmdUpdated method raised an exception";
              NS_ENDHANDLER
            }
          if ([err length] > 0)
            {
              EcAlarm       *a;

              /* Truncate additional text to fit if necessary.
               */
              err = [err stringByTrimmingSpaces];
              if ([err length] > 255)
                {
                  err = [err substringToIndex: 255];
                  while (255 < strlen([err UTF8String]))
                    {
                      err = [err substringToIndex: [err length] - 1];
                    }
                }
              a = [EcAlarm alarmForManagedObject: nil
                at: nil
                withEventType: EcAlarmEventTypeProcessingError
                probableCause: EcAlarmConfigurationOrCustomizationError
                specificProblem: @"configuration error"
                perceivedSeverity: EcAlarmSeverityMajor
                proposedRepairAction:
                _(@"Correct config or software (check log for details).")
                additionalText: err];
              [self alarm: a];
            }
          else
            {
              EcAlarm       *a;

              a = [EcAlarm alarmForManagedObject: nil
                at: nil
                withEventType: EcAlarmEventTypeProcessingError
                probableCause: EcAlarmConfigurationOrCustomizationError
                specificProblem: @"configuration error"
                perceivedSeverity: EcAlarmSeverityCleared
                proposedRepairAction: nil
                additionalText: nil];
              [self alarm: a];
            }

	  launchInfo = [d objectForKey: @"Launch"];
	  if ([launchInfo isKindOfClass: [NSDictionary class]] == NO)
	    {
	      NSLog(@"No 'Launch' information in latest config update");
	      launchInfo = nil;
	    }
	  else
	    {
	      NSEnumerator	*e = [launchInfo keyEnumerator];

	      while ((k = [e nextObject]) != nil)
		{
		  NSDictionary	*d = [launchInfo objectForKey: k];
		  id		o;

		  if ([d isKindOfClass: [NSDictionary class]] == NO)
		    {
		      NSLog(@"bad 'Launch' information for %@", k);
		      launchInfo = nil;
		      break;
		    }
		  o = [d objectForKey: @"Auto"];
		  if (o != nil && [o isKindOfClass: [NSString class]] == NO)
		    {
		      NSLog(@"bad 'Launch' Auto for %@", k);
		      launchInfo = nil;
		      break;
		    }
		  o = [d objectForKey: @"Disabled"];
		  if (o != nil && [o isKindOfClass: [NSString class]] == NO)
		    {
		      NSLog(@"bad 'Launch' Disabled for %@", k);
		      launchInfo = nil;
		      break;
		    }
		  o = [d objectForKey: @"Args"];
		  if (o != nil && [o isKindOfClass: [NSArray class]] == NO)
		    {
		      NSLog(@"bad 'Launch' Args for %@", k);
		      launchInfo = nil;
		      break;
		    }
		  o = [d objectForKey: @"Home"];
		  if (o != nil && [o isKindOfClass: [NSString class]] == NO)
		    {
		      NSLog(@"bad 'Launch' Home for %@", k);
		      launchInfo = nil;
		      break;
		    }
		  o = [d objectForKey: @"Prog"];
		  if (o == nil || [o isKindOfClass: [NSString class]] == NO)
		    {
		      NSLog(@"bad 'Launch' Prog for %@", k);
		      launchInfo = nil;
		      break;
		    }
		  o = [d objectForKey: @"AddE"];
		  if (o != nil && [o isKindOfClass: [NSDictionary class]] == NO)
		    {
		      NSLog(@"bad 'Launch' AddE for %@", k);
		      launchInfo = nil;
		      break;
		    }
		  o = [d objectForKey: @"SetE"];
		  if (o != nil && [o isKindOfClass: [NSDictionary class]] == NO)
		    {
		      NSLog(@"bad 'Launch' SetE for %@", k);
		      launchInfo = nil;
		      break;
		    }
		}
	    }
	  RETAIN(launchInfo);
	  environment = [d objectForKey: @"Environment"];
	  if ([environment isKindOfClass: [NSDictionary class]] == NO)
	    {
	      NSLog(@"No 'Environment' information in latest config update");
	      environment = nil;
	    }
	  RETAIN(environment);

	  k = [d objectForKey: @"NodesFree"];
	  if (YES == [k isKindOfClass: [NSString class]])
	    {
	      nodesFree = [k floatValue];
	      nodesFree /= 100.0;
	    }
	  else
	    {
	      nodesFree = 0.0;
	    }
	  if (nodesFree < 0.02 || nodesFree > 0.9)
	    {
	      NSLog(@"bad or missing minimum disk 'NodesFree' ... using 10%%");
	      nodesFree = 0.1;
	    }
	  k = [d objectForKey: @"SpaceFree"];
	  if (YES == [k isKindOfClass: [NSString class]])
	    {
	      spaceFree = [k floatValue];
	      spaceFree /= 100.0;
	    }
	  else
	    {
	      spaceFree = 0.0;
	    }
	  if (spaceFree < 0.02 || spaceFree > 0.9)
	    {
	      NSLog(@"bad or missing minimum disk 'SpaceFree' ... using 10%%");
	      spaceFree = 0.1;
	    }
	}
      else
	{
	  NSLog(@"No '%@' information in latest config update", [self cmdName]);
	}

      a = [NSArray arrayWithArray: clients];
      i = [a count];
      while (i-- > 0)
	{ 
	  EcClientI	*c = [a objectAtIndex: i];

	  if ([clients indexOfObjectIdenticalTo: c] != NSNotFound)
	    {
	      NS_DURING
		{
		  NSData	*d = [self configurationFor: [c name]];

		  if (nil != d)
		    {
		      [c setConfig: d];
		      [[c obj] updateConfig: d];
		    }
		}
	      NS_HANDLER
		{
		  NSLog(@"Setting config for client: %@", localException);
		}
	      NS_ENDHANDLER
	    }
	}
      if (nil == data)
	{
	  /* Need to update on-disk cache
	   */
	  data = [NSPropertyListSerialization
	    dataFromPropertyList: newConfig
	    format: NSPropertyListBinaryFormat_v1_0
	    errorDescription: 0];
	  [data writeToFile: diskCache atomically: YES];
	}
    }
}

- (void) pingControl
{
  if (control == nil)
    {
      return;
    }
  if (fwdSequence == revSequence)
    {
      lastUnanswered = RETAIN([NSDate date]);
      NS_DURING
	{
	  [control cmdPing: self sequence: ++fwdSequence extra: nil];
	}
      NS_HANDLER
	{
	  NSLog(@"Ping to control server - %@", localException);
	}
      NS_ENDHANDLER
    }
  else
    {
      NSLog(@"Ping to control server when one is already in progress.");
    }
}

- (void) cmdGnip: (id <CmdPing>)from
	sequence: (unsigned)num
	   extra: (NSData*)data
{
  if (from == control)
    {
      if (num != revSequence + 1 && revSequence != 0)
	{
	  NSLog(@"Gnip from control server seq: %u when expecting %u",
	    num, revSequence);
	  if (num == 0)
	    {
	      fwdSequence = 0;	// Reset
	    }
	}
      revSequence = num;
      if (revSequence == fwdSequence)
	{
	  DESTROY(lastUnanswered);
	}
    }
  else
    {
      EcClientI	*r;

      /* See if we have a fitting client - and update records.
       */
      r = [self findIn: clients byObject: (id)from];
      if (r != nil)
	{
          NSString      *n = [r name];

	  [r gnip: num];

          /* After the first ping response from a client we assume
           * that client has completed startup and is running OK.
           * We can therefore clear any loss of client alarm.
           */
          if (nil != [alarmed member: n])
            {
              NSString	*managedObject;
              EcAlarm	*a;

              [alarmed removeObject: n];
              managedObject = EcMakeManagedObject(host, n, nil);
              a = [EcAlarm alarmForManagedObject: managedObject
                at: nil
                withEventType: EcAlarmEventTypeProcessingError
                probableCause: EcAlarmSoftwareProgramAbnormallyTerminated
                specificProblem: @"Process availability"
                perceivedSeverity: EcAlarmSeverityCleared
                proposedRepairAction: nil
                additionalText: nil];
              [self alarm: a];
              [self clearConfigurationFor: managedObject
                          specificProblem: @"Process launch"
                           additionalText: @"Process is now running"];
            }
	}
    }
}

- (BOOL) cmdIsClient
{
  return NO;	// Not a client of the Command server.
}

- (void) cmdPing: (id <CmdPing>)from
	sequence: (unsigned)num
	   extra: (NSData*)data
{
  /* Send back a response to let the other party know we are alive.
   */
  [from cmdGnip: self sequence: num extra: nil];
}

- (void) cmdQuit: (NSInteger)sig
{
  if (sig == tStatus && control != nil)
    {
      NS_DURING
	{
	  [control unregister: self];
	}
      NS_HANDLER
	{
	  NSLog(@"Exception unregistering from Control: %@", localException);
	}
      NS_ENDHANDLER
    }
  exit(sig);
}

- (void) command: (NSData*)dat
	      to: (NSString*)t
	    from: (NSString*)f
{
  NSMutableArray	*cmd = [NSPropertyListSerialization
    propertyListWithData: dat
    options: NSPropertyListMutableContainers
    format: 0
    error: 0];

  if (cmd == nil || [cmd count] == 0)
    {
      [self information: cmdLogFormat(LT_ERROR, @"bad command array")
		   from: nil
		     to: f
		   type: LT_ERROR];
    }
  else if (t == nil)
    {
      NSString	*m = @"";
      NSString	*wd = cmdWord(cmd, 0);

      if ([wd length] == 0)
	{
	  /* Quietly ignore.	*/
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
      else if (comp(wd, @"help") >= 0)
	{
	  wd = cmdWord(cmd, 1);
	  if ([wd length] == 0)
	    {
	      m = @"Commands are -\n"
	      @"Help\tArchive\tControl\tLaunch\tList\tMemory\tQuit\tTell\n\n"
	      @"Type 'help' followed by a command word for details.\n"
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
	      if (comp(wd, @"Archive") >= 0)
		{
		  m = @"Archive\nArchives the log file. The archived log "
		      @"file is stored in a subdirectory whose name is of "
		      @"the form YYYYMMDDhhmmss being the date and time at "
		      @"which the archive was created.\n";
		}
	      else if (comp(wd, @"Control") >= 0)
		{
		  m = @"Control ...\nPasses the command to the Control "
		      @"process.  You may disconnect from this host by "
		      @"typing 'control host'\n";
		}
	      else if (comp(wd, @"Launch") >= 0)
		{
		  m = @"Launch <name>\nAdds the named program to the list "
		      @"of programs to be launched as soon as possible.\n"
		      @"Launch all\nAdds all unlaunched programs which do "
		      @"not have autolaunch disabled.\n";
		}
	      else if (comp(wd, @"List") >= 0)
		{
		  m = @"List\nLists all the connected clients.\n"
		      @"List launches\nLists the programs we can launch.\n";
		}
	      else if (comp(wd, @"Memory") >= 0)
		{
		  m = @"Memory\nDisplays recent memory allocation stats.\n"
		      @"Memory all\nDisplays all memory allocation stats.\n";
		}
	      else if (comp(wd, @"Quit") >= 0)
		{
		  m = @"Quit 'name'\n"
		      @"Shuts down the named client process(es).\n"
		      @"Quit all\n"
		      @"Shuts down all client processes.\n"
		      @"Quit self\n"
		      @"Shuts down the command server for this host.\n";
		}
	      else if (comp(wd, @"Tell") >= 0)
		{
		  m = @"Tell 'name' 'command'\n"
		      @"Sends the command to the named client(s).\n"
		      @"You may use 'tell all ...' to send to all clients.\n";
		}
	    }
	}
      else if (comp(wd, @"launch") >= 0)
	{
	  if ([cmd count] > 1)
	    {
	      if (launchInfo != nil)
		{
		  NSEnumerator	*enumerator;
		  NSString	*key;
		  NSString	*nam = [cmd objectAtIndex: 1];
		  BOOL		found = NO;

		  enumerator = [launchInfo keyEnumerator];
                  if ([nam caseInsensitiveCompare: @"all"] == NSOrderedSame)
                    {
                      NSMutableArray  *names = [NSMutableArray array];

                      while ((key = [enumerator nextObject]) != nil)
                        {
                          EcClientI	*r;
                          NSDictionary  *inf;

                          inf = [launchInfo objectForKey: key];
			  if ([[inf objectForKey: @"Auto"] boolValue]==NO)
                            {
                              continue;
                            }
                          r = [self findIn: clients byName: key];
                          if (nil != r)
                            {
                              continue;
                            }
                          found = YES;
                          [launches setObject: [NSDate distantPast]
                                       forKey: key];
                          [names addObject: key];
                        }
                      if (YES == found)
                        {
                          [names sortUsingSelector: @selector(compare:)];
                          m = [NSString stringWithFormat:
                            @"Ok - I will launch %@ when I get a chance.\n",
                            names];
                        }
                    }
                  else
                    {
                      while ((key = [enumerator nextObject]) != nil)
                        {
                          if (comp(nam, key) >= 0)
                            {
                              EcClientI	*r;

                              found = YES;
                              r = [self findIn: clients byName: key];
                              if (r == nil)
                                {
                                  [launches setObject: [NSDate distantPast]							   forKey: key];
                                  m = @"Ok - I will launch that program "
                                      @"when I get a chance.\n";
                                }
                              else
                                {
                                  m = @"That program is already running\n";
                                }
                            }
                        }
                    }
		  if (found == NO)
		    {
		      m = @"I don't know how to launch that program.\n";
		    }
		}
	      else
		{
		  m = @"There are no programs we can launch.\n";
		}
	    }
	  else
	    {
	      m = @"I need the name of a program to launch.\n";
	    }
	}
      else if (comp(wd, @"list") >= 0)
	{
	  wd = cmdWord(cmd, 1);
	  if ([wd length] == 0 || comp(wd, @"clients") >= 0)
	    {
	      if ([clients count] == 0)
		{
		  m = @"No clients currently connected.\n";
		}
	      else
		{
		  unsigned	i;

		  m = @"Current client processes -\n";
		  for (i = 0; i < [clients count]; i++)
		    {
		      EcClientI*	c = [clients objectAtIndex: i];

		      m = [NSString stringWithFormat: 
			  @"%@%2d.   %-32.32s\n", m, i, [[c name] cString]];
		    }
		}
	    }
	  else if (comp(wd, @"launches") >= 0)
	    {
	      if (launchInfo != nil)
		{
		  NSEnumerator	*enumerator;
		  NSString	*key;
		  NSDate	*date;
		  NSDate	*now = [NSDate date];

		  m = @"Programs we can launch -\n";
		  enumerator = [[[launchInfo allKeys] sortedArrayUsingSelector:
		    @selector(compare:)] objectEnumerator];
		  while ((key = [enumerator nextObject]) != nil)
		    {
		      EcClientI	*r;
		      NSDictionary	*inf = [launchInfo objectForKey: key];

		      m = [m stringByAppendingFormat: @"  %-32.32s ",
			[key cString]];
		      r = [self findIn: clients byName: key];
		      if (r == nil)
			{
			  if ([[inf objectForKey: @"Disabled"] boolValue]==YES)
			    {
			      m = [m stringByAppendingString: 
				@"disabled in config\n"];
			    }
			  else if ([[inf objectForKey: @"Auto"] boolValue]==NO)
			    {
			      date = [launches objectForKey: key];
			      if (nil == date
				|| [NSDate distantFuture] == date)
				{
				  m = [m stringByAppendingString: 
				    @"may be launched manually\n"];
				}
			      else if ([now timeIntervalSinceDate: date] > DLY)
				{
				  m = [m stringByAppendingString: 
				    @"ready to autolaunch now\n"];
				}
			      else
				{
				  m = [m stringByAppendingString: 
				    @"autolaunch in a few minutes\n"];
				}
			    }
			  else
			    {
			      date = [launches objectForKey: key];
			      if (date == nil)
				{
				  date = now;
				  [launches setObject: date forKey: key];
				}
			      if ([NSDate distantFuture] == date)
				{
				  m = [m stringByAppendingString: 
				    @"manually suspended\n"];
				}
			      else
				{
				  if ([now timeIntervalSinceDate: date] > DLY)
				    {
				      m = [m stringByAppendingString: 
					@"ready to autolaunch now\n"];
				    }
				  else
				    {
				      m = [m stringByAppendingString: 
					@"autolaunch in a few minutes\n"];
				    }
				}
			    }
			}
		      else
			{
			  m = [m stringByAppendingString: @"running\n"];
			}
		    }
		  if ([launchInfo count] == 0)
		    {
		      m = [m stringByAppendingString: @"nothing\n"];
		    }
		}
	      else
		{
		  m = @"There are no programs we can launch.\n";
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
	  wd = cmdWord(cmd, 1);
	  if ([wd length] > 0)
	    {
	      if (comp(wd, @"self") == 0)
		{
		  if (terminating == nil)
		    {
		      NS_DURING
			{
			  [control unregister: self];
			}
		      NS_HANDLER
			{
			  NSLog(@"Exception unregistering from Control: %@",
			    localException);
			}
		      NS_ENDHANDLER
		      exit(0);
		    }
		  else
		    {
		      m = @"Already terminating!\n";
		    }
		}
	      else if (comp(wd, @"all") == 0)
		{
		  [self quitAll];

		  if ([clients count] == 0)
		    {
		      m = @"All clients have been shut down.\n";
		    }
		  else if ([clients count] == 1)
		    {
		      m = @"One client did not shut down.\n";
		    }
		  else
		    {
		      m = @"Some clients did not shut down.\n";
		    }
		}
	      else
		{
		  NSArray	*a = [self findAll: clients byAbbreviation: wd];
		  unsigned	i;
		  BOOL		found = NO;

		  for (i = 0; i < [a count]; i++)
		    {
		      EcClientI	*c = [a objectAtIndex: i];

		      NS_DURING
			{
			  [launches setObject: [NSDate distantFuture]
				       forKey: [c name]];
			  m = [m stringByAppendingFormat: 
			    @"Sent 'quit' to '%@'\n", [c name]];
			  m = [m stringByAppendingString:
			    @"  Please wait for this to be 'removed' before "
			    @"proceeding.\n"];
			  [[c obj] cmdQuit: 0];
			  found = YES;
			}
		      NS_HANDLER
			{
			  NSLog(@"Caught exception: %@", localException);
			}
		      NS_ENDHANDLER
		    } 
		  if (launchInfo != nil)
		    {
		      NSEnumerator	*enumerator;
		      NSString		*key;

		      enumerator = [launchInfo keyEnumerator];
		      while ((key = [enumerator nextObject]) != nil)
			{
			  if (comp(wd, key) >= 0)
			    {
			      NSDate	*when = [launches objectForKey: key];

			      found = YES;
			      [launches setObject: [NSDate distantFuture]
					   forKey: key];
			      if (when != [NSDate distantFuture])
				{
				  m = [m stringByAppendingFormat:
				    @"Suspended %@\n", key];
				}
			    }
			}
		    }
		  if (NO == found)
		    {
		      m = [NSString stringWithFormat: 
			@"Nothing to shut down as '%@'\n", wd];
		    }
		}
	    }
	  else
	    {
	      m = @"Quit what?.\n";
	    }
	}
      else if (comp(wd, @"tell") >= 0)
	{
	  wd = cmdWord(cmd, 1);
	  if ([wd length] > 0)
	    {
	      NSString	*dest = AUTORELEASE(RETAIN(wd));

	      [cmd removeObjectAtIndex: 0];
	      [cmd removeObjectAtIndex: 0];
	      if (comp(dest, @"all") == 0)
		{
		  unsigned	i;
		  NSArray	*a = [[NSArray alloc] initWithArray: clients];

		  for (i = 0; i < [a count]; i++)
		    {
		      EcClientI*	c = [a objectAtIndex: i];

		      if ([clients indexOfObjectIdenticalTo: c]!=NSNotFound)
			{
			  NS_DURING
			    {
			      NSData	*dat = [NSPropertyListSerialization
				dataFromPropertyList: cmd
				format: NSPropertyListBinaryFormat_v1_0
				errorDescription: 0];
			      [[c obj] cmdMesgData: dat from: f];
			      m = @"Sent message.\n";
			    }
			  NS_HANDLER
			    {
			      NSLog(@"Caught exception: %@", localException);
			    }
			  NS_ENDHANDLER
			}
		    }
		}
	      else
		{
		  NSArray	*a;

		  a = [self findAll: clients byAbbreviation: dest];
		  if ([a count] == 0)
		    {
		      m = [NSString stringWithFormat: 
			@"No such client as '%@'\n", dest];
		    }
		  else
		    {
		      unsigned	i;

		      m = nil;

		      for (i = 0; i < [a count]; i++)
			{
			  EcClientI	*c = [a objectAtIndex: i];

			  NS_DURING
			    {
			      NSData	*dat = [NSPropertyListSerialization
				dataFromPropertyList: cmd
				format: NSPropertyListBinaryFormat_v1_0
				errorDescription: 0];

			      [[c obj] cmdMesgData: dat from: f];
			      if (m == nil)
				{
				  m = [NSString stringWithFormat:
				    @"Sent message to %@", [c name]];
				}
			      else
				{
				  m = [m stringByAppendingFormat:
				    @", %@", [c name]];
				}
			    }
			  NS_HANDLER
			    {
			      NSLog(@"Caught exception: %@", localException);
			      if (m == nil)
				{
				  m = @"Failed to send message!";
				}
			      else
				{
				  m = [m stringByAppendingFormat:
				    @", failed to send to %@", [c name]];
				}
			    }
			  NS_ENDHANDLER
			}
		      if (m != nil)
			m = [m stringByAppendingString: @"\n"];
		    }
		}
	    }
	  else
	    {
	      m = @"Tell where?.\n";
	    }
	}
      else
	{
	  m = [NSString stringWithFormat: @"Unknown command - '%@'\n", wd];
	}

      [self information: m from: t to: f type: LT_AUDIT];
    }
  else
    {
      EcClientI	*client = [self findIn: clients byName: t];

      if (client)
	{
	  NS_DURING
	    {
	      NSData	*dat = [NSPropertyListSerialization
		dataFromPropertyList: cmd
		format: NSPropertyListBinaryFormat_v1_0
		errorDescription: 0];
	      [[client obj] cmdMesgData: dat from: f];
	    }
	  NS_HANDLER
	    {
	      NSLog(@"Caught exception: %@", localException);
	    }
	  NS_ENDHANDLER
	}
      else
	{
	  NSString	*m;

	  m = [NSString stringWithFormat:
            @"command to unregistered client '%@'", t];
	  [self information: cmdLogFormat(LT_ERROR, m)
		       from: nil
			 to: f
		       type: LT_ERROR];
	}
    }
}

- (NSData *) configurationFor: (NSString *)name
{
  NSMutableDictionary *dict;
  NSString	*base;
  NSRange	r;
  id		o;
  
  if (nil == config || 0 == [name length])
    {
      return nil;	// Not available
    }

  r = [name rangeOfString: @"-"
		  options: NSBackwardsSearch | NSLiteralSearch];
  if (r.length > 0)
    {
      base = [name substringToIndex: r.location];
    }
  else
    {
      base = nil;
    }

  dict = [NSMutableDictionary dictionaryWithCapacity: 2];
  o = [config objectForKey: @"*"];
  if (o != nil)
    {
      [dict setObject: o forKey: @"*"];
    }

  o = [config objectForKey: name];		// Lookup config
  if (base != nil)
    {
      if (nil == o)
	{
	  /* No instance specific config found for server,
	   * try using the base server name without instance ID.
	   */
	  o = [config objectForKey: base];
	}
      else
	{
	  id	tmp;

	  /* We found instance specific configuration for the server,
	   * so we merge by taking values from generic server config
	   * (if any) and overwriting them with instance specific values.
	   */
	  tmp = [config objectForKey: base];
	  if ([tmp isKindOfClass: [NSDictionary class]]
	    && [o isKindOfClass: [NSDictionary class]])
	    {
	      tmp = [[tmp mutableCopy] autorelease];
	      [tmp addEntriesFromDictionary: o];
	      o = tmp;
	    }
	}
    }
  if (o != nil)
    {
      [dict setObject: o forKey: name];
    }

  o = [config objectForKey: @"Operators"];
  if (o != nil)
    {
      [dict setObject: o forKey: @"Operators"];
    }

  return [NSPropertyListSerialization
    dataFromPropertyList: dict
    format: NSPropertyListBinaryFormat_v1_0
    errorDescription: 0];
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

  [[NSNotificationCenter defaultCenter]
    removeObserver: self
	      name: NSConnectionDidDieNotification
	    object: conn];
  if ([conn isKindOfClass: [NSConnection class]])
    {
      NSMutableArray	*a = [NSMutableArray arrayWithCapacity: 2];
      NSMutableString	*l = [NSMutableString stringWithCapacity: 20];
      NSMutableString	*e = [NSMutableString stringWithCapacity: 20];
      NSMutableString	*m = [NSMutableString stringWithCapacity: 20];
      BOOL		lostClients = NO;
      unsigned		i;

      if (control && [(NSDistantObject*)control connectionForProxy] == conn)
	{
	  [[self cmdLogFile: logname]
	    puts: @"Lost connection to control server.\n"];
	  DESTROY(control);
	}

      /*
       *	Now remove the clients from the active list.
       */
      i = [clients count];
      while (i-- > 0)
	{
	  EcClientI*	o = [clients objectAtIndex: i];

	  if ([(id)[o obj] connectionForProxy] == conn)
	    {
	      NSString	*name = [o name];
	      NSString	*s;

	      lostClients = YES;
	      [a addObject: o];
	      [clients removeObjectAtIndex: i];
	      if (i <= pingPosition && pingPosition > 0)
		{
		  pingPosition--;
		}
	      if ([o transient] == NO)
		{
		  EcAlarm	*a;

		  s = EcMakeManagedObject(host, name, nil);
                  [alarmed addObject: name];
		  a = [EcAlarm alarmForManagedObject: s
		    at: nil
		    withEventType: EcAlarmEventTypeProcessingError
		    probableCause: EcAlarmSoftwareProgramAbnormallyTerminated
		    specificProblem: @"Process availability"
		    perceivedSeverity: EcAlarmSeverityCritical
		    proposedRepairAction: @"Check system status"
		    additionalText: @"removed (lost) server"];
		  [self alarm: a];
		}
	      else
		{
		  s = [NSString stringWithFormat: cmdLogFormat(LT_DEBUG,
		    @"removed (lost) server - '%@' on %@"), name, host];
		  [l appendString: s];
		}
	    }
	}

      [a removeAllObjects];

      if ([l length] > 0)
	{
	  [[self cmdLogFile: logname] puts: l];
	}
      if ([m length] > 0)
	{
	  [self information: m from: nil to: nil type: LT_ALERT];
	}
      if ([e length] > 0)
	{
	  [self information: e from: nil to: nil type: LT_ERROR];
	}
      if (lostClients)
	{
	  [self update];
	}
    }
  else
    {
      [self error: "non-Connection sent invalidation"];
    }
  return self;
}

- (void) dealloc
{
  [self cmdLogEnd: logname];
  if (timer != nil)
    {
      [timer invalidate];
    }
  RELEASE(alarmed);
  RELEASE(launching);
  RELEASE(launches);
  DESTROY(control);
  RELEASE(host);
  RELEASE(clients);
  RELEASE(launchInfo);
  RELEASE(environment);
  RELEASE(lastUnanswered);
  [super dealloc];
}

- (NSArray*) findAll: (NSArray*)a
      byAbbreviation: (NSString*)s
{
  NSMutableArray	*r = [NSMutableArray arrayWithCapacity: 4];
  int			i;

  /*
   *	Special case - a numeric value is used as an index into the array.
   */
  if (isdigit(*[s cString]))
    {
      i = [s intValue];
      if (i >= 0 && i < (int)[a count])
	{
	  [r addObject: [a objectAtIndex: i]];
	}
    }
  else
    {
      EcClientI	*o;

      for (i = 0; i < (int)[a count]; i++)
	{
	  o = (EcClientI*)[a objectAtIndex: i];
	  if (comp(s, [o name]) == 0 || comp_len == (int)[s length])
	    {
	      [r addObject: o];
	    }
	}
    }
  return r;
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
      if (i >= 0 && i < (int)[a count])
	{
	  return (EcClientI*)[a objectAtIndex: i];
	}
    }

  for (i = 0; i < (int)[a count]; i++)
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

  for (i = 0; i < (int)[a count]; i++)
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

  for (i = 0; i < (int)[a count]; i++)
    {
      o = (EcClientI*)[a objectAtIndex: i];

      if ([o obj] == s)
	{
	  return o;
	}
    }
  return nil;
}

- (void) flush
{
  /*
   * Flush logs to disk ... dummy method as we don't cache them at present.
   */
}

- (void) information: (NSString*)inf
		from: (NSString*)s
		type: (EcLogType)t
{
  [self information: inf from: s to: nil type: t];
}

- (void) information: (NSString*)inf
		from: (NSString*)s
		  to: (NSString*)d
		type: (EcLogType)t
{
  if (t != LT_DEBUG && inf != nil && [inf length] > 0)
    {
      if (control == nil)
	{
	  [self timedOut: nil];
	}
      if (control == nil)
	{
	  NSLog(@"Information (from:%@ to:%@ type:%d) with no Control -\n%@",
	    s, d, t, inf);
	}
      else
	{
	  NS_DURING
	    {
	      [control information: inf type: t to: d from: s];
	    }
	  NS_HANDLER
	    {
	      NSLog(@"Sending %@ from %@ to %@ type %x exception: %@",
		inf, s, d, t, localException);
	    }
	  NS_ENDHANDLER
	}
    }
}

- (id) initWithDefaults: (NSDictionary*)defs
{
  if (nil != (self = [super initWithDefaults: defs]))
    {
      uncompressed = 0.0;
      undeleted = 0.0;
      nodesFree = 0.1;
      spaceFree = 0.1;

      logname = [[self cmdName] stringByAppendingPathExtension: @"log"];
      RETAIN(logname);
      if ([self cmdLogFile: logname] == nil)
	{
	  exit(0);
	}
      host = RETAIN([[NSHost currentHost] name]);
      clients = [[NSMutableArray alloc] initWithCapacity: 10];
      launches = [[NSMutableDictionary alloc] initWithCapacity: 10];
      launching = [[NSMutableSet alloc] initWithCapacity: 10];
      alarmed = [[NSMutableSet alloc] initWithCapacity: 10];

      timer = [NSTimer scheduledTimerWithTimeInterval: 5.0
					       target: self
					     selector: @selector(timedOut:)
					     userInfo: nil
					      repeats: YES];
      [self timedOut: nil];
    }
  return self;
}

- (void) launch
{
  if (launchInfo != nil)
    {
      NSEnumerator	*enumerator;
      NSString		*key;
      NSDate		*date;
      NSString		*firstKey = nil;
      NSDate		*firstDate = nil;
      NSDate		*now = [NSDate date];

      enumerator = [launchInfo keyEnumerator];
      while ((key = [enumerator nextObject]) != nil)
	{
	  EcClientI	*r = [self findIn: clients byName: key];

	  if (r == nil)
	    {
	      NSDictionary	*taskInfo = [launchInfo objectForKey: key];
	      BOOL		disabled;
	      BOOL		autoLaunch;

	      autoLaunch = [[taskInfo objectForKey: @"Auto"] boolValue];
	      disabled = [[taskInfo objectForKey: @"Disabled"] boolValue];

	      if (disabled == NO)
		{
		  date = [launches objectForKey: key];
		  if (nil == date)
		    {
		      if (autoLaunch == YES)
			{
			  NSDate		*start;
			  NSTimeInterval	offset = -(DLY - 5.0);

			  /* If there is no launch date, we set launch
			   * dates so that we can try this in 5 seconds.
			   */
		          start = [NSDate dateWithTimeIntervalSinceNow: offset];
			  [launches setObject: start forKey: key];
			  date = start;
			}
		    }
		  if (date != nil)
		    {
		      if (firstDate == nil
			|| [date earlierDate: firstDate] == date)
			{
			  firstDate = date;
			  firstKey = key;
			}
		    }
		}
	    }
	}

      key = firstKey;
      date = firstDate;

      if (date != nil && [now timeIntervalSinceDate: date] > DLY)
	{
	  NSDictionary	*taskInfo = [launchInfo objectForKey: key];
	  NSDictionary	*env = environment;
	  NSArray	*args = [taskInfo objectForKey: @"Args"];
	  NSString	*home = [taskInfo objectForKey: @"Home"];
	  NSString	*prog = [taskInfo objectForKey: @"Prog"];
	  NSDictionary	*addE = [taskInfo objectForKey: @"AddE"];
	  NSDictionary	*setE = [taskInfo objectForKey: @"SetE"];
          NSString      *failed = nil;
          NSString	*m;

          /* As a convenience, the 'Home' option sets the -HomeDirectory
           * for the process.
           */
          if ([home length] > 0)
            {
              NSMutableArray    *a = [[args mutableCopy] autorelease];

              if (nil == a)
                {
                  a = [NSMutableArray arrayWithCapacity: 2];
                }
              [a addObject: @"-HomeDirectory"];
              [a addObject: home];
              args = a;
            }

	  /* Record time of launch start and the fact that this is launching.
	   */
	  [launches setObject: now forKey: key];
	  if (nil == [launching member: key])
	    {
	      [launching addObject: key];
	    }
	  else if (nil == [alarmed member: key])
	    {
              NSString  *managedObject;
	      EcAlarm	*a;

	      /* We are re-attempting a launch of a program which never
	       * contacted us and registered with us ... raise an alarm.
	       */
              [alarmed addObject: key];
              managedObject = EcMakeManagedObject(host, key, nil);
	      a = [EcAlarm alarmForManagedObject: managedObject
		at: nil
		withEventType: EcAlarmEventTypeProcessingError
		probableCause: EcAlarmSoftwareProgramAbnormallyTerminated
		specificProblem: @"Process availability"
		perceivedSeverity: EcAlarmSeverityCritical
		proposedRepairAction: @"Check system status"
		additionalText: @"failed to register after launch"];
	      [self alarm: a];
	    }

	  if (prog != nil && [prog length] > 0)
	    {
	      NSTask		*task;
	      NSFileHandle	*hdl;

	      if (setE != nil)
		{
		  env = setE;
		}
	      else if (env == nil)
		{
		  env = [[NSProcessInfo processInfo] environment];
		}
	      if (addE != nil)
		{
		  NSMutableDictionary	*e = [env mutableCopy];

		  [e addEntriesFromDictionary: addE];
		  env = AUTORELEASE(e);
		}
	      task = [NSTask new];
	      [task setEnvironment: env];
	      hdl = [NSFileHandle fileHandleWithNullDevice];
	      NS_DURING
		{
		  [task setLaunchPath: prog];

		  if ([task validatedLaunchPath] == nil)
		    {
                      failed = @"failed to launch (not executable)";
                      m = [NSString stringWithFormat: cmdLogFormat(LT_AUDIT,
                        @"failed to launch (not executable) %@"), key];
                      [self information: m from: nil to: nil type: LT_AUDIT];
		      prog = nil;
		    }
		  if (prog != nil)
		    {
		      [task setStandardInput: hdl];
		      [task setStandardOutput: hdl];
		      [task setStandardError: hdl];
		      if (home != nil && [home length] > 0)
			{
			  [task setCurrentDirectoryPath: home];
			}
		      if (args != nil)
			{
			  [task setArguments: args];
			}
		      [task launch];
		      [[self cmdLogFile: logname]
			printf: @"%@ launched %@\n", [NSDate date], prog];
		    }
		}
	      NS_HANDLER
		{
                  failed = @"failed to launch";
                  m = [NSString stringWithFormat: cmdLogFormat(LT_AUDIT,
                    @"failed to launch (%@) %@"), localException, key];
                  [self information: m from: nil to: nil type: LT_AUDIT];
		}
	      NS_ENDHANDLER
	      RELEASE(task);
	    }
	  else
	    {
              failed = @"bad program name to launch";
	      m = [NSString stringWithFormat: cmdLogFormat(LT_AUDIT,
		@"bad program name to launch %@"), key];
	      [self information: m from: nil to: nil type: LT_AUDIT];
	    }
          if (nil != failed && nil == [alarmed member: key])
            {
              NSString      *managedObject;

              [alarmed addObject: key];
              managedObject = EcMakeManagedObject(host, key, nil);
              [self alarmConfigurationFor: managedObject
                specificProblem: @"Process launch"
                additionalText: failed
                critical: NO];
            }
	}
    }
}

- (void) logMessage: (NSString*)msg
	       type: (EcLogType)t
		for: (id<CmdClient>)o
{
  EcClientI*		r = [self findIn: clients byObject: o];
  NSString		*c;

  if (r == nil)
    {
      c = @"unregistered client";
    }
  else
    {
      c = [r name];
    }
  [self logMessage: msg
	      type: t
	      name: c];
}

- (void) logMessage: (NSString*)msg
	       type: (EcLogType)t
	       name: (NSString*)c
{
  NSString		*m;
  
  switch (t)
    {
      case LT_DEBUG: 
	  m = msg;
	  break;

      case LT_WARNING: 
	  m = msg;
	  break;

      case LT_ERROR: 
	  m = msg;
	  break;

      case LT_AUDIT: 
	  m = msg;
	  break;

      case LT_ALERT: 
	  m = msg;
	  break;

      default: 
	  m = [NSString stringWithFormat: @"%@: Message of unknown type - %@",
		      c, msg];
	  break;
    }

  [[self cmdLogFile: logname] puts: m];
  [self information: m from: c to: nil type: t];
}

- (void) quitAll
{
  /*
   * Suspend any task that might potentially be started.
   */
  if (launchInfo != nil)
    {
      NSEnumerator	*enumerator;
      NSString	*key;

      enumerator = [launchInfo keyEnumerator];
      while ((key = [enumerator nextObject]) != nil)
	{
	  [launches setObject: [NSDate distantFuture] forKey: key];
	}
    }

  if ([clients count] > 0)
    {
      unsigned		i;
      unsigned		j;
      NSMutableArray	*a;

      /* Now we tell all connected clients to quit.
       */
      i = [clients count];
      a = [NSMutableArray arrayWithCapacity: i];
      while (i-- > 0)
	{
	  [a addObject: [[clients objectAtIndex: i] name]];
	}
      for (i = 0; i < [a count]; i++)
	{
	  EcClientI	*c;
	  NSString	*n;

	  n = [a objectAtIndex: i];
	  c = [self findIn: clients byName: n];
	  if (nil != c)
	    {
	      NS_DURING
		{
		  [launches setObject: [NSDate distantFuture] forKey: n];
		  [[c obj] cmdQuit: 0];
		}
	      NS_HANDLER
		{
		  NSLog(@"Caught exception: %@", localException);
		}
	      NS_ENDHANDLER
	    }
	}

      /* Give the clients a short time to quit, and re-send
       * the instruction to any which haven't budged.
       */
      for (j = 0; j < 15; j++)
	{
	  NSDate	*next = [NSDate dateWithTimeIntervalSinceNow: 2.0];

	  while ([clients count] > 0 && [next timeIntervalSinceNow] > 0.0)
	    {
	      [[NSRunLoop currentRunLoop] runMode: NSDefaultRunLoopMode
				       beforeDate: next];
	    }
	  for (i = 0; i < [a count] && [clients count] > 0; i++)
	    {
	      EcClientI	*c;
	      NSString		*n;

	      n = [a objectAtIndex: i];
	      c = [self findIn: clients byName: n];
	      if (nil != c)
		{
		  NS_DURING
		    {
		      [launches setObject: [NSDate distantFuture] forKey: n];
		      [[c obj] cmdQuit: 0];
		    }
		  NS_HANDLER
		    {
		      NSLog(@"Caught exception: %@", localException);
		    }
		  NS_ENDHANDLER
		}
	    }
	}
    }
}

/*
 * Handle a request for re-config from a client.
 */
- (void) requestConfigFor: (id<CmdConfig>)c
{
  EcClientI	*info = [self findIn: clients byObject: (id<CmdClient>)c];
  NSData	*conf = [info config];

  if (nil != conf)
    {
      NS_DURING
	{
	  [[info obj] updateConfig: conf];
	}
      NS_HANDLER
	{
	  NSLog(@"Sending config to client: %@", localException);
	}
      NS_ENDHANDLER
    }
}

- (NSData*) registerClient: (id<CmdClient>)c
		      name: (NSString*)n
{
  return [self registerClient: c name: n transient: NO];
}

- (NSData*) registerClient: (id<CmdClient>)c
		      name: (NSString*)n
		 transient: (BOOL)t
{
  NSMutableDictionary	*dict;
  EcClientI		*obj;
  EcClientI		*old;
  NSString		*m;

  [(NSDistantObject*)c setProtocolForProxy: @protocol(CmdClient)];

  if (nil == config)
    {
      m = [NSString stringWithFormat: 
	@"%@ back-off new server with name '%@' on %@\n",
	[NSDate date], n, host];
      [[self cmdLogFile: logname] puts: m];
      [self information: m from: nil to: nil type: LT_AUDIT];
      dict = [NSMutableDictionary dictionaryWithCapacity: 1];
      [dict setObject: @"configuration data not yet available."
	       forKey: @"back-off"];
      return [NSPropertyListSerialization
	dataFromPropertyList: dict
	format: NSPropertyListBinaryFormat_v1_0
	errorDescription: 0];
    }

  /*
   *	Create a new reference for this client.
   */
  obj = [[EcClientI alloc] initFor: c name: n with: self];

  if ((old = [self findIn: clients byName: n]) == nil)
    {
      NSData	*d;

      [clients addObject: obj];
      RELEASE(obj);
      [clients sortUsingSelector: @selector(compare:)];

      /* This client has launched ... remove it from the set of launching
       * clients.
       */
      [launching removeObject: n];

      /*
       * If this client is in the list of launchable clients, set
       * it's last launch time to now so that if it dies it will
       * be restarted.  This overrides any previous shutdown - we
       * assume that if it has been started by some process
       * external to the Command server then we really don't want
       * it shut down.
       */
      if ([launches objectForKey: n] != nil)
	{
	  [launches setObject: [NSDate date] forKey: n];
	}
      m = [NSString stringWithFormat: 
	@"%@ registered new server with name '%@' on %@\n",
	[NSDate date], n, host];
      [[self cmdLogFile: logname] puts: m];
      if (t == YES)
	{
	  [obj setTransient: YES];
	}
      else
	{
	  [obj setTransient: NO];
	  [self information: m from: nil to: nil type: LT_AUDIT];
	}
      [self update];
      d = [self configurationFor: n];
      if (nil != d)
	{
	  [obj setConfig: d];
	}
      return [obj config];
    }
  else
    {
      RELEASE(obj);
      m = [NSString stringWithFormat: 
	@"%@ rejected new server with name '%@' on %@\n",
	[NSDate date], n, host];
      [[self cmdLogFile: logname] puts: m];
      [self information: m from: nil to: nil type: LT_AUDIT];
      dict = [NSMutableDictionary dictionaryWithCapacity: 1];
      [dict setObject: @"client with that name already registered."
	       forKey: @"rejected"];
      return [NSPropertyListSerialization
	dataFromPropertyList: dict
	format: NSPropertyListBinaryFormat_v1_0
	errorDescription: 0];
    }
}

- (void) reply: (NSString*) msg to: (NSString*)n from: (NSString*)c
{
  if (control == nil)
    {
      [self timedOut: nil];
    }
  if (control != nil)
    {
      NS_DURING
	{
	  [control reply: msg to: n from: c];
	}
      NS_HANDLER
	{
	  NSLog(@"reply: %@ to: %@ from: %@ - %@", msg, n, c, localException);
	}
      NS_ENDHANDLER
    }
  else
    {
    }
}

- (NSString*) makeSpace
{
  NSInteger             deleteAfter;
  NSTimeInterval        latestDeleteAt;
  NSTimeInterval        now;
  NSTimeInterval        ti;
  NSFileManager         *mgr;
  NSCalendarDate        *when;
  NSString		*logs;
  NSString		*file;
  NSString              *gone;
  NSAutoreleasePool	*arp;

  gone = nil;
  arp = [NSAutoreleasePool new];
  when = [NSCalendarDate date];
  now = [when timeIntervalSinceReferenceDate];

  logs = [[self ecUserDirectory] stringByAppendingPathComponent: @"Logs"];

  /* When trying to make space, we can delete up to the point when we
   * would start compressing but no further ... we don't want to delete
   * all logs!
   */
  deleteAfter = [[self cmdDefaults] integerForKey: @"CompressLogsAfter"];
  if (deleteAfter < 1)
    {
      deleteAfter = 14;
    }

  mgr = [NSFileManager defaultManager];

  if (0.0 == undeleted)
    {
      undeleted = now - 365.0 * day;
    }
  ti = undeleted;
  latestDeleteAt = now - day * deleteAfter;
  while (nil == gone && ti < latestDeleteAt)
    {
      when = [NSCalendarDate dateWithTimeIntervalSinceReferenceDate: ti];
      file = [[logs stringByAppendingPathComponent:
        [when descriptionWithCalendarFormat: @"%Y-%m-%d"]]
        stringByStandardizingPath];
      if ([mgr fileExistsAtPath: file])
        {
          [mgr removeFileAtPath: file handler: nil];
          gone = [when descriptionWithCalendarFormat: @"%Y-%m-%d"];
        }
      ti += day;
    }
  undeleted = ti;
  RETAIN(gone);
  DESTROY(arp);
  return AUTORELEASE(gone);
}

/* Perform this one in another thread.
 * The sweep operation may compress really large logfiles and could be
 * very slow, so it's performed in a separate thread to avoid blocking
 * normal operations.
 */
- (void) sweep: (NSCalendarDate*)when
{
  NSInteger             compressAfter;
  NSInteger             deleteAfter;
  NSTimeInterval        latestCompressAt;
  NSTimeInterval        latestDeleteAt;
  NSTimeInterval        now;
  NSTimeInterval        ti;
  NSFileManager         *mgr;
  NSString		*logs;
  NSString		*file;
  NSAutoreleasePool	*arp;

  arp = [NSAutoreleasePool new];
  if (nil == when)
    {
      now = [NSDate timeIntervalSinceReferenceDate];
    }
  else
    {
      now = [when timeIntervalSinceReferenceDate];
    } 

  logs = [[self ecUserDirectory] stringByAppendingPathComponent: @"Logs"];

  /* get number of days after which to do log compression/deletion.
   */
  compressAfter = [[self cmdDefaults] integerForKey: @"CompressLogsAfter"];
  if (compressAfter < 1)
    {
      compressAfter = 14;
    }
  deleteAfter = [[self cmdDefaults] integerForKey: @"DeleteLogsAfter"];
  if (deleteAfter < 1)
    {
      deleteAfter = 1000;
    }
  if (deleteAfter < compressAfter)
    {
      deleteAfter = compressAfter;
    }

  mgr = [[NSFileManager new] autorelease];

  if (0.0 == undeleted)
    {
      undeleted = now - 365.0 * day;
    }
  ti = undeleted;
  latestDeleteAt = now - day * deleteAfter;
  while (ti < latestDeleteAt)
    {
      NSAutoreleasePool *pool = [NSAutoreleasePool new];

      when = [NSCalendarDate dateWithTimeIntervalSinceReferenceDate: ti];
      file = [[logs stringByAppendingPathComponent:
        [when descriptionWithCalendarFormat: @"%Y-%m-%d"]]
        stringByStandardizingPath];
      if ([mgr fileExistsAtPath: file])
        {
          [mgr removeFileAtPath: file handler: nil];
        }
      ti += day;
      [pool release];
    }
  undeleted = ti;

  if (uncompressed < undeleted)
    {
      uncompressed = undeleted;
    }
  ti = uncompressed;
  latestCompressAt = now - day * compressAfter;
  while (ti < latestCompressAt)
    {
      NSAutoreleasePool         *pool = [NSAutoreleasePool new];
      NSDirectoryEnumerator	*enumerator;
      BOOL	                isDirectory;
      NSString                  *base;

      when = [NSCalendarDate dateWithTimeIntervalSinceReferenceDate: ti];
      base = [[logs stringByAppendingPathComponent:
        [when descriptionWithCalendarFormat: @"%Y-%m-%d"]]
        stringByStandardizingPath];
      if ([mgr fileExistsAtPath: base isDirectory: &isDirectory] == NO
        || NO == isDirectory)
        {
          ti += day;
          [pool release];
          continue;     // No log directory for this date.
        }

      enumerator = [mgr enumeratorAtPath: base];
      while ((file = [enumerator nextObject]) != nil)
        {
          NSString	        *src;
          NSString	        *dst;
          NSFileHandle          *sh;
          NSFileHandle          *dh;
          NSDictionary          *a;
          NSData                *d;

          if (YES == [[file pathExtension] isEqualToString: @"gz"])
            {
              continue; // Already compressed
            }
          a = [enumerator fileAttributes];
          if (NSFileTypeRegular != [a fileType])
            {
              continue;	// Not a regular file ... can't compress
            }

          src = [base stringByAppendingPathComponent: file];

          if ([a fileSize] == 0)
            {
              [mgr removeFileAtPath: src handler: nil];
              continue; // Nothing to compress
            }

          dst = [src stringByAppendingPathExtension: @"gz"];
          if ([mgr fileExistsAtPath: dst isDirectory: &isDirectory] == YES)
            {
              [mgr removeFileAtPath: dst handler: nil];
            }

          [mgr createFileAtPath: dst contents: nil attributes: nil];
          dh = [NSFileHandle fileHandleForWritingAtPath: dst];
          if (NO == [dh useCompression])
            {
              [dh closeFile];
              [mgr removeFileAtPath: dst handler: nil];
              [self cmdError: @"Unable to compress %@ to %@", src, dst];
              continue;
            }

          sh = nil;
          NS_DURING
            {
              NSAutoreleasePool *inner;

              sh = [NSFileHandle fileHandleForReadingAtPath: src];
              inner = [NSAutoreleasePool new];
              while ([(d = [sh readDataOfLength: 1000000]) length] > 0)
                {
                  [dh writeData: d];
                  [inner release];
                  inner = [NSAutoreleasePool new];
                }
              [inner release];
              [sh closeFile];
              [dh closeFile];
              [mgr removeFileAtPath: src handler: nil];
            }
          NS_HANDLER
            {
              [mgr removeFileAtPath: dst handler: nil];
              [sh closeFile];
              [dh closeFile];
            }
          NS_ENDHANDLER
        }
      ti += day;
      [pool release];
    }
  uncompressed = ti;

  DESTROY(arp);
  sweeping = NO;
}

- (void) ecNewHour: (NSCalendarDate*)when
{
  if (sweeping == YES)
    {
      NSLog(@"Argh - nested sweep attempt");
      return;
    }
  sweeping = YES;
  [NSThread detachNewThreadSelector: @selector(sweep:)
                           toTarget: self
                         withObject: when];
}


/*
 * Tell all our clients to quit, and wait for them to do so.
 * If called while already terminating ... force immediate shutdown.
 */
- (void) terminate: (NSTimer*)t
{
  if (terminating == nil)
    {
      [self information: @"Handling shutdown."
		   from: nil
		     to: nil
		   type: LT_AUDIT];
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
	  [self cmdQuit: tStatus];
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
      static unsigned	pingControlCount = 0;
      NSFileManager	*mgr;
      NSDictionary	*a;
      float		f;
      unsigned		count;
      BOOL		lost = NO;

      inTimeout = YES;
      if (control == nil)
	{
	  NSUserDefaults	*defs;
	  NSString		*ctlName;
	  NSString		*ctlHost;
	  id			c;

	  defs = [self cmdDefaults];
	  ctlName = [defs stringForKey: @"ControlName"];
	  if (ctlName == nil)
	    {
	      ctlName = @"Control";
	    }
	  if (nil != (ctlHost = [NSHost controlWellKnownName]))
            {
              /* Map to operating system host name.
               */
              ctlHost = [[NSHost hostWithWellKnownName: ctlHost] name];
            }
	  if (nil == ctlHost)
	    {
	      ctlHost = @"*";
	    }

	  NS_DURING
	    {
	      NSLog(@"Connecting to %@ on %@", ctlName, ctlHost);
	      control = (id<Control>)[NSConnection
		  rootProxyForConnectionWithRegisteredName: ctlName
						      host: ctlHost
	       usingNameServer: [NSSocketPortNameServer sharedInstance] ];
	    }
	  NS_HANDLER
	    {
	      NSLog(@"Connecting to control server: %@", localException);
	      control = nil;
	    }
	  NS_ENDHANDLER
	  c = control;
	  if (RETAIN(c) != nil)
	    {
	      /* Re-initialise control server ping */
	      DESTROY(lastUnanswered);
	      fwdSequence = 0;
	      revSequence = 0;

	      [(NSDistantObject*)c setProtocolForProxy: @protocol(Control)];
	      c = [(NSDistantObject*)c connectionForProxy];
	      [c setDelegate: self];
	      [[NSNotificationCenter defaultCenter]
		addObserver: self
		   selector: @selector(connectionBecameInvalid:)
		       name: NSConnectionDidDieNotification
		     object: c];
	      NS_DURING
		{
		  NSData		*dat;

		  dat = [control registerCommand: self
					    name: host];
		  if (nil == dat)
		    {
		      // Control server not yet ready.
		      DESTROY(control);
		    }
		  else
		    {
		      NSMutableDictionary	*conf;

		      conf = [NSPropertyListSerialization
			propertyListWithData: dat
			options: NSPropertyListMutableContainers
			format: 0
			error: 0];
		      if ([conf objectForKey: @"rejected"] == nil)
			{
			  [self updateConfig: dat];
			}
		      else
			{
			  [[self cmdLogFile: logname]
			    printf: @"registration attempt rejected - %@\n",
			      [conf objectForKey: @"rejected"]];
			  DESTROY(control);
			}
		    }
		}
	      NS_HANDLER
		{
		  NSLog(@"Registering with control server: %@", localException);
		  DESTROY(control);
		}
	      NS_ENDHANDLER
	      if (control != nil)
		{
		  [self update];
		}
	    }
	}
      [self launch];

      count = [clients count];
      while (count-- > 0)
	{
	  EcClientI	*r = [clients objectAtIndex: count];
	  NSDate	*d = [r lastUnanswered];
	  
	  if (d != nil && [d timeIntervalSinceDate: now] < -pingDelay)
	    {
	      NSString	*m;

	      m = [NSString stringWithFormat: cmdLogFormat(LT_AUDIT,
		@"Client '%@' failed to respond for over %d seconds"),
		[r name], (int)pingDelay];
	      [[[[r obj] connectionForProxy] sendPort] invalidate];
	      [self information: m from: nil to: nil type: LT_AUDIT];
	      lost = YES;
	    }
	}
      if (control != nil && lastUnanswered != nil
	&& [lastUnanswered timeIntervalSinceDate: now] < -pingDelay)
	{
	  NSString	*m;

	  m = [NSString stringWithFormat: cmdLogFormat(LT_AUDIT,
	    @"Control server failed to respond for over %d seconds"),
	    (int)pingDelay];
	  [[(NSDistantObject*)control connectionForProxy] invalidate];
	  [self information: m from: nil to: nil type: LT_AUDIT];
	  lost = YES;
	}
      if (lost == YES)
	{
	  [self update];
	}
      /*
       * We ping each client in turn.  If there are fewer than 4 clients,
       * we skip timeouts so that clients get pinged no more frequently
       * than one per 4 timeouts.
       */
      count = [clients count];
      pingPosition++;
      if (pingPosition >= 4 && pingPosition >= count)
	{
	  pingPosition = 0;
	}
      if (pingPosition < count)
	{
	  [[clients objectAtIndex: pingPosition] ping];
	}
      // Ping the control server too - once every four times.
      pingControlCount++;
      if (pingControlCount >= 4)
	{
	  pingControlCount = 0;
	}
      if (pingControlCount == 0)
	{
	  [self pingControl];
	}

      /* See if the filesystem containing our logging directory has enough
       * space.
       */
      mgr = [NSFileManager defaultManager];
      a = [mgr fileSystemAttributesAtPath: cmdLogsDir(nil)];
      f = [[a objectForKey: NSFileSystemFreeSize] floatValue] 
        / [[a objectForKey: NSFileSystemSize] floatValue];
      if (f <= spaceFree)
	{
	  static NSDate	*last = nil;

	  if (nil == last || [last timeIntervalSinceNow] < -DLY)
	    {
	      NSString	*m;

	      m = [self makeSpace];
	      ASSIGN(last, [NSDate date]);
              if ([m length] == 0)
                {
                  m = [NSString stringWithFormat: cmdLogFormat(LT_ALERT,
                    @"Disk space at %02.1f percent"), f * 100.0];
                }
              else
                {
                  m = [NSString stringWithFormat: cmdLogFormat(LT_ALERT,
                    @"Disk space at %02.1f percent"
                    @" - deleted logs from %@ to make space"),
                    f * 100.0, m];
                }
	      [self information: m from: nil to: nil type: LT_ALERT];
	    }
	}
      f = [[a objectForKey: NSFileSystemFreeNodes] floatValue] 
        / [[a objectForKey: NSFileSystemNodes] floatValue];
      if (f <= nodesFree)
	{
	  static NSDate	*last = nil;

	  if (nil == last || [last timeIntervalSinceNow] < -DLY)
	    {
	      NSString	*m;

	      m = [self makeSpace];
	      ASSIGN(last, [NSDate date]);
              if ([m length] == 0)
                {
                  m = [NSString stringWithFormat: cmdLogFormat(LT_ALERT,
                    @"Disk nodes at %02.1f percent"), f * 100.0];
                }
              else
                {
                  m = [NSString stringWithFormat: cmdLogFormat(LT_ALERT,
                    @"Disk nodes at %02.1f percent"
                    @" - deleted logs from %@ to make space"),
                    f * 100.0, m];
                }
	      [self information: m from: nil to: nil type: LT_ALERT];
	    }
	}
    }
  inTimeout = NO;
}

- (void) unregisterByObject: (id)obj
{
  EcClientI	*o = [self findIn: clients byObject: obj];

  if (o != nil)
    {
      NSString	        *m;
      NSUInteger	i;
      BOOL	        transient = [o transient];
      NSString	        *name = [[[o name] retain] autorelease];

      m = [NSString stringWithFormat: 
	@"\n%@ removed (unregistered) server -\n  '%@' on %@\n",
	[NSDate date], name, host];
      [[self cmdLogFile: logname] puts: m];
      [o setUnregistered: YES];
      i = [clients indexOfObjectIdenticalTo: o];
      if (i != NSNotFound)
	{
	  [clients removeObjectAtIndex: i];
	  if (i <= pingPosition && pingPosition > 0)
	    {
	      pingPosition--;
	    }
	}
      if (transient == NO)
	{
	  [self information: m from: nil to: nil type: LT_AUDIT];
	}
      [self update];
    }
}

- (void) unregisterByName: (NSString*)n
{
  EcClientI	*o = [self findIn: clients byName: n];

  if (o)
    {
      NSString	        *m;
      NSUInteger       	i;
      BOOL	        transient = [o transient];
      NSString	        *name = [[[o name] retain] autorelease];

      m = [NSString stringWithFormat: 
	@"\n%@ removed (unregistered) server -\n  '%@' on %@\n",
	[NSDate date], name, host];
      [[self cmdLogFile: logname] puts: m];
      [o setUnregistered: YES];
      i = [clients indexOfObjectIdenticalTo: o];
      if (i != NSNotFound)
	{
	  [clients removeObjectAtIndex: i];
	  if (i <= pingPosition && pingPosition > 0)
	    {
	      pingPosition--;
	    }
	}
      if (transient == NO)
	{
	  [self information: m from: nil to: nil type: LT_AUDIT];
	}
      [self update];
    }
}

- (void) update
{
  if (control == nil)
    {
      [self timedOut: nil];
    }
  if (control)
    {
      NS_DURING
	{
	  NSMutableArray	*a;
	  int			i;

	  a = [NSMutableArray arrayWithCapacity: [clients count]];
	  for (i = 0; i < (int)[clients count]; i++)
	    {
	      EcClientI	*c;

	      c = [clients objectAtIndex: i];
	      [a addObject: [c name]];
	    }
	  [control servers: [NSPropertyListSerialization
	    dataFromPropertyList: a
	    format: NSPropertyListBinaryFormat_v1_0
	    errorDescription: 0] on: self];
	}
      NS_HANDLER
	{
	  NSLog(@"Exception sending servers to Control: %@", localException);
	}
      NS_ENDHANDLER
    }
  if (terminating != nil && [clients count] == 0)
    {
      [self information: @"Final shutdown."
		   from: nil
		     to: nil
		   type: LT_AUDIT];
      [terminating invalidate];
      terminating = nil;
      [self cmdQuit: tStatus];
    }
}

- (void) updateConfig: (NSData*)data
{
  NSMutableDictionary	*info;
  NSMutableDictionary	*dict;
  NSMutableDictionary	*newConfig;
  NSDictionary		*operators;
  NSEnumerator		*enumerator;
  NSString		*key;

  /* Ignore invalid/empty configuration
   */
  if (nil == data)
    {
      return;
    }
  info = [NSPropertyListSerialization
    propertyListWithData: data
    options: NSPropertyListMutableContainers
    format: 0
    error: 0];
  if (NO == [info isKindOfClass: [NSMutableDictionary class]]
    || 0 == [info count])
    {
      return;
    }

  newConfig = [NSMutableDictionary dictionaryWithCapacity: 32];
  /*
   *	Put all values for this host in the config dictionary.
   */
  dict = [info objectForKey: host];
  if (dict)
    {
      [newConfig addEntriesFromDictionary: dict];
    }
  /*
   *	Add any default values to the config dictionary where we don't have
   *	host specific values.
   */
  dict = [info objectForKey: @"*"];
  if (dict)
    {
      enumerator = [dict keyEnumerator];
      while ((key = [enumerator nextObject]) != nil)
	{
	  NSMutableDictionary	*partial = [newConfig objectForKey: key];
	  NSMutableDictionary	*general = [dict objectForKey: key];
	  NSString		*app = key;

	  if (partial == nil)
	    {
	      /*
	       *	No host-specific info for this application -
	       *	Use the general stuff for the application.
	       */
	      [newConfig setObject: general forKey: key];
	    }
	  else
	    {
	      NSEnumerator	*another = [general keyEnumerator];

	      /*
	       *	Merge in any values for this application which
	       *	exist in the general stuff, but not in the host
	       *	specific area.
	       */
	      while ((key = [another nextObject]) != nil)
		{
		  if ([partial objectForKey: key] == nil)
		    {
		      id	obj = [general objectForKey: key];

		      [partial setObject: obj forKey: key];
		    }
		  else
		    {
		      [[self cmdLogFile: logname]
			printf: @"General config for %@/%@ overridden by"
			@" host-specific version\n", app, key];
		    }
		}
	    }
	}
    }

  /*
   * Add the list of operators to the config.
   */
  operators = [info objectForKey: @"Operators"];
  if (operators != nil)
    {
      [newConfig setObject: operators forKey: @"Operators"];
    }

  /* Finally, replace old config with new if they differ.
   */
  [self newConfig: newConfig];
}

@end

