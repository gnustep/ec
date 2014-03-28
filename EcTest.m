
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
#import "EcProcess.h"
#import "EcTest.h"

id<EcTest>
EcTestConnect(NSString *name, NSString *host, NSTimeInterval timeout)
{
  CREATE_AUTORELEASE_POOL(pool);
  id<EcTest>    proxy = nil;
  NSDate        *when;

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
            host: @""
            usingNameServer: [NSSocketPortNameServer sharedInstance]];
        }
      NS_HANDLER
        {
          proxy = nil;
        }
      NS_ENDHANDLER
      if (nil == proxy)
        {
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

