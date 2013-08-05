
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
#import "EcProcess.h"
#import "EcUserDefaults.h"

int
main()
{
  NSUserDefaults        *defs;
  EcAlarm               *alrm;
  NSArray               *args;
  NSString		*cnam;
  NSString		*host;
  NSString              *comp;
  NSString              *mobj;
  NSString              *pref;
  NSString              *prob;
  NSString              *proc;
  NSString              *repr;
  NSString              *text;
  NSString              *str;
  id			proxy;
  EcAlarmEventType      type;
  EcAlarmProbableCause  cause;
  EcAlarmSeverity       severity;
  CREATE_AUTORELEASE_POOL(arp);

  pref = EC_DEFAULTS_PREFIX;
  if (nil == pref)
    {
      pref = @"";
    }
  defs = [NSUserDefaults userDefaultsWithPrefix: pref
                                         strict: EC_DEFAULTS_STRICT];

  args = [[NSProcessInfo processInfo] arguments];
  if ([args containsObject: @"--help"] == YES)
    {
      printf("AlarmTool ... options are\n");
      printf("-Cause NN (no default)\n");
      printf("\tSpecify probable cause of alarm (and implicitly the even type)\n");
      printf("-Component NN (empty)\n");
      printf("\tSpecify the name of the component raising the alarm.\n");
      printf("-Problem NN (no default)\n");
      printf("\tSpecify the specific problem causing the alarm.  May be omitted for a clear.\n");
      printf("-Process NN (no default)\n");
      printf("\tSpecify the name of the process raising the alarm.\n");
      printf("-Repair NN (no default)\n");
      printf("\tSpecify the proposed repair action.  May be omitted for a clear.\n");
      printf("-Severity NN (clear)\n");
      printf("\tSpecify the severity (clear, warning, minor, major, or critical)\n");
      printf("-Text NN (none)\n");
      printf("\tSpecify the additional text to be logged\n");
      exit(0);
    }

  str = [defs stringForKey: @"Cause"];
  if (nil == str)
    {
      NSLog(@"Missing Cause, try --help", str);
      exit(1);
    }
  cause = EcAlarmVersionMismatch;
  while (cause > EcAlarmProbableCauseUnknown)
    {
      NSString  *s = [EcAlarm stringFromProbableCause: cause];

      if (nil != s && [s caseInsensitiveCompare: str] == NSOrderedSame)
        {
          break;
        }
      cause--;
    }
  if (EcAlarmProbableCauseUnknown == cause)
    {
      NSMutableArray   *ma = [NSMutableArray arrayWithCapacity: 100];

      cause = EcAlarmVersionMismatch;
      while (cause > EcAlarmProbableCauseUnknown)
        {
          NSString  *s = [EcAlarm stringFromProbableCause: cause];

          if (nil != s)
            {
              [ma addObject: s];
            }
          cause--;
        }
      [ma sortUsingSelector: @selector(compare:)];
      NSLog(@"Probable Cause (%@) unknown, try one of %@", str, ma);
      exit(1);
    }
  type = [EcAlarm eventTypeFromProbableCause: cause];

  str = [defs stringForKey: @"Severity"];
  if (nil == str)
    severity = EcAlarmSeverityCleared;
  else if ([str caseInsensitiveCompare: @"clear"] == NSOrderedSame)
    severity = EcAlarmSeverityCleared;
  else if ([str caseInsensitiveCompare: @"warning"] == NSOrderedSame)
    severity = EcAlarmSeverityWarning;
  else if ([str caseInsensitiveCompare: @"minor"] == NSOrderedSame)
    severity = EcAlarmSeverityMinor;
  else if ([str caseInsensitiveCompare: @"major"] == NSOrderedSame)
    severity = EcAlarmSeverityMajor;
  else if ([str caseInsensitiveCompare: @"critical"] == NSOrderedSame)
    severity = EcAlarmSeverityCritical;
  else
    {
      NSLog(@"Severity (%@) unknown, try --help", str);
      exit(1);
    }
  
  comp = [defs stringForKey: @"Component"];
  proc = [defs stringForKey: @"Process"];
  if ([proc length] == 0)
    {
      NSLog(@"No Process specified, try --help");
      exit(1);
    }
  mobj = EcMakeManagedObject(nil, proc, comp);

  prob = [defs stringForKey: @"Problem"];
  if ([prob length] == 0)
    {
      NSLog(@"No Problem specified, try --help");
      exit(1);
    }

  repr = [defs stringForKey: @"Repair"];
  if (severity != EcAlarmSeverityCleared && [repr length] == 0)
    {
      NSLog(@"No Repair specified, try --help");
      exit(1);
    }

  text = [defs stringForKey: @"Text"];

  alrm = [EcAlarm alarmForManagedObject: mobj
                                     at: nil
                          withEventType: type
                          probableCause: cause
                        specificProblem: prob
                      perceivedSeverity: severity
                   proposedRepairAction: repr
                         additionalText: text];

  cnam = [defs stringForKey: @"CommandName"];
  if (cnam == nil)
    {
      cnam = @"Command";
    }

  host = [defs stringForKey: @"CommandHost"];
  if ([host length] == 0)
    {
      host = [[NSHost currentHost] name];
    }

  proxy = [NSConnection rootProxyForConnectionWithRegisteredName: cnam
							    host: host
    usingNameServer: [NSSocketPortNameServer sharedInstance]];

  if (nil == proxy)
    {
      NSLog(@"Unable to contact %@ on %@", cnam, host);
      exit(1);
    }

  NS_DURING
    {
      [(id<Command>)proxy alarm: alrm];  
    }
  NS_HANDLER
    {
      NSLog (@"Could not send alarm to server: %@", localException);
      exit(1);
    }
  NS_ENDHANDLER

  RELEASE(arp);
  return 0;
}
