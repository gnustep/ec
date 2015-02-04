
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

#import	<Foundation/NSDictionary.h>
#import	<Foundation/NSInvocation.h>
#import	<Foundation/NSLock.h>
#import	<Foundation/NSMethodSignature.h>
#import	<Foundation/NSNotification.h>
#import	<Foundation/NSProxy.h>
#import	<Foundation/NSString.h>

#import	"EcUserDefaults.h"

static NSUserDefaults	*latest = nil;
static NSLock 		*lock = nil;

@interface	EcUserDefaults : NSProxy
{
  NSUserDefaults	*defs;
  NSString		*prefix;
  BOOL			enforce;
}
- (id) initWithPrefix: (NSString*)p strict: (BOOL)s;
- (NSString*) _getKey: (NSString*)baseKey;
@end

@implementation	EcUserDefaults

+ (void) initialize
{
  if (nil == lock)
    {
      lock = [NSLock new];
      [[NSObject leakAt: &lock] release];
      [[NSObject leakAt: &latest] release];
    }
}

- (NSArray*) arrayForKey: (NSString*)aKey
{
  return [defs arrayForKey: [self _getKey: aKey]];
}

- (BOOL) boolForKey: (NSString*)aKey
{
  return [defs boolForKey: [self _getKey: aKey]];
}

- (NSData*) dataForKey: (NSString*)aKey
{
  return [defs dataForKey: [self _getKey: aKey]];
}

- (void) dealloc
{
  [lock lock];
  if (latest == (NSUserDefaults*)self)
    {
      latest = nil;
    }
  [lock unlock];
  [prefix release];
  [defs release];
  [super dealloc];
}

- (NSString*) defaultsPrefix
{
  return prefix;
}

- (NSDictionary*) dictionaryForKey: (NSString*)aKey
{
  return [defs dictionaryForKey: [self _getKey: aKey]];
}

- (double) doubleForKey: (NSString*)aKey
{
  return [defs doubleForKey: [self _getKey: aKey]];
}

- (float) floatForKey: (NSString*)aKey
{
  return [defs floatForKey: [self _getKey: aKey]];
}

- (void) forwardInvocation: (NSInvocation*)anInvocation
{
  [anInvocation invokeWithTarget: defs];
}

- (NSString*) _getKey: (NSString*)aKey
{
  /* Make sure we have the prefix.
   */
  if (nil != prefix)
    {
      if (NO == [aKey hasPrefix: prefix])
	{
	  aKey = [prefix stringByAppendingString: aKey];
	}
      if (NO == enforce && nil == [defs objectForKey: aKey])
	{
	  /* Nothing found for key ... try without the prefix.
	   */
	  aKey = [aKey substringFromIndex: [prefix length]];
	}
    }
  return aKey;
}

- (id) init
{
  [self release];
  return nil;
}

- (id) initWithPrefix: (NSString*)p strict: (BOOL)s
{
  NSMutableArray	*list;

  [lock lock];
  enforce = s;
  defs = [[NSUserDefaults standardUserDefaults] retain];
  if (0 == [p length])
    {
      p = [defs stringForKey: @"EcUserDefaultsPrefix"]; 
      if (0 == [p length])
	{
	  p = nil;
	}
    }
  prefix = [p copy];

  /* Make sure the defaults database has our special domains at the start
   * of the search list and in the correct order.
   */
  list = [[defs searchList] mutableCopy];
  [list removeObject: @"EcCommand"];
  [list removeObject: @"EcConfiguration"];
  [list insertObject: @"EcCommand" atIndex: 0]; 
  [list insertObject: @"EcConfiguration" atIndex: 1]; 
  [defs setSearchList: list];
  [list release];
  ASSIGN(latest, (NSUserDefaults*)self);
  [lock unlock];
  return self;
}

- (NSInteger) integerForKey: (NSString*)aKey
{
  return [defs integerForKey: [self _getKey: aKey]];
}

- (NSString*) key: (NSString*)aKey
{
  /* Make sure we have the prefix.
   */
  if (nil != prefix && NO == [aKey hasPrefix: prefix])
    {
      aKey = [prefix stringByAppendingString: aKey];
    }
  return aKey;
}

- (NSMethodSignature*) methodSignatureForSelector: (SEL)aSelector
{
  if (class_respondsToSelector(object_getClass(self), aSelector))
    {
      return [super methodSignatureForSelector: aSelector];
    }
  return [defs methodSignatureForSelector: aSelector];
}

