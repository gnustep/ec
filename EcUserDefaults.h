
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

