
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

#import <Foundation/Foundation.h>

#import "EcBroadcastProxy.h"

/*
  EcBroadcastProxy 
*/

static NSNotificationCenter *nc;
static NSNull *null;

@interface EcBroadcastProxy (Private)
/* Methods which make it work :) */

/* NB: We post a @"EcBroadcastProxyHadIPNotification" when this method
   is called, and a @"EcBroadcastProxyHadOPNotification" when it completed
   (if any output was sent). */
- (void) forwardInvocation: (NSInvocation*)anInvocation;
- (NSMethodSignature*) methodSignatureForSelector: (SEL)aSelector;
- (void) BCPforwardOneWayInvocation: (NSInvocation*)anInvocation;
- (void) BCPforwardIdInvocation: (NSInvocation*)anInvocation;
- (void) BCPforwardPrivateInvocation: (NSInvocation*)anInvocation;
@end

@implementation EcBroadcastProxy
+ (void) initialize
{
  if (self == [EcBroadcastProxy class])
    {
      nc = [NSNotificationCenter defaultCenter];
      null = [NSNull null];
    }
}

/* Designated initializer */
- (id) initWithReceiverNames: (NSArray *)names
	       receiverHosts: (NSArray *)hosts
{
  int i, count;

  NSLog (@"EcBroadcastProxy: initializing with %@ names and %@ host", 
	 names, hosts);

  if (nil != (self = [super init]))
    {

      if ([names count] != [hosts count])
	{
	  [NSException raise: NSInvalidArgumentException format:
			 @"invalid initialization of EcBroadcastProxy: "
			 @"[names count] != [hosts count]"];
	}
      
      ASSIGN (receiverNames, names);
      ASSIGN (receiverHosts, hosts);
      receiverObjects = [NSMutableArray new];
      count = [receiverNames count];
      for (i = 0; i < count; i++)
	{ 
	  [receiverObjects addObject: null]; 
	}
    }
  /* All the statistical ivars are automatically initialized to zero */
  return self;
}

- (id) initWithReceivers: (NSArray *)receivers
{
  int i, count;
  NSMutableArray *names;
  NSMutableArray *hosts;

  names = AUTORELEASE ([NSMutableArray new]);
  hosts = AUTORELEASE ([NSMutableArray new]);

  count = [receivers count];
  for (i = 0; i < count; i++)
    {
      NSString *string;
      NSDictionary *dict = (NSDictionary *)[receivers objectAtIndex: i];

      if ([dict isKindOfClass: [NSDictionary class]] == NO)
	{
	  [NSException raise: NSInvalidArgumentException format:
			 @"invalid initialization of EcBroadcastProxy: "
		         @"config dictionary is not a dictionary"];
	}
      
      string = [dict objectForKey: @"Name"];
      [(NSMutableArray *)names addObject: string];

      string = [dict objectForKey: @"Host"];
      if (string == nil)
	{
	  /* Would `localhost' be a better choice ? */
	  string = @"*";
	}
      [(NSMutableArray *)hosts addObject: string];
    }

  return [self initWithReceiverNames: names  receiverHosts: hosts];
}

- (void) dealloc
{
  RELEASE (receiverNames);
  RELEASE (receiverHosts);
  RELEASE (receiverObjects);
  [nc removeObserver: self];
  [super dealloc];
}

- (void) BCPraiseConnections
{
  int i, count;

  count = [receiverNames count];

  for (i = 0; i < count; i++)
    {
      [self BCPraiseConnection: i];
    }  
}

- (void) BCPraiseConnection: (int)index
{
  NSString *host = [receiverHosts objectAtIndex: index];
  NSString *name = [receiverNames objectAtIndex: index];
  id object = [receiverObjects objectAtIndex: index];
  
  if (object == null)
    {
      NS_DURING
	{
	  object = [NSConnection 
		     rootProxyForConnectionWithRegisteredName: name
		     host: host
		     usingNameServer: [NSSocketPortNameServer sharedInstance]];
	}
      NS_HANDLER
	{
	  NSLog(@"Caught exception trying to connect to '%@:%@' - %@\n",
		host, name, localException);
	  object = nil;
	}
      NS_ENDHANDLER
	
	if (object != nil)
	  {
	    id c = [object connectionForProxy];
	    
	    [receiverObjects replaceObjectAtIndex: index  withObject: object];
	    [nc addObserver: self
		selector: @selector(BCPconnectionBecameInvalid:)
		name: NSConnectionDidDieNotification
		object: c];
	    if ([delegate respondsToSelector:
			    @selector(BCP:madeConnectionToServer:host:)])
	      {
		[delegate BCP: self madeConnectionToServer: name 
			  host: host];
	      }
	  }
    }
}

