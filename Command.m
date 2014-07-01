
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

#if	!defined(EC_BASE_CLASS)
#define	EC_BASE_CLASS	EcCommand
#endif

/* Create a fake interface to satisfy compiler ...
 */
@interface	EC_BASE_CLASS : EcProcess
@end

void
inner_main()
{
  NSAutoreleasePool	*arp;
  NSDictionary		*defs;

  arp = [NSAutoreleasePool new];

  cmdVersion(@"$Date: 2012-02-13 08:11:49 +0000 (Mon, 13 Feb 2012) $ $Revision: 65934 $");

  defs = [NSDictionary dictionaryWithObjectsAndKeys:
    @"Command", @"HomeDirectory",
    @"YES", @"Daemon",
#if	defined(EC_REGISTRATION_DOMAIN)
    EC_REGISTRATION_DOMAIN
#endif
    nil];

  if (nil == [[EC_BASE_CLASS alloc] initWithDefaults: defs])
    {
      NSLog(@"Unable to create command object.");
      exit(1);
    }

  [EcProc ecRun];

  [arp release];

  exit(0);
}

int
main(int argc, char *argv[])
{
  NSProcessInfo		*pInfo;
  NSArray               *pArgs;
  NSString              *pName;
  CREATE_AUTORELEASE_POOL(pool);

  pInfo = [NSProcessInfo processInfo];
  pArgs = [pInfo arguments];
  pName = [pInfo processName];

  if ([pArgs containsObject: @"--Watched"] == NO)
    {
      NSMutableArray	*args = AUTORELEASE([pArgs mutableCopy]);
      NSString          *path = [[NSBundle mainBundle] executablePath];
      NSAutoreleasePool *inner = nil;
      BOOL              done = NO;
      int               status = 0;
      NSFileHandle	*null;
      NSTask	        *t;

      [args removeObjectAtIndex: 0];

      if ([pArgs containsObject: @"--Watcher"] == NO)
        {
          /* In the top level task ... set flags to create a subtask
           * to act as a watcher for other tasks, and once that has
           * been created, exit to leave it running as a daemon.
           */
          [args addObject: @"--Watcher"];
          t = [NSTask new];
          NS_DURING
            {
              [t setLaunchPath: path];
              [t setArguments: args];
              [t setEnvironment: [pInfo environment]];
              null = [NSFileHandle fileHandleWithNullDevice];
              [t setStandardInput: null];
              [t setStandardOutput: null];
              [t setStandardError: null];
              [t launch];
            }
          NS_HANDLER
            {
              NSLog(@"Problem creating %@ subprocess: %@",
                pName, localException);
              exit(1);
            }
          NS_ENDHANDLER
          [t release];
          exit(0);
        }

      /* This is the watcher ... its subtasks are those which are watched.
       */

      /* Set args to tell subtask task not to make itself a daemon
       */
      [args addObject: @"-Daemon"];
      [args addObject: @"NO"];

      /* Set args to tell task it is being watched.
       */
      [args removeObject: @"--Watcher"];
      [args addObject: @"--Watched"];

      while (NO == done)
        {
          DESTROY(inner);
          inner = [NSAutoreleasePool new];
          t = [[NSTask new] autorelease];
          NS_DURING
            {
              [t setLaunchPath: path];
              [t setArguments: args];
              [t setEnvironment: [pInfo environment]];
              null = [NSFileHandle fileHandleWithNullDevice];
              [t setStandardInput: null];
              [t setStandardOutput: null];
              [t setStandardError: null];
              [t launch];
              [t waitUntilExit];
              if (0 == [t terminationStatus])
                {
                  done = YES;
                }
              else
                {
                  /* Subprocess died ... try to restart after 30 seconds
                   */
                  [NSThread sleepForTimeInterval: 30.0];
                }
            }
          NS_HANDLER
            {
              done = YES;
              status = 1;
              NSLog(@"Problem creating %@ subprocess: %@",
                pName, localException);
            }
          NS_ENDHANDLER
        }
      DESTROY(inner);
      DESTROY(pool);
      exit(status);
    }
  DESTROY(pool);

  inner_main();
  return 0;
}
