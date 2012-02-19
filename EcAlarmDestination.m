
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
#import "EcAlarm.h"
#import	"EcAlarmDestination.h"


@interface	EcAlarmDestination (Private)

/* Loss of connection ... clear destination.
 */
- (void) _connectionBecameInvalid: (id)connection;

/* Regular timer to handle alarms.
 */
- (void) _timeout: (NSTimer*)t;

@end

@implementation	EcAlarmDestination

- (oneway void) alarm: (in bycopy EcAlarm*)event
{
  if (NO == [event isKindOfClass: [EcAlarm class]])
    {
      NSLog(@"[%@-%@] invalid argument (%@)",
	NSStringFromClass([self class]), NSStringFromSelector(_cmd),
	event);
    }
  else
    {
      [_alarmLock lock];
      if (YES  == _coalesceOff)
	{
	  [_alarmQueue addObject: event];
	}
      else
	{
	  [event retain];
	  [_alarmQueue removeObject: event];
	  [_alarmQueue addObject: event];
	  [event release];
	}
      [_alarmLock unlock];
    }
}

- (NSArray*) alarms
{
  NSArray	*a;

  [_alarmLock lock];
  a = [_alarmsActive allObjects];
  [_alarmLock unlock];
  return a;
}

- (NSArray*) backups
{
  NSArray	*a;

  [_alarmLock lock];
  a = [_backups retain];
  [_alarmLock unlock];
  return [a autorelease];
}

- (void) dealloc
{
  [self shutdown];
  [_backups release];
  [(id)_destination release];
  _destination = nil;
  [_alarmQueue release];
  _alarmQueue = nil;
  [_alarmsActive release];
  _alarmsActive = nil;
  [_managedObjects release];
  _managedObjects = nil;
  [_alarmLock release];
  _alarmLock = nil;
  [super dealloc];
}

- (id) init
{
  if (nil != (self = [super init]))
    {
      NSDate	*begin;

      _alarmLock = [NSRecursiveLock new];
      _alarmQueue = [NSMutableArray new];
      _alarmsActive = [NSMutableSet new];
      _managedObjects = [NSMutableSet new];

      [NSThread detachNewThreadSelector: @selector(run)
			       toTarget: self
			     withObject: nil];
      begin = [NSDate date];
      while (NO == [self isRunning])
	{
	  if ([begin timeIntervalSinceNow] < -5.0)
	    {
	      NSLog(@"alarm thread failed to start within 5 seconds");
	      [_alarmLock lock];
	      _shouldStop = YES;	// If the thread starts ... shutdown
	      [_alarmLock unlock];
	      [self release];
	      return nil;
	    }
	  [NSThread sleepForTimeInterval: 0.1];
	}
    }
  return self;
}

- (oneway void) domanage: (in bycopy NSString*)managedObject
{
  if (NO == [managedObject isKindOfClass: [NSString class]]
    || 4 != [[managedObject componentsSeparatedByString: @"_"] count])
    {
      NSLog(@"[%@-%@] invalid argument (%@)",
	NSStringFromClass([self class]), NSStringFromSelector(_cmd),
	managedObject);
    }
  else
    {
      NSString	*event;

      event = [NSString stringWithFormat: @"domanage %@", managedObject];
      [_alarmLock lock];
      if (YES  == _coalesceOff)
	{
	  [_alarmQueue addObject: event];
	}
      else
	{
	  [_alarmQueue removeObject: event];
	  [_alarmQueue addObject: event];
	}
      [_alarmLock unlock];
    }
}

- (id) initWithHost: (NSString*)host name: (NSString*)name
{
  /* We set the host namd name before calling -init, so that subclasses
   * which override -init may make use of the values we have set.
   */
  _host = [host copy];
  _name = [name copy];
  return [self init];
}

- (BOOL) isRunning
{
  BOOL	result;

  [_alarmLock lock];
  result = _isRunning;
  [_alarmLock unlock];
  return result;
}

- (void) run
{
  NSAutoreleasePool	*pool = [NSAutoreleasePool new];
  NSRunLoop		*loop = [NSRunLoop currentRunLoop];
  NSDate		*future = [NSDate distantFuture];

  _isRunning = YES;
  _timer = [NSTimer scheduledTimerWithTimeInterval: 1.0
					    target: self
					  selector: @selector(_timeout:)
					  userInfo: nil
					   repeats: YES];

  while (NO == _shouldStop)
    {
      [loop runMode: NSDefaultRunLoopMode beforeDate: future];
    }
  [pool release];

  _isRunning = NO;
}