- (void) BCPsetDelegate: (id)object
{
  delegate = object;
}

- (id) BCPdelegate 
{
  return delegate;
}

- (NSArray *) BCPreceiverNames
{
  return receiverNames;
}

- (NSArray *) BCPreceiverHosts
{
  return receiverHosts;
}

- (int) BCPreceiverCount
{
  return [receiverNames count];
}

- (id) BCPproxy: (int)index
{
  id proxy;

  [self BCPraiseConnection: index];
  proxy = [receiverObjects objectAtIndex: index];
  
  if (proxy == null)
    { return nil; }
  else
    { return proxy; }
}

- (NSString *) BCPstatus
{
  NSMutableString *output;
  int i, count;

  output = AUTORELEASE ([NSMutableString new]);

  count = [receiverNames count];

  [output appendFormat: @"EcBroadcastProxy with %d receivers:\n", count];
  for (i = 0; i < count; i++)
    {
      NSString *host = [receiverHosts objectAtIndex: i];
      NSString *name = [receiverNames objectAtIndex: i];
      id object = [receiverObjects objectAtIndex: i];
      
      [output appendFormat: @" (%d) Connection to `%@' on host `%@' is ", 
	      i, name, host];

      if (object == null)
	{
	  [output appendString: @"DEAD\n"];
	}
      else
	{
	  [output appendString: @"LIVE\n"];
	}
    }   
  [output appendString: @"\nVoid messages statistics:\n"];
  [output appendFormat: @" * succesfully broadcasted: %d\n", onewayFullySent];
  [output appendFormat: @" * partially broadcasted: %d\n", 
	  onewayPartiallySent];
  [output appendFormat: @" * failed to broadcast: %d\n", onewayFailed];

  [output appendString: @"\nId messages statistics:\n"];
  [output appendFormat: @" * succesfully broadcasted: %d\n", idFullySent];
  [output appendFormat: @" * partially broadcasted: %d\n", idPartiallySent];
  [output appendFormat: @" * failed to broadcast: %d\n", idFailed];
  
  /* TODO: Should display info about the last message ? */
  return output;
}

- (void) BCPforwardOneWayInvocation: (NSInvocation*)anInvocation
{
  unsigned int i, count;
  NSMutableArray *list;
  unsigned int sent = 0;
  
  /* Raise any pending connection */
  [self BCPraiseConnections];
  
  /* Prepare a mutable list of servers to message */
  list = [NSMutableArray arrayWithArray: receiverObjects];

  count = [list count];

  for (i = 0; i < count; i++)
    {
      id receiver = [list objectAtIndex: i];
      
      /* Check that we are connected to the server. */
      if (receiver == null)
	{ continue; }
      
      /* Check in case server has died. */
      if ([receiverObjects indexOfObjectIdenticalTo: receiver] 
	  == NSNotFound)
	{ continue; }
      
      /* Send the method */
      NS_DURING
	{
	  [anInvocation invokeWithTarget: receiver];
	  sent++;
	}
      NS_HANDLER
	{
	  /* Not sure what to do here */
	  NSLog (@"Caught exception trying to send event - %@\n",
		 localException);
	}
      NS_ENDHANDLER
  }

  /* Update statistical records */
  if (sent == [receiverObjects count])
    {
      onewayFullySent++;
    }
  else if (sent == 0)
    {
      onewayFailed++;
    }
  else
    {
      onewayPartiallySent++;
    }

  if (sent != 0)
    {
      /* Post notification we had an output */
      [nc postNotificationName: @"EcBroadcastProxyHadOPNotification"  
	  object: self]; 
    }

  NSLog (@"Broadcasted oneway message to %d (out of %"PRIuPTR") targets",
    sent, [receiverObjects count]);     
}

