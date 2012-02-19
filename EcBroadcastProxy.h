/* -*-objc-*-
 * Nicola Pero, Brainstorm, October 2000
 * EcBroadcastProxy - an object able to broadcast a message to 
 * a list of remote objects.
 *
 */

#ifndef _ECBROADCASTPROXY_H
#define _ECBROADCASTPROXY_H

#include <Foundation/NSObject.h>

@class	NSArray;
@class	NSMutableArray;
@class	NSString;

enum EcBroadcastProxyError
{
  BCP_NO_ERROR = 0,
  BCP_COULD_NOT_CONNECT = 1,
  BCP_CONNECTION_WENT_DOWN = 2,
  BCP_MESSAGING_TIMEOUT = 3
};

/**
 * In this class, remote servers are always listed in the same order.
 * So, you can access them by their index; to get the host/name, you
 * can get it by asking the receiverNames and receiverHosts and then 
 * looking up the one at the index you want.
 */

@interface EcBroadcastProxy : NSObject
{
  /* The names of the receiver object */
  NSArray *receiverNames;
  /* The hosts the receiver objects are on */
  NSArray *receiverHosts;

  /* The [proxy to the] remote objects */
  NSMutableArray *receiverObjects;

  /* The delegate (if any) */
  id delegate;

  /* The statistical info about what we did */

  /* Messages returning void */
  int onewayFullySent; 
  int onewayPartiallySent;   
  int onewayFailed; 
  /* Messages returning id */
  int idFullySent; 
  int idPartiallySent;   
  int idFailed; 
}

- (id) initWithReceiverNames: (NSArray *)names
	       receiverHosts: (NSArray *)hosts;

/** Configuration array contains a list of dictionaries (one for each
   receiver) - each dictionary has two keys: `Name' and `Host', with
   the corresponding values set. */

- (id) initWithReceivers: (NSArray *)receivers;

/* Methods specific to EcBroadcastProxy (which should not be forwarded 
   to remote servers) are prefixed with `BCP' to avoid name clashes.  
   Anything not prefixed with BCP is forwarded. */

/** Create connections to the receivers if needed.  It is called
   internally when a message to broadcast comes in; but you may want
   to call this method in advance to raise the connections so that
   when a message to broadcast comes in, the connections are already
   up and ready. */
- (void) BCPraiseConnections;

/** Get a string describing the status of the broadcast object */
- (NSString *) BCPstatus;

/** Set a delegate.<br /> 
 * The delegate gets a -BCP:lostConnectionToServer:onHost: message
 * upon connection lost, and -BCP:madeConnectionToServer:onHost:
 * message upon connection made.
 */
- (void) BCPsetDelegate: (id)delegate;

- (id) BCPdelegate;

/* [Advanced stuff] 
   Access to a single one of the servers we are broadcasting to.

   Eg, after sending a search to multiple servers, you might need to
   get further information only from the servers which answered
   affirmatively to your query.  To do it, use BCPproxyForName:host:
   to get the single remote server(s) you want to talk to, and talk to
   it (each of them) directly. */

/* Get the list of servers */
- (NSArray *) BCPreceiverNames;

- (NSArray *) BCPreceiverHosts;

/* Get only the number of receivers */
- (int) BCPreceiverCount;

/* Raise connection to server at index */
- (void) BCPraiseConnection: (int)index;

/* The following one gives you back the proxy to talk to.  
   It automatically BCPraise[s]Connection to that server before sending 
   you back a proxy.  It returns nil upon failure. */
- (id) BCPproxy: (int)index;

@end

@interface NSObject (BCPdelegate)

- (void) BCP: (EcBroadcastProxy *)proxy
  lostConnectionToServer: (NSString *)name
  host: (NSString *)host;

- (void) BCP: (EcBroadcastProxy *)proxy
  madeConnectionToServer: (NSString *)name
  host: (NSString *)host;

@end

#endif /* _BROADCASTPROXY_H */