- (void) setBackups: (NSArray*)backups
{
  NSUInteger	i;

  if (nil != backups && NO == [backups isKindOfClass: [NSArray class]])
    {
      [NSException raise: NSInvalidArgumentException
		  format: @"[%@-%@] argument is not nil or an array",
	NSStringFromClass([self class]), NSStringFromSelector(_cmd)];
    }
  i = [backups count];
  if (0 == i)
    {
      backups = nil;
    }
  else
    {
      while (i-- > 0)
	{
	  if (NO == [[backups objectAtIndex: i]
	    isKindOfClass: [EcAlarmDestination class]])
	    {
	      [NSException raise: NSInvalidArgumentException
			  format: @"[%@-%@] array contains bad destination",
		NSStringFromClass([self class]), NSStringFromSelector(_cmd)];
	    }
	}
    }
  [_alarmLock lock];
  ASSIGNCOPY(_backups, backups);
  [_alarmLock unlock];
}

- (BOOL) setCoalesce: (BOOL)coalesce
{
  BOOL	old;

  [_alarmLock lock];
  old = (NO == _coalesceOff) ? YES : NO;
  _coalesceOff = (NO == coalesce) ? YES : NO;
  [_alarmLock unlock];
  return old;
}

- (id<EcAlarmDestination>) setDestination: (id<EcAlarmDestination>)destination
{
  id	old;

  if (nil != (id)destination && NO == [(id)destination
    conformsToProtocol: @protocol(EcAlarmDestination)])
    {
      [NSException raise: NSInvalidArgumentException
	format: @"[%@-%@] arg does not conform to EcAlarmDestination protocol",
	NSStringFromClass([self class]), NSStringFromSelector(_cmd)];
    }
  [_alarmLock lock];
  old = (id)_destination;
  _destination = (id<EcAlarmDestination>)[(id)destination retain];
  [_alarmLock unlock];
  return (id<EcAlarmDestination>)[old autorelease];
}

- (void) shutdown
{
  NSDate	*begin;

  [_alarmLock lock];
  _shouldStop = YES;
  [_host release];
  _host = nil;
  [_name release];
  _name = nil;
  [_alarmLock unlock];
  begin = [NSDate date];
  while (YES == [self isRunning])
    {
      if ([begin timeIntervalSinceNow] < -5.0)
	{
	  NSLog(@"alarm thread failed to stop within 5 seconds");
	  return;
	}
      [NSThread sleepForTimeInterval: 0.1];
    }
}

- (oneway void) unmanage: (in bycopy NSString*)managedObject
{
  if (NO == [managedObject isKindOfClass: [NSString class]]
    || 4 != [[managedObject componentsSeparatedByString: @"_"] count])
    {
      NSLog(@"[%@-%@] invalid argument (%@)",
	NSStringFromClass([self class]), NSStringFromSelector(_cmd),
	managedObject);
    }
  else
    {
      NSString	*event;

      event = [NSString stringWithFormat: @"unmanage %@", managedObject];
      [_alarmLock lock];
      if (YES  == _coalesceOff)
	{
	  [_alarmQueue addObject: event];
	}
      else
	{
	  [_alarmQueue removeObject: event];
	  [_alarmQueue addObject: event];
	}
      [_alarmLock unlock];
    }
}

@end

@implementation	EcAlarmDestination (Private)

- (void) _connectionBecameInvalid: (id)connection
{
  [self setDestination: nil];
}