- (void) BCPforwardIdInvocation: (NSInvocation*)anInvocation
{
  int i, count;
  NSMutableArray *list;
  NSMutableArray *returnArray;
  unsigned int sent = 0;

  /* Raise any pending connection */
  [self BCPraiseConnections];

  /* Prepare a mutable list of servers to message */
  list = [NSMutableArray arrayWithArray: receiverObjects];

  /* Prepare the return array - this will contain an entry for *each*
     server.  Failures in contacting a server result in the error info 
     being set for that server. */
  returnArray = [NSMutableArray new];

  count = [list count];

  /* We need to make sure we keep the order */
  for (i = 0; i < count; i++)
    {
      id		receiver = [list objectAtIndex: i];
      NSDictionary	*dict;
      id		returnValue;
      
      /* Check that we are connected to the server. */
      if (receiver == null) 
	{
	  /* No server to talk to */
	  dict = [NSDictionary dictionaryWithObjectsAndKeys: 
				 [NSNumber numberWithInt: 
					     BCP_COULD_NOT_CONNECT],
			       @"error", nil];
	  [returnArray addObject: dict];
	  continue;
	}
      
      if ([receiverObjects indexOfObjectIdenticalTo: receiver] 
	  == NSNotFound)
	{
	  /* Server died in the meanwhile */
	  dict = [NSDictionary dictionaryWithObjectsAndKeys: 
				 [NSNumber numberWithInt: 
					     BCP_CONNECTION_WENT_DOWN], 
			       @"error", nil];
	  [returnArray addObject: dict];
	  continue;
	}
      
      /* Send the method */
      NS_DURING
	{
	  [anInvocation invokeWithTarget: receiver];
	  [anInvocation getReturnValue: &returnValue];
	  /* OK - done it! */
	  dict = [NSDictionary dictionaryWithObjectsAndKeys: 
				 [NSNumber numberWithInt: BCP_NO_ERROR], 
			       @"error",
			       returnValue, @"response", nil];	  
	  [returnArray addObject: dict];
	  sent++;
	}
      NS_HANDLER
	{
	  /* Didn't work - messaging timeout */
	  NSLog (@"Caught exception trying to send event - %@\n",
		 localException);
	  dict = [NSDictionary dictionaryWithObjectsAndKeys: 
				 [NSNumber numberWithInt: 
					     BCP_MESSAGING_TIMEOUT],
			       @"error", 
			       [localException description], 
			       @"error description", nil];
	  [returnArray addObject: dict];
	}
      NS_ENDHANDLER
    }

  [anInvocation setReturnValue: &returnArray];
  
  /* Update statistical records */
  if (sent == [receiverObjects count])
    {
      idFullySent++;
    }
  else if (sent == 0)
    {
      idFailed++;
    }
  else
    {
      idPartiallySent++;
    }

  if (sent != 0)
    {
      /* Post notification we had an output */
      [nc postNotificationName: @"EcBroadcastProxyHadOPNotification"  
	  object: self]; 
    }
  
  NSLog (@"Broadcasted Id message to %d (out of %"PRIuPTR") targets",
	 sent, [receiverObjects count]);     
}

- (void) forwardInvocation: (NSInvocation*)anInvocation
{
  NSMethodSignature *methodSig;

  NSLog (@"ForwardInvocation: %@", anInvocation);

  /* Post notification we had an input */
  [nc postNotificationName: @"EcBroadcastProxyHadIPNotification"  object: self]; 

  /* Get information about the return type */
  methodSig = [anInvocation methodSignature];
  
  if ([methodSig isOneway] == YES)
    {
      [self BCPforwardOneWayInvocation: anInvocation];
    }
  else
    {
      const char *signature;
      
      signature = [methodSig methodReturnType];

      if (*signature == _C_VOID)
	{
	  /* Issue a warning here ? */
	  [self BCPforwardOneWayInvocation: anInvocation];
	}
      else if (*signature == _C_ID)
	{
	  [self BCPforwardIdInvocation: anInvocation];
	}
      else
	{
	  /* We only accept (id) return types */
	  [NSException raise: NSInvalidArgumentException format:
	    @"EcBroadcastProxy can only respond to oneway methods "
	    @"or methods returning an object or void"];
	}
    }
}

- (void) BCPconnectionBecameInvalid: (NSNotification*)notification
{
  id connection;

  connection = [notification object];

  [nc removeObserver: self  
      name: NSConnectionDidDieNotification
      object: connection];
  
  if ([connection isKindOfClass: [NSConnection class]])
    {
      unsigned int i;
      /*
       * Now - remove any proxy that uses this connection from the cache.
       */
      for (i = 0; i < [receiverObjects count]; i++)
	{
	  id  obj = [receiverObjects objectAtIndex: i];

	  if (obj != null)
	    {
	      if ([obj connectionForProxy] == connection)
		{
		  [receiverObjects replaceObjectAtIndex: i 
				   withObject: null];
		  if ([delegate respondsToSelector:
				  @selector(BCP:lostConnectionToServer:host:)])
		    {
		      NSString *name = [receiverNames objectAtIndex: i];
		      NSString *host = [receiverHosts objectAtIndex: i];
		      [delegate BCP: self  lostConnectionToServer: name 
				host: host];
		    }
		}
	    }
	}
      NSLog (@"client (%p) gone away.", connection);
    }
  else
    {
      NSLog (@"non-Connection sent invalidation");
    }
}

