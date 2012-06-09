
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

int
main()
{
  CREATE_AUTORELEASE_POOL(arp);
  NSUserDefaults	*defs = [NSUserDefaults standardUserDefaults];
  NSString		*host;
  NSString		*name;
  id			proxy;

  host = [defs stringForKey: @"BSCommandHost"];
  if (host == nil)
    {
      host = [defs stringForKey: @"CommandHost"];
      if (host == nil)
	{
	  host = @"*";
	}
    }
  if ([host length] == 0)
    {
      host = [[NSHost currentHost] name];
    }

  /*
   * Shut down the local command server.
   */
  name = [defs stringForKey: @"BSCommandName"];
  if (name == nil)
    {
      name = [defs stringForKey: @"CommandName"];
      if (name == nil)
	{
	  name = @"Command";
	}
    }

  proxy = [NSConnection rootProxyForConnectionWithRegisteredName: name
							    host: host
    usingNameServer: [NSSocketPortNameServer sharedInstance]];
  [(id<Command>)proxy terminate];

  RELEASE(arp);
  return 0;
}