- (void) _timeout: (NSTimer*)t
{
  [_alarmLock lock];
  if (NO == _inTimeout && YES == _isRunning && NO == _shouldStop)
    {
      _inTimeout = YES;
      NS_DURING
	{
	  if ([_alarmQueue count] > 0)
	    {
	      if (nil == (id)_destination)
		{
		  if (nil != _name)
		    {
		      id	proxy;

		      if (nil == _host)
			{
			  proxy = [NSConnection
			    rootProxyForConnectionWithRegisteredName: _name 
								host: _host
			    usingNameServer:
			      [NSMessagePortNameServer sharedInstance]];
			}
		      else
			{
			  proxy = [NSConnection
			    rootProxyForConnectionWithRegisteredName: _name 
								host: _host
			    usingNameServer:
			      [NSSocketPortNameServer sharedInstance]];
			}

		      if (proxy != nil)
			{
			  id connection = [proxy connectionForProxy];
		      
			  [connection setDelegate: self];
			  [[NSNotificationCenter defaultCenter]
			    addObserver: self
			    selector: @selector(_connectionBecameInvalid:)
			    name: NSConnectionDidDieNotification
			    object: connection];
			  [self setDestination: (id<EcAlarmDestination>)proxy];
			}
		    }
		}
	      // Do stuff here

	      while ([_alarmQueue count] > 0)
		{
		  id	o = [_alarmQueue objectAtIndex: 0];

		  if (YES == [o isKindOfClass: [EcAlarm class]])
		    {
		      EcAlarm	*next = (EcAlarm*)o;
		      EcAlarm	*prev = [_alarmsActive member: next];
		      NSString	*m = [next managedObject];

		      if (nil == prev)
			{
			  [next setFirstEventDate: [next eventDate]];
			}
		      else
			{
			  [next setFirstEventDate: [prev firstEventDate]];
			}

		      if ([next perceivedSeverity] == EcAlarmSeverityCleared)
			{
			  if (nil != prev)
			    {
			      /* send the clear for the entry and remove it
			       */
			      [_alarmsActive removeObject: prev];
			      [self alarmFwd: next];
			    }
			}
		      else
			{
			  /* If the managed object is not registered,
			   * register before sending an alarm for it.
			   */
			  if (nil == [_managedObjects member: m])
			    {
			      [_managedObjects addObject: m];
			      [self domanageFwd: m];
			    }

			  /* If the alarm is new or of changed severity,
			   * update the records and pass it on.
			   */
			  if (nil == prev || [next perceivedSeverity]
			    != [prev perceivedSeverity])
			    {
			      [_alarmsActive addObject: next];
			      [self alarmFwd: next];
			    }
			}
		    }
		  else
		    {
		      NSString	*s = [o description];

		      if (YES == [s hasPrefix: @"domanage "])
			{
			  NSString	*m = [s substringFromIndex: 9];

			  if (nil == [_managedObjects member: m])
			    {
			      [_managedObjects addObject: m];
			      [self domanageFwd: m];
			    }
			}
		      else if (YES == [s hasPrefix: @"unmanage "])
			{
			  NSString	*m = [s substringFromIndex: 9];

			  if (nil != [_managedObjects member: m])
			    {
			      [_managedObjects removeObject: m];
			      [self unmanageFwd: m];
			    }

			  /* When we unmanage an object, we also
			   * implicitly unmanage objects which
			   * are components of that object.
			   */
			  if (YES == [m hasSuffix: @"_"])
			    {
			      NSEnumerator	*e;
			      NSString		*s;

			      e = [[[_managedObjects copy] autorelease]
				objectEnumerator];
			      while (nil != (s = [e nextObject]))
				{
				  if (YES == [s hasPrefix: m])
				    {
				      [_managedObjects removeObject: s];
				    }
				}
			    }
			}
		      else
			{
			  NSLog(@"ERROR ... unexpected command '%@'", s);
			}
		    }
		  [_alarmQueue removeObjectAtIndex: 0];
		}
	    }
	  _inTimeout = NO;
	  [_alarmLock unlock];
	}
      NS_HANDLER
	{
	  _inTimeout = NO;
	  [_alarmLock unlock];
	  NSLog(@"%@ %@", NSStringFromClass([self class]), localException);
	}
      NS_ENDHANDLER
    }
}

@end

@implementation	EcAlarmDestination (Forwarding)

- (void) alarmFwd: (EcAlarm*)event
{
  NS_DURING
    [_destination alarm: event];
    NS_DURING
      [_backups makeObjectsPerformSelector: @selector(alarm:)
				withObject: event];
    NS_HANDLER
      DESTROY(_backups);
      NSLog(@"Problem sending alarm to backups ... %@", localException);
    NS_ENDHANDLER
  NS_HANDLER
    [self setDestination: nil];
    NSLog(@"Problem sending alarm to destination ... %@", localException);
  NS_ENDHANDLER
}

- (void) domanageFwd: (NSString*)managedObject
{
  NS_DURING
    [_destination domanage: managedObject];
    NS_DURING
      [_backups makeObjectsPerformSelector: @selector(domanage:)
				withObject: managedObject];
    NS_HANDLER
      DESTROY(_backups);
      NSLog(@"Problem with domanage to backups ... %@", localException);
    NS_ENDHANDLER
  NS_HANDLER
    [self setDestination: nil];
    NSLog(@"Problem with domanage to destination ... %@", localException);
  NS_ENDHANDLER
}

- (void) unmanageFwd: (NSString*)managedObject
{
  NS_DURING
    [_destination unmanage: managedObject];
    NS_DURING
      [_backups makeObjectsPerformSelector: @selector(unmanage:)
				withObject: managedObject];
    NS_HANDLER
      DESTROY(_backups);
      NSLog(@"Problem with unmanage to backups ... %@", localException);
    NS_ENDHANDLER
  NS_HANDLER
    [self setDestination: nil];
    NSLog(@"Problem with unmanage to destination ... %@", localException);
  NS_ENDHANDLER
}

@end

