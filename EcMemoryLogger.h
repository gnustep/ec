
/** Enterprise Control Configuration and Logging 
    -- memory logger protocol

   Copyright (C) 2015 Free Software Foundation, Inc.

   Written by: Niels Grewe <niels.grewe@halbordnung.de>
   Date: July 2015

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

@class EcProcess;

/**
 * This protocol should be implemented by classes that want to receive
 * callbacks about memory usage in the process. This feature is enabled
 * by setting the MemoryLoggerBundle user default to a bundle whose 
 * principal class implements this protocol.
 */
@protocol EcMemoryLogger <NSObject>
/**
 * This callback is issued once per minute, with totalUsage representing
 * the memory usage of the process and notLeaked the amount of memory 
 * accounted for as active by -ecNotLeaked. All values are in bytes.
 */
- (void)process: (EcProcess*)process
   didUseMemory: (uint64_t)totalUsage
      notLeaked: (uint64_t)notLeaked;
@end
