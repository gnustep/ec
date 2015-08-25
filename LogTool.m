
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

#if     !defined(EC_DEFAULTS_PREFIX)
#define EC_DEFAULTS_PREFIX nil
#endif
#if     !defined(EC_DEFAULTS_STRICT)
#define EC_DEFAULTS_STRICT NO
#endif
#if     !defined(EC_EFFECTIVE_USER)
#define EC_EFFECTIVE_USER nil
#endif

#import "EcProcess.h"
#import "EcUserDefaults.h"
#import "EcHost.h"

int
main()
{
  NSUserDefaults        *defs;
  NSDictionary          *dict;
  NSArray               *args;
  NSString              *pref;
  NSString		*host;
  NSString		*cnam;
  NSString              *name;
  NSString              *mode;
  NSString              *mesg;
  NSString              *date;
  id			proxy;
  NSRange               r;
  EcLogType             eclt;
  CREATE_AUTORELEASE_POOL(arp);

  [EcProcess class];            // Force linker to provide library

  pref = EC_DEFAULTS_PREFIX;
  if (nil == pref)
    {
      pref = @"";
    }
  defs = [NSUserDefaults userDefaultsWithPrefix: pref
                                         strict: EC_DEFAULTS_STRICT];
  dict = [defs dictionaryForKey: @"WellKnownHostNames"];
  if (nil != dict)
    {
      [NSHost setWellKnownNames: dict];
    }

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

  date = [[NSCalendarDate date] descriptionWithCalendarFormat:
    @"%Y-%m-%d %H:%M:%S %z" locale: [defs dictionaryRepresentation]];

  mesg = [NSString stringWithFormat: @"%@(%@): %@ %@ - %@\n", 
    name, [[NSHost currentHost] name], date, mode, mesg];

  /*
   * A last check to remove any embedded newlines.
   */
  r = [mesg rangeOfString: @"\n"];
  if (r.location != [mesg length] - 1)
    {
      NSMutableString	*m = [[mesg mutableCopy] autorelease];

      while (r.location != [m length] - 1)
	{
	  [m replaceCharactersInRange: r withString: @" "];
	  r = [m rangeOfString: @"\n"];
	}
      mesg = m;
    }
  
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
      [(id<Command>)proxy logMessage: mesg  
                                type: eclt  
                                name: name];
    }
  NS_HANDLER
    {
      NSLog (@"Could not log message to server: %@", localException);
      exit(1);
    }
  NS_ENDHANDLER

  RELEASE(arp);
  return 0;
}
