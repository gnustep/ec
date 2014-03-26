
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

#import	<Foundation/NSUserDefaults.h>

@class	NSString;

/**
 * This category simply provides an easy way to work with user defaults
 * where you want all keys to share a common prefix.
 */
@interface	NSUserDefaults (EcUserDefaults)

/** Returns the latest prefixed version of the shared user defaults,
 * or nil if none has been set up.
 */
+ (NSUserDefaults*) prefixedDefaults;

/** Returns a proxy to the shared user defaults instance, which will use
 * aPrefix at the start of every key.<br />
 * If aPrefix is nil, the string given by the EcUserDefaultsPrefix user
 * default is used.<br />
 * If the enforcePrefix flag is YES, the prefix is strictly enforced,
 * otherwise the system will read defaults using the unprefixed key
 * if no value is found for the prefixed key.
 */
+ (NSUserDefaults*) userDefaultsWithPrefix: (NSString*)aPrefix
				    strict: (BOOL)enforcePrefix;

/** Returns the prefix used by the receiver, or nil if no prefix is in use.
 */
- (NSString*) defaultsPrefix;

/** Convenience method to prepend the pefix to the supplied aKey value
 * if it is not already present.
 */
- (NSString*) key: (NSString*)aKey;

/** Sets a value to take precedence over others (in the volatile domain
 * reserved for commands issued to the current process by an operator).<br />
 * Setting a nil value removes any previously set value so that behavior
 * reverts to the default.<br />
 * Returns YES if the configuration was changed, NO otherwise.
 */
- (BOOL) setCommand: (id)val forKey: (NSString*)key;

/** Replaces the system central configuration information for this process
 * with the contents of the dictionary. Values in this dictionary take
 * precedence over other configured values except for those set using the
 * -setCommand:forKey: method.<br />
 * Returns YES if the configuration changed, NO otherwise.
 */
- (BOOL) setConfiguration: (NSDictionary*)config;

@end

