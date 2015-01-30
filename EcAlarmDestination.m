
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

/* Make connection to destination host.
 */
- (id<EcAlarmDestination>) _connect;

/* Loss of connection ... clear destination.
 */
- (void) _connectionBecameInvalid: (id)connection;

/* Regular timer to handle alarms.
 */
- (void) _timeout: (NSTimer*)t;

/* Remove alll recdords for managed object
 */
- (void) _unmanage: (NSString*)m;

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
      else if ([event perceivedSeverity] == EcAlarmSeverityCleared)
        {
          NSUInteger    index;

          /* Event clears may only be coalesced with other clears,
           * otherwise we might have a case where a clear is sent
           * to the alarm sink without a corresponding alarm having
           * been raised.
           */
          index = [_alarmQueue indexOfObject: event];
	  [_alarmQueue addObject: event];
          if (NSNotFound != index)
            {
              [_alarmQueue removeObjectAtIndex: index];
            }
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
  [_alarmsCleared release];
  _alarmsCleared = nil;
  [_managedObjects release];
  _managedObjects = nil;
  [_alarmLock release];
  _alarmLock = nil;
  [super dealloc];
}

- (id) initWithHost: (NSString*)host name: (NSString*)name
{
  if (nil != (self = [super init]))
    {
      NSDate	*begin;

      _host = [host copy];
      _name = [name copy];
      _alarmLock = [NSRecursiveLock new];
      _alarmQueue = [NSMutableArray new];
      _alarmsActive = [NSMutableSet new];
      _alarmsCleared = [NSMutableSet new];
      _managedObjects = [NSMutableSet new];

      [NSThread detachNewThreadSelector: @selector(run)
			       toTarget: self
			     withObject: nil];
      begin = [NSDate date];
      while (NO == [self isRunning])
	{
          NSDate        *when;

	  if ([begin timeIntervalSinceNow] < -5.0)
	    {
	      NSLog(@"alarm thread failed to start within 5 seconds");
	      [_alarmLock lock];
	      _shouldStop = YES;	// If the thread starts ... shutdown
	      [_alarmLock unlock];
	      [self release];
	      return nil;
	    }
          when = [[NSDate alloc] initWithTimeIntervalSinceNow: 0.1];
	  [[NSRunLoop currentRunLoop] runMode: NSDefaultRunLoopMode
                                   beforeDate: when];
          [when release];
	}
    }
  return self;
}

- (oneway void) domanage: (in bycopy NSString*)managedObject
{
  if (nil == managedObject)
    {
      managedObject = EcMakeManagedObject(nil, nil, nil);
    }
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

- (id) init
{
  return [self initWithHost: nil name: nil];
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

  while (YES == _isRunning)
    {
      [loop runMode: NSDefaultRunLoopMode beforeDate: future];
    }
  [pool release];
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
  BOOL		wasShuttingDown;

  [_alarmLock lock];
  wasShuttingDown = _shouldStop;
  _shouldStop = YES;
  [_host release];
  _host = nil;
  [_name release];
  _name = nil;
  [_alarmLock unlock];
  if (NO == wasShuttingDown)
    {
      NSDate	*begin;

      /* Unless we are called recursively, lets wait for a while for
       * the alarm thread to terminate.
       */
      begin = [NSDate date];
      while (YES == [self isRunning])
	{
	  NSDate    *when;

	  if ([begin timeIntervalSinceNow] < -5.0)
	    {
	      NSLog(@"alarm thread failed to stop within 5 seconds");
	      return;
	    }
	  when = [[NSDate alloc] initWithTimeIntervalSinceNow: 0.1];
	  [[NSRunLoop currentRunLoop] runMode: NSDefaultRunLoopMode
				   beforeDate: when];
	  [when release];
	}
    }
}

- (oneway void) unmanage: (in bycopy NSString*)managedObject
{
  if (nil == managedObject)
    {
      managedObject = EcMakeManagedObject(nil, nil, nil);
    }
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

- (id<EcAlarmDestination>) _connect
{
  id<EcAlarmDestination>        d = nil;

  [_alarmLock lock];
  NS_DURING
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
    d = [(id)_destination retain];
  NS_HANDLER
    NSLog(@"Problem connecting to destination ... %@", localException);
  NS_ENDHANDLER
  [_alarmLock unlock];
  return [(id)d autorelease];
}

- (void) _connectionBecameInvalid: (id)connection
{
  [self setDestination: nil];
}

- (void) _timeout: (NSTimer*)t
{
  /* We hold a lock while modifying the internal data structures,
   * but must release it while forwarding things to their eventual
   * destination (in case the forwarding is done in another thread
   * which needs to grab the lock or where a DO message causes an
   * attempt to grab the lock).
   */
  [_alarmLock lock];
  if (NO == _inTimeout && YES == _isRunning)
    {
      _inTimeout = YES;
      NS_DURING
	{
	  if ([_alarmQueue count] > 0)
	    {
	      // Do stuff here

	      while ([_alarmQueue count] > 0)
		{
		  id	o;

		  o = [[[_alarmQueue objectAtIndex: 0] retain] autorelease];
		  [_alarmQueue removeObjectAtIndex: 0];

		  if (YES == [o isKindOfClass: [EcAlarm class]])
		    {
		      EcAlarm	*next = (EcAlarm*)o;
		      EcAlarm	*prev = [_alarmsActive member: next];
		      NSString	*m = [next managedObject];
                      BOOL      shouldForward = NO;

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
                              /* Alarm previously active ...
                               * remove old copy and forward clear.
                               */
			      [_alarmsActive removeObject: prev];
                              shouldForward = YES;
			    }
                          if (nil == [_alarmsCleared member: next])
                            {
                              /* Alarm not previously cleared ...
                               * add to cleared set and forward clear.
                               */
                              [_alarmsCleared addObject: next];
                              shouldForward = YES;
                            }
			}
		      else
			{
                          /* If there was a previous version of the alarm
                           * cleared, remove that so it's re-raised.
                           */
                          [_alarmsCleared removeObject: next];

			  /* If the alarm is new or of changed severity,
			   * update the records and pass it on.
			   */
			  if (nil == prev || [next perceivedSeverity]
			    != [prev perceivedSeverity])
			    {
			      [_alarmsActive addObject: next];
                              shouldForward = YES;
			    }
			}

                      if (YES == shouldForward)
                        {
			  /* If the managed object is not registered,
			   * register before sending an alarm for it.
			   */
			  if (nil == [_managedObjects member: m])
			    {
			      [_managedObjects addObject: m];
			    }
                          else
                            {
                              m = nil;
                            }

                          [_alarmLock unlock];
                          if (nil != m)
                            {
			      [self domanageFwd: m];
                            }
                          [self alarmFwd: next];
                          [_alarmLock lock];
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
                              [_alarmLock unlock];
			      [self domanageFwd: m];
                              [_alarmLock lock];
			    }
			}
		      else if (YES == [s hasPrefix: @"unmanage "])
			{
			  NSString	*m = [s substringFromIndex: 9];

			  if (nil != [_managedObjects member: m])
			    {
                              [_alarmLock unlock];
                              [self _unmanage: m];
			      [self unmanageFwd: m];
                              [_alarmLock lock];
			    }

			  /* When we unmanage an object, we also
			   * implicitly unmanage objects which
			   * are components of that object.
			   */
			  if (YES == [m hasSuffix: @"_"])
			    {
			      NSEnumerator	*e;
			      NSString		*s;

			      e = [[_managedObjects allObjects]
				objectEnumerator];
			      while (nil != (s = [e nextObject]))
				{
				  if (YES == [s hasPrefix: m])
				    {
                                      [_alarmLock unlock];
                                      [self unmanageFwd: s];
                                      [_alarmLock lock];
				    }
				}
			    }
			}
		      else
			{
			  NSLog(@"ERROR ... unexpected command '%@'", s);
			}
		    }
		}
	    }
	  _inTimeout = NO;
	  if (YES == _shouldStop)
	    {
	      _isRunning = NO;
	    }
	  [_alarmLock unlock];
	}
      NS_HANDLER
	{
	  _inTimeout = NO;
	  if (YES == _shouldStop)
	    {
	      _isRunning = NO;
	    }
	  [_alarmLock unlock];
	  NSLog(@"%@ %@", NSStringFromClass([self class]), localException);
	}
      NS_ENDHANDLER
    }
  else
    {
      [_alarmLock unlock];
    }
}

