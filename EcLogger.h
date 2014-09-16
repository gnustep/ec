
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

/** Instances of the EcLogger class are used to handle various types of
 * logging.<br />
 * The default implementation supports writing to local files and sending
 * logs to a remote process (by default, the Command server).<br />
 * Configuration options control the amount of data buffered in memory
 * before logs are flushed, and the amount of time for which data may
 * be buffered in memory before being flushed.<br />
 * Configuration options are ???Server (to specify the name of the
 * server to log to if not Command) and ???Flush (to specify when to
 * flush the in-memory buffer), where ??? is the type of logging being
 * done by a logger object.<br />
 * When there is no type-specific flush configuration, the DefaultFlush
 * configuration key will be used.<br />
 * The flush configuration value must be a floating point number of
 * seconds after which to flush, optionally folowed by a colon and an
 * integer number of kilobytes of data allowed before the buffer is
 * flushed.
 */
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

/** Returns a (cached) logger object for the specified type of logging.<br />
 * Creates a new object (adding it to the cache) if none exists.
 */
+ (EcLogger*) loggerForType: (EcLogType)t;

/** Sets the factory class used by the +loggerForType: method
 * to create new EcLogger objects.<br />
 * This is provided as a convenience so that you can get all code to use
 * a subclass of EcLogger without having to use a category to override
 * that method.
 */
+ (void) setFactory: (Class)c;

/** Supports the CmdPing protocol.
 */
- (void) cmdGnip: (id <CmdPing>)from
	sequence: (unsigned)num
	   extra: (NSData*)data;

- (void) cmdMadeConnectionToServer: (NSString*)name;

/** Supports the CmdPing protocol.
 */
- (void) cmdPing: (id <CmdPing>)from
	sequence: (unsigned)num
	   extra: (NSData*)data;

/** Called to flush accumulated data from the message instance variable.<br />
 * On return from this method the variable should be empty.
 */
- (void) flush;

/** Called to log a message by appending to the message instance variable.
 * This method may also schedule an asynchronous flush if the message
 * buffer is too large or if the last flush was too long ago.
 */
- (void) log: (NSString*)fmt arguments: (va_list)args;

/** Called when the user defaults system has changed and a configuration
 * update may have occurred.
 */
- (void) update;

@end

/** Notification sent when the logging set of cached loggers is emptied.
 */
extern NSString* const EcLoggersDidChangeNotification;

#endif

