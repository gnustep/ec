
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

#import <Foundation/NSData.h>
#import <Foundation/NSException.h>
#import <Foundation/NSFileHandle.h>
#import <Foundation/NSString.h>

#import "NSFileHandle+Printf.h"

@implementation	NSFileHandle (Printf)

- (void) printWithFormat: (NSString*)format arguments: (va_list)args
{
  NSString	*text;

  text = [NSString stringWithFormat: format arguments: args];
  [self puts: text];
}

- (void) printf: (NSString*)format,...
{
  va_list ap;
  va_start(ap, format);
  [self printWithFormat: format arguments: ap];
  va_end(ap);
}

- (void) puts: (NSString*)text
{
  NS_DURING
    {
      NSData	*data;

      data = [text dataUsingEncoding: [NSString defaultCStringEncoding]];
      if (data == nil)
	{
	  data = [text dataUsingEncoding: NSUTF8StringEncoding];
	}
      [self writeData: data];
    }
  NS_HANDLER
    {
      NSLog(@"Exception writing to log file: %@", localException);
      [localException raise];
    }
  NS_ENDHANDLER
}

@end

