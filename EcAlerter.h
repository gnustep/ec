
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

#import <Foundation/NSObject.h>

@class	GSMimeSMTPClient;
@class	NSArray;
@class	NSMutableArray;
@class	NSMutableDictionary;
@class	NSString;
@class	NSTimer;


@interface	EcAlerter : NSObject
{
  NSArray		*rules;
  NSMutableDictionary	*email;
  NSMutableDictionary	*sms;
  NSTimer		*timer;
  NSString		*eFrom;
  NSString		*eHost;
  NSString		*ePort;
  GSMimeSMTPClient	*smtp;
}
- (BOOL) configure: (NSNotification*)n;
- (BOOL) configureWithDefaults: (NSDictionary*)c;
- (void) handleInfo: (NSString*)str;
- (void) flushEmail;
- (void) flushSms;
- (void) log: (NSMutableDictionary*)m to: (NSArray*)destinations;
- (void) mail: (NSMutableDictionary*)m to: (NSArray*)destinations;
- (void) sms: (NSMutableDictionary*)m to: (NSArray*)destinations;
- (void) timeout: (NSTimer*)t;
- (BOOL) setRules: (NSArray*)ra;
@end