/* And now the stuff which makes it work */

- (void) BCPforwardPrivateInvocation: (NSInvocation*)anInvocation
{
  /* TODO - Better stuff */
  int i, count;
  int nilValue = 0;
  BOOL ok = NO;

  /* Raise any pending connection */
  [self BCPraiseConnections];
  
  count = [receiverObjects count];
  
  /* Look for the first not-null receiver */
  for (i = 0; i < count; i++)
    {
      id receiver = [receiverObjects objectAtIndex: i];

      if (receiver != null)
	{
	  /* Send the method to him */
	  NS_DURING
	    {
	      [anInvocation invokeWithTarget: receiver];
	      ok =YES;
	    }
	  NS_HANDLER
	    {
	      NSLog (@"Caught exception trying to send event - %@\n",
		     localException);
	    }
	  NS_ENDHANDLER
	    
          if (ok == YES)
	    return;
	  /* No luck - try with the next one */
	}
    }
  /* Eh - should perhaps raise an exception ? */
  NSLog (@"Could not forward private invocation %@", anInvocation);
  /* Try this trick */
  [anInvocation setReturnValue: &nilValue];
}

- (NSMethodSignature*) methodSignatureForSelector: (SEL)aSelector
{
  /* TODO - Better stuff */
  BOOL ok = NO;
  NSMethodSignature *methodSig = nil;
  int i, count;

  /* Raise any pending connection */
  [self BCPraiseConnections];
  
  count = [receiverObjects count];
  
  /* Look for the first not-null receiver */
  for (i = 0; i < count; i++)
    {
      id receiver = [receiverObjects objectAtIndex: i];
      
      if (receiver != null)
	{
	  /* Ask to him for the method signature */
	  NS_DURING
	    {
	      methodSig = [receiver methodSignatureForSelector: aSelector];
	      ok = YES;
	    }
	  NS_HANDLER
	    {
	      NSLog (@"Caught exception trying to send event - %@\n",
	        localException);
	    }
	  NS_ENDHANDLER
	    
          if (ok == YES)
	    {
	      return methodSig;
	    }
	  /* No luck - try with the next one */
	}
    }
  /* Eh - should perhaps raise an exception ? */
  NSLog (@"Could not determine method signature of selector %@",
   NSStringFromSelector(aSelector));
  return nil;
}

- (BOOL) respondsToSelector:(SEL)aSelector
{
  NSMethodSignature *ms;
  NSInvocation *inv;
  SEL selector = @selector (respondsToSelector:);
  BOOL result;

  /* Recognize standard methods */
  if ([super respondsToSelector: aSelector] == YES)
    return YES;

  /* And remote ones - FIXME/TODO: do not respond YES to stuff which
     is not returning (oneway void) or (id) */
  ms = [self methodSignatureForSelector: selector];
  inv = [NSInvocation invocationWithMethodSignature: ms];
  [inv setSelector: selector];
  [inv setTarget: self];
  [inv setArgument: &aSelector  atIndex: 2];
  [self BCPforwardPrivateInvocation: inv];
  [inv getReturnValue: &result];

  return result;
}


- (BOOL) conformsToProtocol: (Protocol *)aProtocol
{
  NSMethodSignature *ms;
  NSInvocation *inv;
  SEL selector = @selector (conformsToProtocol:);
  BOOL result;
  
  if ([super conformsToProtocol: aProtocol] == YES)
    return YES;

  ms = [self methodSignatureForSelector: selector];
  inv = [NSInvocation invocationWithMethodSignature: ms];
  [inv setSelector: selector];
  [inv setTarget: self];
  [inv setArgument: &aProtocol  atIndex: 2];
  [self BCPforwardPrivateInvocation: inv];
  [inv getReturnValue: &result];

  return result;
}

/* Attention - this will be forwarded as any normal method ! 
   The return is not a NSString, but an NSArray of dictionaries with 
   the responses of the various servers ! */
- (NSString *) description
{
  NSMethodSignature *ms;
  NSInvocation *inv;
  SEL selector = @selector (description);
  NSString *result;

  ms = [self methodSignatureForSelector: selector];
  inv = [NSInvocation invocationWithMethodSignature: ms];
  [inv setSelector: selector];
  [inv setTarget: self];
  [self BCPforwardIdInvocation: inv];
  [inv getReturnValue: &result];

  return result;
}

/* who cares but anyway */
- (BOOL) isProxy
{
  return YES;
}
@end
