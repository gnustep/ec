
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

@interface	LogTool : EcProcess
{
}
@end

@implementation	LogTool
- (void) cmdQuit: (NSInteger)status
{
  [super cmdQuit: status];
  exit(status);
}
@end

static void
inner_main()
{
  NSUserDefaults        *defs;
  NSArray               *args;
  LogTool               *tool;
  NSString              *name;
  NSString              *mode;
  NSString              *mesg;
  EcLogType             eclt;
  CREATE_AUTORELEASE_POOL(arp);

  defs = [NSUserDefaults standardUserDefaults];

  args = [[NSProcessInfo processInfo] arguments];
  if ([args containsObject: @"--help"] == YES)
    {
      printf("LogTool ... options are\n");
      printf("-Name NN (no default)\n");
      printf("\tSpecify name of proceess making log\n");
      printf("-Mode NN (Warn)\n");
      printf("\tSpecify log mode (Audit, Debug, Warn, Error, Alert)\n");
      printf("-Mesg the-message-to-logs (none)\n");
      printf("\tSpecify the test to be logged\n");
      exit(0);
    }

  name = [defs stringForKey: @"Name"];
  if ([name length] == 0)
    {
      NSLog(@"You must define a Name under which to log");
      exit(1);
    }
  mode = [defs stringForKey: @"Mode"];
  if ([mode length] == 0)
    {
      mode = @"Warn";
    }
  if ([@"Audit" isEqual: mode])
    {
      eclt = LT_AUDIT;
    }
  else if ([@"Debug" isEqual: mode])
    {
      eclt = LT_DEBUG;
    }
  else if ([@"Warn" isEqual: mode])
    {
      eclt = LT_WARNING;
    }
  else if ([@"Error" isEqual: mode])
    {
      eclt = LT_ERROR;
    }
  else if ([@"Alert" isEqual: mode])
    {
      eclt = LT_ALERT;
    }
  else
    {
      NSLog(@"You must specify a known log Mode");
      exit(1);
    }

  mesg = [defs stringForKey: @"Mesg"];
  if ([mesg length] == 0)
    {
      NSLog(@"You must specify a Mesg to log");
      exit(1);
    }

  /* Now establish the command server.
   */
  tool = [[[LogTool alloc] initWithDefaults:
      [NSDictionary dictionaryWithObjectsAndKeys:
	      @"yes", @"NoDaemon",			// Never run as daemon
	      @"yes", @"Transient",			// Don't log to console
	      name, @"ProgramName",
	      nil]] autorelease];

  [EcProc cmdNewServer];

  [tool log: mesg type: eclt];

  [tool cmdFlushLogs];

  [tool cmdQuit: 0];

  RELEASE(arp);
  exit(0);
}

int
main(int argc, char *argv[])
{
  inner_main();
  return 0;
}
