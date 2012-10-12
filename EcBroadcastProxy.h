
/** Enterprise Control Configuration and Logging

   Copyright (C) 2012 Free Software Foundation, Inc.

   Written by: Nicola Pero <nicola.pero@meta-innovation.com>
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

#ifndef _ECBROADCASTPROXY_H
#define _ECBROADCASTPROXY_H

#import <Foundation/NSObject.h>

@class	NSArray;
@class	NSMutableArray;
@class	NSString;

/** This type enumerates the possible error conditions occurring when
 * sending a message to the proxy.
 * <deflist>
 *    <term>BCP_NO_ERROR</term>
 *    <desc>A success</desc>
 *    <term>BCP_COULD_NOT_CONNECT</term>
 *    <desc>Unable to connect to the server</desc>
 *    <term>BCP_CONNECTION_WENT_DOWN</term>
 *    <desc>Lost connection while sending</desc>
 *    <term>BCP_MESSAGING_TIMEOUT</term>
 *    <desc>Timeout while waiting for response</desc>
 * </deflist>
 */
enum EcBroadcastProxyError
{
  BCP_NO_ERROR = 0,
  BCP_COULD_NOT_CONNECT = 1,
  BCP_CONNECTION_WENT_DOWN = 2,
  BCP_MESSAGING_TIMEOUT = 3
};

/**
 * An EcBroadcastProxy instance forwards messages to multiple servers
 * via distributed objects.  This is great if you want to send a task
 * to be repeated by multiple servers in order to make a system more
 * scalable.<br />
 * You may also design your servers so that you pass some sort of
 * identifier to let them know that  one of them (which recognises
 * the identifier) should do one thing while the others ignore it.<br />
 * Finally, remote servers are always listed in the same order,
 * so you can access them by their index; to get the host/name, you
 * can get it by asking the receiverNames and receiverHosts and then 
 * looking up the one at the index you want.  This allows you to send
 * specific messages to specific servers.
 */
@interface EcBroadcastProxy : NSObject
{
  /** The names of the receiver object */
  NSArray *receiverNames;

  /** The hosts the receiver objects are on */
  NSArray *receiverHosts;

  /** The [proxies to the] individual remote objects */
  NSMutableArray *receiverObjects;

  /** The delegate (if any) */
  id delegate;

  /* The statistical info about what we did */

  /** Count of completed messages returning void */
  int onewayFullySent; 

  /** Count of partial messages returning void */
  int onewayPartiallySent;   

  /** Count of failed messages returning void */
  int onewayFailed; 

  /** Count of completed messages returning id */
  int idFullySent; 

  /** Count of partial messages returning id */
  int idPartiallySent;   

  /** Count of failed messages returning id */
  int idFailed; 
}

/** <init />
 * Initializes the receiver creating connections to the specified
 * distributed objects servers.  The names are the DO ports (server-names)
 * and hosts are the names of the machines those servers are running on
 * (may be '*' to find the server on any machine on the LAN, or an empty
 * string to find the server on the local host).
 */
- (id) initWithReceiverNames: (NSArray*)names
	       receiverHosts: (NSArray*)hosts;

/** Configuration array contains a list of dictionaries (one for each
 * receiver) - each dictionary has two keys: `Name' and `Host', with
 * the corresponding values set.
 */
- (id) initWithReceivers: (NSArray *)receivers;

/* Methods specific to EcBroadcastProxy (which should not be forwarded 
 * to remote servers) are prefixed with `BCP' to avoid name clashes.  
 * Anything not prefixed with BCP is forwarded. */

/** Create connections to the receivers if needed.  It is called
 * internally when a message to broadcast comes in; but you may want
 * to call this method in advance to raise the connections so that
 * when a message to broadcast comes in, the connections are already
 * up and ready. */
- (void) BCPraiseConnections;

/** Get a string describing the status of the broadcast object */
- (NSString *) BCPstatus;

/** Set a delegate.<br /> 
 * The delegate object gets the messages from the BCPdelegate informal protocol
 * upon connection loss and when a connection is made.
 */
- (void) BCPsetDelegate: (id)object;

/** Returns the delegate set using the -BCPsetDelegate: method.
 */
- (id) BCPdelegate;

/* [Advanced stuff] 
   Access to a single one of the servers we are broadcasting to.

   Eg, after sending a search to multiple servers, you might need to
   get further information only from the servers which answered
   affirmatively to your query.  To do it, use BCPproxyForName:host:
   to get the single remote server(s) you want to talk to, and talk to
   it (each of them) directly. */

/** Get the list of server names */
- (NSArray *) BCPreceiverNames;

/** Get the list of server hosts */
- (NSArray *) BCPreceiverHosts;

/** Get the number of receivers */
- (int) BCPreceiverCount;

/** Raise connection to server at index */
- (void) BCPraiseConnection: (int)index;

/** The following one gives you back the proxy to talk to.  
 * It automatically calls -BCPraiseConnection: to that server before sending 
 * you back a proxy.  It returns nil upon failure. */
- (id) BCPproxy: (int)index;

@end

/** The informal protocol listing messages which will be sent to the
 * EcBroadcastProxy's delegate if it responds to them.
 */
@interface NSObject (BCPdelegate)

/** The method to notify the delegate that a connection to an individual
 * server process has been lost.
 */
- (void) BCP: (EcBroadcastProxy *)proxy
  lostConnectionToServer: (NSString *)name
  host: (NSString *)host;

/** The method to notify the delegate that a connection to an individual
 * server process has been made.
 */
- (void) BCP: (EcBroadcastProxy *)proxy
  madeConnectionToServer: (NSString *)name
  host: (NSString *)host;

@end

#endif /* _BROADCASTPROXY_H */

