
#include <Foundation/Foundation.h>

#include "EcProcess.h"

int
main()
{
  CREATE_AUTORELEASE_POOL(arp);
  NSUserDefaults	*defs = [NSUserDefaults standardUserDefaults];
  NSString		*host;
  NSString		*name;
  id			proxy;

  host = [defs stringForKey: @"BSCommandHost"];
  if (host == nil)
    {
      host = [defs stringForKey: @"CommandHost"];
      if (host == nil)
	{
	  host = @"*";
	}
    }
  if ([host length] == 0)
    {
      host = [[NSHost currentHost] name];
    }

  /*
   * Shut down the local command server.
   */
  name = [defs stringForKey: @"BSCommandName"];
  if (name == nil)
    {
      name = [defs stringForKey: @"CommandName"];
      if (name == nil)
	{
	  name = CMD_SERVER_NAME;
	}
    }

  proxy = [NSConnection rootProxyForConnectionWithRegisteredName: name
							    host: host
    usingNameServer: [NSSocketPortNameServer sharedInstance]];
  [(id<Command>)proxy terminate];

  RELEASE(arp);
  return 0;
}

