
#import	<Foundation/NSHost.h>

@class	NSDictionary;
@class	NSString;

/**
 * <p>This category provides additional methods to standardise host names so
 * that software can consistently refer to a host by a single well known
 * name.<br />
 * This mechanism, as well as ensuring naming consistency, can be used to
 * work with logical names for hosts when the actual naming of the hosts
 * (ie in the domain name system) is not under your control.
 * </p>
 * <p>This operates by managing a map from the various names and addresses a
 * host may be known by, to a single well known name.  This host name may,
 * but need not, be a public domain name.
 * </p>
 * <p>The well known name methods are thread-safe, and on initial use the
 * NSUserDefaults system is queried to set up two well known names
 * automatically:<br />
 * The value of EcHostCurrentName specifies the well known name for the
 * current host (the machine on which the software is running).<br />
 * The value of EcHostControlName specifies the well known name for the
 * control host (the machine on which control functions for your software
 * are centralised).  If this is specified without EcHostControlDomain,
 * it is ignored and the well known name of the current host is used.<br />
 * The value of EcHostControlDomain specifies the fully qualified domain
 * name of the control host.  If it is specified without EcHostControlName,
 * then it is used as the well known name for the control host.<br />
 * NB. the defaults system is accessed via EcUserDefaults, so if a
 * defaults prefix other than Ec has been set, these keys will use that
 * alternative prefix. 
 * </p>
 */
@interface	NSHost (EcHost)

/** Returns the well known name of the 'control' host as obtained from the
 * NSUserDefaults system.<br />
 * If EcHostControlName and EcHostControlDomain are both defined,
 * the well known name is the string specified by EcHostControlName.<br />
 * If EcHostControlDomain is defined, the well known name is the string
 * specified by it.<br />
 * If neither is defined, but EcHostCurrentName is defined, then the well
 * known name is the string specified by that default.<br />
 * Otherwise, the well known name is set to an arbitrarily selected name
 * of the current machine.
 */
+ (NSString*) controlWellKnownName;

/** Returns a host previously established as having the well known name,
 * or nil if no such association exists.
 */
+ (NSHost*) hostWithWellKnownName: (NSString*)aName;

/** Establishes mappings from a variety of host names (the dictionary keys)
 * to well known names (the dictionary values).<br />
 * The keys and values may be (and often are) identical in the case where
 * the well known name for a host is the same as one of its normal names
 * (eg its fully qualified domain name).<br />
 * It is possible to set a well known name for a host which does not yet
 * exist ... in which case the mapping will be established and will take
 * effect later, when the host is set up.
 */
+ (void) setWellKnownNames: (NSDictionary*)map;

/** Sets the well known name for the receiver.<br />
 * This replaces any previous well known name for the receiver and, if the
 * name is already in use, removes any associations of that well known name
 * with other hosts.
 */
- (void) setWellKnownName: (NSString*)aName;

/** Returns the well known name for the receiver (or any name of the receiver
 * if no well known name has been set for it).
 */
- (NSString*) wellKnownName;
@end

