
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

#ifndef	_ECLOGGER_H
#define	_ECLOGGER_H

@interface	EcLogger : NSObject <CmdPing>
{
  NSRecursiveLock       *lock;
  NSDate		*last;
  NSTimer		*timer;
  NSTimeInterval	interval;
  unsigned		size;
  NSMutableString	*message;
  EcLogType		type;
  NSString		*key;
  NSString		*flushKey;
  NSString		*serverKey;
  NSString		*serverName;
  BOOL			inFlush;
  BOOL                  externalFlush;
  BOOL			registered;
  BOOL			pendingFlush;
}
+ (EcLogger*) loggerForType: (EcLogType)t;
- (void) cmdGnip: (id <CmdPing>)from
	sequence: (unsigned)num
	   extra: (NSData*)data;
- (void) cmdMadeConnectionToServer: (NSString*)name;
- (void) cmdPing: (id <CmdPing>)from
	sequence: (unsigned)num
	   extra: (NSData*)data;
- (void) flush;
- (void) log: (NSString*)fmt arguments: (va_list)args;
- (void) update;
@end

#endif