- (void) _unmanage: (NSString*)m
{
  if (nil != [_managedObjects member: m])
    {
      NSEnumerator  *e;
      EcAlarm       *a;

      e = [[_alarmsActive allObjects] objectEnumerator];
      while (nil != (a = [e nextObject]))
        {
          if ([[a managedObject] isEqual: m])
            {
              [_alarmsActive removeObject: a];
            }
        }
      e = [[_alarmsCleared allObjects] objectEnumerator];
      while (nil != (a = [e nextObject]))
        {
          if ([[a managedObject] isEqual: m])
            {
              [_alarmsCleared removeObject: a];
            }
        }
      [_managedObjects removeObject: m];
    }
}

@end

@implementation	EcAlarmDestination (Forwarding)

- (void) alarmFwd: (EcAlarm*)event
{
  if (NO == [NSThread isMainThread])
    {
      [self performSelectorOnMainThread: _cmd
                             withObject: event
                          waitUntilDone: NO];
      return;
    }
  NS_DURING
    [[self _connect] alarm: event];
    NS_DURING
      [[self backups] makeObjectsPerformSelector: @selector(alarm:)
                                      withObject: event];
    NS_HANDLER
      [self setBackups: nil];
      NSLog(@"Problem sending alarm to backups ... %@", localException);
    NS_ENDHANDLER
  NS_HANDLER
    [self setDestination: nil];
    NSLog(@"Problem sending alarm to destination ... %@", localException);
  NS_ENDHANDLER
}

- (void) domanageFwd: (NSString*)managedObject
{
  if (NO == [NSThread isMainThread])
    {
      [self performSelectorOnMainThread: _cmd
                             withObject: managedObject
                          waitUntilDone: NO];
      return;
    }
  NS_DURING
    [[self _connect] domanage: managedObject];
    NS_DURING
      [[self backups] makeObjectsPerformSelector: @selector(domanage:)
                                      withObject: managedObject];
    NS_HANDLER
      [self setBackups: nil];
      NSLog(@"Problem with domanage to backups ... %@", localException);
    NS_ENDHANDLER
  NS_HANDLER
    [self setDestination: nil];
    NSLog(@"Problem with domanage to destination ... %@", localException);
  NS_ENDHANDLER
}

- (void) unmanageFwd: (NSString*)managedObject
{
  if (NO == [NSThread isMainThread])
    {
      [self performSelectorOnMainThread: _cmd
                             withObject: managedObject
                          waitUntilDone: NO];
      return;
    }
  NS_DURING
    [[self _connect] unmanage: managedObject];
    NS_DURING
      [[self backups] makeObjectsPerformSelector: @selector(unmanage:)
                                      withObject: managedObject];
    NS_HANDLER
      [self setBackups: nil];
      NSLog(@"Problem with unmanage to backups ... %@", localException);
    NS_ENDHANDLER
  NS_HANDLER
    [self setDestination: nil];
    NSLog(@"Problem with unmanage to destination ... %@", localException);
  NS_ENDHANDLER
}

@end