- (id) objectForKey: (NSString*)aKey
{
  return [defs objectForKey: [self _getKey: aKey]];
}

- (void) removeObjectForKey: (NSString*)aKey
{
  return [defs removeObjectForKey: [self _getKey: aKey]];
}

- (void) setBool: (BOOL)value forKey: (NSString*)aKey
{
  [defs setBool: value forKey: [self key: aKey]];
}

- (BOOL) setCommand: (id)val forKey: (NSString*)key
{
  return [defs setCommand: val forKey: [self key: key]];
}

- (void) setDouble: (double)value forKey: (NSString*)aKey
{
  [defs setDouble: value forKey: [self key: aKey]];
}

- (void) setFloat: (float)value forKey: (NSString*)aKey
{
  [defs setFloat: value forKey: [self key: aKey]];
}

- (void) setInteger: (NSInteger)value forKey: (NSString*)aKey
{
  [defs setInteger: value forKey: [self key: aKey]];
}

- (void) setObject: (id)anObject forKey: (NSString*)aKey
{
  [defs setObject: anObject forKey: [self key: aKey]];
}

- (NSArray*) stringArrayForKey: (NSString*)aKey
{
  return [defs stringArrayForKey: [self _getKey: aKey]];
}

- (NSString*) stringForKey: (NSString*)aKey
{
  return [defs stringForKey: [self _getKey: aKey]];
}

- (NSUserDefaults*) target
{
  return defs;
}

@end


@implementation	NSUserDefaults (EcUserDefaults)

+ (NSUserDefaults*) prefixedDefaults
{
  NSUserDefaults	*defs = nil;

  if (Nil != [EcUserDefaults class])
    {
      [lock lock];
      defs = [latest retain];
      [lock unlock];
    }
  return [defs autorelease];
}

+ (NSUserDefaults*) userDefaultsWithPrefix: (NSString*)aPrefix
				    strict: (BOOL)enforcePrefix
{
  return (NSUserDefaults*)[[[EcUserDefaults alloc] initWithPrefix:
    aPrefix strict: enforcePrefix] autorelease];
}

- (NSDictionary*) configuration
{
  return [self volatileDomainForName: @"EcConfiguration"];
}

- (NSString*) defaultsPrefix
{
  return nil;	// No prefix in use ... this is not a proxy
}

- (NSString*) key: (NSString*)aKey
{
  NSString	*prefix = [self defaultsPrefix];

  /* Make sure we have the prefix.
   */
  if (nil != prefix && NO == [aKey hasPrefix: prefix])
    {
      aKey = [prefix stringByAppendingString: aKey];
    }
  return aKey;
}

- (BOOL) setCommand: (id)val forKey: (NSString*)key
{
  NSDictionary		*old = [self volatileDomainForName: @"EcCommand"];
  NSMutableDictionary	*new = nil;
  NSString		*pre = [self defaultsPrefix];
  
  /* Make sure prefix is used if we have one set.
   */
  if (nil != pre)
    {
      if (NO == [key hasPrefix: pre])
	{
	  key = [pre stringByAppendingString: key];
	}
    }
  if (nil == val)
    {
      if (nil != [old objectForKey: key])
	{
	  new = [old mutableCopy];
	  [new removeObjectForKey: key];
	}
    }
  else
    {
      if (NO == [val isEqual: [old objectForKey: key]])
	{
	  new = [old mutableCopy];
	  if (nil == new)
	    {
	      new = [NSMutableDictionary new];
	    }
	  [new setObject: val forKey: key];
	}
    }
  if (nil != new)
    {
      if (nil != old)
	{
	  [self removeVolatileDomainForName: @"EcCommand"];
	}
      [self setVolatileDomain: new forName: @"EcCommand"];
      [new release];
      [[NSNotificationCenter defaultCenter] postNotificationName:
	NSUserDefaultsDidChangeNotification object: self];
      return YES;
    }
  return NO;
}

- (BOOL) setConfiguration: (NSDictionary*)config
{
  NSDictionary	*old = [self volatileDomainForName: @"EcConfiguration"];

  if (old != config && NO == [old isEqual: config])
    {
      if (nil != old)
	{
	  [self removeVolatileDomainForName: @"EcConfiguration"];
	}
      if (nil != config)
	{
	  [self setVolatileDomain: config forName: @"EcConfiguration"];
	}
      [[NSNotificationCenter defaultCenter] postNotificationName:
	NSUserDefaultsDidChangeNotification
	object: self];
      return YES;
    }
  return NO;
}

@end

