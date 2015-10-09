
/** Enterprise Control Configuration and Logging

   Copyright (C) 2014 Free Software Foundation, Inc.

   Written by: Richard Frith-Macdonald <rfm@gnu.org>
   Date: March 2014
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
#import "EcTest.h"

static NSUserDefaults*
defaults()
{
  static NSUserDefaults   *defs = nil;

  if (nil == defs)
    {
      NSString              *pref;
      NSDictionary          *dict;

      [EcProcess class];    // Force linker to provide library

      pref = EC_DEFAULTS_PREFIX;
      if (nil == pref)
        {
          pref = @"";
        }
      ASSIGN(defs, [NSUserDefaults userDefaultsWithPrefix: pref
        strict: EC_DEFAULTS_STRICT]);
      dict = [defs dictionaryForKey: @"WellKnownHostNames"];
      if (nil != dict)
        {
          [NSHost setWellKnownNames: dict];
        }
    }
  return defs;
}

id<EcTest>
EcTestConnect(NSString *name, NSString *host, NSTimeInterval timeout)
{
  CREATE_AUTORELEASE_POOL(pool);
  BOOL                  triedLaunching = NO;
  NSUserDefaults        *defs = defaults();
  id<EcTest>            proxy = nil;
  NSDate                *when;

  if (nil == host) host = @"";
  if (timeout > 0)
    {
      when = [NSDate dateWithTimeIntervalSinceNow: timeout];
    }
  else
    {
      when = [NSDate distantFuture];
    }

  while (nil == proxy && [when timeIntervalSinceNow] > 0.0)
    {
      NS_DURING
        {
          proxy = (id<EcTest>)[NSConnection
            rootProxyForConnectionWithRegisteredName: name
            host: host
            usingNameServer: [NSSocketPortNameServer sharedInstance]];
        }
      NS_HANDLER
        {
          proxy = nil;
        }
      NS_ENDHANDLER
      if (nil == proxy)
        {
          /* Where the initial contact attempt failed,
           * try launching the process.
           */
          if (NO == triedLaunching)
            {
              NS_DURING
                {
                  id<Command>           cmd;
                  NSString              *cmdName;

                  cmdName = [defs stringForKey: @"CommandName"];
                  if (nil == cmdName)
                    {
                      cmdName = @"Command";
                    }
                  cmd = (id<Command>)[NSConnection
                    rootProxyForConnectionWithRegisteredName: cmdName
                    host: host
                    usingNameServer: [NSSocketPortNameServer sharedInstance]];
                  [cmd launch: name];
                }
              NS_HANDLER
                {
                  NSLog(@"Failed to get 'Command' on '%@' to launch '%@': %@",
                    host, name, localException);
                }
              NS_ENDHANDLER
              triedLaunching = YES;
            }
          [NSThread sleepForTimeInterval: 0.1];
        }
    }
  [proxy retain];
  DESTROY(pool);
  return [proxy autorelease];
}

id
EcTestGetConfig(id<EcTest> process, NSString *key)
{
  id    val;

  NSCAssert([key isKindOfClass: [NSString class]], NSInvalidArgumentException);
  val = [process ecTestConfigForKey: key];
  if (nil != val)
    {
      val = [NSPropertyListSerialization
        propertyListWithData: val
        options: NSPropertyListMutableContainers
        format: 0
        error: 0];
    }
  return val;
}

void
EcTestSetConfig(id<EcTest> process, NSString *key, id value)
{
  NSCAssert([key isKindOfClass: [NSString class]], NSInvalidArgumentException);
  if (nil != value)
    {
      value = [NSPropertyListSerialization
        dataFromPropertyList: value
        format: NSPropertyListBinaryFormat_v1_0
        errorDescription: 0];
    }
  [process ecTestSetConfig: value forKey: key];

}

