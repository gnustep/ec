
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
#define	EC_BASE_CLASS	EcControl
#endif

@class EC_BASE_CLASS;

void
inner_main()
{
  NSDictionary		*defs;
  NSAutoreleasePool	*arp = [NSAutoreleasePool new];

  cmdVersion(@"$Date: 2012-02-18 08:30:36 +0000 (Sat, 18 Feb 2012) $ $Revision: 66052 $");

  defs = [NSDictionary dictionaryWithObjectsAndKeys:
    @"Command", @"HomeDirectory",
    @"YES", @"Daemon",
#if	defined(EC_REGISTRATION_DOMAIN)
    EC_REGISTRATION_DOMAIN
#endif
    nil];
    
  if (nil == [[EC_BASE_CLASS alloc] initWithDefaults: defs])
    {
      NSLog(@"Unable to create control object.\n");
      exit(1);
    }

  [EcProc ecRun];

  [arp release];
  exit(0);
}

int
main(int argc, char *argv[])
{
  inner_main();
  return 0;
}
