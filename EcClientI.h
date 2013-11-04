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

#import	<Foundation/NSObject.h>

#import	"EcProcess.h"

@class	NSData;
@class	NSMutableSet;
@class	NSString;

/* The EcClientI class provides a lightweight interface to a remote
 * process, equipped to handle inter-process keepalive signalling.
 */
@interface	EcClientI : NSObject
{
  id<CmdClient>	theServer;
  id		obj;
  NSString	*name;
  NSDate	*lastUnanswered;	/* Last unanswered ping.	*/
  unsigned	fwdSequence;		/* Last ping sent TO client.	*/
  unsigned	revSequence;		/* Last gnip sent BY client.	*/
  NSMutableSet	*files;			/* Want update info for these.	*/
  NSData	*config;		/* Config info for client.	*/
  BOOL		pingOk;                 /* Can remote end accept ping?  */
  BOOL		transient;              /* Is this a transient client?  */
  BOOL		unregistered;           /* Has client unregistered?     */
}
- (NSComparisonResult) compare: (EcClientI*)other;
- (NSData*) config;
- (NSMutableSet*) files;
- (BOOL) gnip: (unsigned)seq;
- (id) initFor: (id)obj
          name: (NSString*)n
	  with: (id<CmdClient>)svr;
- (NSDate*) lastUnanswered;
- (NSString*) name;
- (id) obj;
- (void) ping;
- (void) setConfig: (NSData*)c;
- (void) setName: (NSString*)n;
- (void) setObj: (id)o;
- (void) setTransient: (BOOL)flag;
- (void) setUnregistered: (BOOL)flag;
- (BOOL) transient;
@end

